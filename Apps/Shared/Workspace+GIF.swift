import Foundation
import FramepebbleCore

struct GIFSelectionContext {
  var mode: WorkspaceMode
  var precision: Bool
  var inspector: InspectorTask
  var previousWorkflow: StudioWorkflow
  var wasBrowsing: Bool
  var selection: Set<UUID>
  var order: [UUID]
  var selecting: Bool
  var scope: ApplyScope
  var category: LibraryScope
  var query: String
  var filter: WorkspaceFilter
  var activeID: UUID?
  var adding: Bool
  var replacingFrame: UUID?
}
extension Workspace {
  func archiveCurrentGIF() {
    guard let project = gifProject, !project.frames.isEmpty else { return }
    if let i = archivedGIFs.firstIndex(where: { $0.id == project.id }) { archivedGIFs[i] = project } else { archivedGIFs.append(project) }
  }
  func openGIF(_ project: GIFProject) {
    guard !gifExporting, project.id != gifProject?.id else { return }
    archiveCurrentGIF(); gifProject = project; gifUndo = []; gifRedo = []; switchWorkflow(.gif); persist()
  }
  func gifInteraction(_ active: Bool) {
    if active { if gifInteractionStart == nil { gifInteractionStart = gifProject } }
    else if let start = gifInteractionStart {
      gifInteractionStart = nil
      if start != gifProject { gifUndo.append(start); if gifUndo.count > 80 { gifUndo.removeFirst() }; gifRedo = []; persist() }
    }
  }
  func updateGIF(_ project: GIFProject) {
    guard !gifExporting, project != gifProject else { return }
    if gifInteractionStart == nil, let previous = gifProject { gifUndo.append(previous); if gifUndo.count > 80 { gifUndo.removeFirst() } }
    gifRedo = []; gifProject = project; gifExportURL = nil; persist()
  }
  func restoreGIF(_ doc: ProjectDocument) {
    gifUndo = []; gifRedo = []; gifInteractionStart = nil
    archivedGIFs = doc.savedGIFs
    gifProject = doc.gifProject; gifSelectionContext = nil
    selection = Set(doc.workspaceSelection).intersection(Set(assets.map(\.id)))
    var seen: Set<UUID> = []
    selectionOrder = doc.workspaceSelection.filter { selection.contains($0) && seen.insert($0).inserted }
  }
  func gifConfiguration(for id: UUID) -> ProcessingConfiguration {
    var value = configuration(forID: id)
    if !isEdited(id) { value.crop.mode = .preserveAspectRatio; value.resizeBasis = .longestEdge }
    return value
  }
  func startGIF(ids: [UUID]) {
    guard !overlayEditor, !gifExporting else { return }
    guard ids.count <= 1000 else { issues.append("Choose at most 1,000 photos for a GIF."); return }
    archiveCurrentGIF()
    var project = GIFProject()
    project.frames = ids.compactMap { id in
      guard assets.contains(where: { $0.id == id }) else { return nil }
      return GIFFrame(sourceID: id, configuration: gifConfiguration(for: id))
    }
    gifUndo = []; gifRedo = []
    gifProject = project; gifExportURL = nil; switchWorkflow(.gif); persist()
  }
  func selectGIFPhotos(adding: Bool = false, replacing: UUID? = nil) {
    guard !overlayEditor, gifSelectionContext == nil, !gifExporting else { return }
    gifSelectionContext = GIFSelectionContext(mode: mode, precision: precision, inspector: inspectorTask, previousWorkflow: workflow, wasBrowsing: browsingLibrary,
      selection: selection, order: selectionOrder, selecting: selecting, scope: scope,
      category: library, query: query, filter: workspaceFilter, activeID: activePhotoID,
      adding: adding, replacingFrame: replacing)
    showLibrary(.all, clearSearch: true); workspaceFilter = WorkspaceFilter()
    selection = []; selecting = true
  }
  func finishGIFSelection(cancel: Bool) {
    guard let context = gifSelectionContext else { return }
    let ids = orderedSelection
    if !cancel && (ids.isEmpty || (context.replacingFrame != nil && ids.count != 1) || ids.count + (context.adding ? (gifProject?.frames.count ?? 0) : 0) > 1000) { return }
    gifSelectionContext = nil
    selection = context.selection.intersection(Set(assets.map(\.id))); selectionOrder = context.order.filter { selection.contains($0) }
    selecting = context.selecting; scope = context.scope; library = context.category
    query = context.query; workspaceFilter = context.filter; activePhotoID = context.activeID
    workflow = context.previousWorkflow; browsingLibrary = context.wasBrowsing
    mode = context.mode; precision = context.precision; inspectorTask = context.inspector
    if !cancel, !ids.isEmpty {
      if let frame = context.replacingFrame, let id = ids.first,
        let index = gifProject?.frames.firstIndex(where: { $0.id == frame }) {
        if var project = gifProject { project.frames[index].sourceID = id; project.frames[index].configuration = gifConfiguration(for: id); updateGIF(project) }
        switchWorkflow(.gif)
      } else if context.adding, var project = gifProject {
        let newFrames = ids.map { GIFFrame(sourceID: $0, configuration: gifConfiguration(for: $0)) }
        for i in project.annotations.indices where project.annotations[i].extendsToNewFrames { project.annotations[i].frameIDs?.formUnion(newFrames.map(\.id)) }
        project.frames += newFrames
        updateGIF(project); switchWorkflow(.gif)
      } else { startGIF(ids: ids) }
    }
    persist()
  }
  func exportGIF(to directory: URL) {
    guard let project = gifProject, !gifExporting else { return }
    let sources = assets
    gifExportURL = nil; gifExporting = true; gifExportCompleted = 0; gifExportTotal = project.frames.count
    gifExportTask = Task {
      defer { gifExporting = false; gifExportTask = nil }
      do {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await gifRenderer.setPrivateMode(privateEditing)
        let url = try await gifRenderer.export(project, sources: sources, directory: directory) { done, total in
          await MainActor.run { self.gifExportCompleted = done; self.gifExportTotal = total }
        }
        gifExportURL = url
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        status = "GIF exported · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        // Only this operation's output enters native sharing.
        beginSharing([url])
      } catch is CancellationError { status = "GIF export cancelled. Your animation is saved." }
      catch { issues.append("GIF export failed: " + error.localizedDescription) }
    }
  }
}
