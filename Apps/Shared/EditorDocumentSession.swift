import FramepebbleCore
import Foundation
import Observation

/// A document's history and active layer never borrow workspace selection or batch scope.
@MainActor @Observable final class EditorDocumentSession: Identifiable {
  let id=UUID()
  var document:EditorDocument
  var history:EditorDocumentHistory
  var selectedLayerID:UUID?
  var fileURL:URL?
  var savedDocument:EditorDocument?
  var resources:[UUID:URL]=[:]
  var error:String?
  var busy=false
  var closing=false
  var status=""
  let directory:URL
  let renderer=EditorDocumentRenderer()
  let thumbnailRenderer=EditorDocumentRenderer()
  let processor=ImageProcessor()
  let store=EditorDocumentStore()
  private let metadataStore=EditorRecoveryMetadataStore()
  #if os(macOS)
  @ObservationIgnored var fileBookmark:Data?
  #endif
  @ObservationIgnored var recoveryTask:Task<Void,Never>?
  @ObservationIgnored private var interactionStart:EditorDocument?
  var dirty:Bool { document != savedDocument }
  var canUndo:Bool { !history.undoSteps.isEmpty || (interactionStart != nil && document != history.current) }
  var canRedo:Bool { !history.redoSteps.isEmpty && document == history.current }
  var selectedLayer:EditorLayer? { document.layers.first { $0.id==selectedLayerID } }
  var recoveryURL:URL {directory.appendingPathComponent("Recovery.ameluma",isDirectory:true)}
  init(document:EditorDocument = EditorDocument(), directory:URL) {
    self.document=document;self.history=EditorDocumentHistory(document);self.directory=directory
    selectedLayerID=document.layers.last?.id
  }
  func update(_ title:String,_ action:(inout EditorDocument)->Void) {
    var next=document;action(&next)
    next.version = max(next.version, next.requiredVersion)
    do {
      try next.validate()
      if interactionStart == nil {try history.apply(next,title:title)}
      document=next;error=nil
      if interactionStart == nil {scheduleRecovery()}
    } catch {self.error=error.localizedDescription}
  }
  func changeLayer(_ title:String,_ action:(inout EditorLayer)->Void) {
    guard let id=selectedLayerID,let layer=selectedLayer,!layer.locked else{return}
    update(title) { doc in if let i=doc.layers.firstIndex(where:{$0.id==id}) {action(&doc.layers[i])} }
  }
  func beginInteraction() {if interactionStart == nil {interactionStart=document}}
  func endInteraction(_ title:String) {
    guard interactionStart != nil else{return};interactionStart=nil
    do {try history.apply(document,title:title);scheduleRecovery()}catch{self.error=error.localizedDescription}
  }
  func undo() {let active=interactionStart != nil;endInteraction("Edit Layer");history.undo();document=history.current;reconcile();if active {beginInteraction()};scheduleRecovery()}
  func redo() {let active=interactionStart != nil;endInteraction("Edit Layer");history.redo();document=history.current;reconcile();if active {beginInteraction()};scheduleRecovery()}
  func reconcile() {if !document.layers.contains(where:{$0.id==selectedLayerID}) {selectedLayerID=document.layers.last?.id}}
  func addText() {
    endInteraction("Edit Layer")
    var layer=EditorLayer(name:"Text",content:.text(EditorText()));layer.width=min(600,Double(document.width));layer.height=min(200,Double(document.height))
    update("Add Text") {$0.layers.append(layer)};selectedLayerID=layer.id
  }
  func addShape(_ kind:EditorShapeKind) {
    endInteraction("Edit Layer")
    var shape=EditorShape();shape.kind=kind
    var layer=EditorLayer(name:kind.rawValue,content:.shape(shape));layer.width=min(400,Double(document.width));layer.height=min(300,Double(document.height))
    update("Add Shape") {$0.layers.append(layer)};selectedLayerID=layer.id
  }
  func duplicate() {
    endInteraction("Edit Layer")
    guard var layer=selectedLayer else{return}
    let needsReview=document.privacyReviewLayerIDs?.contains(layer.id)==true
    layer.id=UUID();layer.name += " Copy";layer.x += 20;layer.y += 20;layer.locked=false
    update("Duplicate Layer") {$0.layers.append(layer);if needsReview {$0.privacyReviewLayerIDs=($0.privacyReviewLayerIDs ?? []).union([layer.id])}};selectedLayerID=layer.id
  }
  func remove() {
    endInteraction("Edit Layer")
    guard let layer=selectedLayer,!layer.locked else{return}
    update("Delete Layer") {doc in
      doc.layers.removeAll{$0.id==layer.id}
      var used=Set<UUID>()
      for remaining in doc.layers {
        if case .image(let id,_)=remaining.content {used.insert(id)}
        if let watermark=remaining.watermarkResourceID {used.insert(watermark)}
      }
      doc.resources.removeAll{!used.contains($0.id)}
    };reconcile()
  }
  func move(_ id:UUID,before other:UUID) {
    endInteraction("Edit Layer")
    guard id != other,document.layers.contains(where:{$0.id==other}),let original=document.layers.first(where:{$0.id==id}),!original.locked else{return}
    update("Reorder Layer") {doc in
      doc.layers.removeAll{$0.id==id}
      if let i=doc.layers.firstIndex(where:{$0.id==other}) {doc.layers.insert(original,at:i)}
    }
  }
  func addImages(_ inputs:[(URL,ProcessingConfiguration)], fitCanvas:Bool=false,names:[String]=[]) async {
    guard !busy else{error="Wait for the current document operation to finish.";return};busy=true;defer{busy=false}
    do {
      try FileManager.default.createDirectory(at:directory.appendingPathComponent("Sources"),withIntermediateDirectories:true)
      var next=document;var acquired:[UUID:URL]=[:]
      for (index,input) in inputs.enumerated() {
        let url=input.0;var configuration=input.1
        let name=names.indices.contains(index) ? names[index]:url.lastPathComponent
        try Task.checkCancellation()
        let source=try await processor.importSnapshot(url,to:directory.appendingPathComponent("Sources"))
        let resource=EditorResource(name:name,fileExtension:source.url.pathExtension)
        acquired[resource.id]=source.url;next.resources.append(resource)
        var layer=EditorLayer(name:name,content:.image(resourceID:resource.id,configuration:configuration))
        if let watermark=configuration.watermark.imageURL {
          let copy=try await processor.importSnapshot(watermark,to:directory.appendingPathComponent("Sources"))
          let reference=EditorResource(name:watermark.lastPathComponent,fileExtension:copy.url.pathExtension)
          acquired[reference.id]=copy.url;next.resources.append(reference);layer.watermarkResourceID=reference.id
          configuration.watermark.imageURL=nil;layer.content = .image(resourceID:resource.id,configuration:configuration)
        }
        let raw=try await processor.identify(source.url)
        let size=ImageProcessor.outputSize(source:ImageProcessor.transformedSize(raw,configuration:configuration),configuration:configuration)
        if fitCanvas && next.layers.isEmpty {next.width=Int(size.width);next.height=Int(size.height)}
        layer.width=size.width;layer.height=size.height
        next.layers.append(layer)
      }
      try next.validate();try history.apply(next,title:"Add Image Layers");resources.merge(acquired){_,new in new};document=next
      selectedLayerID=document.layers.last?.id;error=nil;scheduleRecovery()
    }catch{self.error=error.localizedDescription}
  }
  func save(to url:URL) async -> Bool {
    endInteraction("Edit Layer")
    let snapshot=document, urls=resources
    busy=true;defer{busy=false}
    do {
      #if os(macOS)
      var destination=url
      if let bookmark=fileBookmark,url==fileURL {
        var stale=false
        destination=try URL(resolvingBookmarkData:bookmark,options:.withSecurityScope,bookmarkDataIsStale:&stale)
      }
      let access=destination.startAccessingSecurityScopedResource();defer{if access {destination.stopAccessingSecurityScopedResource()}}
      try await MacEditorDocumentIO().save(snapshot,resources:urls,to:destination)
      fileBookmark=try? destination.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
      fileURL=destination
      #else
      try await store.save(snapshot,resources:urls,to:url);fileURL=url
      #endif
      savedDocument=snapshot;status="Saved editable document";error=nil;scheduleRecovery();return true
    }
    catch{self.error=error.localizedDescription;return false}
  }
  func open(_ url:URL) async throws {
    let loaded=try await store.load(url)
    // Copy into this session before the user can move/delete the opened package.
    if url==recoveryURL,FileManager.default.fileExists(atPath:directory.appendingPathComponent("Sources").path) {try FileManager.default.removeItem(at:directory.appendingPathComponent("Sources"))}
    try FileManager.default.createDirectory(at:directory.appendingPathComponent("Sources"),withIntermediateDirectories:true)
    var copies:[UUID:URL]=[:]
    for resource in loaded.resources {
      let source=url.appendingPathComponent("Resources").appendingPathComponent(resource.filename)
      let imported=try await processor.importSnapshot(source,to:directory.appendingPathComponent("Sources"))
      copies[resource.id]=imported.url
    }
    document=loaded;history=EditorDocumentHistory(loaded);resources=copies;selectedLayerID=loaded.layers.last?.id
    fileURL=url;savedDocument=loaded
    #if os(macOS)
    fileBookmark=try? url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
    #endif
    if url != recoveryURL {scheduleRecovery()}
  }
  private var recoveryRecord:EditorRecoveryRecord {
    var value=EditorRecoveryRecord(fileURL:fileURL,savedDocument:savedDocument)
    #if os(macOS)
    value.bookmark=fileBookmark
    #endif
    return value
  }
  func restoreRecoveryMetadata() async {
    do {
      let value=try await metadataStore.load(directory.appendingPathComponent("session.json"))
      fileURL=value.fileURL;savedDocument=value.savedDocument
      #if os(macOS)
      fileBookmark=value.bookmark
      #endif
    }catch {fileURL=nil;savedDocument=nil}
    status=dirty ? "Recovered unsaved document":"Restored editable document"
  }
  func scheduleRecovery() {
    guard !closing else{return}
    recoveryTask?.cancel()
    let snapshot=document,urls=resources,destination=recoveryURL,store=store
    let record=recoveryRecord,metadataURL=directory.appendingPathComponent("session.json"),metadataStore=metadataStore
    recoveryTask=Task {
      do {try await Task.sleep(for:.milliseconds(350));try await store.save(snapshot,resources:urls,to:destination);try Task.checkCancellation();try await metadataStore.save(record,to:metadataURL)}
      catch is CancellationError {} catch {self.error="Recovery save failed: "+error.localizedDescription}
    }
  }
  func flushRecovery() async -> Bool {
    recoveryTask?.cancel();endInteraction("Edit Layer");recoveryTask?.cancel()
    do {try await store.save(document,resources:resources,to:recoveryURL);try await metadataStore.save(recoveryRecord,to:directory.appendingPathComponent("session.json"));return true}
    catch{self.error="Recovery save failed: "+error.localizedDescription;return false}
  }
}

