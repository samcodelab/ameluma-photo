import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FramepebbleCore

final class GIFTests: XCTestCase {
  func source(in folder: URL, name: String = "photo.png", width: Int = 120, height: Int = 60) throws -> SourceAsset {
    let url = folder.appendingPathComponent(name)
    let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let d = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(d, try XCTUnwrap(ctx.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(d))
    return SourceAsset(url: url)
  }
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
  }
  func testFrameOrderDuplicateRemoveTimingAndVisibility() throws {
    var p = GIFProject(); p.frames = (0..<4).map { _ in GIFFrame(sourceID: UUID()) }
    let a = p.frames[0].id, b = p.frames[1].id
    var annotation = Annotation(); annotation.kind = .arrow
    p.annotations = [GIFAnnotation(annotation: annotation, frameIDs: [a]), GIFAnnotation(annotation: Annotation())]
    p.duplicate(a)
    XCTAssertEqual(p.frames[0].sourceID, p.frames[1].sourceID)
    XCTAssertNotEqual(p.frames[0].id, p.frames[1].id)
    XCTAssertEqual(p.visibleAnnotations(on: p.frames[1].id).count, 2)
    p.move(b, before: a); XCTAssertEqual(p.frames.first?.id, b)
    XCTAssertEqual(p.visibleAnnotations(on: b).count, 1)
    p.setDuration(0.126, ids: [a]); XCTAssertEqual(p.frames.first { $0.id == a }?.duration, 0.13)
    p.speed = 2; XCTAssertEqual(p.timing(for: p.frames.first { $0.id == a }!), 0.1)
    p.setDuration(0.5); XCTAssertTrue(p.frames.allSatisfy { $0.duration == 0.5 })
    p.remove([a]); XCTAssertFalse(p.frames.contains { $0.id == a }); XCTAssertEqual(p.annotations.count, 2)
    p.frames[0].duration = .nan; XCTAssertThrowsError(try p.validate())
  }
  func testGIFExportReopensWithTimingDimensionsLoopsAndSafeCollisions() async throws {
    let root = try folder(), asset = try source(in: root), original = try Data(contentsOf: asset.url)
    var p = GIFProject(); p.width = 64; p.height = 64; p.plays = 3
    p.frames = [GIFFrame(sourceID: asset.id), GIFFrame(sourceID: asset.id)]
    p.frames[1].duration = 0.23; p.speed = 0.5
    var a = Annotation(); a.kind = .speechBubble; a.text = "Hi"; a.colour = RGBAColour(0,0,0,1)
    p.annotations = [GIFAnnotation(annotation: a, frameIDs: [p.frames[1].id])]
    let renderer = GIFRenderer()
    let out = try await renderer.export(p, sources: [asset], directory: root)
    let second = try await renderer.export(p, sources: [asset], directory: root)
    XCTAssertNotEqual(out, second)
    let s = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetCount(s), 2)
    let props = try XCTUnwrap(CGImageSourceCopyProperties(s, nil) as? [CFString: Any])
    XCTAssertEqual((props[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int, 2)
    for (i, f) in p.frames.enumerated() {
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(s, i, nil)); XCTAssertEqual(image.width, 64); XCTAssertEqual(image.height, 64)
      let info = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [CFString: Any])
      let gif = try XCTUnwrap(info[kCGImagePropertyGIFDictionary] as? [CFString: Any])
      XCTAssertEqual(try XCTUnwrap(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double), p.timing(for: f), accuracy: 0.011)
    }
    XCTAssertEqual(try Data(contentsOf: asset.url), original)
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".tmp") })
  }
  func testSharedCompositionFitAndAnnotationsMatchExport() async throws {
    let root = try folder(), asset = try source(in: root)
    var p = GIFProject(); p.width = 80; p.height = 80; p.frames = [GIFFrame(sourceID: asset.id)]
    p.frames[0].configuration.width = 120; p.frames[0].configuration.height = 60
    let renderer = GIFRenderer()
    let fit = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
      try bytes.withUnsafeMutableBytes { buffer in
        let c = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      }
      let start = (y * image.width + x) * 4; return Array(bytes[start..<start+3])
    }
    XCTAssertEqual(try pixel(fit, 0, 0), [255,255,255])
    p.fit = .fill
    let fill = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
    let red = try pixel(fill, 0, 0); XCTAssertGreaterThan(red[0], 240); XCTAssertLessThan(red[1], 60); XCTAssertLessThan(red[2], 10)
    var a = Annotation(); a.kind = .rectangle; a.x = 0.2; a.y = 0.2; a.width = 0.5; a.height = 0.5; a.lineWidth = 0.05; a.colour = RGBAColour(0,0,0,1)
    p.annotations = [GIFAnnotation(annotation: a)]
    let composed = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
    XCTAssertNotEqual(try pixel(composed, 16, 30), try pixel(fill, 16, 30))
    let out = try await renderer.export(p, sources: [asset], directory: root)
    let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
    let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, 0, nil))
    XCTAssertEqual(try pixel(composed, 16, 30), try pixel(decoded, 16, 30))
  }
  func testPersistenceLegacyMissingAndCancellation() async throws {
    let root = try folder(), asset = try source(in: root)
    var p = GIFProject(); p.frames = (0..<40).map { _ in GIFFrame(sourceID: asset.id) }; p.width = 64; p.height = 64
    var doc = ProjectDocument(); doc.sources = [asset]; doc.gifProject = p; doc.workspaceSelection = [asset.id]
    let url = root.appendingPathComponent("workspace.json"); try doc.save(url)
    let restored = try ProjectDocument.load(url)
    XCTAssertEqual(restored.gifProject, p); XCTAssertEqual(restored.workspaceSelection, [asset.id])
    let legacy = try JSONDecoder().decode(ProjectDocument.self, from: Data("{\"version\":3}".utf8)); XCTAssertNil(legacy.gifProject)
    let renderer = GIFRenderer()
    let captured = p
    let task = Task { try await renderer.export(captured, sources: [asset], directory: root) { done, _ in if done == 1 { withUnsafeCurrentTask { $0?.cancel() } } } }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".tmp") || $0.hasSuffix(".gif") })
    do { _ = try await renderer.renderFrame(p.frames[0], project: p, sources: []); XCTFail("Missing reference should fail") } catch GIFError.missingSource {}
  }
  func testFiltersDatesOrientationFormatAndStableSorting() throws {
    let assets = [SourceAsset(url: URL(fileURLWithPath: "/b.png")), SourceAsset(url: URL(fileURLWithPath: "/a.jpg"))]
    let now = Date(), info = [assets[0].id: WorkspacePhotoInfo(date: now.addingTimeInterval(-60), width: 100, height: 50, format: "public.png"), assets[1].id: WorkspacePhotoInfo(date: now.addingTimeInterval(-86400 * 4), width: 50, height: 100, format: "public.jpeg")]
    var f = WorkspaceFilter(); f.period = .hour
    XCTAssertEqual(f.apply(to: assets, information: info, now: now).map(\.id), [assets[0].id])
    f.period = .any; f.orientation = .portrait; XCTAssertEqual(f.apply(to: assets, information: info).map(\.id), [assets[1].id])
    f.orientation = .any; f.format = "public.png"; XCTAssertEqual(f.apply(to: assets, information: info).count, 1)
    f.format = ""; f.sort = .filename; XCTAssertEqual(f.apply(to: assets, information: info).map(\.id), assets.reversed().map(\.id))
  }
}
