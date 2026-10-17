import Foundation
import FramepebbleCore

extension Workspace {
  var creationDependencyIDs: Set<UUID> {
    var ids = Set((gifProject?.frames ?? []).map(\.sourceID))
    for project in archivedGIFs + gifUndo + gifRedo { ids.formUnion(project.frames.map(\.sourceID)) }
    for project in [collage] + savedCollages.map(\.project) + collageUndo + collageRedo {
      ids.formUnion(project.cells.map(\.sourceID)); if let reference = project.mosaicReferenceID { ids.insert(reference) }
    }
    for (undo, redo) in collageHistories.values { for project in undo + redo { ids.formUnion(project.cells.map(\.sourceID)); if let reference = project.mosaicReferenceID { ids.insert(reference) } } }
    ids.formUnion(pendingExports.map { $0.source.id })
    return ids
  }
  var creationSourceIDs: Set<UUID> { creationDependencyIDs.union(removalUndoSourceIDs) }
  func rebuildDuplicateIndex() async {
    await duplicates.rebuild(assets)
    duplicatesNeedRebuild = false
  }
  /// Return the retained source to the workspace instead of creating another source record.
  func acceptImported(_ asset: SourceAsset, digest: String) async -> Bool {
    let session = sourceSessionID
    guard !clearingWorkspace else { return false }
    if duplicatesNeedRebuild { await rebuildDuplicateIndex() }
    guard !clearingWorkspace, session == sourceSessionID else { return false }
    if skipDuplicates, let id = await duplicates.sourceID(for: digest) {
      guard !clearingWorkspace, session == sourceSessionID else { return false }
      hiddenSourceIDs.remove(id)
      selected = selected ?? id
      importSkipped += 1
      return false
    }
    await duplicates.register(asset.id, digest: digest)
    return !clearingWorkspace && session == sourceSessionID
  }
  /// Free only unused owned copies; current instructions and every readable saved project protect dependencies.
  func freeUnusedWorkingCopies() async throws -> Int {
    guard !clearingWorkspace, !isImporting, sourceAcquisitions == 0, !running, !gifExporting, !collageGenerating else { throw WorkingCopyCleanupError.busy }
    clearingWorkspace = true
    defer { clearingWorkspace = false }
    let unused = hiddenSourceIDs.subtracting(creationSourceIDs)
    assets.removeAll { unused.contains($0.id) }; hiddenSourceIDs.subtract(unused)
    if !unused.isEmpty { duplicatesNeedRebuild = true }
    await flush()
    let cleanup = SourceStorageCleanup()
    let folder = directory.deletingLastPathComponent().appendingPathComponent("Projects")
    let encoded = ["document": try JSONEncoder().encode(document()),
      "gifHistory": try JSONEncoder().encode(gifUndo + gifRedo),
      "watermarkHistory": try JSONEncoder().encode(history.referencedWatermarkURLs),
      "removalUndoSources": try JSONEncoder().encode(assets.filter { removalUndoSourceIDs.contains($0.id) })]
    let envelope = try encoded.mapValues { try JSONSerialization.jsonObject(with: $0) }
    let retained = try await cleanup.retainedSnapshotNames(projects: folder, reusableConfiguration: JSONSerialization.data(withJSONObject: envelope))
    return try await cleanup.removeUnreferenced(in: directory, retaining: retained)
  }
}

extension Workspace {
  func invalidateCreations(afterRelinking id: UUID) {
    Task { await FilterPreviewService.shared.purge([id]) }
    func flagGIF(_ project: inout GIFProject) {
      let frames = project.frames.filter { $0.sourceID == id }
      guard !frames.isEmpty else { return }
      project.reviewFrameIDs = (project.reviewFrameIDs ?? []).union(frames.map(\.id))
      project.privacyReviewFrameIDs = (project.privacyReviewFrameIDs ?? []).union(frames.filter { !$0.configuration.masks.isEmpty }.map(\.id))
    }
    func flagCollage(_ project: inout CollageProject) {
      guard project.cells.contains(where: { $0.sourceID == id }) || project.mosaicReferenceID == id else { return }
      project.requiresFramingReview = true
      if !configuration(forID: id).masks.isEmpty { project.requiresPrivacyReview = true }
    }
    if var project = gifProject { flagGIF(&project); gifProject = project }
    for i in archivedGIFs.indices { flagGIF(&archivedGIFs[i]) }
    for i in gifUndo.indices { flagGIF(&gifUndo[i]) }; for i in gifRedo.indices { flagGIF(&gifRedo[i]) }
    flagCollage(&collage)
    for i in collageDocuments.indices { flagCollage(&collageDocuments[i].project) }
    for i in collageUndo.indices { flagCollage(&collageUndo[i]) }; for i in collageRedo.indices { flagCollage(&collageRedo[i]) }
    for key in Array(collageHistories.keys) {
      guard var histories = collageHistories[key] else { continue }
      for i in histories.0.indices { flagCollage(&histories.0[i]) }; for i in histories.1.indices { flagCollage(&histories.1[i]) }
      collageHistories[key] = histories
    }
    gifExportURL = nil
    status = "Source replaced. Review photo framing and every affected GIF/collage, including captured mask coverage. Previously exported files are unchanged."
  }
}

enum WorkingCopyCleanupError: LocalizedError {
  case busy
  var errorDescription: String? { "Finish or cancel importing and processing before freeing working copies." }
}
