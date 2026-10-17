import FramepebbleCore
import XCTest

@testable import FramepebbleiOS

@MainActor final class WorkflowWorkspaceTests: XCTestCase {
  func makeModel() throws -> Workspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    let model = Workspace(directory: root)
    model.assets = (0..<5).map {
      SourceAsset(url: model.directory.appendingPathComponent("photo-\($0).png"))
    }
    model.selected = model.assets[0].id
    return model
  }
  func testCollageGeometryChangesRequireIndependentMaskReview() throws {
    let model = try makeModel(); let source = model.assets[0]
    var config = model.configuration(for: source); config.masks = [PrivacyMask()]
    model.setImageConfiguration(config, for: source.id)
    model.selection = [source.id]; model.switchWorkflow(.collages); model.ensureCollageDocument()
    var changed = model.collage; changed.cells[0].crop.zoom = 2
    model.changeCollage(changed)
    XCTAssertTrue(model.collage.requiresPrivacyReview)
    model.confirmPrivacyCoverage(source.id)
    XCTAssertTrue(model.collage.requiresPrivacyReview, "Reviewing the source photo does not approve differently framed collage cells")
    changed = model.collage; changed.requiresPrivacyReview = false; model.changeCollage(changed)
    XCTAssertFalse(model.collage.requiresPrivacyReview)
    model.persistenceTask?.cancel()
  }
  func testCollageTabOrderingAndClosingOthersRetainEveryComposition() throws {
    let model = try makeModel(); model.selection = Set(model.assets.prefix(2).map(\.id))
    model.switchWorkflow(.collages); model.ensureCollageDocument()
    let first = try XCTUnwrap(model.activeCollageID)
    model.newCollage(); let second = try XCTUnwrap(model.activeCollageID)
    model.newCollage(); let third = try XCTUnwrap(model.activeCollageID)
    model.moveCollageTab(third, before: first)
    XCTAssertEqual(model.openCollageIDs, [third, first, second])
    model.closeOtherCollageTabs(keeping: first)
    XCTAssertEqual(model.openCollageIDs, [first]); XCTAssertEqual(model.savedCollages.count, 3)
    XCTAssertEqual(model.activeCollageID, first)
    model.persistenceTask?.cancel()
  }
  func testFixedBatchInputsIgnoreGalleryFilteringAndPersist() throws {
    let model = try makeModel()
    let ids = Set(model.assets.prefix(2).map(\.id))
    model.scope = .selected; model.batchInputIDs = ids
    model.selection = [model.assets[4].id]
    model.query = "no matching classification"
    XCTAssertEqual(Set(model.targets.map(\.id)), ids)
    XCTAssertEqual(model.editScopeHeading, "Editing 2 saved batch inputs")
    model.updateField(\.quality, value: 0.4, fields: [.quality])
    for asset in model.assets { XCTAssertEqual(model.configuration(for: asset).quality, ids.contains(asset.id) ? 0.4 : 0.85) }
    model.projectName = "Holiday"
    let saved = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(model.document()))
    XCTAssertEqual(saved.batchInputIDs, ids); XCTAssertEqual(saved.name, "Holiday")
    model.scope = .all; XCTAssertNil(model.batchInputIDs)
    model.persistenceTask?.cancel()
  }
  func testQuickFixKeepsNewerManualFieldsAndCreatesOneUndoStep() throws {
    let model = try makeModel()
    let asset = model.assets[0], second = model.assets[1]
    let before = model.configuration(for: asset)
    var automatic = before; automatic.adjustments.exposure = 0.7; automatic.adjustments.warmth = 0.2
    var manual = before; manual.adjustments.exposure = -0.4; manual.crop.centerX = 0.25
    model.setImageConfiguration(manual, for: asset.id)
    let snapshot = model.edits, steps = model.history.steps.count
    model.applyQuickFixUpdates([
      .init(asset: asset, before: before, after: automatic),
      .init(asset: second, before: before, after: automatic)
    ], title: "Auto Enhance")
    XCTAssertEqual(model.configuration(for: asset).adjustments.exposure, -0.4)
    XCTAssertEqual(model.configuration(for: asset).crop.centerX, 0.25)
    XCTAssertEqual(model.configuration(for: asset).adjustments.warmth, 0.2)
    XCTAssertEqual(model.configuration(for: second).adjustments.exposure, 0.7)
    XCTAssertEqual(model.history.steps.count, steps + 1)
    XCTAssertTrue(model.undoActionTitle.contains("Auto Enhance"))
    model.undo(); XCTAssertEqual(model.edits, snapshot)
    model.persistenceTask?.cancel()
  }
  func testCancelledQuickFixAppliesNothing() async throws {
    let model = try makeModel()
    let before = model.edits
    model.quickFix(.autoEnhance)
    model.quickFixTask?.cancel()
    await model.quickFixTask?.value
    XCTAssertEqual(model.edits, before)
    XCTAssertFalse(model.quickFixRunning)
    model.persistenceTask?.cancel()
  }
  func testPrivacyCoverageSurvivesFramingActionsAndProjectRoundTrip() throws {
    let model = try makeModel(); let asset = model.assets[0]
    var value = model.configuration(for: asset); value.masks = [PrivacyMask()]
    model.setImageConfiguration(value, for: asset.id)
    XCTAssertFalse(model.privacyCoverageNeedsReview(asset.id))
    value.crop.centerX = 0.7; model.setCrop(value.crop, for: asset.id)
    XCTAssertTrue(model.privacyCoverageNeedsReview(asset.id))
    model.acceptReview(asset.id)
    XCTAssertTrue(model.privacyCoverageNeedsReview(asset.id))
    let data = try JSONEncoder().encode(model.document())
    let saved = try JSONDecoder().decode(ProjectDocument.self, from: data)
    XCTAssertTrue(saved.privacyCoverageReviewIDs.contains(asset.id))
    model.confirmPrivacyCoverage(asset.id)
    XCTAssertFalse(model.privacyCoverageNeedsReview(asset.id))
    model.persistenceTask?.cancel()
  }
  func testCropCanKeepExportDimensionsAndTabManagementKeepsEdits() throws {
    let model = try makeModel()
    let a = model.assets[0], b = model.assets[1], c = model.assets[2]
    model.openPhoto(a); model.openPhoto(b); model.openPhoto(c)
    let before = model.configuration(for: c)
    model.applyPhotoCrop(CGRect(x: 100, y: 100, width: 400, height: 300), sourceSize: CGSize(width: 1000, height: 800), id: c.id, keepOutputSize: true)
    XCTAssertEqual(model.configuration(for: c).width, before.width)
    XCTAssertEqual(model.configuration(for: c).height, before.height)
    let edits = model.edits
    model.moveEditorTab(c.id, before: a.id)
    XCTAssertEqual(model.editorTabs, [c.id, a.id, b.id])
    model.closeOtherEditorTabs(keeping: a.id)
    XCTAssertEqual(model.editorTabs, [a.id]); XCTAssertEqual(model.edits, edits)
    model.persistenceTask?.cancel()
  }
  func testCollageReplacementAndSwapKeepDocumentAndUndo() throws {
    let model = try makeModel(); model.selection = Set(model.assets.prefix(3).map(\.id))
    model.switchWorkflow(.collages); model.ensureCollageDocument()
    let a = model.collage.cells[0], b = model.collage.cells[1], original = model.collage
    model.swapCollagePhotos(a.id, b.id)
    XCTAssertEqual(model.collage.cells[0].sourceID, b.sourceID)
    XCTAssertEqual(model.collage.cells[0].id, a.id)
    model.undoCollage(); XCTAssertEqual(model.collage, original)
    model.replaceCollagePhoto(cellID: a.id, sourceID: model.assets[4].id)
    XCTAssertEqual(model.collage.cells[0].sourceID, model.assets[4].id)
    model.undoCollage(); XCTAssertEqual(model.collage, original)
    model.persistenceTask?.cancel()
  }
  func testDirectCropPreservesScopeOtherPhotosAndUnrelatedEdits() throws {
    let model = try makeModel()
    let id = model.assets[0].id
    var value = model.configuration(forID: id)
    value.masks = [PrivacyMask()]; value.annotations = [Annotation()]
    value.adjustments.exposure = 0.6; value.width = 1200
    model.setImageConfiguration(value, for: id)
    model.scope = .all; model.switchWorkflow(.photo)
    let others = model.configuration(forID: model.assets[1].id)
    let before = model.edits
    model.applyPhotoCrop(CGRect(x: 100, y: 200, width: 600, height: 400), sourceSize: CGSize(width: 1000, height: 800), id: id)
    let result = model.configuration(forID: id)
    XCTAssertEqual(result.height, 800)
    XCTAssertEqual(result.width, value.width)
    XCTAssertEqual(result.masks, value.masks)
    XCTAssertEqual(result.annotations, value.annotations)
    XCTAssertEqual(result.adjustments, value.adjustments)
    XCTAssertEqual(model.scope, .all)
    XCTAssertEqual(model.configuration(forID: model.assets[1].id), others)
    model.undo(); XCTAssertEqual(model.edits, before)
    model.persistenceTask?.cancel()
  }
  func testPurposeSpecificResetsPreserveUnrelatedWorkAndProfiles() throws {
    let model = try makeModel()
    let id = model.assets[0].id
    model.rotatePhoto(id)
    model.settings.adjustments.exposure = 0.7
    let override = model.edits.overrides[id]
    var profile = ExportProfile(); profile.name = "Retained profile"
    model.profiles = [profile]; model.exportProfiles = [profile.id]
    model.resetBatchSettingsOnly()
    XCTAssertEqual(model.edits.settings, ProcessingConfiguration())
    XCTAssertEqual(model.edits.overrides[id], override)
    model.restoreLibraryOriginalAppearance()
    for asset in model.assets {
      let value = model.configuration(for: asset)
      XCTAssertEqual(value.quarterTurns, 0)
      XCTAssertEqual(value.percentage, 100)
      XCTAssertEqual(value.crop.mode, .preserveAspectRatio)
    }
    XCTAssertEqual(model.exportProfiles, [profile.id])
    model.undo()
    XCTAssertEqual(model.edits.overrides[id], override)
    model.removeAllIndividualOverrides()
    XCTAssertTrue(model.edits.overrides.isEmpty)
    XCTAssertEqual(model.settings, ProcessingConfiguration())
    model.persistenceTask?.cancel()
  }
  func testScopeHeadingMatchesActualTargetsAndLayoutApplicationKeepsDocument() throws {
    let model = try makeModel()
    model.workflow = .batch; model.scope = .all
    model.selection = [model.assets[0].id]
    XCTAssertEqual(model.editScopeHeading, "Editing all 5 workspace photos")
    model.scope = .selected
    XCTAssertEqual(model.editScopeHeading, "Editing 1 selected photo")
    model.switchWorkflow(.collages)
    model.ensureCollageDocument()
    let id = model.activeCollageID, count = model.savedCollages.count
    let before = model.collage
    model.applyCollageTemplate(CollageTemplate.catalog.last!)
    XCTAssertEqual(model.activeCollageID, id)
    XCTAssertEqual(model.savedCollages.count, count)
    model.undoCollage()
    XCTAssertEqual(model.collage, before)
    model.persistenceTask?.cancel()
  }
  func testSelectedExposurePreservesEachPhotoAndMixedValuesIncludingEqualRepresentativeValue()
    throws
  {
    let model = try makeModel()
    let a = model.assets[0]
    let b = model.assets[1]
    var first = model.configuration(for: a)
    first.crop.centerX = 0.2
    first.width = 777
    first.masks = [PrivacyMask()]
    first.adjustments.exposure = 0.4
    var second = model.configuration(for: b)
    second.crop.centerY = 0.8
    second.height = 999
    second.annotations = [Annotation()]
    second.adjustments.saturation = 0.3
    model.setImageConfiguration(first, for: a.id)
    model.setImageConfiguration(second, for: b.id)
    model.selection = [a.id, b.id]
    model.scope = .selected
    XCTAssertTrue(model.mixedFields.contains(.adjustments_exposure))
    model.updateField(\.adjustments.exposure, value: 0.4, fields: [.adjustments_exposure])
    second.adjustments.exposure = 0.4
    XCTAssertEqual(model.configuration(for: a), first)
    XCTAssertEqual(model.configuration(for: b), second)
    XCTAssertFalse(model.mixedFields.contains(.adjustments_exposure))
    XCTAssertTrue(model.mixedFields.contains(.width))
    model.persistenceTask?.cancel()
  }
  func testRotationInheritanceAndWorkflowScopeAreIndependent() throws {
    let model = try makeModel()
    let id = model.assets[0].id
    model.scope = .all
    model.rotatePhoto(id)
    model.settings.format = .png
    model.settings.quality = 0.2
    model.settings.width = 512
    let before = model.edits
    model.switchWorkflow(.photo)
    XCTAssertEqual(model.targets.map(\.id), [id])
    XCTAssertEqual(model.scope, .all)
    XCTAssertEqual(model.configuration(forID: id).format, .png)
    XCTAssertEqual(model.configuration(forID: id).width, 512)
    model.switchWorkflow(.collages)
    model.switchWorkflow(.automations)
    model.switchWorkflow(.batch)
    XCTAssertEqual(model.edits, before)
    XCTAssertEqual(model.targets.count, 5)
    model.persistenceTask?.cancel()
  }
  func testCommandRangeSelectAllFilteringAndNavigationKeepActiveDistinct() throws {
    let model = try makeModel()
    let assets = model.assets
    model.select(assets[0], extending: false, range: false)
    model.select(assets[2], extending: true, range: false)
    XCTAssertEqual(model.selection, [assets[0].id, assets[2].id])
    XCTAssertEqual(model.selected, assets[2].id)
    model.select(assets[4], extending: false, range: true)
    XCTAssertEqual(model.selection, Set(assets[2...4].map(\.id)))
    model.navigate(-1)
    XCTAssertEqual(model.selected, assets[3].id)
    XCTAssertEqual(model.selection.count, 3)
    model.favourites = [assets[0].id]
    model.library = .favourites
    XCTAssertEqual(model.selected, assets[0].id)
    XCTAssertEqual(model.selection, Set(assets[2...4].map(\.id)))
    XCTAssertEqual(model.targets.count, 3)
    model.selectVisiblePhotos()
    XCTAssertEqual(Set(model.targets.map(\.id)), Set([assets[0].id] + assets[2...4].map(\.id)))
    model.library = .all
    model.selectVisiblePhotos()
    XCTAssertEqual(model.targets.count, 5)
    model.query = "no_actual_classification"
    XCTAssertNil(model.current)
    XCTAssertEqual(model.targets.count, 5)
    model.persistenceTask?.cancel()
  }
  func testExplicitFramingIDsPreserveBatchScopeAndManualException() async throws {
    let model = try makeModel()
    let a = model.assets[0]
    let b = model.assets[1]
    var crop = CropConfiguration()
    crop.centerX = 0.7
    model.setCrop(crop, for: b.id)
    model.scope = .selected
    model.selection = [a.id, b.id]
    model.autoFrame(.smart, replaceManual: true, targetIDs: [a.id])
    await model.analysisTask?.value
    XCTAssertEqual(model.scope, .selected)
    XCTAssertEqual(model.selection, [a.id, b.id])
    XCTAssertEqual(model.configuration(for: b).crop.centerX, 0.7)
    XCTAssertNotNil(model.proposals[a.id])
    XCTAssertNil(model.proposals[b.id])
    model.persistenceTask?.cancel()
  }
  func testProfilesCountPhotoEditorSingleRenditionAndCopyPasteIsolation() throws {
    let model = try makeModel()
    model.profiles = (0..<3).map { index in
      var p = ExportProfile()
      p.name = "Profile \(index)"
      var c = ProcessingConfiguration()
      c.width = 100 * (index + 1)
      p.processing = c
      return p
    }
    model.exportProfiles = Set(model.profiles.map(\.id))
    XCTAssertEqual(model.plannedRequests().count, 15)
    XCTAssertEqual(model.exportPlanSummary, "5 photos → 15 files · 3 profiles")
    let a = model.assets[0]
    let b = model.assets[1]
    var value = model.configuration(for: a)
    value.adjustments.exposure = 0.8
    model.setImageConfiguration(value, for: a.id)
    var target = model.configuration(for: b)
    target.masks = [PrivacyMask()]
    target.crop.centerY = 0.7
    model.setImageConfiguration(target, for: b.id)
    model.copyEdits(from: a.id, categories: [.adjustments])
    model.pasteEdits(to: [b.id])
    target.adjustments.exposure = 0.8
    XCTAssertEqual(model.configuration(for: b), target)
    model.switchWorkflow(.photo)
    XCTAssertEqual(model.plannedRequests().count, 1)
    XCTAssertEqual(model.plannedRequests()[0].configuration.adjustments.exposure, 0.8)
    model.persistenceTask?.cancel()
  }
  func testNewPresetDoesNotPropagatePhotoSpecificMasksOrAnnotations() throws {
    let model = try makeModel(); model.switchWorkflow(.photo)
    var config = model.controlConfiguration; config.masks = [PrivacyMask()]; config.annotations = [Annotation()]; config.privacyExport = true
    model.setImageConfiguration(config, for: model.assets[0].id)
    model.saveProfile(name: "Export preset")
    let saved = try XCTUnwrap(model.profiles.last?.processing)
    XCTAssertTrue(saved.masks.isEmpty); XCTAssertTrue(saved.annotations.isEmpty); XCTAssertFalse(saved.privacyExport)
    XCTAssertEqual(model.configuration(forID: model.assets[0].id), config)
    model.persistenceTask?.cancel()
  }
  func testSharingOnlyCurrentSuccessAndNoSessionForTotalFailure() async throws {
    let model = try makeModel()
    let helper = WorkspaceTests()
    let goodURL = try helper.source(at: model.directory)
    let good = SourceAsset(url: goodURL)
    let bad = SourceAsset(url: model.directory.appendingPathComponent("missing.png"))
    model.assets = [good, bad]
    model.selected = good.id
    model.settings.width = 30
    model.settings.height = 30
    model.results = [
      ProcessingResult(source: good, output: URL(fileURLWithPath: "/tmp/old-photo.png"))
    ]
    model.collageOutputs = [URL(fileURLWithPath: "/tmp/old-collage.png")]
    let folder = model.directory.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    model.export(to: folder) { model.beginSharing($0) }
    await model.task?.value
    let session = try XCTUnwrap(model.sharingSession)
    XCTAssertEqual(session.outputs.count, 1)
    XCTAssertTrue(session.outputs[0].path.hasPrefix(folder.path))
    XCTAssertTrue(session.summary.contains("1 failed"))
    XCTAssertEqual(model.latestExport?.outputs, session.outputs)
    XCTAssertEqual(model.latestExport?.summary, session.summary)
    model.sharingSession = nil
    model.export(to: folder, targetIDs: [bad.id]) { model.beginSharing($0) }
    await model.task?.value
    XCTAssertNil(model.sharingSession)
    XCTAssertTrue(model.status.contains("0 exported"))
    XCTAssertNil(model.latestExport, "A failed operation must not offer the previous files as its result")
    model.persistenceTask?.cancel()
  }
  func testMultipleProfilesPublishFifteenValidatedFilesAndContextPhotoProducesOne() async throws {
    let model = try makeModel()
    let helper = WorkspaceTests()
    let url = try helper.source(at: model.directory)
    let original = try Data(contentsOf: url)
    model.assets = (0..<5).map { SourceAsset(url: url, name: "input-\($0).png") }
    model.selected = model.assets[0].id
    model.profiles = (0..<3).map { index in
      var profile = ExportProfile()
      profile.name = "Variant-\(index)"
      var config = ProcessingConfiguration()
      config.width = 20 + index * 10
      config.height = 16 + index * 10
      config.format = index == 2 ? .jpeg : .png
      profile.processing = config
      return profile
    }
    model.exportProfiles = Set(model.profiles.map(\.id))
    var authored = model.configuration(for: model.assets[0])
    authored.masks = [PrivacyMask()]
    authored.adjustments.exposure = 0.2
    model.setImageConfiguration(authored, for: model.assets[0].id)
    let expected = model.plannedRequests()
    let folder = model.directory.appendingPathComponent("profile-exports")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    model.export(to: folder) { model.beginSharing($0) }
    model.scope = .selected; model.selection = [model.assets[0].id]
    model.switchWorkflow(.photo)
    XCTAssertEqual(model.exportDisplayProfiles.count, 3)
    XCTAssertEqual(model.exportPlanSummary, "5 photos → 15 files · 3 profiles", "Running counts describe the captured operation rather than later selection changes")
    await model.task?.value
    let outputs = try XCTUnwrap(model.sharingSession).outputs
    XCTAssertEqual(outputs.count, 15)
    XCTAssertEqual(Set(outputs).count, 15)
    XCTAssertEqual(model.completed, 15)
    XCTAssertTrue(model.pendingExports.isEmpty)
    for request in expected {
      let prefix = folder.appendingPathComponent(request.profile.name).path
      let output = try XCTUnwrap(
        outputs.first {
          $0.deletingLastPathComponent().path == prefix
            && $0.lastPathComponent.hasPrefix(
              request.source.name.replacingOccurrences(of: ".png", with: ""))
        })
      let size = try await model.processor.identify(output)
      XCTAssertEqual(Int(size.width), request.configuration.width)
      XCTAssertEqual(Int(size.height), request.configuration.height)
    }
    model.sharingSession = nil
    model.export(to: folder, targetIDs: [model.assets[0].id]) { model.beginSharing($0) }
    await model.task?.value
    XCTAssertEqual(model.sharingSession?.outputs.count, 1)
    XCTAssertEqual(try Data(contentsOf: url), original)
    model.persistenceTask?.cancel()
  }

}

