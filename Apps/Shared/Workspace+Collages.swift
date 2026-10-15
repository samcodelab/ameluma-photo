import Foundation
import FramepebbleCore

extension Workspace {
  var collageHasFocus: Bool { !browsingLibrary && workflow == .collages && !overlayEditor }
  var canUndoActiveWorkspace: Bool {
    if overlayEditor { return overlaySession?.canUndo ?? false }
    return collageHasFocus ? !collageUndo.isEmpty && !collageGenerating && !running : canUndo
  }
  var canRedoActiveWorkspace: Bool {
    if overlayEditor { return overlaySession?.canRedo ?? false }
    return collageHasFocus ? !collageRedo.isEmpty && !collageGenerating && !running : canRedo
  }
  func undoActiveWorkspace() {
    guard canUndoActiveWorkspace else {return}
    if overlayEditor {overlaySession?.undo()}
    else if collageHasFocus {undoCollage()} else {undo()}
  }
  func redoActiveWorkspace() {
    guard canRedoActiveWorkspace else {return}
    if overlayEditor {overlaySession?.redo()}
    else if collageHasFocus {redoCollage()} else {redo()}
  }
  var activeCollageName: String { collageDocuments.first { $0.id == activeCollageID }?.name ?? "Untitled Collage" }
  var savedCollages: [SavedCollage] {
    collageDocuments.map { item in
      var value = item
      if value.id == activeCollageID { value.project = collage }
      return value
    }
  }
  func ensureCollageDocument() {
    guard activeCollageID == nil, collageDocuments.isEmpty else { return }
    var item = SavedCollage(name: "Collage \(collageDocuments.count+1)", project:collage)
    if item.project.cells.isEmpty {
      let selectedIDs=assets.filter { selection.contains($0.id) }.map(\.id)
      if selectedIDs.count <= CollageProject.maximumCells { item.project.arrange(selectedIDs,layout:.magazine) }
      else { issues.append("A collage supports up to 10,000 tiles. Choose a smaller starting selection, or use all photos as mosaic candidates.") }
    }
    if item.project.cells.contains(where: { !configuration(forID: $0.sourceID).masks.isEmpty }) { item.project.requiresPrivacyReview = true }
    collageDocuments.append(item); activeCollageID=item.id
    openCollageIDs.append(item.id); collage=item.project
  }
  func syncCollageDocument() {
    guard let id = activeCollageID, let index = collageDocuments.firstIndex(where: { $0.id == id }) else { return }
    collageDocuments[index].project = collage
    collageHistories[id] = (collageUndo,collageRedo)
  }
  func activateCollage(_ id: UUID) {
    guard !running, !collageGenerating, id != activeCollageID else { return }
    syncCollageDocument()
    guard let item = collageDocuments.first(where: { $0.id == id }) else { return }
    activeCollageID=id; collage=item.project
    if !openCollageIDs.contains(id) { openCollageIDs.append(id) }
    collageUndo=collageHistories[id]?.0 ?? []; collageRedo=collageHistories[id]?.1 ?? []
    persist()
  }
  func applyCollageTemplate(_ template: CollageTemplate) {
    guard activeCollageID != nil, !running, !collageGenerating else { return }
    var project = collage
    template.apply(to: &project, sources: project.cells.map(\.sourceID))
    changeCollage(project)
  }
  func newCollage(template: CollageTemplate? = nil) {
    guard !running, !collageGenerating else { return }
    syncCollageDocument()
    var project=CollageProject()
    let selectedIDs = assets.filter { selection.contains($0.id) }.map(\.id)
    let ids = selectedIDs.count <= CollageProject.maximumCells ? selectedIDs : []
    if selectedIDs.count > CollageProject.maximumCells { issues.append("Starting collage is empty: select at most 10,000 photos, or use the entire library as art-collage candidates.") }
    if let template { template.apply(to:&project,sources:ids) }
    else { project.arrange(ids,layout:.magazine) }
    if project.cells.contains(where: { !configuration(forID: $0.sourceID).masks.isEmpty }) { project.requiresPrivacyReview = true }
    let item = SavedCollage(name:"Collage \(collageDocuments.count+1)",project:project)
    collageDocuments.append(item); activeCollageID=nil
    activateCollage(item.id)
  }
  func closeCollageTab(_ id: UUID) {
    guard !running, !collageGenerating, let index=openCollageIDs.firstIndex(of:id) else { return }
    syncCollageDocument(); openCollageIDs.remove(at:index)
    if activeCollageID == id {
      activeCollageID=nil; collage=CollageProject(); collageUndo=[]; collageRedo=[]
      if !openCollageIDs.isEmpty { activateCollage(openCollageIDs[min(index,openCollageIDs.count-1)]) }
    }
    persist()
  }
  func renameCollage(_ name: String) {
    guard let index=collageDocuments.firstIndex(where: { $0.id == activeCollageID }) else { return }
    let trimmed=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
    guard !trimmed.isEmpty else { return }
    collageDocuments[index].name=trimmed; persist()
  }
  func resetCollageDocuments() {
    collageDocuments=[]; openCollageIDs=[]; activeCollageID=nil; collageHistories=[:]
  }
  func restoreCollageDocuments(_ document: ProjectDocument) {
    resetCollageDocuments()
    var ids:Set<UUID>=[]
    collageDocuments=document.collages.filter { ids.insert($0.id).inserted }
    if collageDocuments.isEmpty, let legacy=document.collage {
      collageDocuments=[SavedCollage(name:"Collage 1",project:legacy)]
    }
    var seen:Set<UUID>=[]
    openCollageIDs=document.openCollageIDs.filter { id in ids.contains(id) && seen.insert(id).inserted }
    // Legacy projects had one always-open composition.
    if document.collages.isEmpty, let item=collageDocuments.first { openCollageIDs=[item.id] }
    activeCollageID=document.activeCollageID.flatMap { openCollageIDs.contains($0) ? $0 : nil } ?? openCollageIDs.first
    collage=collageDocuments.first { $0.id == activeCollageID }?.project ?? CollageProject()
  }
  func generateCollageArt(shape: CollageShape?, text: String, sourceIDs: Set<UUID>, count: Int, referenceID: UUID?, reuse: Bool, fontName: String? = nil) {
    guard !collageGenerating, !running, let documentID=activeCollageID else { return }
    let sources=assets.filter { sourceIDs.contains($0.id) && $0.id != referenceID }
    guard !sources.isEmpty, (1...CollageProject.maximumCells).contains(count) else {
      issues.append("Choose source photos and between 1 and \(CollageProject.maximumCells) tiles."); return
    }
    if shape == nil && !reuse && sources.count < count {
      issues.append("This mosaic needs \(count) distinct source photos; \(sources.count) are available after excluding the reference. Choose fewer tiles or allow reuse.");return
    }
    if shape == .text && (text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>64) {
      issues.append("Enter 1–64 outline letters for the text collage.");return
    }
    let before=collage, snapshot=edits
    let reference=assets.first { $0.id == referenceID }
    if shape == nil && reference == nil { issues.append("Choose a reference photo from the library."); return }
    collageGenerating=true; collageArtProgress=CollageArtProgress("Preparing collage",0,1)
    collageGenerationTask=Task {
      defer { collageGenerating=false; collageGenerationTask=nil }
      do {
        let result: CollageProject
        var skipped=0
        if let shape {
          var template = before; template.silhouetteFontName = fontName ?? before.silhouetteFontName
          result=try await collageArtBuilder.shape(project:template,sources:sources.map(\.id),count:count,shape:shape,text:text)
        } else if let reference {
          let generated=try await collageArtBuilder.photomosaic(project:before,sources:sources,reference:reference,edits:snapshot,count:count,allowReuse:reuse) { progress in
            await MainActor.run { self.collageArtProgress=progress }
          }
          result=generated.project; skipped=generated.skippedSources
        } else { return }
        try Task.checkCancellation()
        guard activeCollageID == documentID, collage == before, edits == snapshot, Set(sources).isSubset(of:Set(assets)), reference.map({assets.contains($0)}) ?? true else {
          issues.append("The collage or its photo edits changed. The generated result was not applied; generate again with the current settings."); return
        }
        changeCollage(result)
        status="Created \(result.cells.count) editable photo tiles. \(skipped) unavailable source photos skipped."
      } catch is CancellationError { status="Collage generation cancelled. Your composition is unchanged." }
      catch { issues.append("Could not generate collage: " + error.localizedDescription) }
    }
  }
}

