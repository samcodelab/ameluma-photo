import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import FramepebbleCore
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class RemovalUsabilityTests: XCTestCase {
  private func workspace() async throws -> (Workspace, [URL]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("removal-" + UUID().uuidString)
    let model = Workspace(directory: root)
    addTeardownBlock {
      await model.stopWork()
      await MainActor.run { model.persistenceTask?.cancel() }
      try? FileManager.default.removeItem(at: root)
    }
    var originals: [URL] = []
    for index in 0..<3 {
      let url = root.appendingPathComponent("Original \(index).png")
      let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 12,
        bitsPerComponent: 8, bytesPerRow: 64,
        space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(red: CGFloat(index) / 3, green: 0.4, blue: 0.6, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
      let image = try XCTUnwrap(context.makeImage())
      let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      originals.append(url)
    }
    await model.importURLs(originals)
    await model.indexingTask?.value
    XCTAssertEqual(model.assets.count, 3)
    return (model, originals)
  }

  func testUndoRemovalSurvivesCleanupRestoresMembershipAndKeepsCurrentEdits() async throws {
    let (model, originals) = try await workspace()
    let bytes = try originals.map { try Data(contentsOf: $0) }
    let photos = model.assets
    model.openPhoto(photos[1]); model.openPhoto(photos[0])
    let tabs = model.editorTabs
    model.beginBatch(ids: photos.map(\.id))
    model.selection = [photos[0].id, photos[2].id]
    model.favourites = [photos[0].id]
    model.removeFromWorkspace([photos[0].id])
    XCTAssertFalse(model.workspaceAssets.contains { $0.id == photos[0].id })
    XCTAssertTrue(model.assets.contains { $0.id == photos[0].id })
    XCTAssertFalse(model.persistedSources.contains { $0.id == photos[0].id })
    var current = model.configuration(forID: photos[0].id)
    current.adjustments.exposure = 0.7
    model.setImageConfiguration(current, for: photos[0].id)
    _ = try await model.freeUnusedWorkingCopies()
    XCTAssertTrue(FileManager.default.fileExists(atPath: photos[0].url.path))
    XCTAssertTrue(model.canUndoWorkspaceRemoval)
    model.undoWorkspaceRemoval()
    XCTAssertEqual(Set(model.workspaceAssets.map(\.id)), Set(photos.map(\.id)))
    XCTAssertEqual(model.editorTabs, tabs)
    XCTAssertEqual(model.editorPhotoID, photos[0].id)
    XCTAssertEqual(model.selection, [photos[0].id, photos[2].id])
    XCTAssertEqual(model.favourites, [photos[0].id])
    XCTAssertEqual(model.batchInputIDs, Set(photos.map(\.id)))
    XCTAssertEqual(model.configuration(forID: photos[0].id), current)
    XCTAssertFalse(model.canUndoWorkspaceRemoval)
    XCTAssertEqual(try originals.map { try Data(contentsOf: $0) }, bytes)
  }

  func testUndoRemovalDoesNotExpandNewBatchEvenWhenItsInputsEqualPostRemovalSet() async throws {
    let (model, _) = try await workspace()
    let photos = model.assets
    model.beginBatch(ids: [photos[0].id, photos[1].id])
    model.removeFromWorkspace([photos[0].id])
    model.beginConversion(ids: [photos[1].id])
    model.openPhoto(photos[2])
    model.selection = [photos[2].id]
    model.undoWorkspaceRemoval()
    XCTAssertEqual(model.batchInputIDs, [photos[1].id])
    XCTAssertEqual(model.conversionInputIDs, [photos[1].id])
    XCTAssertEqual(model.editorPhotoID, photos[2].id)
    XCTAssertTrue(model.selection.contains(photos[2].id))
    XCTAssertTrue(model.workspaceAssets.contains { $0.id == photos[0].id })
  }

  func testExpiredRemovalUndoAllowsUnusedCopyCleanupWithoutTouchingOriginal() async throws {
    let (model, originals) = try await workspace()
    let source = model.assets[0]
    let original = try Data(contentsOf: originals[0])
    model.removeFromWorkspace([source.id])
    model.removalUndo = nil
    _ = try await model.freeUnusedWorkingCopies()
    XCTAssertFalse(model.assets.contains { $0.id == source.id })
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.url.path))
    XCTAssertEqual(try Data(contentsOf: originals[0]), original)
  }

  func testNewProjectInvalidatesOldRemovalUndoAndDoesNotPersistUndoOnlySources() async throws {
    let (model, _) = try await workspace()
    let removed = model.assets[0]
    model.removeFromWorkspace([removed.id])
    let oldReceipt = try XCTUnwrap(model.removalUndo)
    let saved = try await model.saveProjectCopy()
    let document = try await model.store.load(saved)
    XCTAssertFalse(document.sources.contains { $0.id == removed.id })
    await model.newProject()
    model.removalUndo = oldReceipt // A stale async/UI reference must not resurrect the old project.
    XCTAssertTrue(model.removalUndoSourceIDs.isEmpty)
    XCTAssertFalse(model.canUndoWorkspaceRemoval)
    model.undoWorkspaceRemoval()
    XCTAssertTrue(model.workspaceAssets.isEmpty)
    _ = try await model.freeUnusedWorkingCopies()
    XCTAssertFalse(FileManager.default.fileExists(atPath: removed.url.path))
  }
}