extension WorkflowWorkspaceTests {
  func testLibraryNavigationShowsGalleryAndPreservesBatchAndPhotoEdits() throws {
    let model = try makeModel()
    let photo = model.assets[1]
    var config = model.configuration(for: photo)
    config.masks = [PrivacyMask()]
    config.crop.centerX = 0.7
    model.setImageConfiguration(config, for: photo.id)
    model.selection = [model.assets[0].id, photo.id]
    model.scope = .selected
    model.selecting = true
    model.mode = .frame
    model.switchWorkflow(.photo)
    model.precision = true
    let edits = model.edits
    let selection = model.selection
    model.showLibrary(.all, clearSearch: true)
    XCTAssertTrue(model.browsingLibrary)
    XCTAssertEqual(model.mode, .browse)
    XCTAssertFalse(model.precision)
    XCTAssertEqual(model.workspaceTitle, "Workspace")
    XCTAssertTrue(model.targets.isEmpty, "Browsing must not implicitly expose batch export targets")
    XCTAssertEqual(model.edits, edits)
    XCTAssertEqual(model.selection, selection)
    model.openPhoto(photo)
    XCTAssertFalse(model.browsingLibrary)
    XCTAssertEqual(model.workflow, .photo)
    XCTAssertEqual(model.targets.map(\.id), [photo.id])
    model.showLibrary()
    model.editSelectedBatch()
    XCTAssertEqual(model.workflow, .batch)
    XCTAssertEqual(model.mode, .frame)
    XCTAssertEqual(model.scope, .selected)
    XCTAssertEqual(Set(model.targets.map(\.id)), selection)
    XCTAssertEqual(model.edits, edits)
    model.persistenceTask?.cancel()
  }
  func testGalleryPrivacyEditingOpensEditorWithoutChangingComposition() throws {
    let model = try makeModel()
    model.switchWorkflow(.collages)
    let composition = model.collage
    model.showLibrary(.all)
    let photo = model.assets[2]
    model.openOverlayEditor(for: photo)
    XCTAssertTrue(model.overlayEditor)
    XCTAssertFalse(model.browsingLibrary)
    XCTAssertEqual(model.selected, photo.id)
    XCTAssertEqual(model.workflow, .photo)
    model.overlayEditor = false
    XCTAssertFalse(model.browsingLibrary)
    XCTAssertEqual(model.collage, composition)
    model.openPhoto(photo, refine: true)
    XCTAssertEqual(model.workflow, .photo)
    XCTAssertTrue(model.precision)
    XCTAssertFalse(model.browsingLibrary)
    model.persistenceTask?.cancel()
  }
  func testLibraryCategoriesAndSearchNeverTargetHiddenCurrentPhoto() throws {
    let model = try makeModel()
    model.selected = model.assets[3].id
    model.query = "missing_label"
    model.favourites = [model.assets[0].id]
    model.showLibrary(.favourites, clearSearch: true)
    XCTAssertEqual(model.current?.id, model.assets[0].id)
    XCTAssertEqual(model.filtered.count, 1)
    XCTAssertTrue(model.targets.isEmpty)
    model.showLibrary(.all, clearSearch: true)
    XCTAssertEqual(model.filtered.count, 5)
    model.openPhoto(model.assets[3])
    XCTAssertEqual(model.current?.id, model.assets[3].id)
    model.persistenceTask?.cancel()
  }
}

