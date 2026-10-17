import Foundation
import FramepebbleCore

enum WorkspaceTask: String { case gif = "Create GIF", collage = "Create Collage", collageAdd = "Add Photos", edit = "Edit Photo", retouch = "Retouch Photo", batch = "Batch Edit", convert = "Convert", resize = "Resize Photos", censor = "Censor" }
struct GIFSelectionContext {
  var task: WorkspaceTask = .gif
  var collageID: UUID?

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
    guard !gifExporting, project.id != gifProject?.id || gifProject?.frames.isEmpty == true else { return }
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
    selection = Set(doc.workspaceSelection).intersection(Set(workspaceAssets.map(\.id)))
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
  func selectPhotos(for task: WorkspaceTask) {
    guard gifSelectionContext == nil, !overlayEditor else { return }
    selectGIFPhotos()
    gifSelectionContext?.task = task
    gifSelectionContext?.collageID = activeCollageID
  }
  func performTask(_ task: WorkspaceTask, ids: [UUID], collageID: UUID? = nil) {
    switch task {
    case .gif: startGIF(ids: ids)
    case .convert: beginConversion(ids: ids)
    case .batch, .resize: beginBatch(ids: ids)
    case .edit: for id in ids { if let source = workspaceAssets.first(where: { $0.id == id }) { openPhoto(source) } }
    case .retouch: if ids.count == 1, let source = workspaceAssets.first(where: { $0.id == ids[0] }) { openPhoto(source); activatePhotoTool(.retouch) }
    case .censor: if ids.count == 1, let source = workspaceAssets.first(where: { $0.id == ids[0] }) { openOverlayEditor(for: source) }
    case .collage: switchWorkflow(.collages); newCollage(sourceIDs: ids)
    case .collageAdd:
      guard activeCollageID == collageID else { issues.append("The active collage changed. Select photos again."); return }
      var value = collage
      if value.cells.isEmpty { value.arrange(ids, layout: value.layout) }
      else { value.cells += ids.map { CollageCell(sourceID: $0, x: 0.25, y: 0.25, width: 0.5, height: 0.5) } }
      changeCollage(value); switchWorkflow(.collages)
    }
  }
  var selectionContextValid: Bool {
    guard let context = gifSelectionContext else { return false }
    let count = selection.count
    if count == 0 { return false }
    if context.task == .censor || context.task == .retouch || context.task == .edit || context.replacingFrame != nil { return count == 1 }
    if context.task == .gif { return count + (context.adding ? (gifProject?.frames.count ?? 0) : 0) <= 1000 }
    if context.task == .collageAdd { return count + collage.cells.count <= CollageProject.maximumCells }
    if context.task == .collage { return count <= CollageProject.maximumCells }
    return true
  }
  func finishGIFSelection(cancel: Bool) {
    guard let context = gifSelectionContext else { return }
    let ids = orderedSelection
    if !cancel && !selectionContextValid { return }
    gifSelectionContext = nil
    selection = context.selection.intersection(Set(assets.map(\.id))); selectionOrder = context.order.filter { selection.contains($0) }
    selecting = context.selecting; scope = context.scope; library = context.category
    query = context.query; workspaceFilter = context.filter; activePhotoID = context.activeID
    workflow = context.previousWorkflow; browsingLibrary = context.wasBrowsing
    mode = context.mode; precision = context.precision; inspectorTask = context.inspector
    if !cancel, !ids.isEmpty {
      if context.task != .gif { performTask(context.task, ids: ids, collageID: context.collageID) }
      else if let frame = context.replacingFrame, let id = ids.first,
        let index = gifProject?.frames.firstIndex(where: { $0.id == frame }) {
        if var project = gifProject {
          let masked = !project.frames[index].configuration.masks.isEmpty
          project.frames[index].sourceID = id; project.frames[index].configuration = gifConfiguration(for: id)
          project.reviewFrameIDs = (project.reviewFrameIDs ?? []).union([frame])
          if masked || !project.frames[index].configuration.masks.isEmpty { project.privacyReviewFrameIDs = (project.privacyReviewFrameIDs ?? []).union([frame]) }
          updateGIF(project)
        }
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
