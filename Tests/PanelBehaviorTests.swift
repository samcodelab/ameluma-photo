import Foundation
import XCTest
import CoreImage
import ImageIO
import FramepebbleCore
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class PanelBehaviorTests: XCTestCase {
  func testFloatingOptionsRemainReachableAfterResizeAndSnapAwayFromPhoto() {
    for available in [CGSize(width: 1194, height: 700), CGSize(width: 900, height: 400), CGSize(width: 390, height: 500)] {
      let panel = CGSize(width: min(340, available.width - 24), height: min(260, available.height - 24))
      for position in ToolPanelPosition.allCases {
        let point = position.origin(in: available, panel: panel, toolIndex: 8)
        XCTAssertGreaterThanOrEqual(point.x, 12)
        XCTAssertGreaterThanOrEqual(point.y, 12)
        XCTAssertLessThanOrEqual(point.x + panel.width, available.width - 12)
        XCTAssertLessThanOrEqual(point.y + panel.height, available.height - 12)
      }
      let left = ToolPanelPosition.snapped(origin: CGPoint(x: -40, y: 0), panel: panel, available: available)
      XCTAssertEqual(left, .topLeading)
      let right = ToolPanelPosition.snapped(origin: CGPoint(x: available.width, y: available.height), panel: panel, available: available)
      XCTAssertEqual(right, .bottomTrailing)
      XCTAssertNotEqual(left.origin(in: available, panel: panel, toolIndex: 4), right.origin(in: available, panel: panel, toolIndex: 4))
    }
  }

  func testWatermarkedPhotoToGIFKeepsCapturedEditsAndIndependentHistory() throws {
    let model = workspace()
    let photo = model.assets[0]
    model.openPhoto(photo); model.choosePhotoInspector(.watermark)
    model.updateField(\.watermark.enabled, value: true, fields: [.watermark_enabled])
    model.updateField(\.watermark.text, value: "Demo mark", fields: [.watermark_text])
    let captured = model.configuration(for: photo)
    model.startGIF(ids: [photo.id, model.assets[1].id])
    XCTAssertEqual(model.workflow, .gif)
    XCTAssertEqual(model.gifProject?.frames.first?.configuration, captured)
    XCTAssertEqual(model.configuration(for: photo), captured)
    XCTAssertFalse(model.overlayEditor)
    model.openPhoto(photo)
    XCTAssertEqual(model.inspectorTask, .watermark)
    XCTAssertEqual(model.configuration(for: photo), captured)
  }

  func testInspectorReadoutsAvoidFalsePrecision() {
    XCTAssertEqual(EditorChrome.value(0.49957624, percentage: true), EditorChrome.value(0.5, percentage: true))
    XCTAssertEqual(EditorChrome.value(1.00001, percentage: false), EditorChrome.value(1, percentage: false))
    XCTAssertNotEqual(EditorChrome.value(0.25, percentage: false), EditorChrome.value(0.26, percentage: false))
    XCTAssertGreaterThanOrEqual(EditorChrome.toolExtent, 32)
    #if os(iOS)
    XCTAssertGreaterThanOrEqual(EditorChrome.toolExtent, 44)
    #endif
  }
  func testRetouchEntryRestoresSelectionAndKeepsBatchInputs() throws {
    let model = workspace()
    let photos = model.assets
    model.beginBatch(ids: photos.prefix(2).map(\.id))
    let inputs = model.batchInputIDs
    model.selection = [photos[0].id, photos[1].id]
    let selection = model.selection
    model.selectPhotos(for: .retouch)
    model.selection = Set(photos.prefix(2).map(\.id))
    XCTAssertFalse(model.selectionContextValid)
    model.finishGIFSelection(cancel: true)
    XCTAssertEqual(model.selection, selection)
    XCTAssertFalse(model.overlayEditor)
    model.selectPhotos(for: .retouch)
    model.selection = [photos[2].id]
    XCTAssertTrue(model.selectionContextValid)
    model.finishGIFSelection(cancel: false)
    XCTAssertTrue(model.overlayEditor)
    XCTAssertTrue(model.overlayRetouch)
    XCTAssertEqual(model.current?.id, photos[2].id)
    XCTAssertEqual(model.selection, selection)
    XCTAssertEqual(model.batchInputIDs, inputs)
  }
  func testFiltersPatchOnlyCapturedPhotosAndRemainIndependentInGIFs() throws {
    let model = workspace()
    let first = model.assets[0], second = model.assets[1], other = model.assets[2]
    var original = model.configuration(for: first)
    original.adjustments.exposure = 0.4; original.masks = [PrivacyMask()]
    model.setImageConfiguration(original, for: first.id)
    model.beginBatch(ids: [first.id, second.id], tool: .adjust)
    let inputs = model.batchInputIDs
    model.selection = [other.id]; model.query = other.name
    var look = model.controlConfiguration; look.look = .warm; look.lookStrength = 0.65
    model.applyChange(ConfigurationPatch(values: look, fields: [.look, .lookStrength]))
    XCTAssertEqual(model.configuration(for: first).look, .warm)
    XCTAssertEqual(model.configuration(for: second).lookStrength, 0.65)
    XCTAssertNil(model.configuration(for: other).look)
    XCTAssertEqual(model.configuration(for: first).adjustments, original.adjustments)
    XCTAssertEqual(model.configuration(for: first).masks, original.masks)
    model.undo(); XCTAssertNil(model.configuration(for: first).look)
    model.redo(); XCTAssertEqual(model.configuration(for: first).look, .warm)
    model.startGIF(ids: [first.id, second.id])
    let frames = try XCTUnwrap(model.gifProject).frames
    var remove = model.configuration(for: first); remove.look = nil
    model.applyChange(ConfigurationPatch(values: remove, fields: [.look]), ids: [first.id])
    XCTAssertNil(model.configuration(for: first).look)
    XCTAssertEqual(model.gifProject?.frames, frames)
    let saved = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(model.document()))
    XCTAssertEqual(saved.gifProject?.frames, frames)
    XCTAssertEqual(saved.edits.configuration(for: second.id).look, .warm)
    XCTAssertEqual(model.batchInputIDs, inputs)
    XCTAssertEqual(model.selection, [other.id])
  }
  func testSinglePhotoBackToWorkspacePreservesEditsSelectionAndCapturedBatch() throws {
    let model = workspace()
    let first = model.assets[0], next = model.assets[1], other = model.assets[2]
    model.beginBatch(ids: [first.id, other.id])
    let inputs = model.batchInputIDs
    model.selection = [other.id]; model.query = first.name
    model.openPhoto(first)
    model.updateField(\.adjustments.exposure, value: 0.35, fields: [.adjustments_exposure])
    model.updateField(\.look, value: PhotoLook.warm, fields: [.look])
    let edits = model.edits
    model.showLibrary()
    XCTAssertTrue(model.browsingLibrary)
    XCTAssertEqual(model.edits, edits)
    XCTAssertEqual(model.selection, [other.id]); XCTAssertEqual(model.batchInputIDs, inputs)
    model.openPhoto(next)
    XCTAssertEqual(model.current?.id, next.id)
    XCTAssertEqual(model.configuration(for: first).adjustments.exposure, 0.35)
    XCTAssertEqual(model.configuration(for: first).look, .warm)
    XCTAssertEqual(model.selection, [other.id]); XCTAssertEqual(model.batchInputIDs, inputs)
    let restored = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(model.document()))
    XCTAssertEqual(restored.edits, model.edits)
    // Legacy navigation IDs remain readable, but are no longer mobile document controls.
    XCTAssertEqual(restored.editorTabIDs, model.editorTabs)
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    model.showLibrary()
    XCTAssertFalse(model.browsingLibrary, "Back cannot abandon an active draft")
    XCTAssertEqual(model.current?.id, next.id)
  }
  func workspace() -> Workspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("panel-tests-" + UUID().uuidString)
    let model = Workspace(directory: root)
    model.assets = (1...3).map { SourceAsset(url: root.appendingPathComponent("Photo \($0).png")) }
    addTeardownBlock { await MainActor.run { model.persistenceTask?.cancel() }; try? FileManager.default.removeItem(at: root) }
    return model
  }
  func testInputGalleryViewDoesNotChangeCapturedInputsOrHiddenSelection() {
    let model = workspace()
    model.beginBatch(ids: model.assets.prefix(2).map(\.id))
    let captured = model.batchInputIDs
    model.selection = Set(model.assets.map(\.id))
    XCTAssertEqual(model.galleryPhotos(operationOnly: true).count, 2)
    XCTAssertEqual(model.galleryPhotos(operationOnly: false).count, 3)
    model.query = model.assets[2].name
    XCTAssertTrue(model.galleryPhotos(operationOnly: true).isEmpty)
    XCTAssertEqual(model.galleryPhotos(operationOnly: false).map(\.id), [model.assets[2].id])
    XCTAssertEqual(model.batchInputIDs, captured)
    XCTAssertEqual(model.selection.count, 3)
    model.showLibrary()
    XCTAssertEqual(model.galleryPhotos(operationOnly: true).map(\.id), [model.assets[2].id])
    XCTAssertEqual(model.batchInputIDs, captured)
  }

  func testVisibleHistoryUsesDraftThenPhotoWithoutChangingBatchInputs() throws {
    let model = workspace()
    model.beginBatch(ids: model.assets.prefix(2).map(\.id))
    let batch = model.batchInputIDs
    let photo = model.assets[2]
    model.openPhoto(photo)
    model.updateField(\.adjustments.exposure, value: 0.6, fields: [.adjustments_exposure])
    let photoEdits = model.edits
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    var draft = OverlayEditingSession(sourceID: photo.id, configuration: model.configuration(for: photo))
    var masked = draft.current; masked.masks = [PrivacyMask()]; draft.update(masked)
    model.overlaySession = draft
    model.undoActiveWorkspace()
    XCTAssertTrue(try XCTUnwrap(model.overlaySession).current.masks.isEmpty)
    XCTAssertEqual(model.edits, photoEdits)
    model.redoActiveWorkspace()
    XCTAssertEqual(model.overlaySession?.current.masks, masked.masks)
    XCTAssertTrue(model.activatePhotoTool(.adjust, resolvingDraft: .apply))
    model.undoActiveWorkspace()
    XCTAssertEqual(model.edits, photoEdits)
    model.redoActiveWorkspace()
    XCTAssertEqual(model.configuration(for: photo).masks, masked.masks)
    XCTAssertEqual(model.batchInputIDs, batch)
  }
  func testOperationSummaryDistinguishesSelectionFromCapturedInputs() {
    let model = workspace()
    let captured = [model.assets[0].id]
    model.beginBatch(ids: captured)
    model.selection = Set(model.assets.map(\.id))
    XCTAssertEqual(model.operationSelectionSummary, "1 fixed input · 3 in Workspace · 3 selected")
    XCTAssertEqual(model.targets.map(\.id), captured)
    model.query = "Photo 3"
    XCTAssertEqual(model.targets.map(\.id), captured)
    XCTAssertEqual(model.operationSelectionSummary, "1 fixed input · 3 in Workspace · 3 selected")
    model.openPhoto(model.assets[2])
    XCTAssertNil(model.operationSelectionSummary)
    XCTAssertEqual(model.batchInputIDs, Set(captured))
  }
  func testCompactBatchControlsKeepCapturedScopeAndSparsePhotoEdits() {
    let model = workspace()
    let first = model.assets[0], second = model.assets[1], other = model.assets[2]
    model.openPhoto(first)
    model.updateField(\.adjustments.exposure, value: 0.7, fields: [.adjustments_exposure])
    model.beginBatch(ids: [first.id, second.id])
    model.selection = [other.id]
    model.query = other.name
    model.inspectorTask = .resize
    model.updateField(\.width, value: 2048, fields: [.width])
    model.rotatePhoto(other.id)
    XCTAssertEqual(model.batchInputIDs, [first.id, second.id])
    XCTAssertEqual(model.selection, [other.id])
    XCTAssertEqual(Set(model.targets.map(\.id)), [first.id, second.id])
    XCTAssertEqual(model.configuration(for: first).adjustments.exposure, 0.7)
    XCTAssertEqual(model.configuration(for: first).width, 2048)
    XCTAssertEqual(model.configuration(for: second).width, 2048)
    XCTAssertEqual(model.configuration(for: first).quarterTurns, 0)
    XCTAssertEqual(model.configuration(for: second).quarterTurns, 0)
    XCTAssertEqual(model.configuration(for: other).quarterTurns, 1)
    model.undo()
    XCTAssertEqual(model.configuration(for: other).quarterTurns, 0)
    XCTAssertEqual(model.configuration(for: first).width, 2048)
  }
  func testConciseSelectionStatusCountsHiddenPhotosWithoutChangingOperation() {
    let model = workspace()
    let captured = [model.assets[0].id]
    model.beginBatch(ids: captured)
    model.selection = Set(model.assets.map(\.id))
    XCTAssertEqual(model.workspaceSelectionStatus, "3 selected · 0 hidden")
    model.query = "Photo 3"
    XCTAssertEqual(model.workspaceSelectionStatus, "3 selected · 2 hidden")
    XCTAssertEqual(Set(model.targets.map(\.id)), Set(captured))
    XCTAssertEqual(model.selection.count, 3)
    model.query = ""
    XCTAssertEqual(model.workspaceSelectionStatus, "3 selected · 0 hidden")
  }
  func testContextualAdjustmentSwitchPreservesPhotoEditsAndBatchMembership() {
    let model = workspace()
    let input = model.assets[0], photo = model.assets[1], other = model.assets[2]
    model.beginBatch(ids: [input.id])
    model.openPhoto(photo)
    model.updateField(\.adjustments.exposure, value: 0.6, fields: [.adjustments_exposure])
    let selectedControl = AdjustmentParameter.saturation
    let captured = model.batchInputIDs
    let selected = model.selection
    let before = model.configuration(for: photo)
    // Changing the contextual picker is presentation-only; its control writes the existing patch path.
    model.updateField(selectedControl.keyPath, value: 1.3, fields: [selectedControl.field])
    let after = model.configuration(for: photo)
    XCTAssertEqual(after.adjustments.saturation, 1.3)
    XCTAssertEqual(after.adjustments.exposure, 0.6)
    XCTAssertEqual(after.width, before.width)
    XCTAssertEqual(after.crop, before.crop)
    XCTAssertEqual(model.configuration(for: other).adjustments.saturation, 1)
    XCTAssertEqual(model.configuration(for: input).adjustments.saturation, 1)
    XCTAssertEqual(model.batchInputIDs, captured)
    XCTAssertEqual(model.selection, selected)
    model.undo()
    XCTAssertEqual(model.configuration(for: photo), before)
    model.redo()
    XCTAssertEqual(model.configuration(for: photo), after)
  }
  func testPortraitBatchPropertiesNeverReserveTheGalleryColumn() {
    XCTAssertTrue(EditorPanelLayout.supportsBatchInspector(CGSize(width: 1194, height: 834), accessibility: false))
    XCTAssertFalse(EditorPanelLayout.supportsBatchInspector(CGSize(width: 834, height: 1194), accessibility: false))
    XCTAssertFalse(EditorPanelLayout.supportsBatchInspector(CGSize(width: 900, height: 700), accessibility: false))
    XCTAssertFalse(EditorPanelLayout.supportsBatchInspector(CGSize(width: 1194, height: 834), accessibility: true))
  }
  func testWatermarkRemovalIsScopedUndoableAndPreservesSettings() {
    let model = workspace()
    model.beginBatch(ids: model.assets.prefix(2).map(\.id))
    let batch = model.batchInputIDs
    let photo = model.assets[2]
    model.openPhoto(photo)
    var configuration = model.configuration(for: photo)
    configuration.watermark.enabled = true
    configuration.watermark.text = "My watermark"
    configuration.watermark.opacity = 0.47
    configuration.adjustments.exposure = 0.6
    model.setImageConfiguration(configuration, for: photo.id)
    let otherPhotos = model.assets.prefix(2).map { model.configuration(for: $0) }
    model.updateField(\.watermark.enabled, value: false, fields: [.watermark_enabled])
    var removed = configuration; removed.watermark.enabled = false
    XCTAssertEqual(model.configuration(for: photo), removed)
    XCTAssertEqual(model.assets.prefix(2).map { model.configuration(for: $0) }, otherPhotos)
    XCTAssertEqual(model.batchInputIDs, batch)
    model.undo()
    XCTAssertEqual(model.configuration(for: photo), configuration)
    model.redo()
    XCTAssertEqual(model.configuration(for: photo), removed)
  }
  func testResizeQuickTaskCapturesInputsAndCancelPreservesPreviousTask() {
    let model = workspace()
    let original = [model.assets[0].id]
    model.beginConversion(ids: original)
    model.selectPhotos(for: .resize)
    model.selection = [model.assets[1].id]
    model.finishGIFSelection(cancel: true)
    XCTAssertEqual(model.conversionInputIDs, Set(original))
    XCTAssertEqual(model.inspectorTask, .output)
    model.selectPhotos(for: .resize)
    let requested = Set(model.assets.suffix(2).map(\.id))
    model.selection = requested
    model.finishGIFSelection(cancel: false)
    XCTAssertEqual(model.workflow, .batch)
    XCTAssertEqual(model.inspectorTask, .resize)
    XCTAssertEqual(model.batchInputIDs, requested)
    XCTAssertNil(model.conversionInputIDs)
    model.selection = [model.assets[0].id]
    XCTAssertEqual(Set(model.targets.map(\.id)), requested)
  }
  func testOperationHeaderKeepsCapturedInputsWhenGallerySelectionChanges() {
    let model = workspace()
    let ids = Array(model.assets.prefix(2).map(\.id))
    model.beginConversion(ids: ids)
    XCTAssertEqual(model.operationTitle, "Convert · 2 photos")
    model.selection = [model.assets[2].id]
    model.query = "Photo 3"
    XCTAssertEqual(model.operationTitle, "Convert · 2 photos")
    XCTAssertEqual(Set(model.targets.map(\.id)), Set(ids))
    model.selectPhotos(for: .convert)
    model.selection = [model.assets[2].id]
    model.finishGIFSelection(cancel: true)
    XCTAssertEqual(model.operationTitle, "Convert · 2 photos")
    XCTAssertEqual(Set(model.targets.map(\.id)), Set(ids))
  }
  func testToolSwitchingAndTabsPreserveEditsAndBatchMembership() {
    let model = workspace()
    let ids = model.assets.prefix(2).map(\.id)
    model.beginBatch(ids: Array(ids))
    var patch = model.settings; patch.adjustments.exposure = 0.7
    model.applyChange(ConfigurationPatch(values: patch, fields: [.adjustments_exposure]))
    let snapshot = model.edits
    let batch = model.batchInputIDs
    for task in InspectorTask.allCases {
      model.choosePhotoInspector(task)
      XCTAssertEqual(model.edits, snapshot)
      XCTAssertEqual(model.batchInputIDs, batch)
    }
    model.openPhoto(model.assets[2])
    XCTAssertEqual(model.operationTitle, "This photo")
    model.openPhoto(model.assets[0])
    model.activateEditorTab(model.assets[2].id)
    model.closeEditorTab(model.assets[0].id)
    XCTAssertEqual(model.batchInputIDs, batch)
    XCTAssertEqual(model.edits, snapshot)
  }
  func testPrivacyAndAnnotationToolSwitchKeepsOneDraftAndBatchMembership() {
    let model = workspace()
    model.beginBatch(ids: model.assets.prefix(2).map(\.id))
    let batch = model.batchInputIDs
    model.openPhoto(model.assets[2])
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    let source = model.assets[2]
    var draft = OverlayEditingSession(sourceID: source.id, configuration: model.configuration(for: source))
    var configuration = draft.current
    configuration.masks = [PrivacyMask()]
    draft.update(configuration)
    model.overlaySession = draft
    let masks = draft.current.masks
    XCTAssertTrue(model.activatePhotoTool(.annotate))
    XCTAssertFalse(model.overlayStartsWithMasks)
    XCTAssertEqual(model.overlaySession?.current.masks, masks)
    XCTAssertTrue(model.overlaySession?.canUndo == true)
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    XCTAssertTrue(model.overlayStartsWithMasks)
    XCTAssertFalse(model.activatePhotoTool(.adjust), "Leaving a changed draft needs a resolution")
    XCTAssertTrue(model.overlayEditor)
    XCTAssertEqual(model.overlaySession?.current.masks, masks)
    XCTAssertTrue(model.configuration(for: source).masks.isEmpty)
    XCTAssertTrue(model.activatePhotoTool(.adjust, resolvingDraft: .apply))
    XCTAssertFalse(model.overlayEditor)
    XCTAssertNil(model.overlaySession)
    XCTAssertEqual(model.configuration(for: source).masks, masks)
    XCTAssertEqual(model.inspectorTask, .adjust)
    XCTAssertEqual(model.batchInputIDs, batch)
    XCTAssertEqual(model.current?.id, source.id)
    XCTAssertTrue(model.configuration(for: model.assets[0]).masks.isEmpty)
  }
  func testToolSwitchDiscardAndConcurrentEditProtection() {
    let model = workspace()
    model.openPhoto(model.assets[0])
    let photo = model.assets[0]
    let original = model.configuration(for: photo)
    model.openOverlayEditor(for: photo)
    var draft = OverlayEditingSession(sourceID: photo.id, configuration: original)
    var edited = original; edited.masks = [PrivacyMask()]; draft.update(edited)
    model.overlaySession = draft
    var newer = original; newer.adjustments.exposure = 0.7
    model.setImageConfiguration(newer, for: photo.id)
    XCTAssertFalse(model.activatePhotoTool(.crop, resolvingDraft: .apply))
    XCTAssertTrue(model.overlayEditor)
    XCTAssertEqual(model.overlaySession?.current, edited)
    XCTAssertEqual(model.configuration(for: photo), newer)
    XCTAssertTrue(model.activatePhotoTool(.crop, resolvingDraft: .discard))
    XCTAssertFalse(model.overlayEditor)
    XCTAssertTrue(model.precision)
    XCTAssertEqual(model.configuration(for: photo), newer)
  }
  func testRetouchDraftSharesHistoryAndNeverChangesBatchOrPresets() throws {
    let model = workspace(); model.beginBatch(ids: model.assets.prefix(2).map(\.id))
    let inputs = model.batchInputIDs, photo = model.assets[2]
    model.openPhoto(photo)
    XCTAssertTrue(model.activatePhotoTool(.retouch))
    XCTAssertTrue(model.overlayRetouch)
    var draft = OverlayEditingSession(sourceID: photo.id, configuration: model.configuration(for: photo))
    var edited = draft.current, stroke = RetouchStroke()
    stroke.points = [NormalizedPoint(0.5, 0.5)]; stroke.source = NormalizedPoint(0.2, 0.2)
    edited.retouchStrokes = [stroke]; draft.update(edited); model.overlaySession = draft
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    XCTAssertFalse(model.overlayRetouch)
    XCTAssertEqual(model.overlaySession?.current.retouchStrokes, [stroke])
    model.overlaySession?.undo(); XCTAssertTrue(model.overlaySession?.current.retouchStrokes.isEmpty == true)
    model.overlaySession?.redo(); XCTAssertEqual(model.overlaySession?.current.retouchStrokes, [stroke])
    XCTAssertTrue(model.activatePhotoTool(.adjust, resolvingDraft: .apply))
    XCTAssertEqual(model.configuration(for: photo).retouchStrokes, [stroke])
    XCTAssertEqual(model.batchInputIDs, inputs)
    XCTAssertTrue(model.configuration(for: model.assets[0]).retouchStrokes.isEmpty)
    model.saveProfile(name: "Retouch should not become a batch preset")
    XCTAssertTrue(try XCTUnwrap(model.profiles.last?.processing).retouchStrokes.isEmpty)
    var profile = ExportProfile(); profile.processing = ProcessingConfiguration()
    XCTAssertEqual(model.exportConfiguration(for: photo, profile: profile).retouchStrokes, [stroke])
    model.restoreOriginalPhoto(photo.id)
    XCTAssertTrue(model.configuration(for: photo).retouchStrokes.isEmpty)
  }
  func testContextToolsApplyCombinedDraftThenUndoWithoutChangingOtherPhotos() throws {
    let model = workspace()
    let photo = model.assets[2], others = Array(model.assets.prefix(2))
    model.beginBatch(ids: others.map(\.id))
    let inputs = model.batchInputIDs
    model.openPhoto(photo)
    model.updateField(\.adjustments.exposure, value: 0.35, fields: [.adjustments_exposure])
    let before = model.configuration(for: photo)
    XCTAssertTrue(model.activatePhotoTool(.retouch))
    var draft = OverlayEditingSession(sourceID: photo.id, configuration: before)
    var edited = before
    edited.retouchStrokes = [RetouchStroke()]
    draft.update(edited); model.overlaySession = draft
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    edited.masks = [PrivacyMask()]
    model.overlaySession?.update(edited)
    XCTAssertFalse(model.activatePhotoTool(.adjust))
    XCTAssertEqual(model.configuration(for: photo), before)
    XCTAssertTrue(model.activatePhotoTool(.adjust, resolvingDraft: .apply))
    XCTAssertEqual(model.configuration(for: photo), edited)
    model.undo()
    XCTAssertEqual(model.configuration(for: photo), before)
    model.redo()
    XCTAssertEqual(model.configuration(for: photo), edited)
    XCTAssertEqual(model.batchInputIDs, inputs)
    for other in others {
      XCTAssertTrue(model.configuration(for: other).masks.isEmpty)
      XCTAssertTrue(model.configuration(for: other).retouchStrokes.isEmpty)
      XCTAssertEqual(model.configuration(for: other).adjustments.exposure, 0)
    }
  }
  func testTabletLayoutAdaptsToOrientationAndLargeText() {
    XCTAssertTrue(EditorPanelLayout.usesTabletRail(CGSize(width: 1194, height: 834)))
    XCTAssertFalse(EditorPanelLayout.usesTabletRail(CGSize(width: 834, height: 1194)))
    XCTAssertFalse(EditorPanelLayout.usesTabletRail(CGSize(width: 600, height: 500)))
    XCTAssertFalse(EditorPanelLayout.usesTabletRail(CGSize(width: 1194, height: 834), accessibility: true))
  }
  func testNewPrivacyTraceDefaultsCloseAroundTheTracedArea() throws {
    XCTAssertEqual(PrivacyToolDefaults.effects.first, .pixelate)
    XCTAssertEqual(PrivacyToolDefaults.shapes.first, .freehand)
    let trace = [NormalizedPoint(0.2, 0.2), NormalizedPoint(0.8, 0.2), NormalizedPoint(0.2, 0.8)]
    let mask = try XCTUnwrap(PrivacyToolDefaults.mask(points: trace))
    XCTAssertEqual(mask.effect, .pixelate)
    XCTAssertEqual(mask.shape, .freehand)
    XCTAssertEqual(mask.x, 0.2, accuracy: 0.00001)
    XCTAssertEqual(mask.width, 0.6, accuracy: 0.00001)
    let path = PrivacyRenderer.path(shape: mask.shape,
      rect: CGRect(x: mask.x * 100, y: mask.y * 100, width: mask.width * 100, height: mask.height * 100),
      points: mask.points, output: CGSize(width: 100, height: 100))
    XCTAssertTrue(path.contains(CGPoint(x: 30, y: 30)))
    XCTAssertFalse(path.contains(CGPoint(x: 70, y: 70)), "The untraced portion of the bounding box must stay outside the mask")
    XCTAssertNil(PrivacyToolDefaults.mask(points: Array(trace.prefix(2))))
    XCTAssertNil(PrivacyToolDefaults.mask(points: [NormalizedPoint(0, 0), NormalizedPoint(0.5, 0.5), NormalizedPoint(1, 1)]))
    XCTAssertNil(PrivacyToolDefaults.mask(points: [NormalizedPoint(.nan, 0)]))
    let legacy = PrivacyMask()
    let restored = try JSONDecoder().decode(PrivacyMask.self, from: JSONEncoder().encode(legacy))
    XCTAssertEqual(restored.shape, .rectangle)
    XCTAssertEqual(restored.effect, .cover)
    XCTAssertEqual(restored, legacy)
  }
  func testOverlayInspectorLeavesRoomForDirectManipulation() {
    XCTAssertFalse(EditorPanelLayout.supportsOverlayInspector(width: 834, accessibility: false))
    XCTAssertFalse(EditorPanelLayout.supportsOverlayInspector(width: 600, accessibility: false))
    XCTAssertTrue(EditorPanelLayout.supportsOverlayInspector(width: 1194, accessibility: false))
    XCTAssertFalse(EditorPanelLayout.supportsOverlayInspector(width: 1194, accessibility: true))
    XCTAssertGreaterThanOrEqual(920 - 62 - EditorPanelLayout.inspectorWidth - 1, 540)
  }
  func testPresentationWidthsProtectCanvasAndKeepUserNavigationChoice() {
    XCTAssertFalse(EditorPanelLayout.supportsInspector(760))
    XCTAssertTrue(EditorPanelLayout.supportsInspector(761))
    for width: CGFloat in [779, 780, 781, 1024] { XCTAssertTrue(EditorPanelLayout.supportsInspector(width)) }
    XCTAssertFalse(EditorPanelLayout.navigationVisible(width: 1040, editing: true, preference: nil))
    XCTAssertFalse(EditorPanelLayout.navigationVisible(width: 1440, editing: true, preference: nil))
    XCTAssertTrue(EditorPanelLayout.navigationVisible(width: 1040, editing: false, preference: nil))
    XCTAssertTrue(EditorPanelLayout.navigationVisible(width: 1040, editing: true, preference: true))
    XCTAssertFalse(EditorPanelLayout.navigationVisible(width: 1440, editing: true, preference: false))
    XCTAssertGreaterThan((1040 - EditorPanelLayout.inspectorWidth - 5) / 1040, 0.65)
    let available = CGFloat(1040 - 221)
    let fitted = EditorPanelLayout.fittedInspectorWidth(requested: 420, available: available)
    XCTAssertGreaterThanOrEqual(available - fitted - 5, EditorPanelLayout.minimumCanvasWidth)
    XCTAssertEqual(EditorPanelLayout.fittedInspectorWidth(requested: 420, available: 1200), 420)
    XCTAssertTrue(EditorPanelLayout.expandedControls(height: 390, accessibility: false))
    XCTAssertTrue(EditorPanelLayout.expandedControls(height: 479, accessibility: false))
    XCTAssertFalse(EditorPanelLayout.expandedControls(height: 480, accessibility: false))
    XCTAssertTrue(EditorPanelLayout.expandedControls(height: 900, accessibility: true))
  }
  func testGIFEditorFocusResetsWhenOpeningShorterSavedCreation() {
    let first = UUID(), second = UUID(), frames = (0..<5).map { _ in UUID() }
    var focus = GIFEditorFocus()
    focus.reconcile(projectID: first, frames: frames)
    focus.frameIndex = 4; focus.selectedFrames = [frames[0], frames[4]]
    focus.annotationID = UUID(); focus.selectingFrames = true
    focus.reconcile(projectID: second, frames: [UUID()])
    XCTAssertEqual(focus.frameIndex, 0)
    XCTAssertTrue(focus.selectedFrames.isEmpty)
    XCTAssertNil(focus.annotationID)
    XCTAssertFalse(focus.selectingFrames)
  }
  func testKeyboardHeightChangeKeepsInlineEditorAndRotationAdapts() {
    var viewport = EditorPanelViewport()
    viewport.observe(CGSize(width: 390, height: 760))
    viewport.observe(CGSize(width: 390, height: 410))
    XCTAssertFalse(EditorPanelLayout.expandedControls(height: viewport.height(fallback: 410), accessibility: false),
      "Typing must not remove the inline form and dismiss its focused field")
    viewport.observe(CGSize(width: 844, height: 300))
    XCTAssertTrue(EditorPanelLayout.expandedControls(height: viewport.height(fallback: 300), accessibility: false))
    viewport.observe(CGSize(width: 390, height: 760))
    XCTAssertFalse(EditorPanelLayout.expandedControls(height: viewport.height(fallback: 760), accessibility: false))
  }
  func testGIFEditorFocusReconcilesUndoAndFrameRemovalWithoutLosingOtherSelection() {
    let project = UUID(), frames = (0..<4).map { _ in UUID() }
    var focus = GIFEditorFocus()
    focus.reconcile(projectID: project, frames: frames)
    focus.frameIndex = 3; focus.selectedFrames = [frames[0], frames[3]]; focus.selectingFrames = true
    focus.reconcile(projectID: project, frames: Array(frames.prefix(2)))
    XCTAssertEqual(focus.frameIndex, 1)
    XCTAssertEqual(focus.selectedFrames, [frames[0]])
    XCTAssertTrue(focus.selectingFrames)
    focus.reconcile(projectID: project, frames: [])
    XCTAssertEqual(focus.frameIndex, 0)
    XCTAssertTrue(focus.selectedFrames.isEmpty)
  }
}

