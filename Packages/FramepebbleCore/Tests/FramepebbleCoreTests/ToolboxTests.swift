import CoreImage
import ImageIO
import XCTest

@testable import FramepebbleCore

final class ToolboxTests: XCTestCase {
  func testNeutralAdjustmentsAndBounds() throws {
    let base = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(
      to: CGRect(x: 0, y: 0, width: 16, height: 16))
    let output = try PhotoAdjustments().apply(to: base)
    let ctx = CIContext()
    let a = try XCTUnwrap(ctx.createCGImage(base, from: base.extent))
    let b = try XCTUnwrap(ctx.createCGImage(output, from: output.extent))
    XCTAssertEqual(a.dataProvider?.data as Data?, b.dataProvider?.data as Data?)
    var c = PhotoAdjustments()
    c.exposure = .nan
    XCTAssertThrowsError(try c.validate())
    c.exposure = 3
    XCTAssertThrowsError(try c.validate())
  }
  func testAdjustmentsChangePixelsAndPreserveSource() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let original = try Data(contentsOf: url)
    var c = ProcessingConfiguration()
    c.width = 40
    c.height = 20
    c.format = .png
    let engine = ImageProcessor()
    let neutral = try await engine.render(url, configuration: c)
    c.adjustments.exposure = -1
    c.adjustments.saturation = 0.5
    c.adjustments.warmth = 0.2
    c.adjustments.shadows = 0.2
    c.adjustments.highlights = 0.8
    let result = try await engine.render(url, configuration: c)
    let preview = try await engine.render(url, configuration: c, previewMaximum: 100)
    XCTAssertNotEqual(try helper.pixels(neutral), try helper.pixels(result))
    XCTAssertEqual(try helper.pixels(result), try helper.pixels(preview))
    XCTAssertEqual(try Data(contentsOf: url), original)
  }
  func testOpaqueMaskCoverageAndFlattenedMetadata() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let original = try Data(contentsOf: url)
    var c = ProcessingConfiguration()
    c.width = 40
    c.height = 20
    c.format = .png
    c.metadata = .preserve
    var m = PrivacyMask()
    m.x = 0
    m.y = 0
    m.width = 1
    m.height = 1
    c.masks = [m]
    let engine = ImageProcessor()
    let image = try await engine.render(url, configuration: c)
    XCTAssertEqual(Array(try helper.pixels(image).prefix(4)), [0, 0, 0, 255])
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let result = try await engine.export(SourceAsset(url: url), configuration: c, to: dir)
    let source = try XCTUnwrap(
      CGImageSourceCreateWithURL(try XCTUnwrap(result.output) as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetCount(source), 1)
    let props = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    XCTAssertNil(props[kCGImagePropertyGPSDictionary])
    let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
    XCTAssertNil(exif?[kCGImagePropertyExifMakerNote])
    XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
    XCTAssertEqual(try Data(contentsOf: url), original)
  }
  func testMaskEffectsShapesAndInvalidGeometry() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let engine = ImageProcessor()
    var c = ProcessingConfiguration()
    c.width = 40
    c.height = 20
    for effect in MaskEffect.allCases {
      var m = PrivacyMask()
      m.effect = effect
      m.shape = .ellipse
      m.rotation = 30
      c.masks = [m]
      let image = try await engine.render(url, configuration: c)
      XCTAssertEqual(image.width, 40)
    }
    c.masks[0].strength = .infinity
    do {
      _ = try await engine.render(url, configuration: c)
      XCTFail()
    } catch { XCTAssertTrue(error is ProcessingError) }
  }
  func testAnnotationsAllKindsAndPersistenceMigration() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    var c = ProcessingConfiguration()
    c.width = 200
    c.height = 100
    for kind in AnnotationKind.allCases {
      var a = Annotation()
      a.kind = kind
      a.points = [NormalizedPoint(0.1, 0.1), NormalizedPoint(0.8, 0.8)]
      a.rotation = 20
      a.opacity = 0.6
      c.annotations = [a]
      let image = try await ImageProcessor().render(url, configuration: c)
      XCTAssertEqual(image.height, 100)
    }
    let data = try JSONEncoder().encode(c)
    XCTAssertEqual(try JSONDecoder().decode(ProcessingConfiguration.self, from: data), c)
    let old = try JSONDecoder().decode(ProcessingConfiguration.self, from: Data("{}".utf8))
    XCTAssertEqual(old.adjustments, PhotoAdjustments())
    XCTAssertTrue(old.masks.isEmpty)
  }
  func testCanvasCornersAndBorders() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    var c = ProcessingConfiguration()
    c.width = 40
    c.height = 40
    c.format = .png
    c.canvasStyle.cornerRadius = 0.2
    c.canvasStyle.border = 0.05
    let image = try await ImageProcessor().render(url, configuration: c)
    XCTAssertEqual(try helper.pixels(image)[3], 0)
  }
  func testCollageEightImagesLayoutsFramingTitleAndDimensions() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let assets = (0..<8).map { SourceAsset(url: url, name: "Photo\($0).png") }
    var project = CollageProject()
    project.width = 320
    project.height = 240
    project.title = "Family"
    let engine = ImageProcessor()
    for layout in CollageLayout.allCases {
      project.arrange(assets.map(\.id), layout: layout)
      XCTAssertEqual(project.cells.count, 8)
      project.cells[0].crop.zoom = 2
      let image = try await engine.renderCollage(project, sources: assets, edits: EditingSnapshot())
      XCTAssertEqual(image.width, 320)
      XCTAssertEqual(image.height, 240)
    }
    let decoded = try JSONDecoder().decode(CollageProject.self, from: JSONEncoder().encode(project))
    XCTAssertEqual(decoded, project)
  }
  func testCollageCancellationAndMissingSource() async throws {
    var p = CollageProject()
    p.arrange([UUID()], layout: .grid)
    do {
      _ = try await ImageProcessor().renderCollage(p, sources: [], edits: EditingSnapshot())
      XCTFail()
    } catch { XCTAssertTrue(error is ProcessingError) }
    let task = Task {
      try Task.checkCancellation()
      return try await ImageProcessor().renderCollage(p, sources: [], edits: EditingSnapshot())
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail()
    } catch { XCTAssertTrue(error is CancellationError) }
  }
}

