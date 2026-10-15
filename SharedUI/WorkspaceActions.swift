import SwiftUI
import FramepebbleCore

extension Workspace {
  var orderedSelection: [UUID] { selectionOrder.filter { selection.contains($0) } }
  func contextIDs(for id: UUID) -> [UUID] { selection.contains(id) ? orderedSelection : [id] }
  func beginBatch(ids: [UUID], tool: InspectorTask = .resize) {
    guard !overlayEditor, !ids.isEmpty else { return }
    switchWorkflow(.batch); scope = .selected; batchInputIDs = Set(ids); inspectorTask = tool; persist()
  }
  func removeFromWorkspace(_ ids: [UUID]) {
    guard !running, !overlayEditor, !isImporting else { return }
    let removing = Set(ids)
    // Remove references only. Compositions retain missing-source IDs for explicit repair.
    assets.removeAll { removing.contains($0.id) }
    editorTabs.removeAll { removing.contains($0) }
    if editorPhotoID.map({ removing.contains($0) }) == true { editorPhotoID = editorTabs.first }
    selection.subtract(removing); favourites.subtract(removing)
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
      Button("Convert \(ids.count) Photos") { model.beginBatch(ids: ids, tool: .output) }
      Button("Create Collage from \(ids.count) Photos") {
        model.selection = Set(ids); model.switchWorkflow(.collages); model.newCollage()
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
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Menu("Filters", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Date", selection: $model.workspaceFilter.period) { ForEach(WorkspaceFilter.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Orientation", selection: $model.workspaceFilter.orientation) { ForEach(WorkspaceFilter.Orientation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Format", selection: $model.workspaceFilter.format) {
            Text("Any format").tag("")
            ForEach(Array(Set(model.photoInfo.values.map(\.format))).sorted(), id: \.self) { Text($0.replacingOccurrences(of: "public.", with: "").uppercased()).tag($0) }
          }
          Picker("Sort", selection: $model.workspaceFilter.sort) { ForEach(WorkspaceFilter.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Button("Clear filters") { model.workspaceFilter = WorkspaceFilter(); model.library = .all; model.query = "" }
        }
        TextField("Filename or recognised content", text: $model.query).textFieldStyle(.roundedBorder)
      }
      if model.workspaceFilter.period == .custom {
        DatePicker("From", selection: $model.workspaceFilter.start, displayedComponents: .date)
        DatePicker("Through", selection: $model.workspaceFilter.end, in: model.workspaceFilter.start..., displayedComponents: .date)
      }
      if model.workspaceFilter.period != .any { Text("Capture date where available; otherwise local file date.").font(.caption).foregroundStyle(.secondary) }
    }.padding(.horizontal).padding(.vertical, 6)
      .task(id: model.assets.map(\.id)) {
        do { let info = try await reader.read(model.assets); try Task.checkCancellation(); model.photoInfo = info }
        catch is CancellationError {} catch { model.issues.append("Could not read photo details: " + error.localizedDescription) }
      }
  }
}
