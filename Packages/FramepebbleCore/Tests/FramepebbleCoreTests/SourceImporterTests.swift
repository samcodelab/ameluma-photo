import CoreGraphics
import FramepebbleCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class SourceImporterTests: XCTestCase {
  func folders() throws -> (URL, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("Input")
    let destination = root.appendingPathComponent("Snapshots")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return (source, destination)
  }
  func image(_ url: URL) throws {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
  func testCompletedImageCanBePreviewedWhileAcquisitionRemainsPaused() async throws {
    let (input, destination) = try folders()
    let first = input.appendingPathComponent("first.png")
    let second = input.appendingPathComponent("second.png")
    try image(first)
    try image(second)
    let probe = ImportProbe(holdFirst: true)
    let worker = SourceImporter()
    let operation = Task {
      try await worker.run([first, second], destination: destination) { await probe.receive($0) }
    }
    let available = await probe.firstAsset()
    let preview = try await ImageProcessor().thumbnail(available.url, maximum: 40)
    XCTAssertEqual(preview.width, 40)
    let countDuringImport = await probe.count
    XCTAssertEqual(countDuringImport, 1)
    XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: available.url))
    await probe.releaseFirst()
    try await operation.value
    let count = await probe.count
    XCTAssertEqual(count, 2)
  }
  func testCancellationPreservesCompletedSnapshots() async throws {
    let (input, destination) = try folders()
    let first = input.appendingPathComponent("first.png")
    let second = input.appendingPathComponent("second.png")
    try image(first)
    try image(second)
    let probe = ImportProbe(holdFirst: true)
    let worker = SourceImporter()
    let operation = Task {
      try await worker.run([first, second], destination: destination) { await probe.receive($0) }
    }
    let available = await probe.firstAsset()
    operation.cancel()
    await probe.releaseFirst()
    do {
      try await operation.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: available.url.path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
  }
  func testFolderStreamsNestedFilesAndReportsCorruptInputsWithoutLeakingSnapshots() async throws {
    let (input, destination) = try folders()
    let nested = input.appendingPathComponent("Nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let original = nested.appendingPathComponent("good.png")
    try image(original)
    try Data("broken".utf8).write(to: input.appendingPathComponent("bad.png"))
    let probe = ImportProbe()
    try await SourceImporter().run([input], destination: destination) { await probe.receive($0) }
    let count = await probe.count
    let failures = await probe.failures
    let digests = await probe.digests
    let copied = await probe.progress
    XCTAssertEqual(count, 1)
    XCTAssertEqual(failures, 1)
    XCTAssertEqual(digests, [try ContentDigest.read(original)])
    XCTAssertTrue(copied.contains { $0.0 == $0.1 && $0.1 > 0 })
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)
  }
  func testAncestorImportDoesNotReimportItsOwnSnapshots() async throws {
    let (input, destination) = try folders()
    try image(input.appendingPathComponent("photo.png"))
    let probe = ImportProbe()
    try await SourceImporter().run([input.deletingLastPathComponent()], destination: destination) {
      await probe.receive($0)
    }
    let count = await probe.count
    XCTAssertEqual(count, 1)
  }
  func testPrivateSnapshotFolderCannotBeImportedRecursively() async throws {
    let (_, destination) = try folders()
    try image(destination.appendingPathComponent("existing.png"))
    let probe = ImportProbe()
    try await SourceImporter().run([destination], destination: destination) {
      await probe.receive($0)
    }
    let count = await probe.count
    let failures = await probe.failures
    XCTAssertEqual(count, 0)
    XCTAssertEqual(failures, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)
  }
  func testIndividualSymlinkProducesAnIndependentRegularSnapshot() async throws {
    let (input, destination) = try folders()
    let original = input.appendingPathComponent("original.png")
    try image(original)
    let link = input.appendingPathComponent("alias.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    let probe = ImportProbe()
    try await SourceImporter().run([link], destination: destination) { await probe.receive($0) }
    let snapshots = await probe.assets
    let asset = try XCTUnwrap(snapshots.first)
    XCTAssertEqual(try Data(contentsOf: asset.url), try Data(contentsOf: original))
    XCTAssertNotEqual(
      try asset.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
  }
  func testChangingSourceDuringCopyIsRejected() async throws {
    let (input, destination) = try folders()
    let original = input.appendingPathComponent("changing.png")
    try image(original)
    let probe = ImportProbe()
    try await SourceImporter().run([original], destination: destination) { event in
      if case .copying(_, 0, _) = event {
        try? Data("replacement".utf8).write(to: original, options: .atomic)
      }
      await probe.receive(event)
    }
    let count = await probe.count
    let failures = await probe.failures
    XCTAssertEqual(count, 0)
    XCTAssertEqual(failures, 1)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
  }
}
private actor ImportProbe {
  let holdFirst: Bool
  var assets: [SourceAsset] = []
  var failures = 0
  var digests: [String] = []
  var progress: [(Int64, Int64)] = []
  var waiting: CheckedContinuation<SourceAsset, Never>?
  var held: CheckedContinuation<Void, Never>?
  init(holdFirst: Bool = false) { self.holdFirst = holdFirst }
  var count: Int { assets.count }
  func receive(_ event: SourceImportEvent) async {
    switch event {
    case .ready(let asset, let digest):
      assets.append(asset)
      digests.append(digest)
      if assets.count == 1 {
        waiting?.resume(returning: asset)
        waiting = nil
        if holdFirst { await withCheckedContinuation { held = $0 } }
      }
    case .copying(_, let bytes, let total): progress.append((bytes, total))
    case .failed: failures += 1
    case .discovered: break
    }
  }
  func firstAsset() async -> SourceAsset {
    if let asset = assets.first { return asset }
    return await withCheckedContinuation { waiting = $0 }
  }
  func releaseFirst() {
    held?.resume()
    held = nil
  }
}
