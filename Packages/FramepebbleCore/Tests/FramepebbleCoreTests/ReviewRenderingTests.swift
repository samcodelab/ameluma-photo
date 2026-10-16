import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FramepebbleCore

extension GIFTests {
  func testFillPansAtNormalZoomOnBothAxesAndMatchesPreviewExport() async throws {
    let root = try folder()
    for portrait in [false, true] {
      let w = portrait ? 60 : 120, h = portrait ? 120 : 60
      let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
      ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
      ctx.fill(portrait ? CGRect(x: 0, y: 60, width: 60, height: 60) : CGRect(x: 60, y: 0, width: 60, height: 60))
      let url = root.appendingPathComponent(portrait ? "portrait.png" : "landscape.png")
      let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
      let asset = SourceAsset(url: url)
      var config = ProcessingConfiguration(); config.crop.mode = .preserveAspectRatio; config.resizeBasis = .percentage; config.percentage = 100
      var p = GIFProject(); p.width = 40; p.height = 40; p.fit = .fill; p.frames = [GIFFrame(sourceID: asset.id, configuration: config)]
      let renderer = GIFRenderer()
      func rgb(_ image: CGImage) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { b in
          let c = try XCTUnwrap(CGContext(data: b.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          c.draw(image, in: CGRect(x: -image.width/2, y: -image.height/2, width: image.width, height: image.height))
        }
        return Array(pixel.prefix(3))
      }
      if portrait { p.frames[0].crop.centerY = 0 } else { p.frames[0].crop.centerX = 0 }
      let first = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
      let reduced = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset], maximum: 20)
      XCTAssertEqual(try rgb(first), try rgb(reduced))
      if portrait { p.frames[0].crop.centerY = 1 } else { p.frames[0].crop.centerX = 1 }
      let last = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
      XCTAssertNotEqual(try rgb(first), try rgb(last), "Fill pan must move content at zoom 1")
      let output = try await renderer.export(p, sources: [asset], directory: root)
      let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
      XCTAssertEqual(try rgb(last), try rgb(XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))))
      p.fit = .fit
      let fit1 = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
      p.frames[0].crop.centerX = 0; p.frames[0].crop.centerY = 0
      let fit2 = try await renderer.renderFrame(p.frames[0], project: p, sources: [asset])
      XCTAssertEqual(try rgb(fit1), try rgb(fit2), "Fit does not clip at normal zoom")
    }
    var crop = CropConfiguration(); crop.zoom = 20; crop.centerX = -100; crop.centerY = 100
    let rect = CropGeometry.rect(source: CGSize(width: 1200, height: 800), ratio: 0.5, crop: crop)
    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1200, height: 800).contains(rect))
    XCTAssertEqual(rect.width / rect.height, 0.5, accuracy: 0.00001)
  }
  func testNativeConversionOptInPreservesPixelsAndLegacyMeaning() async throws {
    let root = try folder(), asset = try source(in: root, width: 123, height: 77)
    let processor = ImageProcessor(); var c = ProcessingConfiguration(); c.format = .png
    let old = try await processor.render(asset.url, configuration: c)
    XCTAssertEqual(old.width, 1600); XCTAssertEqual(old.height, 1200)
    c.nativeOutputSizing = true; c.adjustments.exposure = 0.2; c.quarterTurns = 1
    let converted = try await processor.render(asset.url, configuration: c)
    XCTAssertEqual(converted.width, 77); XCTAssertEqual(converted.height, 123)
    let restored = try JSONDecoder().decode(ProcessingConfiguration.self, from: JSONEncoder().encode(c))
    XCTAssertEqual(restored.nativeOutputSizing, true)
    let legacy = try JSONDecoder().decode(ProcessingConfiguration.self, from: Data("{}".utf8))
    XCTAssertNil(legacy.nativeOutputSizing)
    XCTAssertEqual(ImageProcessor.outputSize(source: CGSize(width: 123, height: 77), configuration: legacy), CGSize(width: 1600, height: 1200))
  }
  func testReviewMembershipFollowsFrameDuplicationAndRemoval() {
    var project = GIFProject(); let frame = GIFFrame(sourceID: UUID()); project.frames = [frame]
    project.reviewFrameIDs = [frame.id]; project.privacyReviewFrameIDs = [frame.id]
    project.duplicate(frame.id)
    XCTAssertEqual(project.reviewFrameIDs, Set(project.frames.map(\.id)))
    XCTAssertEqual(project.privacyReviewFrameIDs, Set(project.frames.map(\.id)))
    project.remove(Set(project.frames.map(\.id)))
    XCTAssertEqual(project.reviewFrameIDs, []); XCTAssertEqual(project.privacyReviewFrameIDs, [])
  }
  func testPreviewFailureIdentifiesFrameAndRemovesPartialFiles() async throws {
    let root = try folder(), asset = try source(in: root)
    var p = GIFProject(); p.width = 40; p.height = 40; p.frames = [GIFFrame(sourceID: asset.id), GIFFrame(sourceID: UUID())]
    let temp = FileManager.default.temporaryDirectory
    func previews() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: temp.path).filter { $0.hasPrefix("Ameluma-GIF-Preview-") }) }
    let before = try previews()
    do { _ = try await GIFPreviewBuilder().prepare(p, sources: [asset]); XCTFail("Expected missing frame") }
    catch let error as GIFPreviewFailure { XCTAssertEqual(error.frameID, p.frames[1].id); XCTAssertEqual(error.index, 1) }
    XCTAssertEqual(try previews(), before)
  }
}