extension WorkflowWorkspaceTests {
  func testPhotoCanvasOnlyReframesWithExplicitCropTool() throws {
    let model = try makeModel()
    model.switchWorkflow(.photo)
    model.choosePhotoInspector(.adjust)
    XCTAssertFalse(model.photoCanvasAllowsFraming)
    let edits = model.edits
    let selection = model.selection
    let scope = model.scope
    model.precision = true
    XCTAssertTrue(model.photoCanvasAllowsFraming)
    model.choosePhotoInspector(.output)
    XCTAssertFalse(model.photoCanvasAllowsFraming)
    XCTAssertEqual(model.inspectorTask, .output)
    XCTAssertEqual(model.edits, edits)
    XCTAssertEqual(model.selection, selection)
    XCTAssertEqual(model.scope, scope)
    model.precision = true
    model.showLibrary()
    XCTAssertFalse(model.photoCanvasAllowsFraming)
    model.persistenceTask?.cancel()
  }
  func testAnnotationAndPrivacyEntryChooseRequestedToolWithoutChangingEdits() throws {
    let model = try makeModel()
    let asset = model.assets[1]
    var config = model.configuration(for: asset)
    config.masks = [PrivacyMask()]
    config.annotations = [Annotation()]
    model.setImageConfiguration(config, for: asset.id)
    let edits = model.edits
    model.openOverlayEditor(for: asset, masking: false)
    XCTAssertFalse(model.overlayStartsWithMasks)
    XCTAssertTrue(model.overlayEditor)
    XCTAssertEqual(model.current?.id, asset.id)
    XCTAssertEqual(model.edits, edits)
    model.overlayEditor = false
    model.openOverlayEditor(for: asset)
    XCTAssertTrue(model.overlayStartsWithMasks)
    XCTAssertEqual(model.edits, edits)
    model.overlayEditor = false
    model.openOverlayEditor(for: asset, masking: false)
    model.overlayEditor = false
    model.openPrivacyEditor(.overlays, asset: asset)
    model.finishPrivacyReviewPresentation()
    XCTAssertTrue(model.overlayStartsWithMasks, "Privacy review must not reuse a previous annotation tool")
    XCTAssertEqual(model.edits, edits)
    model.persistenceTask?.cancel()
  }
}


