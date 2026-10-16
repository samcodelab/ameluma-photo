import XCTest
import ImageIO
import Photos
import CoreGraphics
import UniformTypeIdentifiers
import FramepebbleCore
@testable import FramepebbleiOS

@MainActor final class WorkspaceTests: XCTestCase {
    func workspace() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Workspace(directory: root)
    }
    func source(at directory: URL, name: String = "source.png") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data:nil,width:80,height:40,bitsPerComponent:8,bytesPerRow:320,space:try XCTUnwrap(CGColorSpace(name:CGColorSpace.sRGB)),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));context.fill(CGRect(x:0,y:0,width:80,height:40))
        let dest=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil));CGImageDestinationAddImage(dest,try XCTUnwrap(context.makeImage()),nil);XCTAssertTrue(CGImageDestinationFinalize(dest));return url
    }
    func testOverlayDraftCancelApplyAndGlobalUndoPreserveOtherImages() throws {
        let model = try workspace()
        model.assets = [SourceAsset(url: model.directory.appendingPathComponent("one.png")), SourceAsset(url: model.directory.appendingPathComponent("two.png"))]
        let a = model.assets[0], other = model.assets[1]
        model.selected = a.id
        let before = model.edits
        var draft = OverlayEditingSession(sourceID: a.id, configuration: model.configuration(for: a))
        var c = draft.current; var mask = PrivacyMask(); mask.effect = .frosted; c.masks = [mask]; draft.update(c)
        XCTAssertEqual(model.edits, before, "Draft previews must not change saved project state")
        draft.cancel(); XCTAssertEqual(model.edits, before)
        draft.update(c); XCTAssertTrue(model.applyOverlaySession(draft))
        XCTAssertEqual(model.configuration(for: a).masks, [mask])
        XCTAssertTrue(model.configuration(for: other).masks.isEmpty)
        model.undo(); XCTAssertEqual(model.edits, before)
        model.redo(); XCTAssertEqual(model.configuration(for: a).masks, [mask])
        model.persistenceTask?.cancel()
    }
    func testHideSomethingShowsFlagsAndContextEditingRevealsOnlyChosenPhoto() throws {
        let model = try workspace()
        model.assets = (0..<3).map { SourceAsset(url: model.directory.appendingPathComponent("photo-\($0).png")) }
        let a = model.assets[1], b = model.assets[2]
        model.sensitivity.mark(a.id, forReview: true); model.sensitivity.mark(b.id, forReview: true)
        model.query = "dog"; model.showHideSomething()
        XCTAssertEqual(model.filtered.map(\.id), [a.id, b.id])
        XCTAssertEqual(model.scope, .results)
        XCTAssertTrue(model.query.isEmpty)
        model.openOverlayEditor(for: a)
        XCTAssertTrue(model.overlayEditor)
        XCTAssertEqual(model.selected, a.id)
        XCTAssertFalse(model.sensitivity.concealed(a.id))
        XCTAssertTrue(model.sensitivity.concealed(b.id))
        XCTAssertEqual(model.scope, .results)
    }
    func testOverlayApplyRejectsConcurrentChangesRatherThanOverwritingThem() throws {
        let model = try workspace(); let asset = SourceAsset(url: model.directory.appendingPathComponent("one.png")); model.assets = [asset]
        var draft = OverlayEditingSession(sourceID: asset.id, configuration: model.configuration(for: asset))
        var c = draft.current; c.masks = [PrivacyMask()]; draft.update(c)
        var crop = model.configuration(for: asset).crop; crop.centerX = 0.7; model.setCrop(crop, for: asset.id)
        XCTAssertFalse(model.applyOverlaySession(draft))
        XCTAssertTrue(model.configuration(for: asset).masks.isEmpty)
        XCTAssertEqual(model.configuration(for: asset).crop.centerX, 0.7)
        model.persistenceTask?.cancel()
    }
    func testSelectionModeLimitsTargetsWithoutDiscardingEdits() throws {
        let model = try workspace()
        model.assets = (0..<3).map { SourceAsset(url: model.directory.appendingPathComponent("image-\($0).png")) }
        var crop = model.settings.crop; crop.centerX = 0.7
        model.setCrop(crop, for: model.assets[0].id)
        model.toggleSelectionMode()
        XCTAssertEqual(model.scope, .selected)
        XCTAssertTrue(model.targets.isEmpty)
        model.select(model.assets[1])
        XCTAssertEqual(model.targets.map(\.id), [model.assets[1].id])
        model.toggleSelectionMode()
        XCTAssertEqual(model.targets.map(\.id), [model.assets[1].id])
        XCTAssertEqual(model.configuration(for: model.assets[0]).crop.centerX, 0.7)
        model.selectVisiblePhotos()
        XCTAssertEqual(model.targets.count, 3)
        XCTAssertTrue(model.selecting)
        model.persistenceTask?.cancel()
    }
    func testClearRemovesLocalCopiesPreservesOriginalAndAllowsReimport() async throws {
        let model = try workspace()
        let original = try source(at: model.directory.deletingLastPathComponent())
        let bytes = try Data(contentsOf: original)
        await model.importURLs([original])
        let snapshot = try XCTUnwrap(model.assets.first?.url)
        await model.clearImportedPhotos()
        XCTAssertTrue(model.assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path))
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        await model.importURLs([original])
        XCTAssertEqual(model.assets.count, 1)
        await model.stopWork(); model.persistenceTask?.cancel()
    }
    func testUnreadableSavedProjectStopsCleanupWithoutDiscardingWorkspace() async throws {
        let model = try workspace()
        let original = try source(at: model.directory.deletingLastPathComponent())
        await model.importURLs([original])
        let snapshot = try XCTUnwrap(model.assets.first?.url)
        let projects = model.directory.deletingLastPathComponent().appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try Data("invalid project".utf8).write(to: projects.appendingPathComponent("broken.json"))
        await model.clearImportedPhotos()
        XCTAssertEqual(model.assets.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(model.issues.isEmpty)
        await model.stopWork(); model.persistenceTask?.cancel()
    }
    func testCloseAndClearRetainSourcesReferencedBySavedProject() async throws {
        let model = try workspace()
        let original = try source(at: model.directory.deletingLastPathComponent())
        await model.importURLs([original])
        let snapshot = try XCTUnwrap(model.assets.first?.url)
        await model.closeProject()
        XCTAssertTrue(model.assets.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
        await model.clearImportedPhotos()
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        await model.importURLs([original])
        XCTAssertEqual(model.assets.count, 1, "Closing must reset current-library duplicate detection")
        await model.stopWork(); model.persistenceTask?.cancel()
    }
    func testGalleryShowsFiftyThousandUnindexedAssetsInImportOrder() throws {
        let model = try workspace()
        model.assets = (0..<50_000).map { SourceAsset(url: model.directory.appendingPathComponent("photo-\($0).png")) }
        XCTAssertTrue(model.index.records.isEmpty)
        XCTAssertEqual(model.filtered.count, 50_000)
        XCTAssertEqual(model.filtered.first?.id, model.assets.first?.id)
        XCTAssertEqual(model.filtered.last?.id, model.assets.last?.id)
        model.sensitivity.mark(model.assets[49_999].id, forReview: true)
        model.library = .privacyReview
        XCTAssertEqual(model.filtered.map(\.id), [model.assets[49_999].id])
    }
    func testImagesPublishAndRemainEditableBeforeFolderImportCompletes() async throws {
        let model = try workspace()
        model.skipDuplicates = false
        let input = model.directory.appendingPathComponent("Incoming")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        for index in 0..<50 { _ = try source(at: input, name: "photo-\(index).png") }
        let importing = Task { await model.importURLs([input]) }
        for _ in 0..<500 { if !model.assets.isEmpty { break }; try await Task.sleep(for: .milliseconds(1)) }
        let first = try XCTUnwrap(model.assets.first)
        XCTAssertNotNil(model.fileImportTask, "The image is published before the batch finishes")
        var crop = model.configuration(for: first).crop
        crop.centerX = 0.7
        model.setCrop(crop, for: first.id)
        let preview = try await model.processor.thumbnail(first.url, maximum: 40)
        XCTAssertEqual(preview.width, 40)
        await importing.value
        XCTAssertEqual(model.assets.count, 50)
        XCTAssertEqual(model.configuration(for: first).crop.centerX, 0.7)
        XCTAssertEqual(model.importCompleted, 50)
        XCTAssertFalse(model.isImporting)
        await model.stopWork(); model.persistenceTask?.cancel()
    }
    func testDuplicateImportProgressAndOriginalPreservation() async throws {
        let model = try workspace()
        let input = model.directory.appendingPathComponent("Incoming")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let original = try source(at: input)
        let bytes = try Data(contentsOf: original)
        await model.importURLs([original, original])
        XCTAssertEqual(model.importDiscovered, 2)
        XCTAssertEqual(model.importCompleted, 1)
        XCTAssertEqual(model.importSkipped, 1)
        XCTAssertEqual(model.assets.count, 1)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        await model.stopWork(); model.persistenceTask?.cancel()
    }
    func testThumbnailAndPrecisionShareStateAndGestureUndo() throws {
        let model=try workspace();let asset=SourceAsset(url:model.directory.appendingPathComponent("source.png"));model.assets=[asset];model.selected=asset.id
        var crop=CropConfiguration();crop.mode = .fill;model.beginInteraction()
        crop.centerX=0.6;model.setCrop(crop,for:asset.id);crop.centerX=0.7;model.setCrop(crop,for:asset.id);model.endInteraction()
        XCTAssertEqual(model.configuration(for:asset).crop.centerX,0.7);XCTAssertTrue(model.canUndo)
        model.precision=true;XCTAssertEqual(model.configuration(for:asset).crop.centerX,0.7)
        model.undo();XCTAssertEqual(model.configuration(for:asset).crop.centerX,0.5)
        model.redo();XCTAssertEqual(model.configuration(for:asset).crop.centerX,0.7)
        model.settings.quality=0.4;XCTAssertEqual(model.configuration(for:asset).crop.centerX,0.7)
        model.settings.width=1024;model.settings.height=1024;XCTAssertTrue(model.proposals[asset.id]?.needsReview == true)
        model.setImageAspect(1, for: asset.id); model.settings.quality=0.25; model.settings.watermark.enabled=true
        XCTAssertEqual(model.configuration(for:asset).quality,0.25); XCTAssertTrue(model.configuration(for:asset).watermark.enabled)
        XCTAssertEqual(model.configuration(for:asset).width,1024); XCTAssertEqual(model.configuration(for:asset).height,1024)
        model.settings.width=512; XCTAssertEqual(model.configuration(for:asset).width,512); XCTAssertEqual(model.configuration(for:asset).height,512)
        model.reset([asset.id]);XCTAssertNil(model.edits.overrides[asset.id]);model.persistenceTask?.cancel()
    }
    func testSearchSelectionOnlyExportsMatchesAndPartialFailuresRetry() async throws {
        let model=try workspace();let url=try source(at:model.directory);let good=SourceAsset(url:url,name:"dog.png");let missing=SourceAsset(url:model.directory.appendingPathComponent("missing.png"));model.assets=[good,missing];model.selected=good.id
        let record=ClassificationRecord(assetID:good.id,labels:[ClassificationLabel("dog",confidence:0.9)],revision:1,fingerprint:try SourceFingerprint.read(url));model.index.insert(record);model.query="dog";model.scope = .results
        XCTAssertEqual(model.targets.map(\.id),[good.id]);model.settings.width=40;model.settings.height=40
        let output=model.directory.appendingPathComponent("out");try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        model.export(to:output);await model.task?.value;XCTAssertEqual(model.results.compactMap(\.output).count,1);XCTAssertTrue(model.pendingExports.isEmpty)
        model.scope = .all;model.export(to:output);await model.task?.value
        XCTAssertEqual(model.results.filter{$0.error != nil}.count,1);XCTAssertEqual(model.pendingExports.map{ $0.source.id },[missing.id])
        let before=try FileManager.default.contentsOfDirectory(atPath:output.path).count
        model.export(to:output,retry:true);await model.task?.value
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:output.path).count,before,"Retry must not duplicate successful images")
        model.persistenceTask?.cancel()
    }
    func testManualOverrideNotReplacedByAutoFrameAndImportKeepsSettings() async throws {
        let model=try workspace();let url=try source(at:model.directory);let asset=SourceAsset(url:url);model.assets=[asset];model.selected=asset.id
        var crop=CropConfiguration();crop.centerX=0.7;model.setCrop(crop,for:asset.id);model.settings.watermark.enabled=true;model.settings.width=1024
        model.autoFrame(.smart);await model.analysisTask?.value
        XCTAssertEqual(model.configuration(for:asset).crop.centerX,0.7)
        model.skipDuplicates = false
        await model.importURLs([url]);XCTAssertTrue(model.settings.watermark.enabled);XCTAssertEqual(model.settings.width,1024);XCTAssertEqual(model.assets.count,2)
        model.indexingTask?.cancel();model.persistenceTask?.cancel()
    }
    func testPersistentSessionRestoresEditsAndPendingWork() async throws {
        let model=try workspace();let url=try source(at:model.directory);let asset=SourceAsset(url:url);model.assets=[asset];model.selected=asset.id;model.settings.width=512
        var crop=CropConfiguration();crop.zoom=2;model.setCrop(crop,for:asset.id);model.pendingExports=[ExportRequest(source:asset,configuration:model.settings,profile:ExportProfile())];model.persist();await model.persistenceTask?.value
        let restored=Workspace(directory:model.directory.deletingLastPathComponent());await restored.start()
        XCTAssertEqual(restored.assets,[asset]);XCTAssertEqual(restored.settings.width,512);XCTAssertEqual(restored.configuration(for:asset).crop.zoom,2);XCTAssertEqual(restored.pendingExports.count,1)
        restored.indexingTask?.cancel();restored.persistenceTask?.cancel()
    }
    func testScopeSpecificSettingsDoNotChangeUnselectedImage() throws {
        let model=try workspace();let a=SourceAsset(url:model.directory.appendingPathComponent("a.png"));let b=SourceAsset(url:model.directory.appendingPathComponent("b.png"));model.assets=[a,b];model.selection=[a.id];model.scope = .selected
        var config=model.controlConfiguration;config.width=512;model.controlConfiguration=config
        XCTAssertEqual(model.configuration(for:a).width,512);XCTAssertEqual(model.configuration(for:b).width,1600)
        model.persistenceTask?.cancel()
    }
    func testHundredImageBatchProgressPreservationAndCompletedRequests() async throws {
        let model = try workspace(); let url = try source(at: model.directory); let original = try Data(contentsOf: url)
        model.assets = (0..<100).map { SourceAsset(url: url, name: "photo-\($0).png") }
        model.settings.width = 1024; model.settings.height = 1024; model.settings.crop.mode = .fill
        let output = model.directory.appendingPathComponent("batch"); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        model.export(to: output); await model.task?.value
        XCTAssertEqual(model.completed, 100); XCTAssertEqual(model.results.compactMap(\.output).count, 100)
        XCTAssertTrue(model.pendingExports.isEmpty); XCTAssertFalse(model.running)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 100)
        let exported=try XCTUnwrap(model.results.last?.output);let encoded=try XCTUnwrap(CGImageSourceCreateWithURL(exported as CFURL,nil));let decoded=try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded,0,nil));XCTAssertEqual(decoded.width,1024);XCTAssertEqual(decoded.height,1024)
        model.persistenceTask?.cancel()
    }

    func testAppContainerRelocationRestoresSnapshotsLogosAndPendingJobs() async throws {
        let model = try workspace(); let url = try source(at: model.directory); let asset = SourceAsset(url: url)
        model.assets = [asset]; model.settings.watermark.imageURL = url
        model.pendingExports = [ExportRequest(source: asset, configuration: model.settings, profile: ExportProfile())]
        await model.flush()
        let oldRoot = model.directory.deletingLastPathComponent()
        let newRoot = oldRoot.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: oldRoot, to: newRoot)
        addTeardownBlock { try? FileManager.default.removeItem(at: newRoot) }
        let restored = Workspace(directory: newRoot); await restored.start()
        let expected = restored.directory.appendingPathComponent(url.lastPathComponent)
        XCTAssertEqual(restored.assets.first?.url, expected)
        XCTAssertEqual(restored.settings.watermark.imageURL, expected)
        XCTAssertEqual(restored.pendingExports.first?.source.url, expected)
        XCTAssertEqual(restored.pendingExports.first?.configuration.watermark.imageURL, expected)
        let size = try await restored.processor.identify(expected); XCTAssertEqual(size.width, 80)
        restored.indexingTask?.cancel(); restored.persistenceTask?.cancel()
    }

    func testMissingSourceInvalidatesPersistedClassification() async throws {
        let model = try workspace(); let asset = SourceAsset(url: model.directory.appendingPathComponent("missing.png")); model.assets = [asset]
        model.index.insert(ClassificationRecord(assetID: asset.id, labels: [ClassificationLabel("dog", confidence: 0.9)], revision: VisionAnalyzer.classificationRevision, fingerprint: SourceFingerprint(bytes: 1, modified: .distantPast)))
        model.query = "dog"; model.startIndexing(); await model.indexingTask?.value
        XCTAssertNil(model.index.records[asset.id]); XCTAssertTrue(model.filtered.isEmpty); XCTAssertFalse(model.issues.isEmpty)
        model.persistenceTask?.cancel()
    }

    func testSavedNamingAndMultipleProfileFoldersUseExactDimensions() async throws {
        let model = try workspace(); let url = try source(at: model.directory); let original = try Data(contentsOf: url)
        let asset = SourceAsset(url: url, name: "source.png"); model.assets = [asset]; model.selected = asset.id
        model.settings.width = 32; model.settings.height = 32; model.namingTemplate = "{name}-{id}{suffix}"; model.saveProfile(name: "Small")
        let small = try XCTUnwrap(model.profiles.last); XCTAssertEqual(small.namingTemplate, model.namingTemplate)
        model.settings.width = 64; model.settings.height = 40; model.saveProfile(name: "Wide"); let wide = try XCTUnwrap(model.profiles.last)
        model.exportProfiles = [small.id, wide.id]
        let out = model.directory.appendingPathComponent("multi"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        model.export(to: out); await model.task?.value
        XCTAssertEqual(model.results.compactMap(\.output).count, 2)
        for (name, width, height) in [("Small",32,32),("Wide",64,40)] {
            let folder = out.appendingPathComponent(name); let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            XCTAssertEqual(files.count,1); let source = try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(files.first) as CFURL,nil)); let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil)); XCTAssertEqual(image.width,width); XCTAssertEqual(image.height,height)
        }
        XCTAssertEqual(try Data(contentsOf:url),original)
        await model.flush(); let restored = Workspace(directory:model.directory.deletingLastPathComponent()); await restored.start()
        XCTAssertEqual(restored.namingTemplate,model.namingTemplate); XCTAssertEqual(restored.exportProfiles,model.exportProfiles)
        restored.indexingTask?.cancel(); restored.persistenceTask?.cancel(); model.persistenceTask?.cancel()
    }

    func testPhotosChangeBlockRunsWithoutMainActorIsolation() async throws {
        let permission = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard permission == .authorized || permission == .limited else { throw XCTSkip("Photos integration requires add-only permission granted through the native QA flow.") }
        let model = try workspace(); let url = try source(at: model.directory)
        try await PhotoLibraryExporter.save(url)
    }

}

