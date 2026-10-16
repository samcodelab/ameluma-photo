import SwiftUI
import FramepebbleCore

extension Workspace {
  var orderedSelection: [UUID] { selectionOrder.filter { selection.contains($0) } }
  func contextIDs(for id: UUID) -> [UUID] { selection.contains(id) ? orderedSelection : [id] }
  func beginBatch(ids: [UUID], tool: InspectorTask = .resize) {
    guard !overlayEditor, !ids.isEmpty else { return }
    conversionInputIDs = nil; conversionResizingEnabled = false
    switchWorkflow(.batch); scope = .selected; batchInputIDs = Set(ids); inspectorTask = tool; persist()
  }
  func beginConversion(ids: [UUID]) {
    beginBatch(ids: ids, tool: .output)
    conversionInputIDs = batchInputIDs; conversionResizingEnabled = false; exportProfiles = []; persist()
  }
  func removeFromWorkspace(_ ids: [UUID]) {
    guard !running, !overlayEditor, !isImporting else { return }
    let removing = Set(ids)
    hiddenSourceIDs.formUnion(removing)
    // Only records unused by current creation/history instructions can leave the registry.
    // Disk snapshots are freed separately after scanning saved projects and watermark dependencies.
    let retained = creationSourceIDs
    assets.removeAll { removing.contains($0.id) && !retained.contains($0.id) }
    hiddenSourceIDs.formIntersection(Set(assets.map(\.id)))
    editorTabs.removeAll { removing.contains($0) }
    if editorPhotoID.map({ removing.contains($0) }) == true { editorPhotoID = editorTabs.first }
    selection.subtract(removing); favourites.subtract(removing)
    batchInputIDs?.subtract(removing)
    duplicatesNeedRebuild = true
    reconcileVisibleSelection(); persist()
    status = "Removed \(removing.count) photos from the workspace. Original files are unchanged."
  }
}
struct WorkspaceActions: View {
  @Bindable var model: Workspace
  let ids: [UUID]
  var body: some View {
    Group {
      if ids.count == 1, let id = ids.first, let asset = model.assets.first(where: { $0.id == id }) {
        Button("Edit Photo") { model.openPhoto(asset) }
        Button("Censor Photo") { model.openOverlayEditor(for: asset) }
      }
      Button("Edit \(ids.count) Selected Photos") { model.beginBatch(ids: ids) }
      Button("Convert \(ids.count) Photos") { model.beginConversion(ids: ids) }
      Button("Create GIF from \(ids.count) Photos") { model.startGIF(ids: ids) }
      Button("Create Collage from \(ids.count) Photos") {
        model.switchWorkflow(.collages); model.newCollage(sourceIDs: ids)
      }
      Button("Export & Share \(ids.count) Photos") {
        let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Exports")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          model.export(to: folder, targetIDs: Set(ids)) { model.beginSharing($0) }
        } catch { model.issues.append(error.localizedDescription) }
      }
      Divider()
      Button("Remove \(ids.count) Photos from Workspace", role: .destructive) { model.removeFromWorkspace(ids) }
    }.disabled(ids.isEmpty || model.overlayEditor || model.running)
  }
}
struct WorkspaceFilterControls: View {
  @Bindable var model: Workspace
  let reader = WorkspaceMetadataReader()
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(alignment: .leading) {
      if let context = model.gifSelectionContext {
        Text(context.task != .gif ? "Select photos · " + context.task.rawValue : context.adding ? "Add photos to your GIF" : context.replacingFrame != nil ? "Choose a replacement photo" : "Select photos for your GIF").font(.headline).fixedSize(horizontal: false, vertical: true)
        if context.task == .edit || context.task == .censor { Text("Choose one photo.").font(.caption) }
        Text("\(model.selection.count) selected · \(model.selection.subtracting(Set(model.filtered.map(\.id))).count) hidden by filters").font(.caption)
        if typeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 8) { contextButtons(context) }
        } else { HStack { Spacer(); contextButtons(context) } }

      }
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) { filterMenu; searchField }
      } else { HStack { filterMenu; searchField } }
      if model.workspaceFilter.period == .custom {
        DatePicker("From", selection: $model.workspaceFilter.start, displayedComponents: .date)
        DatePicker("Through", selection: $model.workspaceFilter.end, in: model.workspaceFilter.start..., displayedComponents: .date)
      }
      if model.workspaceFilter.period != .any { Text("Capture date where available; otherwise local file date.").font(.caption).foregroundStyle(.secondary) }
    }.padding(.horizontal).padding(.vertical, 6)
      .onChange(of: model.workspaceFilter.start) { _, date in if model.workspaceFilter.end < date { model.workspaceFilter.end = date } }
      .task(id: model.workspaceAssets.map(\.id)) {
        do { let info = try await reader.read(model.workspaceAssets); try Task.checkCancellation(); model.photoInfo = info }
        catch is CancellationError {} catch { model.issues.append("Could not read photo details: " + error.localizedDescription) }
      }
  }
  @ViewBuilder func contextButtons(_ context: GIFSelectionContext) -> some View {
    Button("Cancel") { model.finishGIFSelection(cancel: true) }.fixedSize(horizontal: false, vertical: true)
    Button(context.task != .gif ? context.task.rawValue : context.adding ? "Add Photos" : context.replacingFrame != nil ? "Replace Photo" : "Create GIF") { model.finishGIFSelection(cancel: false) }
      .buttonStyle(.borderedProminent).disabled(!model.selectionContextValid).fixedSize(horizontal: false, vertical: true)
  }
  var searchField: some View { TextField("Filename or recognised content", text: $model.query).textFieldStyle(.roundedBorder) }
  var filterMenu: some View {
    Menu("Filters", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Workspace filter", selection: $model.library) { ForEach(LibraryScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Date", selection: $model.workspaceFilter.period) { ForEach(WorkspaceFilter.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Orientation", selection: $model.workspaceFilter.orientation) { ForEach(WorkspaceFilter.Orientation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Format", selection: $model.workspaceFilter.format) {
            Text("Any format").tag("")
            ForEach(Array(Set(model.photoInfo.values.map(\.format))).sorted(), id: \.self) { Text($0.replacingOccurrences(of: "public.", with: "").uppercased()).tag($0) }
          }
          Picker("Sort", selection: $model.workspaceFilter.sort) { ForEach(WorkspaceFilter.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Button("Clear filters") { model.workspaceFilter = WorkspaceFilter(); model.library = .all; model.query = "" }
        }
  }

}
