import CoreGraphics
import FramepebbleCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import FramepebbleiOS

private actor FixtureSensitivityAnalyzer: SensitiveImageAnalyzing {
  let enabled: Bool
  let positive: Bool
  init(enabled: Bool, positive: Bool = false) {
    self.enabled = enabled
    self.positive = positive
  }
  func availability() -> SensitiveAnalysisAvailability {
    enabled ? .available(descriptiveInterventions: false) : .unavailable("Unavailable in this test")
  }
  func analyze(_ image: CGImage) -> Bool { positive }
}
@MainActor final class SensitiveWorkspaceTests: XCTestCase {
  func workspace(_ analyzer: any SensitiveImageAnalyzing) throws -> Workspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root, sensitiveAnalyzer: analyzer)
    addTeardownBlock {
      await model.stopWork()
      try? FileManager.default.removeItem(at: root)
    }
    return model
  }
  func fixture(_ model: Workspace) throws -> SourceAsset {
    let url = model.directory.appendingPathComponent("photo.png")
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return SourceAsset(url: url)
  }
  func testCapabilityUnavailableDoesNotFabricateFindingsAndManualReviewWorks() async throws {
    let model = try workspace(FixtureSensitivityAnalyzer(enabled: false))
    let asset = try fixture(model)
    model.assets = [asset]
    model.scanSensitiveImages()
    await model.sensitivityTask?.value
    XCTAssertTrue(model.sensitivity.findings.isEmpty)
    XCTAssertFalse(model.sensitivityAvailability.canAnalyze)
    model.sensitivity.mark(asset.id, forReview: true)
    model.library = .privacyReview
    XCTAssertEqual(model.filtered.map(\.id), [asset.id])
  }
  func testActualAnalyzerResultFlagsAndFiltersWithoutResettingEdits() async throws {
    let model = try workspace(FixtureSensitivityAnalyzer(enabled: true, positive: true))
    let asset = try fixture(model)
    model.assets = [asset]
    model.selected = asset.id
    var crop = CropConfiguration()
    crop.centerX = 0.7
    model.setCrop(crop, for: asset.id)
    model.scanSensitiveImages()
    await model.sensitivityTask?.value
    XCTAssertTrue(model.sensitivity.flagged.contains(asset.id))
    XCTAssertTrue(model.sensitivity.concealed(asset.id))
    XCTAssertEqual(model.configuration(for: asset).crop.centerX, 0.7)
    model.library = .privacyReview
    XCTAssertEqual(model.filtered.count, 1)
    model.openPrivacyEditor(.overlays, asset: asset)
    XCTAssertFalse(model.sensitivity.concealed(asset.id))
    XCTAssertFalse(model.overlayEditor, "Editor waits until the review sheet is dismissed")
    model.finishPrivacyReviewPresentation()
    XCTAssertTrue(model.overlayEditor)
    model.clearSensitivityReview()
    XCTAssertTrue(model.sensitivity.flagged.isEmpty)
  }
  func testPrivacyFindingsAreNotWrittenIntoSavedProjects() async throws {
    let model = try workspace(FixtureSensitivityAnalyzer(enabled: true, positive: true))
    let asset = try fixture(model)
    model.assets = [asset]
    model.scanSensitiveImages()
    await model.sensitivityTask?.value
    let data = try JSONEncoder().encode(model.document())
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNil(fields["sensitivity"])
    XCTAssertNil(fields["sensitivityFindings"])
    await model.newProject()
    XCTAssertTrue(model.sensitivity.flagged.isEmpty)
  }
  func testNegativeResultDoesNotEraseManualFlag() async throws {
    let model = try workspace(FixtureSensitivityAnalyzer(enabled: true))
    let asset = try fixture(model)
    model.assets = [asset]
    model.sensitivity.mark(asset.id, forReview: true)
    model.scanSensitiveImages()
    await model.sensitivityTask?.value
    XCTAssertTrue(model.sensitivity.flagged.contains(asset.id))
    XCTAssertEqual(model.sensitivity.findings[asset.id]?.sensitive, false)
  }
}
