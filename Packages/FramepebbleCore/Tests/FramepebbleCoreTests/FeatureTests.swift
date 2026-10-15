import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FramepebbleCore

final class FeatureTests: XCTestCase {
    func testComposedJPEGProofAndReviewedCopiesMatchWithoutOverwriting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try XCTUnwrap(context.makeImage())
        var config = ProcessingConfiguration(); config.width = 32; config.height = 32; config.format = .jpeg; config.quality = 0.8
        let processor = ImageProcessor()
        let proof = try await processor.encodedPreview(image, configuration: config)
        let result = try await processor.publish(image, asset: SourceAsset(url: root.appendingPathComponent("project.json"), name: "Composition.jpg"), configuration: config, to: root, flattenTransparency: true)
        let source = try XCTUnwrap(result.output), originalBytes = try Data(contentsOf: source)
        XCTAssertEqual(proof.byteCount, originalBytes.count)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let reader = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            reader.draw(proof.image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        XCTAssertGreaterThan(pixels[0], 240); XCTAssertGreaterThan(pixels[1], 240); XCTAssertGreaterThan(pixels[2], 240)
        let first = try await processor.copyValidatedOutput(source, to: folder)
        let second = try await processor.copyValidatedOutput(source, to: folder)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), originalBytes)
        XCTAssertEqual(try Data(contentsOf: second), originalBytes)
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".tmp") })
    }
    func testStorageAccountingAndResolvedFilenameAreSafe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = UUID().uuidString + ".png", disposable = UUID().uuidString + ".png"
        try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent(kept))
        try Data(repeating: 2, count: 64).write(to: root.appendingPathComponent(disposable))
        try Data(repeating: 3, count: 1024).write(to: root.appendingPathComponent("original.png"))
        let summary = try await SourceStorageCleanup().summary(in: root, retaining: [kept])
        XCTAssertEqual(summary.managedFiles, 2); XCTAssertEqual(summary.totalBytes, 192)
        XCTAssertEqual(summary.retainedBytes, 128); XCTAssertEqual(summary.removableBytes, 64)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("original.png")).count, 1024)
        let asset = SourceAsset(url: root.appendingPathComponent("a.png"), name: "Holiday Photo.png")
        var profile = ExportProfile(); profile.suffix = "-web"
        let filename = ImageProcessor.proposedFilename(asset: asset, profile: profile, format: .jpeg)
        XCTAssertEqual(filename, "Holiday_Photo-web.jpg")
    }
    func testConstrainedCropHandlesAndCollageTransformsUseSharedGeometry() {
        let source = CGSize(width: 4000, height: 3000)
        let original = CGRect(x: 400, y: 500, width: 1600, height: 900)
        let changed = CropGeometry.resized(original, source: source, handle: .bottomRight, translation: CGSize(width: 500, height: 30), preserveAspect: true)
        XCTAssertEqual(changed.width / changed.height, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertGreaterThan(changed.width, original.width)
        XCTAssertTrue(CGRect(origin: .zero, size: source).contains(changed))
        let cell = CollageCell(sourceID: UUID(), x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let moved = CollageGeometry.moved(cell, translation: CGSize(width: 100, height: 44), viewport: CGSize(width: 1000, height: 500), titleBand: 0.12, snap: false)
        XCTAssertEqual(moved.x, 0.3, accuracy: 0.001); XCTAssertEqual(moved.y, 0.3, accuracy: 0.001)
        let resized = CollageGeometry.resized(cell, handle: .bottomRight, translation: CGSize(width: 100, height: 50), viewport: CGSize(width: 1000, height: 500))
        XCTAssertEqual(resized.sourceID, cell.sourceID)
        XCTAssertEqual(resized.width, 0.4, accuracy: 0.001)
    }
    func testCompositionIdentityInvalidatesOnlyRelevantChanges() {
        let first = SourceAsset(url: URL(fileURLWithPath: "/tmp/first.png"))
        let unrelated = SourceAsset(url: URL(fileURLWithPath: "/tmp/other.png"))
        var project = CollageProject(); project.arrange([first.id], layout: .grid)
        let edits = EditingSnapshot()
        let identity = CollageRenderIdentity(project: project, sources: [first, unrelated], edits: edits)
        var changed = edits; var value = edits.settings; value.adjustments.exposure = 0.5
        changed.apply(ConfigurationPatch(values: value, fields: [.adjustments_exposure]), to: unrelated.id)
        XCTAssertEqual(identity, CollageRenderIdentity(project: project, sources: [first, unrelated], edits: changed))
        changed.apply(ConfigurationPatch(values: value, fields: [.adjustments_exposure]), to: first.id)
        XCTAssertNotEqual(identity, CollageRenderIdentity(project: project, sources: [first, unrelated], edits: changed))
        project.title = "Changed title"
        XCTAssertNotEqual(identity, CollageRenderIdentity(project: project, sources: [first, unrelated], edits: edits))
    }
    func testDirectCropBoundariesRoundTripInTransformedSourceCoordinates() {
        for source in [CGSize(width: 4000, height: 3000), CGSize(width: 3000, height: 4000)] {
            let rectangle = CGRect(x: source.width * 0.1, y: source.height * 0.2,
                                   width: source.width * 0.6, height: source.height * 0.5)
            let crop = CropGeometry.crop(selecting: rectangle, source: source, existing: CropConfiguration())
            let output = CropGeometry.rect(source: source, ratio: crop.aspectRatio ?? 1, crop: crop)
            XCTAssertEqual(output.minX, rectangle.minX, accuracy: 0.001)
            XCTAssertEqual(output.minY, rectangle.minY, accuracy: 0.001)
            XCTAssertEqual(output.width, rectangle.width, accuracy: 0.001)
            XCTAssertEqual(output.height, rectangle.height, accuracy: 0.001)
            XCTAssertEqual(crop.framing, .manual)
        }
    }
    func image(width: Int = 160, height: Int = 80, alpha: CGFloat = 1, profile: CFString = CGColorSpace.sRGB, properties: [CFString: Any] = [:]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: try XCTUnwrap(CGColorSpace(name: profile)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: alpha)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)); CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), properties as CFDictionary); XCTAssertTrue(CGImageDestinationFinalize(dest))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func folder() throws -> URL { let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir }
    func bytes(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try data.withUnsafeMutableBytes { buffer in let ctx = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)); ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) }; return data
    }
    func occupied(_ image: CGImage) throws -> CGRect {
        let b = try bytes(image); var rect = CGRect.null
        for y in 0..<image.height { for x in 0..<image.width where b[(y * image.width + x) * 4 + 3] > 10 { rect = rect.union(CGRect(x: x, y: y, width: 1, height: 1)) } }; return rect
    }
    func testDragIndependentOfDisplayResolution() {
        var crop = CropConfiguration(); crop.mode = .fill
        let one = CropGeometry.dragged(crop, source: CGSize(width: 800, height: 400), frame: CGSize(width: 200, height: 200), translation: CGSize(width: 40, height: 0), ratio: 1)
        let two = CropGeometry.dragged(crop, source: CGSize(width: 4000, height: 2000), frame: CGSize(width: 400, height: 400), translation: CGSize(width: 80, height: 0), ratio: 1)
        XCTAssertEqual(one.centerX, two.centerX, accuracy: 0.000001); XCTAssertEqual(one.centerX, 0.4, accuracy: 0.000001); XCTAssertEqual(one.framing, .manual)
    }
    func testDragClampsAndZeroMovementDoesNotShift() {
        var crop = CropConfiguration(); crop.mode = .fill
        let zero = CropGeometry.dragged(crop, source: CGSize(width: 800, height: 400), frame: CGSize(width: 200, height: 200), translation: .zero, ratio: 1)
        XCTAssertEqual(zero.centerX, 0.5)
        let edge = CropGeometry.dragged(crop, source: CGSize(width: 800, height: 400), frame: CGSize(width: 200, height: 200), translation: CGSize(width: 10000, height: -10000), ratio: 1)
        XCTAssertEqual(edge.centerX, 0.25); XCTAssertEqual(edge.centerY, 0.5)
        XCTAssertEqual(CropGeometry.zoomed(crop, factor: 100).zoom, 20)
        XCTAssertEqual(CropGeometry.zoomed(crop, factor: 0.1).zoom, 1)
    }
    func testHistorySynchronizesPrecisionAndGridPreservesOverrides() {
        let id = UUID(); var history = EditingHistory(); var state = history.current
        var crop = CropConfiguration(); crop.centerX = 0.7; crop.zoom = 2; crop.framing = .manual
        state.overrides[id] = ImageOverride(crop: crop); history.apply(state)
        state.settings.quality = 0.4; state.settings.width = 1024; state.settings.height = 1024; history.apply(state)
        XCTAssertEqual(history.current.configuration(for: id).crop, crop); XCTAssertEqual(history.current.configuration(for: id).quality, 0.4)
        history.undo(); XCTAssertEqual(history.current.settings.quality, 0.85); XCTAssertEqual(history.current.configuration(for: id).crop, crop)
        history.redo(); XCTAssertEqual(history.current.configuration(for: id).quality, 0.4)
        var reset = history.current; reset.overrides.removeValue(forKey: id); history.apply(reset)
        XCTAssertEqual(history.current.configuration(for: id).crop, reset.settings.crop)
        history.undo(); XCTAssertEqual(history.current.configuration(for: id).crop, crop)
    }
    func testAutoFrameFallbackAndSubjectBounds() {
        let source = CGSize(width: 800, height: 400)
        let fallback = AutoFramingGeometry.propose(source: source, ratio: 1, subjects: [], mode: .smart)
        XCTAssertTrue(fallback.needsReview); XCTAssertEqual(fallback.crop.centerX, 0.5)
        let subjects = [CGRect(x: 0.05, y: 0.2, width: 0.2, height: 0.4), CGRect(x: 0.75, y: 0.2, width: 0.2, height: 0.4)]
        let proposal = AutoFramingGeometry.propose(source: source, ratio: 1, subjects: subjects, mode: .keepSubjects)
        XCTAssertTrue(proposal.needsReview); XCTAssertTrue(CGRect(origin: .zero, size: source).contains(CropGeometry.rect(source: source, ratio: 1, crop: proposal.crop)))
        let fit = AutoFramingGeometry.propose(source: source, ratio: 2, subjects: subjects, mode: .keepSubjects)
        XCTAssertFalse(fit.needsReview)
    }
    func testClassificationFilteringRankingAndInvalidation() {
        let a = UUID(); let b = UUID(); let missing = UUID(); var index = ClassificationIndex()
        let fp = SourceFingerprint(bytes: 10, modified: .distantPast)
        index.insert(ClassificationRecord(assetID: a, labels: [ClassificationLabel("dog", confidence: 0.9), ClassificationLabel("beach", confidence: 0.7)], revision: 1, fingerprint: fp))
        index.insert(ClassificationRecord(assetID: b, labels: [ClassificationLabel("dog", confidence: 0.4), ClassificationLabel("cat", confidence: 0.05)], revision: 1, fingerprint: fp))
        XCTAssertEqual(index.matches(query: "DOG", candidates: [b,missing,a]), [a,b])
        XCTAssertEqual(index.matches(query: "dog beach", candidates: [b,a]), [a])
        XCTAssertTrue(index.matches(query: "cat", candidates: [a,b]).isEmpty)
        XCTAssertTrue(index.matches(query: "arbitrary phrase", candidates: [a,b]).isEmpty)
        index.invalidate(a); XCTAssertEqual(index.matches(query: "dog", candidates: [a,b]), [b])
    }
    func testNativeVisionReturnsRealRecordAndCancellation() async throws {
        let url = try image(); let asset = SourceAsset(url: url); let cg = try await ImageProcessor().thumbnail(url, maximum: 200); let analyzer = VisionAnalyzer()
        let record = try await analyzer.classify(cg, asset: asset)
        XCTAssertEqual(record.assetID, asset.id); XCTAssertGreaterThan(record.revision, 0); XCTAssertTrue(record.labels.allSatisfy { !$0.identifier.isEmpty && (0...1).contains($0.confidence) })
        let task = Task { try Task.checkCancellation(); return try await analyzer.classify(cg, asset: asset) }; task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let proposal = try await analyzer.frame(cg, ratio: 1, mode: .smart)
        XCTAssertTrue((0...1).contains(proposal.crop.centerX)); XCTAssertTrue((0...1).contains(proposal.crop.centerY))
    }
    func testConcurrentClassificationIsBoundedAndRecordsDistinct() async throws {
        let url = try image(); let cg = try await ImageProcessor().thumbnail(url); let analyzer = VisionAnalyzer(); let a = SourceAsset(url: url); let b = SourceAsset(url: url)
        async let first = analyzer.classify(cg, asset: a); async let second = analyzer.classify(cg, asset: b)
        let results = try await [first,second]; XCTAssertEqual(Set(results.map(\.assetID)), [a.id,b.id])
    }
    func testFingerprintChangesWithSourceAndNestedFolders() async throws {
        let dir = try folder(); let sub = dir.appendingPathComponent("nested"); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let original = try image(); let copy = sub.appendingPathComponent("image.png"); try FileManager.default.copyItem(at: original, to: copy)
        do { _ = try await ImageProcessor(maximumSourcePixels: 1000).identify(copy); XCTFail() } catch { XCTAssertEqual(error as? ProcessingError, .sourceTooLarge) }
        let old = try SourceFingerprint.read(copy); try Data("not an image".utf8).write(to: copy); XCTAssertNotEqual(try SourceFingerprint.read(copy), old)
        let listing = try await ImageProcessor().folderImages(dir); XCTAssertEqual(listing.map { $0.resolvingSymlinksInPath() }, [copy.resolvingSymlinksInPath()])
        do { _ = try await ImageProcessor().identify(copy); XCTFail() } catch { XCTAssertTrue(error is ProcessingError) }
    }
    func testResizeBasisStretchCanvasPreventUpscaleAndExtremeRatio() async throws {
        let url = try image(); let engine = ImageProcessor(); var c = ProcessingConfiguration(); c.width = 40; c.height = 30; c.crop.mode = .preserveAspectRatio; c.resizeBasis = .height
        var result = try await engine.render(url, configuration: c); XCTAssertEqual(result.width,60); XCTAssertEqual(result.height,30)
        c.resizeBasis = .percentage; c.percentage = 50
        result = try await engine.render(url, configuration: c, previewMaximum: 100); XCTAssertEqual(result.width,80); XCTAssertEqual(result.height,40)
        c.crop.mode = .stretch; c.width = 10; c.height = 100
        result = try await engine.render(url, configuration: c); XCTAssertEqual(result.width,10); XCTAssertEqual(result.height,100)
        c.crop.mode = .canvas; c.width = 400; c.height = 400; c.format = .png; c.preventUpscaling = true; c.canvasAlignment = .topLeft
        result = try await engine.render(url, configuration: c); let bounds = try occupied(result)
        XCTAssertEqual(bounds.width,160); XCTAssertEqual(bounds.height,80)
        c.crop.mode = .fill; c.width = 200; c.height = 1; c.preventUpscaling = false
        result = try await engine.render(url, configuration: c); XCTAssertEqual(result.width,200); XCTAssertEqual(result.height,1)
    }
    func testFlipAndStraighteningKeepValidDimensions() async throws {
        let url = try image(); var c = ProcessingConfiguration(); c.width = 100; c.height = 100; c.crop.mode = .fill; c.crop.flipHorizontal = true; c.crop.flipVertical = true; c.crop.straighten = 12
        let result = try await ImageProcessor().render(url, configuration: c); XCTAssertEqual(result.width,100); XCTAssertEqual(result.height,100)
    }
    func testWatermarkNinePositionsAndRelativeMargins() {
        for anchor in WatermarkAnchor.allCases {
            var w = WatermarkConfiguration(); w.anchor = anchor; w.margin = 0.1
            let rect = WatermarkRenderer.placement(size: CGSize(width: 20,height: 10), output: CGSize(width:100,height:100), configuration:w)
            XCTAssertTrue(CGRect(x:0,y:0,width:100,height:100).contains(rect))
            XCTAssertEqual(rect.minX, [10.0,40.0,70.0][anchor.rawValue % 3]); XCTAssertEqual(rect.minY,[10.0,45.0,80.0][anchor.rawValue / 3])
        }
    }
    func testImageWatermarkOpacityRotationAndPreviewConsistency() async throws {
        let source = try image(alpha: 0); let logo = try image(width: 40,height:20); let engine = ImageProcessor(); var c = ProcessingConfiguration()
        c.width = 400; c.height = 400; c.format = .png; c.watermark.enabled = true; c.watermark.kind = .image; c.watermark.imageURL = logo; c.watermark.relativeWidth = 0.25; c.watermark.opacity = 0.5
        let final = try await engine.render(source,configuration:c); let preview = try await engine.render(source,configuration:c,previewMaximum:200)
        let f = try occupied(final); let p = try occupied(preview)
        XCTAssertEqual(f.minX / 400,p.minX / 200,accuracy:0.01); XCTAssertEqual(f.minY / 400,p.minY / 200,accuracy:0.01); XCTAssertEqual(f.width / 400,p.width / 200,accuracy:0.01)
        let pixels = try bytes(final); let alpha = pixels[(Int(f.midY) * 400 + Int(f.midX)) * 4 + 3]; XCTAssertEqual(Int(alpha),128,accuracy:2)
        c.watermark.rotation = 90
        let rotated = try await engine.render(source,configuration:c); let r = try occupied(rotated); XCTAssertEqual(r.width,f.height,accuracy:2); XCTAssertEqual(r.height,f.width,accuracy:2)
        c.watermark.tiled = true
        let tiled = try await engine.render(source,configuration:c); XCTAssertGreaterThan(try occupied(tiled).width, r.width)
    }
    func testTextWatermarkProducesPixelsAndScales() async throws {
        let source = try image(alpha:0); var c = ProcessingConfiguration(); c.width = 400; c.height = 200; c.format = .png; c.watermark.enabled = true; c.watermark.text = "Framepebble"; c.watermark.anchor = .centre
        let image = try await ImageProcessor().render(source,configuration:c); let rect = try occupied(image); XCTAssertFalse(rect.isNull); XCTAssertGreaterThan(rect.width,70); XCTAssertLessThan(rect.width,110)
        var large = WatermarkConfiguration(); large.text = "MMMM"; large.relativeWidth = 1
        XCTAssertThrowsError(try WatermarkRenderer.stamp(large, outputWidth: 20000))
    }
    func testTargetSizeFailurePreservesOriginalAndPublishesNothing() async throws {
        let source = try image(); let original = try Data(contentsOf:source); let dir = try folder(); var c = ProcessingConfiguration(); c.width=100;c.height=100;c.targetBytes=1
        do { _ = try await ImageProcessor().export(SourceAsset(url:source),configuration:c,to:dir); XCTFail() } catch { XCTAssertEqual(error as? ProcessingError,.targetSizeUnreachable) }
        XCTAssertEqual(try Data(contentsOf:source),original); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:dir.path).isEmpty)
        c.targetBytes=100000
        let success=try await ImageProcessor().export(SourceAsset(url:source),configuration:c,to:dir); XCTAssertLessThanOrEqual(try Data(contentsOf: XCTUnwrap(success.output)).count,100000)
    }
    func testRGBProfilePreservedOrConverted() async throws {
        let source=try image(profile: CGColorSpace.displayP3); var c=ProcessingConfiguration(); c.width=80;c.height=40;c.format = .png;c.colourPolicy = .preserve
        let engine=ImageProcessor(); let preserved=try await engine.render(source,configuration:c); XCTAssertEqual(preserved.colorSpace?.name,CGColorSpace.displayP3)
        c.colourPolicy = .sRGB;let converted=try await engine.render(source,configuration:c);XCTAssertEqual(converted.colorSpace?.name,CGColorSpace.sRGB)
    }
    func testGPSMetadataPolicies() async throws {
        let source=try image(properties:[kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:33.0,kCGImagePropertyGPSLatitudeRef:"S",kCGImagePropertyGPSLongitude:151.0,kCGImagePropertyGPSLongitudeRef:"E"]]);let dir=try folder();let engine=ImageProcessor();var c=ProcessingConfiguration();c.width=80;c.height=40
        for policy in MetadataPolicy.allCases { c.metadata=policy;let r=try await engine.export(SourceAsset(url:source),configuration:c,to:dir);let cg=try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(r.output) as CFURL,nil));let props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(cg,0,nil) as? [CFString:Any]); if policy == .preserve { XCTAssertNotNil(props[kCGImagePropertyGPSDictionary]) } else { XCTAssertNil(props[kCGImagePropertyGPSDictionary]) };XCTAssertEqual(props[kCGImagePropertyOrientation] as? Int,1) }
    }
    func testVersionedProjectRoundTripPendingRequestsAndMissingSources() throws {
        let dir=try folder();let url=dir.appendingPathComponent("project.json");var doc=ProjectDocument();let source=SourceAsset(url:dir.appendingPathComponent("missing.png"));doc.sources=[source];doc.edits.settings.watermark.enabled=true;doc.pendingExports=[ExportRequest(source:source,configuration:doc.edits.settings,profile:ExportProfile())]
        try doc.save(url);let loaded=try ProjectDocument.load(url);XCTAssertEqual(loaded.version,4);XCTAssertEqual(loaded.pendingExports.count,1);XCTAssertEqual(loaded.sources,[source]);XCTAssertTrue(loaded.edits.settings.watermark.enabled)
        doc.version=99;try doc.save(url);XCTAssertThrowsError(try ProjectDocument.load(url))
    }
    func testAdditiveConfigurationMigrationAndRotatedIntent() throws {
        let json = Data("{\"width\":512,\"height\":512,\"crop\":{\"centerX\":0.7,\"centerY\":0.3}}".utf8)
        let c = try JSONDecoder().decode(ProcessingConfiguration.self, from: json)
        XCTAssertEqual(c.width, 512); XCTAssertFalse(c.flipHorizontal); XCTAssertEqual(c.crop.zoom, 1)
        let clockwise = CropGeometry.rotated(c.crop, turns: 1)
        XCTAssertEqual(clockwise.centerX, 0.7, accuracy: 0.00001); XCTAssertEqual(clockwise.centerY, 0.7, accuracy: 0.00001)
        XCTAssertEqual(CropGeometry.rotated(clockwise, turns: -1).centerY, 0.3, accuracy: 0.00001)
    }
    func testBoundedTargetEncodingActuallySearchesQuality() async throws {
        let width = 256; var data = [UInt8](repeating: 255, count: width * width * 4); var seed: UInt32 = 7
        for pixel in 0..<(width * width) { for component in 0..<3 { seed = seed &* 1664525 &+ 1013904223; data[pixel * 4 + component] = UInt8(truncatingIfNeeded: seed >> 24) } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(data) as CFData))
        let cg = try XCTUnwrap(CGImage(width: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let dir = try folder(); let source = dir.appendingPathComponent("noise.png"); let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)); CGImageDestinationAddImage(dest, cg, nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        let engine = ImageProcessor(); let high = try await engine.encode(cg, format: .jpeg, quality: 0.95); let low = try await engine.encode(cg, format: .jpeg, quality: 0.35)
        var c = ProcessingConfiguration(); c.width = width; c.height = width; c.quality = 0.95; c.targetBytes = (high.count + low.count) / 2
        let result = try await engine.export(SourceAsset(url: source), configuration: c, to: dir)
        let count = try Data(contentsOf: XCTUnwrap(result.output)).count
        XCTAssertLessThanOrEqual(count, try XCTUnwrap(c.targetBytes)); XCTAssertGreaterThan(count, low.count)
    }

    func testSharedLayoutAlignsSubjectGuidesCanvasAndPreventUpscaleDrag() {
        var c = ProcessingConfiguration(); c.crop.mode = .fit
        var layout = FramingLayout(source: CGSize(width: 800,height:400), output: CGSize(width:400,height:400), configuration:c)
        XCTAssertEqual(layout.contentRect, CGRect(x:0,y:100,width:400,height:200))
        XCTAssertEqual(layout.normalizedSubjectInOutput(CGRect(x:0,y:0,width:1,height:1)),layout.contentRect)
        c.crop.mode = .canvas; c.preventUpscaling = true; c.canvasAlignment = .topRight
        layout = FramingLayout(source:CGSize(width:80,height:40),output:CGSize(width:400,height:400),configuration:c)
        XCTAssertEqual(layout.contentRect,CGRect(x:320,y:0,width:80,height:40))
        var crop=CropConfiguration();crop.mode = .fill
        let dragged=CropGeometry.dragged(crop,source:CGSize(width:80,height:40),frame:CGSize(width:200,height:200),translation:CGSize(width:2,height:0),ratio:1,nativeOutput:CGSize(width:1600,height:1600),preventUpscaling:true)
        XCTAssertEqual(dragged.centerX,0.3,accuracy:0.00001)
    }

}

extension FeatureTests {
    func testHistoryTimelineNamesChangesAndLimitsMemory() throws {
        var history = EditingHistory()
        var snapshot = history.current
        snapshot.settings.adjustments.exposure = 0.5
        history.apply(snapshot)
        XCTAssertTrue(history.steps.last?.title.contains("Exposure") == true)
        let first = try XCTUnwrap(history.steps.first?.id)
        let edited = try XCTUnwrap(history.steps.last?.id)
        history.move(to: first)
        XCTAssertEqual(history.current, EditingSnapshot())
        XCTAssertTrue(history.steps.last?.isRedo == true)
        history.move(to: edited)
        XCTAssertEqual(history.current, snapshot)
        for index in 0..<100 {
            snapshot.settings.quality = Double(index) / 100
            history.apply(snapshot)
        }
        XCTAssertEqual(history.steps.count, 81)
        XCTAssertFalse(history.steps.contains { $0.id == first })
    }
}
