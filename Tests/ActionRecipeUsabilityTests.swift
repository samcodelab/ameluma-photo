import XCTest
import FramepebbleCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class ActionRecipeUsabilityTests:XCTestCase {
  func fixture(_ root:URL) throws -> URL {
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let space=try XCTUnwrap(CGColorSpace(name:CGColorSpace.sRGB))
    let context=try XCTUnwrap(CGContext(data:nil,width:80,height:60,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red:0.5,green:0.2,blue:0.3,alpha:1));context.fill(CGRect(x:0,y:0,width:80,height:60))
    let url=root.appendingPathComponent("Original.png")
    let destination=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(destination,try XCTUnwrap(context.makeImage()),nil);XCTAssertTrue(CGImageDestinationFinalize(destination));return url
  }
  func testRecipeTargetsStayCapturedPreservePerPhotoEditsAndUndoOnlySuccessfulChanges() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let local=Workspace(directory:root)
    defer {local.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root)}
    let source=try fixture(root),bytes=try Data(contentsOf:source)
    let a=SourceAsset(url:source),b=SourceAsset(url:source),missing=SourceAsset(url:root.appendingPathComponent("Missing.png"))
    local.assets=[a,b,missing];local.openPhoto(a)
    var before=local.configuration(for:a);before.annotations=[Annotation()];before.crop.centerX=0.8;before.filterEdit=FilterEdit(grainSeed:123)
    local.setImageConfiguration(before,for:a.id)
    let request=local.makeRecipeRequest(ids:[a.id,missing.id])
    local.selection=[b.id];local.selectionOrder=[b.id];local.query="hidden"
    let untouched=local.configuration(for:b)
    var recipe=ProcessingRecipe();recipe.enabled=[.filter];recipe.presetID="essentials.warm"
    let outcome=await local.applyRecipe(recipe,request:request)
    XCTAssertEqual(outcome.changedIDs,[a.id]);XCTAssertEqual(outcome.changed,1);XCTAssertEqual(outcome.failed,1)
    XCTAssertEqual(local.configuration(for:b),untouched);XCTAssertEqual(local.selection,[b.id])
    XCTAssertEqual(local.configuration(for:a).annotations,before.annotations);XCTAssertEqual(local.configuration(for:a).crop,before.crop)
    XCTAssertEqual(local.configuration(for:a).filterEdit?.grainSeed,123)
    local.undo();XCTAssertEqual(local.configuration(for:a),before)
    local.redo();XCTAssertEqual(local.configuration(for:a).filterEdit?.presetID,"essentials.warm")
    XCTAssertEqual(try Data(contentsOf:source),bytes)
  }
  func testConcurrentEditsAndProjectSwitchRevokeRecipeTargetsAndCancellationCommitsNothing() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),model=Workspace(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer {model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:model.directory.deletingLastPathComponent())}
    let photo=SourceAsset(url:try fixture(root));model.assets=[photo];model.openPhoto(photo)
    let request=model.makeRecipeRequest(ids:[photo.id]);var newer=model.configuration(for:photo);newer.adjustments.exposure=0.4;model.setImageConfiguration(newer,for:photo.id)
    var recipe=ProcessingRecipe();recipe.enabled=[.filter];recipe.presetID="film.amber"
    let skipped=await model.applyRecipe(recipe,request:request);XCTAssertEqual(skipped.skipped,1);XCTAssertEqual(model.configuration(for:photo),newer)
    let current=model.makeRecipeRequest(ids:[photo.id]),edits=model.edits
    let task=Task {await model.applyRecipe(recipe,request:current)};task.cancel();let cancelled=await task.value
    XCTAssertTrue(cancelled.cancelled);XCTAssertEqual(model.edits,edits)
    model.sourceSessionID=UUID()
    let stale=await model.applyRecipe(recipe,request:current);XCTAssertEqual(stale.skipped,1);XCTAssertEqual(model.edits,edits)
  }
  func testRecipeReapplicationRefreshesOnlySuccessfulTargetsAndExplicitResizeOverridesConversion() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),model=Workspace(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer {model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:model.directory.deletingLastPathComponent())}
    let source=try fixture(root),a=SourceAsset(url:source),b=SourceAsset(url:source)
    model.assets=[a,b];model.openPhoto(a)
    let request=model.makeRecipeRequest(ids:[a.id,b.id])
    var newer=model.configuration(for:b);newer.adjustments.exposure=0.3;model.setImageConfiguration(newer,for:b.id)
    var recipe=ProcessingRecipe();recipe.enabled=[.corrections];recipe.exposure=0.5
    let first=await model.applyRecipe(recipe,request:request)
    XCTAssertEqual(first.changedIDs,[a.id]);XCTAssertEqual(first.skipped,1)
    let continued=model.continuingRecipeRequest(request,changedIDs:first.changedIDs)
    recipe.exposure=0.8
    let second=await model.applyRecipe(recipe,request:continued)
    XCTAssertEqual(second.changedIDs,[a.id]);XCTAssertEqual(second.skipped,1)
    XCTAssertEqual(model.configuration(for:b),newer)
    let context=model.actionContext
    let convert=try XCTUnwrap(model.universalActions(context:context,query:"convert to png").first)
    model.queueUniversalAction(convert,context:context);model.finishUniversalAction()
    XCTAssertEqual(model.configuration(for:a).nativeOutputSizing,true)
    model.updateField(\.width,value:640,fields:[.width])
    XCTAssertEqual(model.configuration(for:a).nativeOutputSizing,false)
    XCTAssertEqual(model.configuration(for:a).width,640)
    model.undo();XCTAssertEqual(model.configuration(for:a).nativeOutputSizing,true)
  }
  func testRecipeLibraryOwnsWatermarkAndDoesNotStoreTheRestOfPhotoConfiguration() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let source=try fixture(root),library=RecipeLibrary(root:root.appendingPathComponent("Library"))
    var recipe=ProcessingRecipe();recipe.enabled=[.watermark];recipe.watermark.enabled=true;recipe.watermark.kind = .image;recipe.watermark.imageURL=source
    let saved=try await library.save(recipe)
    XCTAssertNotEqual(saved.watermark.imageURL,source)
    try FileManager.default.removeItem(at:source)
    let restored=try await library.list();XCTAssertEqual(restored,[saved]);XCTAssertTrue(FileManager.default.fileExists(atPath:try XCTUnwrap(saved.watermark.imageURL).path))
    try await library.remove(saved.id)
    XCTAssertTrue(FileManager.default.fileExists(atPath:try XCTUnwrap(saved.watermark.imageURL).path),"Applied/saved photos can still own the immutable stamp")
  }
  func testRecipeOwnedAssetsRelocateWithTheLibrary() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let source=try fixture(root),original=root.appendingPathComponent("Before"),moved=root.appendingPathComponent("After")
    let library=RecipeLibrary(root:original)
    var recipe=ProcessingRecipe();recipe.enabled=[.output];recipe.watermark.kind = .image;recipe.watermark.imageURL=source
    _ = try await library.save(recipe)
    try FileManager.default.moveItem(at:original,to:moved)
    let reopened=try await RecipeLibrary(root:moved).list()
    let mark=try XCTUnwrap(reopened.first?.watermark.imageURL)
    XCTAssertEqual(mark.deletingLastPathComponent().path,moved.appendingPathComponent("RecipeAssets").path)
    XCTAssertTrue(FileManager.default.fileExists(atPath:mark.path))
  }

  func testUniversalContextNeverSubstitutesWorkspaceSelectionForPhotoDocumentOrCreation() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),model=Workspace(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer {model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:model.directory.deletingLastPathComponent())}
    let source=try fixture(root),a=SourceAsset(url:source),b=SourceAsset(url:source)
    model.assets=[a,b];model.selection=[b.id];model.selectionOrder=[b.id];model.openPhoto(a)
    XCTAssertEqual(model.actionContext.photoIDs,[a.id])
    let convert=try XCTUnwrap(model.universalActions(context:model.actionContext,query:"convert to png").first)
    model.queueUniversalAction(convert,context:model.actionContext);model.finishUniversalAction()
    XCTAssertEqual(model.configuration(for:a).format,.png);XCTAssertEqual(model.configuration(for:a).nativeOutputSizing,true)
    XCTAssertNotEqual(model.configuration(for:b).format,.png);XCTAssertEqual(model.selection,[b.id])
    model.newEditorDocument();let doc=try XCTUnwrap(model.activeEditorDocument)
    XCTAssertEqual(model.actionContext.kind,.document);XCTAssertTrue(model.actionContext.photoIDs.isEmpty)
    XCTAssertTrue(model.universalActions(context:model.actionContext,query:"resize to 1920").isEmpty)
    let add=try XCTUnwrap(model.universalActions(context:model.actionContext,query:"Add Text").first)
    model.queueUniversalAction(add,context:model.actionContext);model.finishUniversalAction();XCTAssertEqual(doc.document.layers.count,1)
    let captured=model.actionContext;model.newEditorDocument();XCTAssertFalse(model.contextIsCurrent(captured))
    model.activeEditorDocumentID=nil;model.startGIF(ids:[a.id]);XCTAssertEqual(model.actionContext.kind,.gif);XCTAssertTrue(model.actionContext.photoIDs.isEmpty)
    for session in model.editorDocuments {session.recoveryTask?.cancel();await session.recoveryTask?.value}
  }
  func testNaturalActionTermsRespectExplicitSelectionAndWatermarkRemovalScope() {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),model=Workspace(directory:root)
    defer {model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root)}
    let a=SourceAsset(url:root.appendingPathComponent("A.png")),b=SourceAsset(url:root.appendingPathComponent("B.png"))
    model.assets=[a,b];model.selection=[b.id];model.openPhoto(a)
    var value=model.configuration(for:a);value.watermark.enabled=true;model.setImageConfiguration(value,for:a.id)
    XCTAssertEqual(model.universalActions(context:model.actionContext,query:"add watermark").first?.intent,.watermark)
    XCTAssertNotNil(model.universalActions(context:model.actionContext,query:"export selected images").first?.disabledReason)
    let removal=model.universalActions(context:model.actionContext,query:"remove watermark").first
    XCTAssertEqual(removal?.intent,.removeWatermark)
    if let removal {model.queueUniversalAction(removal,context:model.actionContext);model.finishUniversalAction()}
    XCTAssertFalse(model.configuration(for:a).watermark.enabled);XCTAssertEqual(model.configuration(for:a).watermark.text,value.watermark.text)
    XCTAssertEqual(model.selection,[b.id])
    model.showLibrary();XCTAssertEqual(model.actionContext.photoIDs,[b.id])
    XCTAssertNil(model.universalActions(context:model.actionContext,query:"export selected images").first?.disabledReason)
  }

  func testNativeSizingConversionRevokesProtectiveCoverageReviewAndRejectsInvalidParameters() {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),model=Workspace(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer {model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:model.directory.deletingLastPathComponent())}
    let photo=SourceAsset(url:root.appendingPathComponent("Photo.png"));model.assets=[photo];model.openPhoto(photo)
    var c=model.configuration(for:photo);c.masks=[PrivacyMask()];model.setImageConfiguration(c,for:photo.id);model.confirmPrivacyCoverage(photo.id)
    let context=model.actionContext
    XCTAssertNotNil(model.universalActions(context:context,query:"resize to 20001").first?.disabledReason)
    guard let action=model.universalActions(context:context,query:"convert to png").first else {XCTFail("Missing conversion action");return}
    model.queueUniversalAction(action,context:context);model.finishUniversalAction()
    XCTAssertTrue(model.privacyCoverageNeedsReview(photo.id))
  }
  func testCapturedExportFreezesOnlyRequestedSourcesAndDocumentBridgeDoesNotInheritBatchEdits() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),model=Workspace(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer {model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:model.directory.deletingLastPathComponent())}
    let a=SourceAsset(url:try fixture(root));model.assets=[a];model.openPhoto(a)
    model.presentCapturedExport(ids:[a.id]);let captured=try XCTUnwrap(model.capturedPhotoExport)
    var changed=model.configuration(for:a);changed.adjustments.exposure=1;model.setImageConfiguration(changed,for:a.id)
    XCTAssertNotEqual(captured.requests[0].configuration,model.configuration(for:a));XCTAssertEqual(captured.requests.count,1)
    model.newEditorDocument();let doc=try XCTUnwrap(model.activeEditorDocument);doc.addText()
    var settings=model.settings;settings.watermark.enabled=true;settings.adjustments.exposure=1;model.settings=settings
    let selected=model.selection,batch=model.batchInputIDs
    await model.addDocumentResult(doc,sendToGIF:true)
    XCTAssertNil(doc.error);XCTAssertEqual(model.assets.count,2);XCTAssertEqual(model.gifProject?.frames.count,1)
    let added=try XCTUnwrap(model.assets.last);let config=model.configuration(for:added)
    XCTAssertFalse(config.watermark.enabled);XCTAssertEqual(config.adjustments.exposure,0);XCTAssertEqual(config.nativeOutputSizing,true)
    XCTAssertEqual(model.selection,selected);XCTAssertEqual(model.batchInputIDs,batch)
    XCTAssertEqual(model.gifProject?.frames.first?.sourceID,added.id)
    model.undo();XCTAssertEqual(model.configuration(for:added),config)
    model.redo();XCTAssertEqual(model.configuration(for:added),config)
    doc.recoveryTask?.cancel();await doc.recoveryTask?.value
  }
}