extension Workspace {
  func newEditorDocument() {
    guard !overlayEditor else{return}
    let root=directory.appendingPathComponent("EditorDocuments").appendingPathComponent(UUID().uuidString)
    let session=EditorDocumentSession(directory:root)
    editorDocuments.append(session);activeEditorDocumentID=session.id;session.scheduleRecovery()
  }
  func openPhotosAsDocument(_ ids:[UUID]) async {
    guard !overlayEditor else{return}
    let sources=workspaceActionIDs(ids).compactMap{id in workspaceAssets.first{$0.id==id}}
    let captured=sources.map{($0.url,configuration(for:$0))}
    let names=sources.map(\.name)
    let needsReview=sources.map{requirePrivacyReview || privacyCoverageNeedsReview($0.id)}
    guard !captured.isEmpty else{return}
    newEditorDocument()
    if let session=activeEditorDocument {
      await session.addImages(captured,fitCanvas:true,names:names)
      let flagged=Set(zip(session.document.layers,needsReview).filter{$0.1}.map{$0.0.id})
      if !flagged.isEmpty {session.update("Photo Review Required") {$0.privacyReviewLayerIDs=flagged}}
    }
  }
  var activeEditorDocument:EditorDocumentSession? {editorDocuments.first{$0.id==activeEditorDocumentID}}
}