extension ToolboxTests {
  func testDuplicateHashIndependentOfNamesAndCancellation() async throws {
    let helper = ProcessingTests()
    let first = try helper.fixture()
    let second = first.deletingLastPathComponent().appendingPathComponent(
      UUID().uuidString + ".png")
    try FileManager.default.copyItem(at: first, to: second)
    defer {
      try? FileManager.default.removeItem(at: first)
      try? FileManager.default.removeItem(at: second)
    }
    XCTAssertEqual(try ContentDigest.read(first), try ContentDigest.read(second))
    let index = DuplicateIndex()
    let a = try await index.insert(first)
    let b = try await index.insert(second)
    XCTAssertTrue(a)
    XCTAssertFalse(b)
    let task = Task {
      try Task.checkCancellation()
      return try ContentDigest.read(first)
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail()
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testAutomationLoopSafetyAndTransferStability() throws {
    let root = URL(fileURLWithPath: "/tmp/incoming")
    XCTAssertTrue(AutomationSafety.overlaps(root, root.appendingPathComponent("outputs")))
    XCTAssertTrue(AutomationSafety.overlaps(root, root))
    XCTAssertFalse(AutomationSafety.overlaps(root, URL(fileURLWithPath: "/tmp/incoming-other")))
    var tracker = FileStabilityTracker()
    let one = SourceFingerprint(bytes: 10, modified: Date(timeIntervalSince1970: 1))
    let two = SourceFingerprint(bytes: 20, modified: Date(timeIntervalSince1970: 2))
    XCTAssertFalse(tracker.stable(root, fingerprint: one, now: Date(timeIntervalSince1970: 0)))
    XCTAssertFalse(tracker.stable(root, fingerprint: two, now: Date(timeIntervalSince1970: 1)))
    XCTAssertFalse(tracker.stable(root, fingerprint: two, now: Date(timeIntervalSince1970: 2)))
    XCTAssertTrue(tracker.stable(root, fingerprint: two, now: Date(timeIntervalSince1970: 3)))
  }
  func testPrivateModeBypassesThumbnailCache() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let engine = ImageProcessor()
    let a = try await engine.thumbnail(url)
    let b = try await engine.thumbnail(url)
    XCTAssertTrue(a === b)
    await engine.setPrivateMode(true)
    let c = try await engine.thumbnail(url)
    let d = try await engine.thumbnail(url)
    XCTAssertFalse(c === d)
  }
}
extension ToolboxTests {
  func testLegacyProjectMigratesWithoutLosingFraming() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(
      "{\"version\":2,\"edits\":{\"settings\":{\"width\":512,\"height\":512},\"overrides\":[]}}"
        .utf8
    ).write(to: url)
    let doc = try ProjectDocument.load(url)
    XCTAssertEqual(doc.version, 4)
    XCTAssertEqual(doc.edits.settings.width, 512)
    XCTAssertTrue(doc.edits.settings.masks.isEmpty)
  }
}
extension ToolboxTests {
  func testQuickFixProducesRealBoundedAdjustments() async throws {
    let helper = ProcessingTests()
    let url = try helper.fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let engine = ImageProcessor()
    let c = ProcessingConfiguration()
    let lighting = try await engine.quickFix(.lighting, url: url, configuration: c)
    XCTAssertNotEqual(lighting.adjustments, PhotoAdjustments())
    try lighting.adjustments.validate()
    let colour = try await engine.quickFix(.colour, url: url, configuration: c)
    XCTAssertNotEqual(colour.adjustments.warmth, 0)
    XCTAssertLessThanOrEqual(abs(colour.adjustments.warmth), 0.25)
    let sharing = try await engine.quickFix(.sharing, url: url, configuration: c)
    XCTAssertEqual(sharing.width, 1600)
    XCTAssertEqual(sharing.metadata, .removeLocation)
  }
}
extension ToolboxTests {
  func testBlurPixelateAndFreehandAffectOnlySelectedOutputRegion() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for y in 0..<64 {
      for x in 0..<64 {
        ctx.setFillColor(
          (x + y) % 2 == 0
            ? CGColor(red: 1, green: 0, blue: 0, alpha: 1)
            : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    let source = try XCTUnwrap(ctx.makeImage())
    let base = CIImage(cgImage: source)
    let renderer = CIContext()
    let helper = ProcessingTests()
    let original = try helper.pixels(source)
    for effect in [MaskEffect.blur, .pixelate, .frosted] {
      var m = PrivacyMask()
      m.effect = effect
      m.strength = 1
      let image = try PrivacyRenderer.apply(to: base, masks: [m])
      let cg = try XCTUnwrap(renderer.createCGImage(image, from: base.extent))
      let pixels = try helper.pixels(cg)
      let centre = (32 * 64 + 32) * 4
      XCTAssertNotEqual(Array(pixels[centre..<centre + 4]), Array(original[centre..<centre + 4]))
      XCTAssertEqual(Array(pixels.prefix(4)), Array(original.prefix(4)))
    }
    var m = PrivacyMask()
    m.shape = .freehand
    m.points = [
      NormalizedPoint(0, 0), NormalizedPoint(1, 0), NormalizedPoint(1, 1), NormalizedPoint(0, 1),
    ]
    let masked = try PrivacyRenderer.apply(to: base, masks: [m])
    let cg = try XCTUnwrap(renderer.createCGImage(masked, from: base.extent))
    let pixels = try helper.pixels(cg)
    let centre = (32 * 64 + 32) * 4
    XCTAssertEqual(Array(pixels[centre..<centre + 4]), [0, 0, 0, 255])
    XCTAssertEqual(Array(pixels.prefix(4)), Array(original.prefix(4)))
  }
}
extension ToolboxTests {
  func testManualReviewNeverApprovesUntilExplicitConsentAndRevokesOnExclusion() {
    let a = URL(fileURLWithPath: "/tmp/final-a.png")
    let b = URL(fileURLWithPath: "/tmp/final-b.png")
    var review = ShareReviewSession(outputs: [a, b])
    XCTAssertTrue(review.approvedOutputs.isEmpty)
    review.revealed.insert(a)
    XCTAssertTrue(review.approvedOutputs.isEmpty)
    review.include(b, false)
    review.approve()
    XCTAssertEqual(review.approvedOutputs, [a])
    review.include(b, true)
    XCTAssertTrue(review.approvedOutputs.isEmpty)
    review.approve()
    XCTAssertEqual(review.approvedOutputs, [a, b])
    review.include(a, false)
    review.include(b, false)
    review.approve()
    XCTAssertTrue(review.approvedOutputs.isEmpty)
  }
}
extension ToolboxTests {
  func testAutomationDisabledActionsAndNativeFormatValidation() throws {
    var recipe = AutomationRecipe()
    recipe.resizeEnabled = false
    recipe.convertEnabled = false
    recipe.compressionEnabled = false
    recipe.watermarkEnabled = false
    recipe.metadataEnabled = false
    recipe.configuration.watermark.enabled = true
    recipe.configuration.targetBytes = 500
    let c = try recipe.processingConfiguration(sourceFormat: .png)
    XCTAssertEqual(c.crop.mode, .preserveAspectRatio)
    XCTAssertEqual(c.resizeBasis, .percentage)
    XCTAssertEqual(c.percentage, 100)
    XCTAssertEqual(c.format, .png)
    XCTAssertNil(c.targetBytes)
    XCTAssertEqual(c.quality, 1)
    XCTAssertFalse(c.watermark.enabled)
    XCTAssertEqual(c.metadata, .preserve)
    XCTAssertThrowsError(try recipe.processingConfiguration(sourceFormat: nil))
    recipe.configuration.crop.framing = .smart
    XCTAssertThrowsError(try recipe.processingConfiguration(sourceFormat: .png))
  }
}
extension ToolboxTests {
  func testNewViewportKeepsPerImageOrientation() {
    var original = CropConfiguration()
    original.quarterTurns = 3
    original.flipHorizontal = true
    original.straighten = 7
    var proposed = CropConfiguration()
    proposed.centerX = 0.3
    proposed.zoom = 2
    let value = original.adoptingGeometry(proposed)
    XCTAssertEqual(value.quarterTurns, 3)
    XCTAssertTrue(value.flipHorizontal)
    XCTAssertEqual(value.straighten, 7)
    XCTAssertEqual(value.centerX, 0.3)
    XCTAssertEqual(value.zoom, 2)
  }
}
extension ToolboxTests {
    func testStagingCollisionNeverDeletesExistingSource() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);let original=Data("original image bytes".utf8);try original.write(to:url);defer{try? FileManager.default.removeItem(at:url)}
        XCTAssertThrowsError(try StagingWriter.write(Data("replacement".utf8),to:url));XCTAssertEqual(try Data(contentsOf:url),original)
    }
}
extension ToolboxTests {
    func testRemoteImageAndProjectURLsAreRejectedWithoutFetching() async throws {
        let url=try XCTUnwrap(URL(string:"https://example.invalid/image.png"))
        do{_ = try await ImageProcessor().identify(url);XCTFail()}catch{XCTAssertTrue(error is ProcessingError)}
        XCTAssertThrowsError(try SourceFingerprint.read(url));XCTAssertThrowsError(try ContentDigest.read(url));XCTAssertThrowsError(try ProjectDocument.load(url))
        var w=WatermarkConfiguration();w.kind = .image;w.imageURL=url;XCTAssertThrowsError(try WatermarkRenderer.stamp(w,outputWidth:100))
    }
}
extension ToolboxTests {
    func testSymlinkImportCreatesIndependentValidatedSnapshot() async throws {
        let helper=ProcessingTests();let original=try helper.fixture();let bytes=try Data(contentsOf:original);let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder);try? FileManager.default.removeItem(at:original)}
        let link=folder.appendingPathComponent("reference.png");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:original);let engine=ImageProcessor();let asset=try await engine.importSnapshot(link,to:folder)
        XCTAssertEqual(try Data(contentsOf:asset.url),bytes);XCTAssertFalse(try asset.url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink==true)
        try Data("external change".utf8).write(to:original);let size=try await engine.identify(asset.url);XCTAssertEqual(size,CGSize(width:80,height:40))
    }
}