extension WorkflowWorkspaceTests {
  func testEditorTabsAreUniqueIndependentOfLibraryAndPreserveEditsOnClose() throws {
    let model = try makeModel()
    let a = model.assets[0], b = model.assets[1], c = model.assets[2]
    model.selection = [a.id, c.id]; model.scope = .selected
    let batch = model.selection
    model.showLibrary()
    model.openPhoto(a)
    model.choosePhotoInspector(.output)
    model.rotatePhoto(a.id)
    let edits = model.edits
    model.openPhoto(b)
    model.precision = true
    model.openPhoto(a)
    XCTAssertEqual(model.editorTabs, [a.id, b.id])
    XCTAssertEqual(model.inspectorTask, .output)
    XCTAssertFalse(model.precision)
    XCTAssertEqual(model.targets.map(\.id), [a.id])
    model.showLibrary(.favourites)
    XCTAssertNil(model.current)
    model.switchWorkflow(.photo)
    XCTAssertEqual(model.current?.id, a.id, "Explicit editor tabs are independent of library filters")
    XCTAssertEqual(model.selection, batch, "Filtering retains hidden workspace selection")
    model.activateEditorTab(b.id)
    XCTAssertTrue(model.precision)
    model.closeEditorTab(a.id)
    XCTAssertEqual(model.current?.id, b.id)
    model.closeEditorTab(b.id)
    XCTAssertTrue(model.browsingLibrary)
    XCTAssertTrue(model.editorTabs.isEmpty)
    XCTAssertEqual(model.edits, edits)
    model.showLibrary(.all)
    model.openPhoto(a)
    XCTAssertEqual(model.configuration(for: a).quarterTurns, 1)
    XCTAssertEqual(model.scope, .selected)
    XCTAssertEqual(batch.count, 2)
    model.persistenceTask?.cancel()
  }
  func testPrivacyOpensTabAndDoesNotChangeBatchMembershipOrScope() throws {
    let model = try makeModel()
    let a = model.assets[0], b = model.assets[1]
    model.selection = [a.id]; model.scope = .selected
    model.openOverlayEditor(for: b)
    XCTAssertEqual(model.workflow, .photo)
    XCTAssertEqual(model.editorTabs, [b.id])
    XCTAssertEqual(model.targets.map(\.id), [b.id])
    XCTAssertEqual(model.selection, [a.id])
    XCTAssertEqual(model.scope, .selected)
    model.closeEditorTab(b.id)
    XCTAssertEqual(model.editorTabs, [b.id], "A draft must be applied or cancelled before closing its tab")
    model.showLibrary(); model.switchWorkflow(.batch)
    XCTAssertFalse(model.browsingLibrary)
    XCTAssertEqual(model.workflow, .photo)
    model.overlayEditor = false
    model.switchWorkflow(.batch)
    XCTAssertEqual(model.targets.map(\.id), [a.id])
    model.persistenceTask?.cancel()
  }
}


