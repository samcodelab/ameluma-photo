import XCTest
import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class EditorDocumentUsabilityTests:XCTestCase {
  func testDocumentUndoCannotChangeWorkspaceSelectionOrBatchEdits() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model=Workspace(directory:root)
    defer{model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root)}
    let a=SourceAsset(url:root.appendingPathComponent("a.png")),b=SourceAsset(url:root.appendingPathComponent("b.png"))
    model.assets=[a,b];model.selection=[a.id,b.id];model.batchInputIDs=[b.id]
    let before=model.edits
    model.newEditorDocument();let first=try XCTUnwrap(model.activeEditorDocument)
    first.addText();let textID=first.selectedLayerID
    first.beginInteraction();first.changeLayer("Move") {$0.x=10};first.changeLayer("Move") {$0.x=20};first.endInteraction("Move Text")
    XCTAssertEqual(first.history.undoSteps.count,2)
    first.undo();XCTAssertEqual(first.selectedLayer?.x,0);XCTAssertEqual(first.selectedLayerID,textID)
    first.redo();XCTAssertEqual(first.selectedLayer?.x,20)
    model.newEditorDocument();let second=try XCTUnwrap(model.activeEditorDocument);second.addShape(.ellipse)
    second.undo();XCTAssertTrue(second.document.layers.isEmpty);XCTAssertEqual(first.document.layers.count,1)
    XCTAssertEqual(model.selection,[a.id,b.id]);XCTAssertEqual(model.batchInputIDs,[b.id]);XCTAssertEqual(model.edits,before)
    for session in model.editorDocuments {session.recoveryTask?.cancel();await session.recoveryTask?.value}
  }
  func testTextTransactionsStayGroupedAfterUndoAndBeforeAddingAnotherLayer() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let session=EditorDocumentSession(directory:root);session.addText()
    session.beginInteraction()
    session.changeLayer("Text") {if case .text(var text)=$0.content {text.text="First";$0.content = .text(text)}}
    session.changeLayer("Text") {if case .text(var text)=$0.content {text.text="First complete";$0.content = .text(text)}}
    XCTAssertTrue(session.canUndo)
    session.undo()
    if case .text(let text)=session.selectedLayer?.content {XCTAssertEqual(text.text,"Your text")}else{XCTFail("Missing text")}
    session.redo()
    if case .text(let text)=session.selectedLayer?.content {XCTAssertEqual(text.text,"First complete")}else{XCTFail("Missing text")}
    session.addShape(.rectangle)
    XCTAssertEqual(session.history.undoSteps.count,3)
    session.undo();XCTAssertEqual(session.document.layers.count,1)
    session.recoveryTask?.cancel();await session.recoveryTask?.value
  }
  func testDuplicateRetainsReviewRequirementAfterOriginalLayerIsRemoved() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let session=EditorDocumentSession(directory:root);session.addText()
    let original=try XCTUnwrap(session.selectedLayerID)
    session.update("Require Review") {$0.privacyReviewLayerIDs=[original]}
    session.duplicate();let copy=try XCTUnwrap(session.selectedLayerID)
    XCTAssertNotEqual(original,copy);XCTAssertTrue(session.document.pendingPrivacyReviewIDs.contains(copy))
    session.selectedLayerID=original;session.remove()
    XCTAssertThrowsError(try session.document.validateForExport())
    session.undo();XCTAssertEqual(session.document.layers.count,2)
    session.recoveryTask?.cancel();await session.recoveryTask?.value
  }
  func testLockedLayerAndInvalidGeometryDoNotChangeDocument() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let session=EditorDocumentSession(directory:root);session.addText()
    session.update("Lock") {$0.layers[0].locked=true}
    let locked=session.document
    session.changeLayer("Move") {$0.x=100};session.remove();XCTAssertEqual(session.document,locked)
    session.update("Unlock") {$0.layers[0].locked=false}
    let valid=session.document;session.changeLayer("Invalid") {$0.width = .nan}
    XCTAssertEqual(session.document,valid);XCTAssertNotNil(session.error)
    session.recoveryTask?.cancel();await session.recoveryTask?.value
  }
  func testRecoveryRestoresEditableDocumentWithoutResettingPhotoProject() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let original=Workspace(directory:root);original.newEditorDocument()
    let session=try XCTUnwrap(original.activeEditorDocument);session.addText();session.addShape(.roundedRectangle)
    let snapshot=session.document
    let flushed=await session.flushRecovery();XCTAssertTrue(flushed)
    let restored=Workspace(directory:root);await restored.restoreEditorDocuments()
    XCTAssertEqual(restored.editorDocuments.count,1)
    let recovered=try XCTUnwrap(restored.editorDocuments.first)
    XCTAssertEqual(recovered.document,snapshot);XCTAssertTrue(recovered.dirty);XCTAssertNil(recovered.fileURL)
    XCTAssertNil(restored.activeEditorDocumentID,"Restoring recovery should not force navigation away from Workspace")
    for item in original.editorDocuments+restored.editorDocuments {item.recoveryTask?.cancel();await item.recoveryTask?.value}
    original.persistenceTask?.cancel();restored.persistenceTask?.cancel()
  }
  func testSavedDocumentRecoveryRetainsSaveIdentityAndDirtyState() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let model=Workspace(directory:root);model.newEditorDocument()
    let session=try XCTUnwrap(model.activeEditorDocument);session.addText()
    let file=root.appendingPathComponent("Saved.ameluma")
    let saved=await session.save(to:file);XCTAssertTrue(saved);XCTAssertFalse(session.dirty)
    session.changeLayer("Move Text") {$0.x=25}
    XCTAssertTrue(session.dirty)
    let flushed=await session.flushRecovery();XCTAssertTrue(flushed)
    let restored=Workspace(directory:root);await restored.restoreEditorDocuments()
    let recovered=try XCTUnwrap(restored.editorDocuments.first)
    XCTAssertEqual(recovered.fileURL?.standardizedFileURL.path,file.standardizedFileURL.path)
    XCTAssertEqual(recovered.document,session.document);XCTAssertEqual(recovered.savedDocument,session.savedDocument);XCTAssertTrue(recovered.dirty)
    let before=recovered.document
    recovered.move(try XCTUnwrap(before.layers.first?.id),before:UUID())
    XCTAssertEqual(recovered.document,before,"A drop outside this document must not remove a layer")
    for item in model.editorDocuments+restored.editorDocuments {item.recoveryTask?.cancel();await item.recoveryTask?.value}
    model.persistenceTask?.cancel();restored.persistenceTask?.cancel()
  }
  #if os(macOS)
  func testDocumentEditorCapture() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner=Workspace(directory:root.appendingPathComponent("Personal"))
    await owner.openDemoWorkspace(root:root.appendingPathComponent("Demo"))
    let model=try XCTUnwrap(owner.demoWorkspace)
    let asset=try XCTUnwrap(model.assets.first(where:{$0.name=="Coastal Hero.jpg"}))
    await model.openPhotosAsDocument([asset.id]);let session=try XCTUnwrap(model.activeEditorDocument)
    session.addText();session.changeLayer("Title") {layer in
      layer.x=30;layer.y=30;layer.width=600;layer.height=160
      var text=EditorText();text.text="Your photos.\nYour way.";text.fontSize=64;text.bold=true;text.colour=RGBAColour(1,1,1,1);layer.content = .text(text)
    }
    let window=NSWindow(contentRect:CGRect(x:0,y:0,width:1280,height:800),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let host=NSHostingView(rootView:MacWorkspace(model:model).environment(\.colorScheme,.dark));window.contentView=host;window.orderFront(nil)
    defer{window.orderOut(nil);window.contentView=nil}
    try await Task.sleep(for:.seconds(2));host.layoutSubtreeIfNeeded()
    let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
    let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
    let attachment=XCTAttachment(data:data,uniformTypeIdentifier:UTType.png.identifier);attachment.name="Layered document editor";attachment.lifetime = .keepAlways;add(attachment)
    XCTAssertNil(session.error);XCTAssertEqual(session.document.layers.count,2)
    let captured=session.document
    session.selectedLayerID=session.document.layers.first?.id;session.remove()
    XCTAssertTrue(session.document.resources.isEmpty,"Deleted image resources must not leak into saved text-only packages")
    session.undo();XCTAssertEqual(session.document,captured)
    _ = try await session.renderer.render(session.document,resources:session.resources,maximum:100)

    session.recoveryTask?.cancel();await session.recoveryTask?.value
    await model.stopWork();await owner.stopWork();model.persistenceTask?.cancel();owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at:root)
  }
  #endif
}
