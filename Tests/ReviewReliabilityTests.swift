import FramepebbleCore
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FramepebbleiOS

@MainActor final class ReviewReliabilityTests: XCTestCase {
  func model() throws -> Workspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let m = Workspace(directory: root)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return m
  }
  func imageData(blue: Bool = false) throws -> Data {
    let c = try XCTUnwrap(CGContext(data: nil, width: 96, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    c.setFillColor(CGColor(red: blue ? 0 : 1, green: 0, blue: blue ? 1 : 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
    let data = NSMutableData(); let d = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(d, try XCTUnwrap(c.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(d)); return data as Data
  }
  func testRemovedCreationSourcesSurviveRenderExportSaveReopenAndCleanup() async throws {
    let m = try model(); let bytes = try imageData()
    let original = m.directory.deletingLastPathComponent().appendingPathComponent("Original.png"); try bytes.write(to: original)
    await m.importURLs([original]); let source = try XCTUnwrap(m.assets.first)
    m.startGIF(ids: [source.id]); m.gifProject?.width = 48; m.gifProject?.height = 48
    m.newCollage(sourceIDs: [source.id]); m.collage.width = 48; m.collage.height = 48
    let watermark = m.directory.appendingPathComponent(UUID().uuidString + ".png"); try bytes.write(to: watermark)
    var c = m.configuration(forID: source.id); c.watermark.enabled = true; c.watermark.kind = .image; c.watermark.imageURL = watermark
    m.setImageConfiguration(c, for: source.id)
    let unrelated = m.directory.appendingPathComponent(UUID().uuidString + ".png"); try bytes.write(to: unrelated)
    m.removeFromWorkspace([source.id])
    XCTAssertTrue(m.assets.contains(source)); XCTAssertTrue(m.workspaceAssets.isEmpty); XCTAssertTrue(m.filtered.isEmpty)
    m.switchWorkflow(.batch); m.scope = .all; XCTAssertTrue(m.targets.isEmpty)
    let prior = m.configuration(forID: source.id); m.updateField(\.adjustments.exposure, value: 0.8, fields: [.adjustments_exposure])
    XCTAssertEqual(m.configuration(forID: source.id), prior, "Hidden creation inputs cannot be changed by ordinary batch operations")
    _ = try await m.processor.renderCollage(m.collage, sources: m.assets, edits: m.edits)
    let out = try await m.gifRenderer.export(try XCTUnwrap(m.gifProject), sources: m.assets, directory: m.directory.deletingLastPathComponent())
    XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    let collageImage = try await m.processor.renderCollage(m.collage, sources: m.assets, edits: m.edits)
    var output = ProcessingConfiguration(); output.width = 48; output.height = 48; output.format = .png
    let published = try await m.processor.publish(collageImage, asset: source, configuration: output, to: m.directory.deletingLastPathComponent(), flattenTransparency: true)
    XCTAssertNotNil(published.output)
    let saved = try await m.saveProjectCopy(); await m.flush()
    _ = try await m.freeUnusedWorkingCopies()
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: watermark.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: unrelated.path))
    let restored = Workspace(directory: m.directory.deletingLastPathComponent()); await restored.openProject(saved)
    XCTAssertTrue(restored.workspaceAssets.isEmpty); XCTAssertEqual(restored.gifProject?.frames, m.gifProject?.frames)
    _ = try await restored.processor.renderCollage(restored.collage, sources: restored.assets, edits: restored.edits)
    _ = try await restored.gifRenderer.export(try XCTUnwrap(restored.gifProject), sources: restored.assets, directory: restored.directory.deletingLastPathComponent())
    await restored.clearImportedPhotos()
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: watermark.path))
    XCTAssertEqual(try Data(contentsOf: original), bytes)
    await restored.stopWork(); restored.persistenceTask?.cancel(); await m.stopWork(); m.persistenceTask?.cancel()
  }
  func testLegacyMembershipMigrationAndFreeingUnusedRetainedRecords() async throws {
    let m = try model(); await m.importData(try imageData(), name: "source.png")
    let asset = try XCTUnwrap(m.assets.first); m.selection = [asset.id]; m.startGIF(ids: [asset.id])
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(m.document())) as? [String: Any])
    object.removeValue(forKey: "hiddenSourceIDs"); object.removeValue(forKey: "conversionInputIDs"); object.removeValue(forKey: "conversionResizingEnabled")
    let legacy = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertTrue(legacy.hiddenSourceIDs.isEmpty); XCTAssertEqual(legacy.sources, m.assets)
    XCTAssertEqual(legacy.workspaceSelection, [asset.id]); XCTAssertEqual(legacy.gifProject, m.gifProject)
    let watermark = m.directory.appendingPathComponent(UUID().uuidString + ".png"); try imageData().write(to: watermark)
    var config = m.configuration(forID: asset.id); config.watermark.imageURL = watermark; m.setImageConfiguration(config, for: asset.id)
    config.watermark.imageURL = nil; m.setImageConfiguration(config, for: asset.id)
    m.removeFromWorkspace([asset.id]); m.gifProject = nil; m.archivedGIFs = []; m.gifUndo = []; m.gifRedo = []
    m.removalUndo = nil // Explicitly expire membership Undo before testing unused-copy reclamation.
    _ = try await m.freeUnusedWorkingCopies()
    XCTAssertTrue(m.assets.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: asset.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: watermark.path), "Session Undo watermark dependencies must survive cleanup")
    await m.importData(try imageData(), name: "source.png"); XCTAssertEqual(m.workspaceAssets.count, 1)
    await m.stopWork(); m.persistenceTask?.cancel()
  }
  func testProjectSwitchCannotAdmitAnImportFromThePreviousOperation() async throws {
    let m = try model(); await m.importData(try imageData(), name: "old.png")
    let bytes = try imageData(blue: true)
    let incoming = Task { await m.importData(bytes, name: "late.png") }
    await m.newProject(); await incoming.value
    XCTAssertTrue(m.assets.isEmpty); XCTAssertTrue(m.selection.isEmpty)
    await m.importData(bytes, name: "new.png"); XCTAssertEqual(m.workspaceAssets.count, 1)
    await m.stopWork(); m.persistenceTask?.cancel()
  }
  func testDuplicateLifecycleRemovalRestorationRelinkAndProjectSwitch() async throws {
    let m = try model(), bytes = try imageData(), blue = try imageData(blue: true)
    await m.importData(bytes, name: "photo.png"); let first = try XCTUnwrap(m.assets.first)
    m.removeFromWorkspace([first.id]); await m.importData(bytes, name: "again.png")
    XCTAssertEqual(m.workspaceAssets.first?.id, first.id, "Active membership Undo retains the same source for duplicate restoration")
    m.removeFromWorkspace([first.id]); m.removalUndo = nil
    _ = try await m.freeUnusedWorkingCopies()
    await m.importData(bytes, name: "again.png")
    let second = try XCTUnwrap(m.assets.first); XCTAssertNotEqual(first.id, second.id, "Expired, unreferenced working copies may be reclaimed and imported afresh")
    m.startGIF(ids: [second.id]); m.removeFromWorkspace([second.id]); await m.importData(bytes, name: "retained.png")
    XCTAssertEqual(m.assets.count, 1); XCTAssertEqual(m.workspaceAssets.first?.id, second.id)
    m.skipDuplicates = false; await m.importData(bytes, name: "anyway.png"); XCTAssertEqual(m.assets.count, 2)
    m.skipDuplicates = true
    let saved = try await m.saveProjectCopy()
    await m.newProject(); await m.importData(blue, name: "blue.png"); XCTAssertEqual(m.assets.count, 1)
    await m.openProject(saved); await m.importData(blue, name: "blue.png"); XCTAssertEqual(m.assets.count, 3, "Project opening replaces duplicate history")
    let replacement = m.directory.deletingLastPathComponent().appendingPathComponent("replacement.png"); try blue.write(to: replacement)
    await m.relinkSource(replacement, sourceID: second.id)
    let oldIDs = Set(m.assets.map(\.id)); await m.importData(bytes, name: "old.png")
    XCTAssertEqual(Set(m.assets.map(\.id)), oldIDs, "An Import Anyway copy still owns the old digest")
    await m.flush(); let restarted = Workspace(directory: m.directory.deletingLastPathComponent()); await restarted.start()
    let count = restarted.assets.count; await restarted.importData(bytes, name: "old.png"); XCTAssertEqual(restarted.assets.count, count)
    await restarted.stopWork(); restarted.persistenceTask?.cancel(); await m.stopWork(); m.persistenceTask?.cancel()
  }
  func testRelinkFlagsCapturedMasksSavedCreationsAndRevokesReview() async throws {
    let m = try model(); await m.importData(try imageData(), name: "source.png"); let source = try XCTUnwrap(m.assets.first)
    var c = m.configuration(forID: source.id); c.masks = [PrivacyMask()]; m.setImageConfiguration(c, for: source.id)
    m.startGIF(ids: [source.id]); let frame = try XCTUnwrap(m.gifProject?.frames.first)
    m.archiveCurrentGIF(); m.newCollage(sourceIDs: [source.id])
    c.masks = []; m.setImageConfiguration(c, for: source.id)
    let exported = m.directory.deletingLastPathComponent().appendingPathComponent("previous.gif"); try Data("immutable".utf8).write(to: exported); m.beginSharing([exported])
    let replacement = m.directory.deletingLastPathComponent().appendingPathComponent("blue.png"); try imageData(blue: true).write(to: replacement)
    let identity = CollageRenderIdentity(project: m.collage, sources: m.assets, edits: m.edits)
    await m.relinkSource(replacement, sourceID: source.id)
    XCTAssertEqual(m.gifProject?.privacyReviewFrameIDs, [frame.id]); XCTAssertEqual(m.archivedGIFs.first?.privacyReviewFrameIDs, [frame.id])
    XCTAssertTrue(m.collage.requiresFramingReview); XCTAssertTrue(m.collageDocuments.first?.project.requiresFramingReview == true)
    XCTAssertNotEqual(identity, CollageRenderIdentity(project: m.collage, sources: m.assets, edits: m.edits)); XCTAssertNil(m.sharingSession)
    XCTAssertEqual(try String(contentsOf: exported, encoding: .utf8), "immutable")
    let saved = try await m.saveProjectCopy(); await m.openProject(saved)
    XCTAssertEqual(m.gifProject?.privacyReviewFrameIDs, [frame.id]); XCTAssertTrue(m.collage.requiresFramingReview)
    await m.stopWork(); m.persistenceTask?.cancel()
  }
  func testTaskContextConversionScopeAndSavedGIFEmptyRecovery() async throws {
    let m = try model(); await m.importData(try imageData(), name: "first.png"); await m.importData(try imageData(blue: true), name: "second.png")
    let a = m.assets[0], b = m.assets[1]; m.selection = [b.id]; m.startGIF(ids: [b.id]); let old = try XCTUnwrap(m.gifProject)
    m.archiveCurrentGIF(); m.gifProject = nil
    m.selectPhotos(for: .convert); m.select(a); m.finishGIFSelection(cancel: false)
    XCTAssertEqual(m.selection, [b.id]); XCTAssertEqual(m.targets.map(\.id), [a.id])
    XCTAssertEqual(m.plannedRequests().first?.configuration.nativeOutputSizing, true)
    let plan = ExportPlanView(model: m).sizeSummary(try XCTUnwrap(m.plannedRequests().first?.configuration))
    XCTAssertTrue(plan.contains("Source dimensions")); XCTAssertFalse(plan.contains("1600"))
    m.selection = [b.id]; m.query = "second"; XCTAssertEqual(m.targets.map(\.id), [a.id])
    let rendered = try await m.processor.render(a.url, configuration: XCTUnwrap(m.plannedRequests().first?.configuration))
    XCTAssertEqual(rendered.width, 96); XCTAssertEqual(rendered.height, 48)
    m.openPhoto(b); m.closeEditorTab(b.id); XCTAssertEqual(m.batchInputIDs, [a.id])
    m.openGIF(old); XCTAssertEqual(m.gifProject, old)
    m.gifProject?.remove(Set(old.frames.map(\.id))); m.openGIF(old); XCTAssertEqual(m.gifProject?.frames, old.frames)
    m.gifProject = nil; m.selectGIFPhotos(); m.finishGIFSelection(cancel: true)
    m.openGIF(old); XCTAssertEqual(m.gifProject?.frames, old.frames)
    m.selectPhotos(for: .collage); m.select(a); m.finishGIFSelection(cancel: true); XCTAssertEqual(m.gifProject?.frames, old.frames)
    m.selectPhotos(for: .collage); m.select(a); m.finishGIFSelection(cancel: false); XCTAssertEqual(m.collage.cells.map(\.sourceID), [a.id])
    m.collage.title = "Keep me"; let cell = try XCTUnwrap(m.collage.cells.first)
    m.selectPhotos(for: .collageAdd); m.select(b); m.finishGIFSelection(cancel: false)
    XCTAssertEqual(m.collage.title, "Keep me"); XCTAssertEqual(m.collage.cells.first, cell); XCTAssertEqual(m.collage.cells.count, 2)
    let inputs = m.batchInputIDs
    m.selectPhotos(for: .censor); m.select(a); m.select(b)
    XCTAssertFalse(m.selectionContextValid); m.finishGIFSelection(cancel: false); XCTAssertNotNil(m.gifSelectionContext)
    m.select(b); m.finishGIFSelection(cancel: false)
    XCTAssertTrue(m.overlayEditor); XCTAssertEqual(m.current?.id, a.id); XCTAssertEqual(m.targets.map(\.id), [a.id]); XCTAssertEqual(m.batchInputIDs, inputs)
    m.overlayEditor = false
    await m.stopWork(); m.persistenceTask?.cancel()
  }
  func testPreviewSupersessionFailureAndExitRemoveStaleResources() async throws {
    let m = try model(); await m.importData(try imageData(), name: "first.png"); m.startGIF(ids: m.assets.map(\.id))
    let project = try XCTUnwrap(m.gifProject), session = GIFPreviewSession()
    let first = try await GIFPreviewBuilder().prepare(project, sources: m.assets)
    await session.prepare(project: project, allowed: true) { first }; await session.load(index: 0, project: project); XCTAssertNotNil(session.image)
    let input = GIFPreviewInput(project: project, sources: [], allowed: true)
    XCTAssertNotNil(session.image(for: input, frameID: project.frames[0].id))
    var changed = input; changed.project.id = UUID()
    XCTAssertNil(session.image(for: changed, frameID: project.frames[0].id), "Old pixels must be hidden immediately, before a new SwiftUI task starts")
    XCTAssertNil(session.image(for: input, frameID: UUID()), "A newly selected frame must not display the previous frame")
    var continuation: CheckedContinuation<GIFPreview, Error>?
    let old = Task { await session.prepare(project: project, allowed: true) { try await withCheckedThrowingContinuation { continuation = $0 } } }
    while continuation == nil { await Task.yield() }
    XCTAssertNil(session.image); XCTAssertFalse(FileManager.default.fileExists(atPath: first.directory.path))
    let failedID = UUID()
    await session.prepare(project: project, allowed: true) { throw GIFPreviewFailure(frameID: failedID, index: 4, reason: "Missing source") }
    XCTAssertNotNil(session.error); XCTAssertEqual(session.failedFrameID, failedID); XCTAssertNil(session.image)
    let late = try await GIFPreviewBuilder().prepare(project, sources: m.assets)
    old.cancel(); continuation?.resume(returning: late); await old.value
    XCTAssertNotNil(session.error); XCTAssertNil(session.image); XCTAssertFalse(FileManager.default.fileExists(atPath: late.directory.path))
    let current = try await GIFPreviewBuilder().prepare(project, sources: m.assets)
    await session.prepare(project: project, allowed: true) { current }; await session.load(index: 0, project: project)
    session.invalidate(); XCTAssertNil(session.image); XCTAssertFalse(FileManager.default.fileExists(atPath: current.directory.path))
    await m.stopWork(); m.persistenceTask?.cancel()
  }
}
