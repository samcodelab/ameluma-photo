import Foundation
import FramepebbleCore

/// A session-local membership receipt, not another source registry or edit snapshot.
/// Pixel sources and current edits continue to belong to Workspace.assets/edits.
struct WorkspaceRemovalUndo {
  let sessionID: UUID
  let ids: Set<UUID>
  let favourites: Set<UUID>
  let selection: Set<UUID>
  let selectionOrder: [UUID]
  let tabs: [(id: UUID, position: Int)]
  let editorPhotoID: UUID?
  let editorPhotoAfterRemoval: UUID?
  let batchInputs: Set<UUID>?
  let batchInputsAfterRemoval: Set<UUID>?
  var restoreBatchMembership = true
}

extension Workspace {
  var removalUndoSourceIDs: Set<UUID> {
    guard let receipt = removalUndo, receipt.sessionID == sourceSessionID else { return [] }
    return receipt.ids.intersection(hiddenSourceIDs).intersection(Set(assets.map(\.id)))
  }
  /// An undo-only source stays alive in this session, not in saved project instructions.
  var persistedSources: [SourceAsset] {
    let sessionOnly = removalUndoSourceIDs.subtracting(creationDependencyIDs)
    return assets.filter { !sessionOnly.contains($0.id) }
  }
  var canUndoWorkspaceRemoval: Bool {
    !removalUndoSourceIDs.isEmpty && !running && !overlayEditor && !isImporting
      && !clearingWorkspace && !gifExporting && !collageGenerating && gifSelectionContext == nil
  }
  /// End the receipt before a project switch changes sourceSessionID. The old
  /// project copy must not acquire ownership of sources held only by transient Undo.
  func expireWorkspaceRemovalUndo() {
    let unused = removalUndoSourceIDs.subtracting(creationDependencyIDs)
    assets.removeAll { unused.contains($0.id) }
    hiddenSourceIDs.subtract(unused)
    removalUndo = nil
    if !unused.isEmpty { duplicatesNeedRebuild = true }
  }
  func undoWorkspaceRemoval() {
    guard canUndoWorkspaceRemoval, let receipt = removalUndo else { return }
    let restoring = removalUndoSourceIDs
    hiddenSourceIDs.subtract(restoring)
    favourites.formUnion(receipt.favourites.intersection(restoring))
    selection.formUnion(receipt.selection.intersection(restoring))
    // Restore the removed members' relative order without replacing a newer selection.
    let restoredOrder = receipt.selectionOrder.filter { restoring.contains($0) && selection.contains($0) }
    var order = selectionOrder.filter { !restoring.contains($0) }
    for id in restoredOrder {
      let originalIndex = receipt.selectionOrder.firstIndex(of: id) ?? order.count
      order.insert(id, at: min(originalIndex, order.count))
    }
    selectionOrder = order
    for tab in receipt.tabs where restoring.contains(tab.id) && !editorTabs.contains(tab.id) {
      editorTabs.insert(tab.id, at: min(tab.position, editorTabs.count))
    }
    if editorPhotoID == receipt.editorPhotoAfterRemoval,
       let original = receipt.editorPhotoID, restoring.contains(original) {
      editorPhotoID = original
    }
    if receipt.restoreBatchMembership, batchInputIDs == receipt.batchInputsAfterRemoval,
       let previous = receipt.batchInputs {
      batchInputIDs?.formUnion(previous.intersection(restoring))
    }
    removalUndo = nil
    reconcileVisibleSelection()
    persist()
    status = "Restored \(restoring.count) \(restoring.count == 1 ? "photo" : "photos") to the workspace. Current edits were kept."
  }
}