extension Workspace {
  func replaceCollagePhoto(cellID: UUID, sourceID: UUID) {
    guard !running, !collageGenerating, assets.contains(where: { $0.id == sourceID }),
      let index = collage.cells.firstIndex(where: { $0.id == cellID }) else { return }
    var value = collage; value.cells[index].sourceID = sourceID; changeCollage(value)
  }
  func swapCollagePhotos(_ first: UUID, _ second: UUID) {
    guard !running, !collageGenerating, first != second,
      let a = collage.cells.firstIndex(where: { $0.id == first }),
      let b = collage.cells.firstIndex(where: { $0.id == second }) else { return }
    var value = collage
    let source = value.cells[a].sourceID, crop = value.cells[a].crop
    value.cells[a].sourceID = value.cells[b].sourceID; value.cells[a].crop = value.cells[b].crop
    value.cells[b].sourceID = source; value.cells[b].crop = crop
    changeCollage(value)
  }
}

extension Workspace {
  func moveCollageTab(_ source: UUID, before target: UUID) {
    guard !running, !collageGenerating, source != target,
      let index = openCollageIDs.firstIndex(of: source), openCollageIDs.contains(target) else { return }
    openCollageIDs.remove(at: index)
    if let destination = openCollageIDs.firstIndex(of: target) { openCollageIDs.insert(source, at: destination) }
    persist()
  }
  func closeOtherCollageTabs(keeping id: UUID) {
    guard !running, !collageGenerating, openCollageIDs.contains(id) else { return }
    syncCollageDocument(); activateCollage(id); openCollageIDs = [id]; persist()
  }
}