extension Workspace {
  func restoreEditorDocuments() async {
    guard editorDocuments.isEmpty else{return}
    let root=directory.appendingPathComponent("EditorDocuments")
    guard let folders=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles) else{return}
    for folder in folders.prefix(20) {
      let recovery=folder.appendingPathComponent("Recovery.ameluma")
      guard FileManager.default.fileExists(atPath:recovery.path) else{continue}
      let session=EditorDocumentSession(directory:folder)
      do {try await session.open(recovery);await session.restoreRecoveryMetadata();editorDocuments.append(session)}
      catch{issues.append("Could not restore editable document: "+error.localizedDescription)}
    }
  }
}

#if os(macOS)
/// File coordination belongs to the native adapter, while package validation stays shared.
private actor MacEditorDocumentIO {
  func save(_ document:EditorDocument,resources:[UUID:URL],to url:URL) throws {
    let coordinator=NSFileCoordinator(filePresenter:nil)
    var coordinationError:NSError?,writeError:Error?
    coordinator.coordinate(writingItemAt:url,options:.forReplacing,error:&coordinationError) {destination in
      do {try EditorDocumentStore.writePackage(document,resources:resources,to:destination)}catch{writeError=error}
    }
    if let error=coordinationError ?? (writeError as NSError?) {throw error}
  }
}
#endif

private struct EditorRecoveryRecord:Codable,Sendable {
  var fileURL:URL?
  var savedDocument:EditorDocument?
  var bookmark:Data?
}
private actor EditorRecoveryMetadataStore {
  func save(_ value:EditorRecoveryRecord,to url:URL) throws {
    try Task.checkCancellation();try JSONEncoder().encode(value).write(to:url,options:.atomic)
  }
  func load(_ url:URL) throws -> EditorRecoveryRecord {
    let data=try Data(contentsOf:url)
    guard data.count<=8*1024*1024 else {throw EditorDocumentError.invalidDocument}
    return try JSONDecoder().decode(EditorRecoveryRecord.self,from:data)
  }
}
