import CoreGraphics
import FramepebbleCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import FramepebbleMac

@MainActor final class AutomationTests: XCTestCase {
  func setup() throws -> (Automations, URL, URL, UUID) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let input = root.appendingPathComponent("Input")
    let output = root.appendingPathComponent("Output")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    let controller = Automations(root: root.appendingPathComponent("State"))
    var recipe = AutomationRecipe()
    recipe.inputBookmark = try input.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    recipe.outputBookmark = try output.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    recipe.enabled = true
    recipe.configuration.width = 32
    recipe.configuration.height = 32
    recipe.configuration.format = .jpeg
    controller.recipes = [recipe]
    return (controller, input, output, recipe.id)
  }
  func image(_ input: URL) throws -> URL {
    let url = input.appendingPathComponent("new.png")
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    let dest = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return url
  }
  func testNewImageStabilityPublicationOriginalAndRestartDedup() async throws {
    let (controller, input, output, _) = try setup()
    let source = try image(input)
    let original = try Data(contentsOf: source)
    await controller.reconcile()
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 0)
    try await Task.sleep(for: .milliseconds(2100))
    await controller.reconcile()
    XCTAssertEqual(controller.recipes[0].completed, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 1)
    XCTAssertEqual(try Data(contentsOf: source), original)
    let restored = Automations(root: controller.root)
    await restored.reconcile()
    try await Task.sleep(for: .milliseconds(2100))
    await restored.reconcile()
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 1)
  }
  func testReviewQueueNoPublicationUntilApproval() async throws {
    let (controller, input, output, id) = try setup()
    controller.recipes[0].privacyReview = true
    _ = try image(input)
    await controller.reconcile()
    try await Task.sleep(for: .milliseconds(2100))
    await controller.reconcile()
    XCTAssertEqual(controller.recipes[0].pending.count, 1)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    let job = try XCTUnwrap(controller.recipes[0].pending.first)
    controller.approve(id, job: job)
    await controller.approvalTask?.value
    XCTAssertEqual(controller.recipes[0].completed, 1)
    XCTAssertTrue(controller.recipes[0].pending.isEmpty)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 1)
  }
  func testMissingDestinationRecoveryAndCorruptInputFailure() async throws {
    let (controller, input, output, _) = try setup()
    _ = try image(input)
    try FileManager.default.removeItem(at: output)
    await controller.reconcile()
    XCTAssertNotNil(controller.recipes[0].error)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    controller.recipes[0].outputBookmark = try output.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    await controller.reconcile()
    try await Task.sleep(for: .milliseconds(2100))
    try await Task.sleep(for: .milliseconds(2100))
    await controller.reconcile()
    XCTAssertEqual(controller.recipes[0].completed, 1)
    try Data("invalid".utf8).write(to: input.appendingPathComponent("corrupt.png"))
    await controller.reconcile()
    try await Task.sleep(for: .milliseconds(2100))
    await controller.reconcile()
    XCTAssertEqual(controller.recipes[0].failures.count, 1)
    await controller.reconcile()
    XCTAssertEqual(controller.recipes[0].failures.count, 1)
  }
  func testRejectsFolderLoops() throws {
    let (controller, input, _, _) = try setup()
    controller.recipes[0].outputBookmark = try input.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    XCTAssertThrowsError(try controller.validate(controller.recipes[0]))
  }
}

extension AutomationTests {
  func testRunningMonitorFindsNewFileWithoutManualScan() async throws {
    let (controller, input, output, _) = try setup()
    controller.start()
    defer { controller.task?.cancel() }
    let original = try image(input)
    let bytes = try Data(contentsOf: original)
    for _ in 0..<40 {
      if controller.recipes[0].completed == 1 { break }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTAssertEqual(controller.recipes[0].completed, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 1)
    XCTAssertEqual(try Data(contentsOf: original), bytes)
  }
}
