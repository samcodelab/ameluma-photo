import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FramepebbleCore
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class EditorUsabilityTests: XCTestCase {
  func testCompletedNumericSessionUndoesMultipleLiveValuesTogether() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: directory)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: directory) }
    let source = SourceAsset(url: directory.appendingPathComponent("photo.png"))
    model.assets = [source]; model.openPhoto(source)
    model.selectCreativeFilter("essentials.clean")
    let baseline = model.configuration(for: source)
    XCTAssertFalse(model.interactionInProgress)
    model.beginInteraction()
    XCTAssertTrue(model.interactionInProgress)
    model.setFilterIntensity(0.2)
    model.setFilterIntensity(0.25)
    model.setFilterIntensity(0.3)
    model.endInteraction()
    XCTAssertFalse(model.interactionInProgress)
    XCTAssertEqual(model.configuration(for: source).filterEdit?.intensity, 0.3)
    model.undo()
    XCTAssertEqual(model.configuration(for: source), baseline)
    model.redo()
    XCTAssertEqual(model.configuration(for: source).filterEdit?.intensity, 0.3)
  }

  func testRetouchComparisonKeepsCurrentProtectiveOverlaysAndOtherEdits() {
    var original = ProcessingConfiguration()
    original.retouchStrokes = [RetouchStroke()]
    var current = original
    current.retouchStrokes.append(RetouchStroke())
    current.masks = [PrivacyMask()]
    current.annotations = [Annotation()]
    current.watermark.enabled = true
    current.adjustments.exposure = 0.4
    let compared = OverlayPreviewRequest.beforeRetouch(current: current, original: original)
    XCTAssertEqual(compared.retouchStrokes, original.retouchStrokes)
    var expected = current; expected.retouchStrokes = original.retouchStrokes
    XCTAssertEqual(compared, expected)
    XCTAssertEqual(current.retouchStrokes.count, 2, "Comparing never modifies committed or draft instructions")
  }

  func testNormalPreviewHonorsDetailBudgetWithoutChangingCropPreviewLimits() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: directory)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: directory) }
    let asset = SourceAsset(url: directory.appendingPathComponent("photo.png"))
    var preview = FramingSurface(model: model, asset: asset, interactive: false, maximum: 3200)
    XCTAssertEqual(preview.renderMaximum, 3200)
    preview.maximum = 100_000
    XCTAssertEqual(preview.renderMaximum, 3200, "Viewing detail remains bounded")
    preview.interactive = true
    XCTAssertEqual(preview.renderMaximum, 1000, "Interactive crop preview retains its established budget")
    preview.maximum = 240
    XCTAssertEqual(preview.renderMaximum, 240, "Thumbnail callers retain their requested smaller budget")
  }

  func testFilterChromeDistinguishesOriginalLegacyAndUnavailablePreset() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: directory)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: directory) }
    let source = SourceAsset(url: directory.appendingPathComponent("photo.png"))
    model.assets = [source]; model.openPhoto(source)
    let picker = PhotoLooksPicker(model: model)
    XCTAssertFalse(picker.hasCreativeFilter)
    var configuration = model.configuration(for: source)
    configuration.look = .vivid
    model.setImageConfiguration(configuration, for: source.id)
    XCTAssertTrue(picker.hasCreativeFilter, "Legacy looks must remain removable")
    configuration.look = nil; configuration.filterEdit = FilterEdit(presetID: "future.unavailable")
    model.setImageConfiguration(configuration, for: source.id)
    XCTAssertTrue(picker.hasCreativeFilter, "Unavailable saved recipes must remain removable")
    model.selectCreativeFilter(nil)
    XCTAssertFalse(picker.hasCreativeFilter)
  }

  func testRetouchDetailBudgetDoesNotGrowWithRepeatedZoom() {
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: 1, retouch: true), 1000)
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: 1.5, retouch: true), 2000)
    for zoom in [2.0, 4, 8, 100] {
      XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: zoom, retouch: true), 3200)
    }
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: .nan, retouch: true), 1000)
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: 4, retouch: false), 1000)
  }

  func testPreviewIdentitySeparatesDisplayDetailFromCommittedGeometry() {
    var configuration = ProcessingConfiguration()
    let fit = OverlayPreviewRequest(source: nil, configuration: configuration, maximum: 1000, retry: 0)
    var detail = fit; detail.maximum = 3200
    XCTAssertNotEqual(fit, detail)
    XCTAssertEqual(fit.configuration, detail.configuration)
    configuration.adjustments.exposure = 0.5
    detail.configuration = configuration
    XCTAssertNotEqual(fit.configuration, detail.configuration)
    var retry = fit; retry.retry += 1
    XCTAssertNotEqual(fit, retry)
    let source = SourceAsset(url: URL(fileURLWithPath: "/tmp/original.png"))
    var originalRequest = fit; originalRequest.source = source
    var relinkedSource = source; relinkedSource.url = URL(fileURLWithPath: "/tmp/relinked.png")
    var relinkedRequest = originalRequest; relinkedRequest.source = relinkedSource
    XCTAssertEqual(originalRequest.source?.id, relinkedRequest.source?.id)
    XCTAssertNotEqual(originalRequest, relinkedRequest, "Same source UUID must not accept a preview from its previous pixels")
  }

  func testHigherDetailRenderPreservesOutputGeometryAndOriginalBytes() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: url) }
    let context = try XCTUnwrap(CGContext(data: nil, width: 3600, height: 2400, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.6, green: 0.2, blue: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3600, height: 2400))
    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let original = try Data(contentsOf: url)
    var configuration = ProcessingConfiguration()
    configuration.crop.mode = .preserveAspectRatio
    configuration.resizeBasis = .percentage; configuration.percentage = 100
    let processor = ImageProcessor()
    let fit = try await processor.render(url, configuration: configuration, previewMaximum: 1000)
    let detail = try await processor.render(url, configuration: configuration, previewMaximum: 3200, decodeMaximum: 3200)
    XCTAssertEqual(fit.width, 1000)
    XCTAssertEqual(detail.width, 3200)
    XCTAssertEqual(Double(fit.width) / Double(fit.height), Double(detail.width) / Double(detail.height), accuracy: 0.002)
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(configuration.percentage, 100)
  }
}
