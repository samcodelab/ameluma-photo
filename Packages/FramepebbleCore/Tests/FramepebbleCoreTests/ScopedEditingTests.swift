import CoreGraphics
import ImageIO
import XCTest

@testable import FramepebbleCore

final class ScopedEditingTests: XCTestCase {
  func testFieldPatchPreservesDistinctAuthoredDataAndDimensions() {
    let a = UUID()
    let b = UUID()
    var state = EditingSnapshot()
    var first = state.settings
    first.crop.centerX = 0.2
    first.width = 700
    var mask = PrivacyMask()
    mask.effect = .pixelate
    first.masks = [mask]
    var second = state.settings
    second.crop.centerY = 0.8
    second.height = 900
    second.annotations = [Annotation()]
    second.adjustments.saturation = 0.4
    state.apply(ConfigurationPatch(from: state.settings, to: first), to: a)
    state.apply(ConfigurationPatch(from: state.settings, to: second), to: b)
    var input = first
    input.adjustments.exposure = 0.6
    let change = ConfigurationPatch(values: input, fields: [.adjustments_exposure])
    state.apply(change, to: a)
    state.apply(change, to: b)
    first.adjustments.exposure = 0.6
    second.adjustments.exposure = 0.6
    XCTAssertEqual(state.configuration(for: a), first)
    XCTAssertEqual(state.configuration(for: b), second)
  }
  func testDimensionChangesPreserveTheOtherFixedDimensionAndAspectRule() {
    let fixed = UUID(), aspect = UUID(); var state = EditingSnapshot()
    state.overrides[fixed] = ImageOverride(crop: state.settings.crop, dimensions: PixelDimensions(width: 800, height: 600))
    var crop = state.settings.crop; crop.aspectRatio = 1
    state.overrides[aspect] = ImageOverride(crop: crop, dimensions: PixelDimensions(width: 1600, height: 1600, followsBatchWidth: true))
    var value = state.settings; value.width = 512
    state.apply(ConfigurationPatch(values: value, fields: [.width]), to: fixed)
    state.apply(ConfigurationPatch(values: value, fields: [.width]), to: aspect)
    XCTAssertEqual(state.configuration(for: fixed).width, 512); XCTAssertEqual(state.configuration(for: fixed).height, 600)
    XCTAssertEqual(state.configuration(for: aspect).width, 512); XCTAssertEqual(state.configuration(for: aspect).height, 512)
    state.settings.height = 120; XCTAssertEqual(state.configuration(for: fixed).height, 600)
  }
  func testSparseEncodingPreservesExplicitNilWithoutSavingUnrelatedSettings() throws {
    var batch = ProcessingConfiguration(); batch.targetBytes = 500000; batch.width = 333
    batch.watermark.imageURL = URL(fileURLWithPath: "/tmp/logo.png")
    var values = batch; values.targetBytes = nil; values.watermark.imageURL = nil; values.adjustments.exposure = 0.7
    let patch = ConfigurationPatch(values: values, fields: [.targetBytes, .watermark_imageURL, .adjustments_exposure])
    let data = try JSONEncoder().encode(patch)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let payload = try XCTUnwrap(object["values"] as? [String: Any])
    XCTAssertEqual(Set(payload.keys), ["targetBytes", "watermark.imageURL", "adjustments.exposure"])
    let decoded = try JSONDecoder().decode(ConfigurationPatch.self, from: data)
    XCTAssertEqual(decoded, patch)
    let result = decoded.applying(to: batch)
    XCTAssertNil(result.targetBytes); XCTAssertNil(result.watermark.imageURL)
    XCTAssertEqual(result.width, 333); XCTAssertEqual(result.adjustments.exposure, 0.7)
  }
  func testIndividualRotationKeepsUnrelatedBatchInheritanceAndReset() {
    let id = UUID()
    var state = EditingSnapshot()
    var rotate = state.settings
    rotate.quarterTurns = 1
    state.apply(ConfigurationPatch(values: rotate, fields: [.quarterTurns]), to: id)
    state.settings.width = 1024
    state.settings.height = 1024
    state.settings.format = .png
    state.settings.quality = 0.4
    var expected = state.settings
    expected.quarterTurns = 1
    XCTAssertEqual(state.configuration(for: id), expected)
    state.reset([.orientation], for: id)
    XCTAssertEqual(state.configuration(for: id), state.settings)
    XCTAssertNil(state.overrides[id])
  }
  func testSchemaThreeMigrationPreservesEffectiveOutputAndDynamicDimensions() throws {
    var document = ProjectDocument()
    document.version = 3
    document.edits.settings.width = 1024
    document.edits.settings.quality = 0.5
    let first = UUID()
    let second = UUID()
    var config = document.edits.settings
    config.crop.centerY = 0.7
    config.crop.aspectRatio = 1
    config.masks = [PrivacyMask()]
    config.annotations = [Annotation()]
    config.quarterTurns = 1
    document.edits.overrides[first] = ImageOverride(
      crop: config.crop, processing: config,
      dimensions: PixelDimensions(width: 1024, height: 1024, followsBatchWidth: true))
    var crop = document.edits.settings.crop
    crop.zoom = 2
    document.edits.overrides[second] = ImageOverride(
      crop: crop, dimensions: PixelDimensions(width: 800, height: 600))
    let before = [first, second].map { document.edits.configuration(for: $0) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    try document.save(url)
    var migrated = try ProjectDocument.load(url)
    XCTAssertEqual(migrated.version, 4)
    XCTAssertEqual([first, second].map { migrated.edits.configuration(for: $0) }, before)
    XCTAssertNil(migrated.edits.overrides[first]?.processing)
    migrated.edits.settings.width = 512
    migrated.edits.settings.format = .png
    XCTAssertEqual(migrated.edits.configuration(for: first).height, 512)
    XCTAssertEqual(migrated.edits.configuration(for: first).format, .png)
    XCTAssertEqual(migrated.edits.configuration(for: second).width, 800)
    try migrated.save(url)
    XCTAssertEqual(try ProjectDocument.load(url).edits, migrated.edits)
  }
  func testCategoryCopyIsExplicitAndPreservesOtherCategories() {
    var target = ProcessingConfiguration()
    target.crop.zoom = 2
    target.width = 500
    target.masks = [PrivacyMask()]
    var source = ProcessingConfiguration()
    source.adjustments.exposure = 1
    source.crop.centerX = 0.3
    let copy = ConfigurationPatch(values: source, fields: Set(ConfigurationField.allCases))
      .choosing([.adjustments])
    let result = copy.applying(to: target)
    XCTAssertEqual(result.adjustments, source.adjustments)
    XCTAssertEqual(result.crop, target.crop)
    XCTAssertEqual(result.width, 500)
    XCTAssertEqual(result.masks, target.masks)
  }
  func testShareOperationImmutableOutputsIndependentOfHistory() {
    let first = URL(fileURLWithPath: "/tmp/first.png")
    let second = URL(fileURLWithPath: "/tmp/second.png")
    let operation = ShareOutputSession(outputs: [first, first], summary: "1 exported · 1 failed")
    var history = [first]
    history.append(second)
    XCTAssertEqual(operation.outputs, [first])
    XCTAssertEqual(operation.summary, "1 exported · 1 failed")
    var review = ShareReviewSession(outputs: operation.outputs)
    review.include(second, true)
    review.approve()
    XCTAssertEqual(review.approvedOutputs, [first])
  }
  func testEncodedPreviewMatchesExportGeometryAndByteCount() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let processor = ImageProcessor()
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 320,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    let image = try XCTUnwrap(context.makeImage())
    let original = root.appendingPathComponent("original.jpg")
    let bytes = try await processor.encode(
      image, format: .jpeg, quality: 1, properties: [kCGImagePropertyOrientation: 6])
    try bytes.write(to: original)
    for mode in [CropMode.fit, .fill, .canvas, .manualCrop] {
      var c = ProcessingConfiguration()
      c.width = 37
      c.height = 29
      c.crop.mode = mode
      c.crop.zoom = 1.3
      c.quarterTurns = 1
      c.background = RGBAColour(1, 0, 0, 1)
      c.adjustments.exposure = 0.2
      c.masks = [PrivacyMask()]
      c.watermark.enabled = true
      let preview = try await processor.encodedPreview(original, configuration: c)
      let output = try await processor.export(
        SourceAsset(url: original), configuration: c, to: root)
      let url = try XCTUnwrap(output.output)
      let data = try Data(contentsOf: url)
      let decoded = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
      XCTAssertEqual(preview.image.width, exported.width)
      XCTAssertEqual(preview.image.height, exported.height)
      XCTAssertEqual(
        preview.image.dataProvider?.data as Data?, exported.dataProvider?.data as Data?)
      XCTAssertEqual(preview.byteCount, data.count)
      XCTAssertEqual(exported.width, 37)
      XCTAssertEqual(exported.height, 29)
    }
    XCTAssertEqual(try Data(contentsOf: original), bytes)
  }
}