extension WorkflowWorkspaceTests {
  func testSavedTabStateRoundTripsAndIgnoresStaleOrDuplicateIDs() throws {
    let model = try makeModel()
    let a = model.assets[0], b = model.assets[1]
    model.openPhoto(a); model.openPhoto(b)
    model.rotatePhoto(a.id)
    let data = try JSONEncoder().encode(model.document())
    var document = try JSONDecoder().decode(ProjectDocument.self, from: data)
    document.editorTabIDs += [a.id, UUID()]
    model.resetEditorTabs()
    model.restoreEditorTabs(document)
    XCTAssertEqual(model.editorTabs, [a.id, b.id])
    XCTAssertEqual(model.editorPhotoID, b.id)
    XCTAssertEqual(document.edits.configuration(for: a.id).quarterTurns, 1)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "editorTabIDs"); legacy.removeValue(forKey: "activeEditorPhotoID")
    let old = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertTrue(old.editorTabIDs.isEmpty)
    XCTAssertEqual(old.edits, document.edits)
    model.persistenceTask?.cancel()
  }
}

extension WorkflowWorkspaceTests {
  func testRestoreOriginalOnlyActivePhotoPreservesExportOptionsAndSupportsUndo() async throws {
    let model = try makeModel()
    let helper = WorkspaceTests()
    let url = try helper.source(at: model.directory)
    model.assets[0].url = url
    let a = model.assets[0], b = model.assets[1]
    let originalBytes = try Data(contentsOf: url)
    var batch = model.settings
    batch.adjustments.exposure = 1
    batch.quarterTurns = 1
    batch.crop.mode = .fill
    batch.watermark.enabled = true
    batch.masks = [PrivacyMask()]
    batch.annotations = [Annotation()]
    batch.format = .png
    batch.quality = 0.61
    batch.metadata = .removeLocation
    batch.privacyExport = true
    model.settings = batch
    model.setImageAspect(1, for: a.id)
    model.openPhoto(a)
    let before = model.edits
    let other = model.configuration(for: b)
    model.restoreOriginalPhoto(b.id)
    XCTAssertEqual(model.edits, before, "An editor action cannot reset an unrelated tab")
    model.restoreOriginalPhoto(a.id)
    let result = model.configuration(for: a)
    XCTAssertEqual(result.adjustments, PhotoAdjustments())
    XCTAssertEqual(result.quarterTurns, 0)
    XCTAssertEqual(result.crop.mode, .preserveAspectRatio)
    XCTAssertEqual(result.resizeBasis, .percentage)
    XCTAssertEqual(result.percentage, 100)
    XCTAssertFalse(result.watermark.enabled)
    XCTAssertTrue(result.masks.isEmpty)
    XCTAssertTrue(result.annotations.isEmpty)
    XCTAssertTrue(result.privacyExport, "Restoring appearance must not weaken metadata protection")
    XCTAssertEqual(result.format, .png)
    XCTAssertEqual(result.quality, 0.61)
    XCTAssertEqual(result.metadata, .removeLocation)
    XCTAssertEqual(model.configuration(for: b), other)
    XCTAssertEqual(model.settings, before.settings)
    let image = try await model.processor.render(url, configuration: result)
    XCTAssertEqual(image.width, 80)
    XCTAssertEqual(image.height, 40)
    XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    let restored = model.edits
    model.undo(); XCTAssertEqual(model.edits, before)
    model.redo(); XCTAssertEqual(model.edits, restored)
    model.persistenceTask?.cancel()
  }
}