extension WorkspaceTests {
    func testAdjustmentsMasksAnnotationsUndoAndProjectRelink() async throws {
        let model=try workspace();let url=try source(at:model.directory);let asset=SourceAsset(url:url);model.assets=[asset];model.selected=asset.id;model.scope = .individual
        var c=model.controlConfiguration;c.adjustments.exposure=0.5;c.masks=[PrivacyMask()];c.annotations=[Annotation()];model.controlConfiguration=c
        model.undo();XCTAssertTrue(model.configuration(for:asset).masks.isEmpty);model.redo();XCTAssertEqual(model.configuration(for:asset).adjustments.exposure,0.5)
        let project=try await model.saveProjectCopy();await model.newProject();XCTAssertTrue(model.assets.isEmpty);await model.openProject(project);XCTAssertEqual(model.assets.count,1);XCTAssertEqual(model.configuration(for:asset).masks.count,1)
        let replacement=try source(at:model.directory,name:"replacement.png");await model.relinkSource(replacement);XCTAssertEqual(model.assets.first?.id,asset.id);XCTAssertEqual(model.configuration(for:asset).annotations.count,1);XCTAssertTrue(model.proposals[asset.id]?.needsReview==true);model.indexingTask?.cancel();model.persistenceTask?.cancel()
    }
    func testDuplicateSkipAndImportAnyway() async throws {
        let model=try workspace();let url=try source(at:model.directory);await model.importURLs([url,url]);XCTAssertEqual(model.assets.count,1);model.skipDuplicates=false;await model.importURLs([url]);XCTAssertEqual(model.assets.count,2);model.indexingTask?.cancel();model.persistenceTask?.cancel()
    }
    func testCollageHistoryAndAutosave() async throws {
        let model=try workspace();let url=try source(at:model.directory);let asset=SourceAsset(url:url);model.assets=[asset]
        var project=CollageProject();project.arrange([asset.id],layout:.grid);model.changeCollage(project);project.title="Holiday";model.changeCollage(project);model.undoCollage();XCTAssertEqual(model.collage.title,"");model.redoCollage();XCTAssertEqual(model.collage.title,"Holiday");await model.flush()
        let restored=Workspace(directory:model.directory.deletingLastPathComponent());await restored.start();XCTAssertEqual(restored.collage,project);restored.indexingTask?.cancel();model.persistenceTask?.cancel()
    }
}
extension WorkspaceTests {
    func testCompletedCollageOutputRetainedAcrossProjectRecovery() async throws {
        let model=try workspace();let url=try source(at:model.directory);let asset=SourceAsset(url:url);model.assets=[asset]
        var project=CollageProject();project.width=32;project.height=32;project.arrange([asset.id],layout:.grid);model.changeCollage(project)
        let folder=model.directory.deletingLastPathComponent().appendingPathComponent("Exports");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let cg=try await model.processor.renderCollage(project,sources:model.assets,edits:model.edits);var c=ProcessingConfiguration();c.format = .png
        let result=try await model.processor.publish(cg,asset:SourceAsset(url:model.projectURL,name:"Collage.png"),configuration:c,to:folder);let output=try XCTUnwrap(result.output);model.collageOutputs=[output];await model.flush()
        let restored=Workspace(directory:model.directory.deletingLastPathComponent());await restored.start();XCTAssertEqual(restored.collageOutputs,[output]);XCTAssertEqual(restored.completedOutputs,[output]);XCTAssertTrue(FileManager.default.fileExists(atPath:output.path));restored.indexingTask?.cancel();model.persistenceTask?.cancel()
    }
}
extension WorkspaceTests {
    func testExportProfileCannotDropPerImagePrivacyMask() async throws {
        let model=try workspace();let url=try source(at:model.directory);let asset=SourceAsset(url:url);model.assets=[asset];model.selected=asset.id
        var c=model.configuration(for:asset);var mask=PrivacyMask();mask.x=0;mask.y=0;mask.width=1;mask.height=1;c.masks=[mask];c.privacyExport=true;model.setImageConfiguration(c,for:asset.id)
        var profile=ExportProfile();var variant=ProcessingConfiguration();variant.width=32;variant.height=16;variant.format = .png;variant.metadata = .preserve;profile.processing=variant;model.profiles=[profile];model.exportProfiles=[profile.id]
        let folder=model.directory.appendingPathComponent("ProfileOutput");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);model.export(to:folder);await model.task?.value
        let output=try XCTUnwrap(model.results.last?.output);let source=try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL,nil));let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil));XCTAssertEqual(image.width,32);XCTAssertEqual(image.height,16)
        let helper=ProcessingTests();XCTAssertEqual(Array(try helper.pixels(image).prefix(4)),[0,0,0,255]);XCTAssertTrue(model.pendingExports.isEmpty);model.persistenceTask?.cancel()
    }
}
extension WorkspaceTests {
    func testResetFramingPreservesPrivacyAndAdjustmentEdits() throws {
        let model=try workspace();let asset=SourceAsset(url:model.directory.appendingPathComponent("source.png"));model.assets=[asset];model.selected=asset.id
        var c=model.configuration(for:asset);c.crop.zoom=2;c.adjustments.exposure=0.5;c.masks=[PrivacyMask()];c.annotations=[Annotation()];model.setImageConfiguration(c,for:asset.id)
        model.reset([asset.id]);let result=model.configuration(for:asset);XCTAssertEqual(result.crop.zoom,1);XCTAssertEqual(result.adjustments.exposure,0.5);XCTAssertEqual(result.masks.count,1);XCTAssertEqual(result.annotations.count,1)
        model.persistenceTask?.cancel()
    }
}
extension WorkspaceTests {
    func testFailedImportDoesNotPoisonDuplicateRetry() async throws {
        let model=try workspace();let url=try source(at:model.directory.deletingLastPathComponent());try FileManager.default.removeItem(at:model.directory)
        await model.importURLs([url]);XCTAssertTrue(model.assets.isEmpty)
        try FileManager.default.createDirectory(at:model.directory,withIntermediateDirectories:true);await model.importURLs([url]);XCTAssertEqual(model.assets.count,1);model.indexingTask?.cancel();model.persistenceTask?.cancel()
    }
}