extension PanelBehaviorTests {
  func testVersionedFilterSelectionIntensityHistoryAndOriginal() throws {
    let model=workspace();let source=model.assets[0]
    model.openPhoto(source)
    var c=model.configuration(for:source);c.adjustments.exposure=0.35;c.masks=[PrivacyMask()]
    c.autoEnhance=AutoEnhanceEdit(resolvedAdjustments:[]);c.look = .warm
    model.setImageConfiguration(c,for:source.id)
    XCTAssertTrue(model.activatePhotoTool(.filters))
    model.selectCreativeFilter("film.amber")
    XCTAssertNil(model.configuration(for:source).look)
    let initial=try XCTUnwrap(model.configuration(for:source).filterEdit)
    XCTAssertEqual(initial.intensity,0.7)
    model.beginInteraction();model.setFilterIntensity(0.30);model.setFilterIntensity(0.42);model.endInteraction()
    model.undo();XCTAssertEqual(model.configuration(for:source).filterEdit?.intensity,0.7)
    model.redo();XCTAssertEqual(model.configuration(for:source).filterEdit?.intensity,0.42)
    model.selectCreativeFilter("mono.noir")
    XCTAssertEqual(model.configuration(for:source).filterEdit?.intensity,0.42)
    XCTAssertEqual(model.configuration(for:source).filterEdit?.grainSeed,initial.grainSeed)
    model.selectCreativeFilter(nil)
    XCTAssertNil(model.configuration(for:source).filterEdit?.presetID)
    XCTAssertEqual(model.configuration(for:source).autoEnhance,c.autoEnhance)
    XCTAssertEqual(model.configuration(for:source).adjustments,c.adjustments)
    XCTAssertEqual(model.configuration(for:source).masks,c.masks)
    model.selectCreativeFilter("essentials.clean")
    XCTAssertEqual(model.configuration(for:source).filterEdit?.intensity,0.42)
    let document=try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(model.document()))
    XCTAssertEqual(document.edits.configuration(for:source.id),model.configuration(for:source))
    let committed=model.edits;model.filterComparisonActive=true
    XCTAssertEqual(model.configuration(for:source),committed.configuration(for:source.id),"Comparison must never mutate export instructions")
    model.filterComparisonActive=false
  }
  func writeFilterFixtures(_ model: Workspace) throws {
    try FileManager.default.createDirectory(at:model.directory,withIntermediateDirectories:true)
    let context=CIContext()
    let image=try XCTUnwrap(context.createCGImage(CIImage(color:CIColor(red:0.4,green:0.3,blue:0.2)).cropped(to:CGRect(x:0,y:0,width:24,height:16)),from:CGRect(x:0,y:0,width:24,height:16)))
    for asset in model.assets {
      let output=try XCTUnwrap(CGImageDestinationCreateWithURL(asset.url as CFURL,"public.png" as CFString,1,nil))
      CGImageDestinationAddImage(output,image,nil);XCTAssertTrue(CGImageDestinationFinalize(output))
    }
  }
  func testFilterBatchFrozenTargetsConcurrentEditMissingSourceAndGroupedUndo() async throws {
    let model=workspace();try writeFilterFixtures(model)
    let sources=model.assets
    var c=model.configuration(for:sources[0]);c.crop.centerX=0.2;c.autoEnhance=AutoEnhanceEdit();c.filterEdit=FilterEdit(grainSeed:97)
    model.setImageConfiguration(c,for:sources[0].id)
    model.presentFilterBatch(sources.map(\.id))
    let request=try XCTUnwrap(model.filterBatchRequest)
    model.selection=[sources[2].id];model.query="nothing"
    var concurrent=model.configuration(for:sources[1]);concurrent.adjustments.exposure=0.8
    model.setImageConfiguration(concurrent,for:sources[1].id)
    try FileManager.default.removeItem(at:sources[2].url)
    let result=await model.applyFilterBatch(request,presetID:"cinema.moody",intensity:0.3) {_ in}
    XCTAssertEqual(result.completed,1);XCTAssertEqual(result.skipped,1);XCTAssertEqual(result.failed,1)
    XCTAssertEqual(model.configuration(for:sources[0]).filterEdit?.grainSeed,97)
    XCTAssertEqual(model.configuration(for:sources[0]).autoEnhance,c.autoEnhance)
    XCTAssertEqual(model.configuration(for:sources[0]).crop,c.crop)
    XCTAssertEqual(model.configuration(for:sources[1]),concurrent)
    model.undo();XCTAssertEqual(model.configuration(for:sources[0]),c)
    XCTAssertEqual(model.configuration(for:sources[1]),concurrent)
  }
  func testFilterBatchCancellationKeepsCompletedInstructions() async throws {
    let model=workspace();try writeFilterFixtures(model)
    model.presentFilterBatch(model.assets.map(\.id))
    let request=try XCTUnwrap(model.filterBatchRequest)
    let task=Task { await model.applyFilterBatch(request,presetID:"film.daylight",intensity:0.7) { n in
      if n == 1 { withUnsafeCurrentTask { $0?.cancel() } }
    } }
    let result=await task.value
    XCTAssertTrue(result.cancelled);XCTAssertEqual(result.completed,1)
    XCTAssertEqual(model.configuration(for:model.assets[0]).filterEdit?.presetID,"film.daylight")
    XCTAssertNil(model.configuration(for:model.assets[1]).filterEdit)
    model.undo();XCTAssertNil(model.configuration(for:model.assets[0]).filterEdit)
  }
}