extension WorkflowWorkspaceTests {
  func testUncropRestoresWholeSourceWhileRetainingOtherEditsAndBatchScope() async throws {
    let model = try makeModel()
    let url = try WorkspaceTests().source(at: model.directory)
    model.assets[0].url = url
    let a = model.assets[0], b = model.assets[1]
    let originalBytes = try Data(contentsOf: url)
    var c = model.configuration(for: a)
    c.crop.mode = .manualCrop; c.crop.zoom = 3
    c.crop.centerX = 0.8; c.crop.centerY = 0.2
    c.crop.quarterTurns = 1
    c.adjustments.exposure = 0.4
    c.masks = [PrivacyMask()]; c.annotations = [Annotation()]
    c.watermark.enabled = true; c.format = .png; c.quality = 0.7
    model.setImageConfiguration(c, for: a.id)
    model.setImageAspect(1, for: a.id)
    model.scope = .selected; model.selection = [a.id, b.id]
    model.selected = a.id
    let before = model.edits
    let other = model.configuration(for: b)
    await model.restoreFullImageCrop(a.id)
    let result = model.configuration(for: a)
    XCTAssertEqual(result.crop.zoom, 1)
    XCTAssertNil(result.crop.aspectRatio)
    XCTAssertNil(model.edits.overrides[a.id]?.dimensions)
    XCTAssertEqual(result.adjustments, c.adjustments)
    XCTAssertEqual(result.masks, c.masks)
    XCTAssertEqual(result.annotations, c.annotations)
    XCTAssertEqual(result.watermark, c.watermark)
    XCTAssertEqual(result.crop.quarterTurns, 1)
    XCTAssertEqual(result.format, c.format)
    XCTAssertEqual(result.quality, c.quality)
    XCTAssertEqual(model.configuration(for: b), other)
    XCTAssertEqual(model.scope, .selected)
    XCTAssertEqual(model.selection, [a.id, b.id])
    let image = try await model.processor.render(url, configuration: result)
    XCTAssertEqual(image.width, 40); XCTAssertEqual(image.height, 80)
    var recrop = result
    recrop.crop = CropGeometry.zoomed(result.crop, factor: 2)
    XCTAssertEqual(ImageProcessor.outputSize(source: CGSize(width: 40, height: 80), configuration: recrop), CGSize(width: 40, height: 80), "Recropping must keep the restored viewport, not the previous square output")
    XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    let restored = model.edits
    model.undo(); XCTAssertEqual(model.edits, before)
    model.redo(); XCTAssertEqual(model.edits, restored)
    model.persistenceTask?.cancel()
  }
}

