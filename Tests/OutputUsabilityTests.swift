import Foundation
import XCTest
import FramepebbleCore
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class OutputUsabilityTests: XCTestCase {
  func testBlockedConversionDoesNotChangeCapturedInputsOrProfiles() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let photo = SourceAsset(url: root.appendingPathComponent("One.jpg"))
    model.assets = [photo]; model.batchInputIDs = [photo.id]
    model.conversionInputIDs = [photo.id]; model.conversionResizingEnabled = true
    let profiles = model.exportProfiles
    model.beginConversion(ids: [UUID()])
    XCTAssertEqual(model.conversionInputIDs, [photo.id]); XCTAssertTrue(model.conversionResizingEnabled)
    XCTAssertEqual(model.exportProfiles, profiles)
    model.running = true
    model.beginConversion(ids: [photo.id])
    XCTAssertEqual(model.conversionInputIDs, [photo.id]); XCTAssertTrue(model.conversionResizingEnabled)
    XCTAssertEqual(model.exportProfiles, profiles)
  }

  func testActionCaptureExcludesRetainedSourcesAndDeduplicatesWithoutUsingSelection() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let photos = ["One.jpg", "Two.jpg", "Retained.jpg"].map { SourceAsset(url: root.appendingPathComponent($0)) }
    model.assets = photos; model.hiddenSourceIDs = [photos[2].id]
    model.selection = [photos[1].id]; model.query = "No visible matches"
    XCTAssertEqual(model.workspaceActionIDs([photos[0].id, photos[2].id, photos[0].id, UUID()]), [photos[0].id])
    model.beginConversion(ids: [photos[0].id, photos[0].id])
    XCTAssertEqual(model.batchInputIDs, [photos[0].id]); XCTAssertEqual(model.conversionInputIDs, [photos[0].id])
    XCTAssertEqual(model.selection, [photos[1].id]); XCTAssertFalse(model.conversionResizingEnabled)
  }

  func testCompareFocusAndReturnPreserveBatchMembershipAndEdits() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let photos = ["One.jpg", "Two.jpg", "Three.jpg"].map { SourceAsset(url: root.appendingPathComponent($0)) }
    model.assets = photos; model.selection = [photos[0].id, photos[2].id]
    model.batchInputIDs = [photos[0].id, photos[1].id]; model.selected = photos[0].id
    model.mode = .compare
    let selection = model.selection, order = model.selectionOrder, inputs = model.batchInputIDs, edits = model.edits
    model.focusComparisonPhoto(photos[1].id, in: Array(photos.prefix(2)))
    XCTAssertEqual(model.selected, photos[1].id)
    model.focusComparisonPhoto(photos[2].id, in: Array(photos.prefix(2)))
    XCTAssertEqual(model.selected, photos[1].id, "Hidden photos cannot be targeted from the visible comparison strip")
    model.returnFromComparison()
    XCTAssertEqual(model.mode, .browse)
    XCTAssertEqual(model.selected, photos[1].id)
    XCTAssertEqual(model.selection, selection); XCTAssertEqual(model.selectionOrder, order)
    XCTAssertEqual(model.batchInputIDs, inputs); XCTAssertEqual(model.edits, edits)
  }

  func testShowAllClearsEveryVisibilityPredicateWithoutChangingSelectionOrInputs() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    model.assets = [SourceAsset(url: root.appendingPathComponent("One.jpg")), SourceAsset(url: root.appendingPathComponent("Two.png"))]
    model.selection = Set(model.assets.map(\.id))
    model.batchInputIDs = [model.assets[1].id]
    model.library = .favourites; model.query = "missing"
    model.workspaceFilter.period = .yesterday
    model.workspaceFilter.orientation = .portrait
    model.workspaceFilter.format = "public.tiff"
    model.workspaceFilter.sort = .filename
    let selection = model.selection, order = model.selectionOrder, inputs = model.batchInputIDs
    XCTAssertTrue(model.hasHiddenWorkspaceFilters)
    XCTAssertEqual(model.activeWorkspaceFilterCount, 5)
    XCTAssertTrue(model.filtered.isEmpty)
    model.showAllWorkspacePhotos()
    XCTAssertFalse(model.hasHiddenWorkspaceFilters)
    XCTAssertEqual(model.activeWorkspaceFilterCount, 0, "Sort order must not count as a visibility filter")
    XCTAssertEqual(Set(model.filtered.map(\.id)), Set(model.assets.map(\.id)))
    XCTAssertEqual(model.selection, selection)
    XCTAssertEqual(model.selectionOrder, order)
    XCTAssertEqual(model.batchInputIDs, inputs)
    XCTAssertEqual(model.workspaceFilter.sort, .filename)
    model.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at: root)
  }

  func testContextFilterCommandNamesActualTargetCount() {
    let model = Workspace(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let source = SourceAsset(url: URL(fileURLWithPath: "/tmp/context.jpg"))
    model.assets = [source]
    model.selection = [UUID(), UUID()]
    let ids = model.contextIDs(for: source.id)
    XCTAssertEqual(ids, [source.id])
    XCTAssertEqual(WorkspaceActions(model: model, ids: ids).filterActionTitle, "Apply Filter to This Photo…")
    XCTAssertEqual(WorkspaceActions(model: model, ids: [UUID(), UUID()]).filterActionTitle, "Apply Filter to 2 Photos…")
    model.persistenceTask?.cancel()
  }

  func testReviewedPhotosSaveIsSingleFlightAndRetrySkipsCompletedFiles() async {
    let session = ReviewedPhotoSaveSession()
    let one = URL(fileURLWithPath: "/tmp/one.png"), two = URL(fileURLWithPath: "/tmp/two.png")
    var authorization: CheckedContinuation<Bool, Never>?
    var published: [URL] = []
    let first = Task {
      await session.save([one, two], authorize: {
        await withCheckedContinuation { authorization = $0 }
      }, publish: { url in
        if url == two { throw NSError(domain: "PhotosFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Storage unavailable"]) }
        published.append(url)
      })
    }
    while authorization == nil { await Task.yield() }
    XCTAssertTrue(session.saving)
    await session.save([one, two], authorize: { XCTFail("Concurrent save must not request authorization"); return true }, publish: { _ in XCTFail("Concurrent publication") })
    authorization?.resume(returning: true)
    await first.value
    XCTAssertEqual(published, [one])
    XCTAssertEqual(session.saved, [one])
    XCTAssertNotNil(session.failures[two])
    XCTAssertTrue(session.status.contains("1 saved to Photos · 1 failed"))
    await session.save([one, two], authorize: { true }, publish: { published.append($0) })
    XCTAssertEqual(published, [one, two])
    XCTAssertEqual(session.saved, [one, two])
    XCTAssertTrue(session.failures.isEmpty)
    XCTAssertTrue(session.remaining(in: [one, two]).isEmpty)
  }

  func testCancelledReviewedPhotoSaveKeepsCompletedAdditionForRetry() async {
    let session = ReviewedPhotoSaveSession()
    let one = URL(fileURLWithPath: "/tmp/one.png"), two = URL(fileURLWithPath: "/tmp/two.png")
    var published: [URL] = []
    let task = Task {
      await session.save([one, two], authorize: { true }, publish: { url in
        published.append(url)
        withUnsafeCurrentTask { $0?.cancel() }
      })
    }
    await task.value
    XCTAssertEqual(session.saved, [one])
    XCTAssertEqual(session.remaining(in: [one, two]), [two])
    XCTAssertTrue(session.status.contains("Cancelled"))
    await session.save([one, two], authorize: { true }, publish: { published.append($0) })
    XCTAssertEqual(published, [one, two])
  }
  func testContextualSelectionNamesTaskCountAndExplainsCreationLimits() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    model.assets = [SourceAsset(url: root.appendingPathComponent("One.jpg")), SourceAsset(url: root.appendingPathComponent("Two.jpg"))]
    model.selectPhotos(for: .convert)
    model.selection = Set(model.assets.map(\.id))
    let controls = WorkspaceFilterControls(model: model)
    let convert = try XCTUnwrap(model.gifSelectionContext)
    XCTAssertEqual(controls.selectionTitle(convert), "Choose photos to convert")
    XCTAssertEqual(controls.primaryTitle(convert), "Convert 2 Photos")
    XCTAssertEqual(controls.selectionSummary, "2 selected")
    XCTAssertNil(controls.selectionGuidance(convert))
    model.query = "not-found"
    XCTAssertEqual(controls.selectionSummary, "2 selected · 2 hidden by filters")
    model.query = ""
    model.finishGIFSelection(cancel: true)

    var gif = GIFProject()
    gif.frames = (0..<999).map { _ in GIFFrame(sourceID: model.assets[0].id) }
    model.gifProject = gif
    model.selectGIFPhotos(adding: true)
    model.selection = Set(model.assets.map(\.id))
    let adding = try XCTUnwrap(model.gifSelectionContext)
    XCTAssertFalse(model.selectionContextValid)
    XCTAssertEqual(controls.primaryTitle(adding), "Add 2 Photos")
    XCTAssertEqual(controls.selectionGuidance(adding), "GIFs support up to 1,000 frames. Choose no more than 1 photo.")
    model.selection = [model.assets[0].id]
    XCTAssertTrue(model.selectionContextValid)
    XCTAssertNil(controls.selectionGuidance(adding))
    XCTAssertEqual(controls.primaryTitle(adding), "Add 1 Photo")

    model.gifSelectionContext?.task = .collage
    model.selection = Set((0...CollageProject.maximumCells).map { _ in UUID() })
    let collage = try XCTUnwrap(model.gifSelectionContext)
    XCTAssertFalse(model.selectionContextValid)
    XCTAssertTrue(try XCTUnwrap(controls.selectionGuidance(collage)).contains(CollageProject.maximumCells.formatted()))
    model.gifSelectionContext?.task = .batch
    let batch = try XCTUnwrap(model.gifSelectionContext)
    XCTAssertTrue(model.selectionContextValid, "Batch does not inherit the collage limit")
    XCTAssertNil(controls.selectionGuidance(batch))
  }

  func testResetWorkspaceManualFramingExcludesHiddenCreationSources() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    model.assets = [SourceAsset(url: root.appendingPathComponent("Visible.jpg")), SourceAsset(url: root.appendingPathComponent("Retained.jpg"))]
    for source in model.assets {
      var config = model.configuration(for: source)
      config.crop.framing = .manual
      config.crop.zoom = 1.4
      config.adjustments.exposure = 0.3
      model.setImageConfiguration(config, for: source.id)
    }
    let retained = model.assets[1]
    model.hiddenSourceIDs = [retained.id]
    let retainedConfiguration = model.configuration(for: retained)
    model.resetWorkspaceManualFraming()
    XCTAssertEqual(model.configuration(for: retained), retainedConfiguration)
    XCTAssertNotEqual(model.configuration(for: model.assets[0]).crop.framing, .manual)
    XCTAssertEqual(model.configuration(for: model.assets[0]).adjustments.exposure, 0.3)
  }

  func testBatchSelectionExplanationAppearsOnlyForDifferentOrHiddenSelection() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    model.assets = (0..<3).map { SourceAsset(url: root.appendingPathComponent("Photo \($0).jpg")) }
    let inputs = Set(model.assets.prefix(2).map(\.id))
    model.beginBatch(ids: Array(inputs)); model.selection = inputs
    XCTAssertFalse(model.batchSelectionNeedsExplanation)
    model.query = "no matches"
    XCTAssertTrue(model.batchSelectionNeedsExplanation)
    XCTAssertEqual(model.batchSelectionExplanation, "2 selected separately · 2 hidden by filters")
    model.showAllWorkspacePhotos()
    XCTAssertFalse(model.batchSelectionNeedsExplanation)
    model.selection = [model.assets[2].id]
    XCTAssertTrue(model.batchSelectionNeedsExplanation)
    XCTAssertEqual(model.batchSelectionExplanation, "1 selected separately")
    XCTAssertEqual(model.batchInputIDs, inputs)
  }

  func testRoutineFeedbackDismissalNeverAppliesToWorkErrorsCancellationOrPartialResults() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    model.assets = [SourceAsset(url: root.appendingPathComponent("Photo.jpg"))]
    model.status = "Restored 1 images."
    XCTAssertTrue(model.canDismissRoutineWorkspaceStatus)
    model.running = true; XCTAssertFalse(model.canDismissRoutineWorkspaceStatus); model.running = false
    model.issues = ["A source could not be read"]
    XCTAssertFalse(model.canDismissRoutineWorkspaceStatus)
    model.issues = []
    model.status = "Import cancelled. 1 completed images are retained."
    XCTAssertFalse(model.canDismissRoutineWorkspaceStatus)
    model.status = "Imported 0 images · 1 duplicates skipped · 0 failed."
    XCTAssertTrue(model.canDismissRoutineWorkspaceStatus)
    model.importFailed = 1
    XCTAssertFalse(model.canDismissRoutineWorkspaceStatus)
    model.importFailed = 0
    model.results = [ProcessingResult(source: model.assets[0], error: "Export failed")]
    XCTAssertFalse(model.canDismissRoutineWorkspaceStatus)
    model.results = []
    model.status = "Source permission unavailable"
    XCTAssertFalse(model.canDismissRoutineWorkspaceStatus, "Unknown status messages must remain visible")
  }

  func testSecondarySidebarFiltersStayProminentForWarningsOrActiveZeroState() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root, startInLibrary: true)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    model.assets = [SourceAsset(url: root.appendingPathComponent("Visible.jpg")), SourceAsset(url: root.appendingPathComponent("Retained.jpg"))]
    model.hiddenSourceIDs = [model.assets[1].id]
    let sidebar = LibrarySidebar(model: model)
    XCTAssertFalse(sidebar.prominent(.review))
    XCTAssertFalse(sidebar.prominent(.privacyReview))
    model.sensitivity.mark(model.assets[1].id, forReview: true)
    XCTAssertEqual(sidebar.count(.privacyReview), 0, "Hidden creation sources are not workspace review rows")
    model.sensitivity.mark(model.assets[0].id, forReview: true)
    XCTAssertTrue(sidebar.prominent(.privacyReview))
    XCTAssertEqual(sidebar.count(.privacyReview), 1)
    model.selection = [model.assets[0].id]
    model.showLibrary(.review)
    XCTAssertEqual(sidebar.count(.review), 0)
    XCTAssertTrue(sidebar.prominent(.review), "An active empty filter must remain visible")
    XCTAssertEqual(model.selection, [model.assets[0].id])
  }

}