extension WorkflowWorkspaceTests {
  func testResetAllBatchChangesIsOneUndoableStepAndRetainsLibraryAndOtherWorkspaces() throws {
    let model = try makeModel()
    let a = model.assets[0], b = model.assets[1]
    var settings = model.settings
    settings.adjustments.exposure = 0.7
    settings.crop.mode = .fill
    settings.format = .png
    model.settings = settings
    var photo = model.configuration(for: a)
    photo.masks = [PrivacyMask()]; photo.annotations = [Annotation()]
    photo.quarterTurns = 1
    model.setImageConfiguration(photo, for: a.id)
    model.setImageAspect(1, for: b.id)
    model.profiles = Workspace.defaultProfiles()
    model.exportProfiles = [model.profiles[0].id]
    model.selection = [a.id]; model.scope = .selected
    model.favourites = [b.id]
    model.collage.title = "Keep my composition"
    model.showLibrary(.favourites)
    model.editSelectedBatch()
    model.switchWorkflow(.batch)
    let before = model.edits
    let sources = model.assets
    let collage = model.collage
    let profiles = model.exportProfiles
    let historyCount = model.history.steps.count
    model.proposals[a.id] = FramingProposal(crop: photo.crop, subjects: [], reviewReasons: ["Review crop"])
    model.resetAllProcessingChanges()
    XCTAssertEqual(model.edits, EditingSnapshot())
    XCTAssertTrue(model.proposals.isEmpty)
    XCTAssertEqual(model.assets, sources)
    XCTAssertEqual(model.collage, collage)
    XCTAssertEqual(model.exportProfiles, profiles)
    XCTAssertEqual(model.favourites, [b.id])
    XCTAssertEqual(model.history.steps.count, historyCount + 1)
    XCTAssertTrue(model.history.steps.last?.title.contains("Reset All Changes") == true)
    model.undo(); XCTAssertEqual(model.edits, before)
    model.redo(); XCTAssertEqual(model.edits, EditingSnapshot())
    model.persistenceTask?.cancel()
  }
  func testHistoryJumpRestoresBatchAndPhotoStateAndKeepsRedoBranch() throws {
    let model = try makeModel()
    let initial = model.edits
    let start = try XCTUnwrap(model.history.steps.first?.id)
    var settings = model.settings; settings.adjustments.exposure = 0.5
    model.settings = settings
    let exposure = try XCTUnwrap(model.history.steps.last?.id)
    let exposureState = model.edits
    model.rotatePhoto(model.assets[1].id)
    let rotated = model.edits
    let rotation = try XCTUnwrap(model.history.steps.last?.id)
    model.moveEditingHistory(to: start)
    XCTAssertEqual(model.edits, initial)
    XCTAssertTrue(model.canRedo)
    model.moveEditingHistory(to: exposure)
    XCTAssertEqual(model.edits, exposureState)
    model.moveEditingHistory(to: rotation)
    XCTAssertEqual(model.edits, rotated)
    model.moveEditingHistory(to: exposure)
    model.rotatePhoto(model.assets[0].id)
    XCTAssertFalse(model.canRedo)
    XCTAssertFalse(model.history.steps.contains { $0.id == rotation })
    model.persistenceTask?.cancel()
  }
}

extension WorkflowWorkspaceTests {
  func testMultipleCollagesKeepSeparateEditsHistoryAndClosedCompositions() throws {
    let model=try makeModel()
    model.selection=Set(model.assets.prefix(3).map(\.id))
    model.ensureCollageDocument()
    let first=try XCTUnwrap(model.activeCollageID)
    var p=model.collage;p.title="First composition";model.changeCollage(p)
    model.renameCollage("Holiday")
    model.newCollage(template:CollageTemplate.catalog[0])
    let second=try XCTUnwrap(model.activeCollageID)
    XCTAssertNotEqual(first,second)
    var other=model.collage;other.title="Second composition";model.changeCollage(other)
    model.activateCollage(first)
    XCTAssertEqual(model.collage.title,"First composition")
    model.activateCollage(first)
    XCTAssertEqual(model.collage.title,"First composition","Clicking the active tab must not reload stale edits")
    model.undoCollage();XCTAssertEqual(model.collage.title,"")
    model.redoCollage();XCTAssertEqual(model.collage.title,"First composition")
    model.activateCollage(second)
    XCTAssertEqual(model.collage.title,"Second composition")
    model.closeCollageTab(first)
    XCTAssertFalse(model.openCollageIDs.contains(first))
    XCTAssertEqual(model.savedCollages.first {$0.id==first}?.project.title,"First composition")
    model.closeCollageTab(second)
    XCTAssertNil(model.activeCollageID)
    XCTAssertEqual(model.savedCollages.count,2)
    let doc=try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(model.document()))
    model.restoreCollageDocuments(doc)
    XCTAssertTrue(model.openCollageIDs.isEmpty)
    XCTAssertNil(model.activeCollageID)
    model.activateCollage(first)
    XCTAssertEqual(model.activeCollageName,"Holiday")
    XCTAssertEqual(model.collage.title,"First composition")
    XCTAssertEqual(model.assets.count,5)
    model.persistenceTask?.cancel()
  }
  func testLegacyCollageMigrationAndArtGenerationCancellation() async throws {
    let model=try makeModel()
    var legacy=ProjectDocument(), p=CollageProject()
    p.arrange(model.assets.map(\.id),layout:.magazine);p.title="Legacy"
    legacy.collage=p
    model.restoreCollageDocuments(legacy)
    XCTAssertEqual(model.collage,p)
    XCTAssertEqual(model.openCollageIDs.count,1)
    let before=model.collage
    model.generateCollageArt(shape:.heart,text:"",sourceIDs:Set(model.assets.map(\.id)),count:1000,referenceID:nil,reuse:true)
    model.collageGenerationTask?.cancel()
    await model.collageGenerationTask?.value
    XCTAssertEqual(model.collage,before)
    XCTAssertFalse(model.collageGenerating)
    model.generateCollageArt(shape:.text,text:"HELLO",sourceIDs:Set(model.assets.map(\.id)),count:100,referenceID:nil,reuse:true)
    await model.collageGenerationTask?.value
    XCTAssertEqual(model.collage.cells.count,100)
    XCTAssertEqual(model.collage.silhouette,.text)
    model.undoCollage();XCTAssertEqual(model.collage,before)
    model.persistenceTask?.cancel()
  }
}


extension WorkflowWorkspaceTests {
  func testCollageKeyboardUndoRoutingKeepsPhotoHistorySeparate() throws {
    let model=try makeModel()
    let initial = model.edits
    model.rotatePhoto(model.assets[0].id)
    let photoEdits=model.edits
    model.switchWorkflow(.collages);model.ensureCollageDocument()
    var p=model.collage;p.title="Title";model.changeCollage(p)
    XCTAssertTrue(model.canUndoActiveWorkspace)
    model.undoActiveWorkspace()
    XCTAssertEqual(model.collage.title,"")
    XCTAssertEqual(model.edits,photoEdits)
    model.redoActiveWorkspace();XCTAssertEqual(model.collage.title,"Title")
    model.showLibrary();model.undoActiveWorkspace()
    XCTAssertEqual(model.edits,initial)
    XCTAssertEqual(model.collage.title,"Title")
    model.persistenceTask?.cancel()
  }
}

extension WorkflowWorkspaceTests {
  func testWorkspaceSelectionSurvivesFiltersAndCapturesStableOperations() throws {
    let model = try makeModel(); let a = model.assets[0], b = model.assets[1], c = model.assets[2]
    model.showLibrary(); model.selecting = true; model.select(a); model.select(b)
    model.query = "photo-2"; XCTAssertEqual(model.selection, [a.id, b.id])
    model.select(c); XCTAssertEqual(model.orderedSelection, [a.id,b.id,c.id])
    XCTAssertEqual(model.contextIDs(for: model.assets[4].id), [model.assets[4].id])
    XCTAssertEqual(model.contextIDs(for: a.id), [a.id,b.id,c.id])
    model.beginBatch(ids: model.orderedSelection)
    model.selection = []; model.query = "nothing"
    XCTAssertEqual(Set(model.targets.map(\.id)), [a.id,b.id,c.id])
    model.persistenceTask?.cancel()
  }
  func testGIFActionFirstCancelRestoresSelectionAndUnfinishedProject() throws {
    let model = try makeModel(); let a = model.assets[0], b = model.assets[1]
    model.startGIF(ids: [b.id,a.id]); let project = model.gifProject
    model.selection = [a.id]; model.query = "photo-0"; model.selecting = false
    model.selectGIFPhotos(adding: true); XCTAssertTrue(model.browsingLibrary); XCTAssertTrue(model.selecting)
    model.select(b); model.query = "unmatched"; XCTAssertEqual(model.selection, [b.id])
    model.finishGIFSelection(cancel: true)
    XCTAssertEqual(model.gifProject, project); XCTAssertEqual(model.selection, [a.id]); XCTAssertEqual(model.query, "photo-0")
    XCTAssertFalse(model.browsingLibrary); XCTAssertEqual(model.workflow, .gif); XCTAssertFalse(model.selecting)
    model.persistenceTask?.cancel()
  }
  func testGIFBothEntryPointsAddReplacePersistenceAndIndependentEdits() throws {
    let model = try makeModel(); let a = model.assets[0], b = model.assets[1], c = model.assets[2]
    model.switchWorkflow(.gif); model.selectGIFPhotos(); model.select(b); model.select(a)
    model.finishGIFSelection(cancel: false)
    XCTAssertEqual(model.gifProject?.frames.map(\.sourceID), [b.id,a.id])
    let captured = try XCTUnwrap(model.gifProject?.frames.first?.configuration)
    model.rotatePhoto(b.id); model.selection = [c.id]
    XCTAssertEqual(model.gifProject?.frames.first?.configuration, captured)
    var range = GIFAnnotation(annotation: Annotation(), frameIDs: Set(model.gifProject?.frames.map(\.id) ?? [])); range.extendsToNewFrames = true
    model.gifProject?.annotations = [range]
    model.selectGIFPhotos(adding: true); model.select(c); model.finishGIFSelection(cancel: false)
    XCTAssertEqual(model.gifProject?.annotations.first?.frameIDs?.count, 3)
    XCTAssertEqual(model.gifProject?.frames.map(\.sourceID), [b.id,a.id,c.id])
    let frame = try XCTUnwrap(model.gifProject?.frames.first?.id)
    model.selectGIFPhotos(replacing: frame); model.select(a); model.finishGIFSelection(cancel: false)
    XCTAssertEqual(model.gifProject?.frames.first?.id, frame); XCTAssertEqual(model.gifProject?.frames.first?.sourceID, a.id)
    let doc = model.document(); let restored = try makeModel(); restored.assets = doc.sources; restored.restoreGIF(doc)
    XCTAssertEqual(restored.gifProject, model.gifProject); XCTAssertEqual(restored.selection, model.selection)
    model.openPhoto(b); let before = model.configuration(for: a); model.rotatePhoto(b.id)
    XCTAssertEqual(model.targets.map(\.id), [b.id]); XCTAssertEqual(model.configuration(for: a), before)
    model.persistenceTask?.cancel(); restored.persistenceTask?.cancel()
  }
  func testWorkspaceRemovalPreservesOriginalFilesAndGIFReferences() throws {
    let model = try makeModel(); let source = model.assets[0]
    try Data("original".utf8).write(to: source.url)
    model.startGIF(ids: [source.id]); model.removeFromWorkspace([source.id])
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
    XCTAssertEqual(model.gifProject?.frames.first?.sourceID, source.id)
    XCTAssertTrue(model.assets.contains(where: { $0.id == source.id }))
    XCTAssertFalse(model.workspaceAssets.contains(where: { $0.id == source.id }))
    model.persistenceTask?.cancel()
  }
}

extension WorkflowWorkspaceTests {
  func testGIFHistoryAndSavedCreationsNeverChangePhotoEdits() throws {
    let model = try makeModel(); model.startGIF(ids: model.assets.prefix(2).map(\.id))
    let first = try XCTUnwrap(model.gifProject), edits = model.edits
    var changed = first; changed.width = 640
    model.gifInteraction(true); model.updateGIF(changed); changed.width = 480; model.updateGIF(changed); model.gifInteraction(false)
    XCTAssertEqual(model.gifUndo.count, 1)
    model.undoActiveWorkspace(); XCTAssertEqual(model.gifProject, first); XCTAssertEqual(model.edits, edits)
    model.redoActiveWorkspace(); XCTAssertEqual(model.gifProject?.width, 480)
    model.startGIF(ids: [model.assets[2].id]); XCTAssertEqual(model.archivedGIFs.first?.width, 480)
    let doc = model.document(), restored = try makeModel(); restored.assets = doc.sources; restored.restoreGIF(doc)
    XCTAssertEqual(restored.archivedGIFs, model.archivedGIFs)
    model.persistenceTask?.cancel(); restored.persistenceTask?.cancel()
  }
}
