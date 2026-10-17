import SwiftUI
import FramepebbleCore

extension Workspace {
  /// Each independently removable visibility constraint counts once; sort never hides photos.
  var activeWorkspaceFilterCount: Int {
    [library != .all, !query.isEmpty, workspaceFilter.period != .any,
     workspaceFilter.orientation != .any, !workspaceFilter.format.isEmpty].filter { $0 }.count
  }
  var hasHiddenWorkspaceFilters: Bool { activeWorkspaceFilterCount > 0 }
  var batchSelectionNeedsExplanation: Bool {
    selection != Set(targets.map(\.id)) || !selection.isSubset(of: Set(filtered.map(\.id)))
  }
  var batchSelectionExplanation: String {
    let hidden = selection.subtracting(Set(filtered.map(\.id))).count
    return "\(selection.count) selected separately" + (hidden > 0 ? " · \(hidden) hidden by filters" : "")
  }
  /// Status is legacy plain text. Only established routine completions opt into
  /// dismissal; unknown messages, errors and recoverable work stay persistent.
  var canDismissRoutineWorkspaceStatus: Bool {
    guard !running, !isImporting, !analysing, !gifExporting, !collageGenerating,
          !clearingWorkspace, issues.isEmpty, pendingExports.isEmpty,
          results.allSatisfy({ $0.error == nil }) else { return false }
    return status.hasPrefix("Restored ")
      || (status.hasPrefix("Imported ") && importFailed == 0)
      || status == "Identical photo is available in the workspace."
      || status == "\(workspaceAssets.count) photos in your workspace."
  }
  /// Clear visibility constraints without changing selection, captured inputs or sort order.
  func showAllWorkspacePhotos() {
    let sort = workspaceFilter.sort
    workspaceFilter = WorkspaceFilter()
    workspaceFilter.sort = sort
    library = .all
    query = ""
  }
  func resetWorkspaceManualFraming() {
    let ids = Set(workspaceAssets.filter { configuration(for: $0).crop.framing == .manual }.map(\.id))
    reset(ids)
  }
  var orderedSelection: [UUID] { selectionOrder.filter { selection.contains($0) } }
  func contextIDs(for id: UUID) -> [UUID] { selection.contains(id) ? orderedSelection : [id] }
  /// Capture only visible project members, once and in caller order. Filters do not alter membership.
  func workspaceActionIDs(_ ids: [UUID]) -> [UUID] {
    let available = Set(workspaceAssets.map(\.id))
    var seen = Set<UUID>()
    return ids.filter { available.contains($0) && seen.insert($0).inserted }
  }
  func beginBatch(ids: [UUID], tool: InspectorTask = .resize) {
    let ids = workspaceActionIDs(ids)
    guard !overlayEditor, !running, !ids.isEmpty else { return }
    removalUndo?.restoreBatchMembership = false
    conversionInputIDs = nil; conversionResizingEnabled = false
    switchWorkflow(.batch); scope = .selected; batchInputIDs = Set(ids); inspectorTask = tool; persist()
  }
  func beginConversion(ids: [UUID]) {
    let ids = workspaceActionIDs(ids)
    guard !overlayEditor, !running, !ids.isEmpty else { return }
    beginBatch(ids: ids, tool: .output)
    conversionInputIDs = batchInputIDs; conversionResizingEnabled = false; exportProfiles = []; persist()
  }
  func removeFromWorkspace(_ ids: [UUID]) {
    guard !running, !overlayEditor, !isImporting, !clearingWorkspace, gifSelectionContext == nil else { return }
    let removing = Set(ids).intersection(Set(workspaceAssets.map(\.id)))
    guard !removing.isEmpty else { return }
    let remainingTabs = editorTabs.filter { !removing.contains($0) }
    let nextEditor = editorPhotoID.map { removing.contains($0) } == true ? remainingTabs.first : editorPhotoID
    let nextInputs = batchInputIDs.map { $0.subtracting(removing) }
    removalUndo = WorkspaceRemovalUndo(sessionID: sourceSessionID, ids: removing,
      favourites: favourites.intersection(removing), selection: selection.intersection(removing),
      selectionOrder: selectionOrder,
      tabs: editorTabs.enumerated().compactMap { removing.contains($0.element) ? (id: $0.element, position: $0.offset) : nil },
      editorPhotoID: editorPhotoID, editorPhotoAfterRemoval: nextEditor,
      batchInputs: batchInputIDs, batchInputsAfterRemoval: nextInputs)
    Task { await FilterPreviewService.shared.purge(removing) }
    // Keep hidden sources in the one registry while session Undo or creations own them.
    hiddenSourceIDs.formUnion(removing)
    editorTabs = remainingTabs
    editorPhotoID = nextEditor
    selection.subtract(removing); favourites.subtract(removing)
    batchInputIDs = nextInputs
    duplicatesNeedRebuild = true
    reconcileVisibleSelection(); persist()
    status = "Removed \(removing.count) photos from the workspace. Original files are unchanged."
  }
}
struct WorkspaceActions: View {
  @Bindable var model: Workspace
  let ids: [UUID]
  var filterActionTitle: String { ids.count == 1 ? "Apply Filter to This Photo…" : "Apply Filter to \(ids.count) Photos…" }
  var photoCount: String { "\(ids.count) \(ids.count == 1 ? "Photo" : "Photos")" }
  var body: some View {
    Group {
      if ids.count == 1, let id = ids.first, let asset = model.assets.first(where: { $0.id == id }) {
        Button("Edit Photo") { model.openPhoto(asset) }
        Button("Annotate Photo") { model.openOverlayEditor(for: asset, masking: false) }
        Button("Retouch Photo") { model.performTask(.retouch, ids: [id]) }
        Button("Censor Photo") { model.openOverlayEditor(for: asset) }
      }
      Button("Apply Recipe to \(photoCount)…") { model.presentRecipes(ids: ids) }
      Button(filterActionTitle) { model.presentFilterBatch(ids) }
      Button("Auto Enhance \(photoCount)") { model.setAutoEnhance(true, targetIDs: Set(ids)) }
      Button("Batch Edit \(photoCount)") { model.beginBatch(ids: ids) }
      Button("Resize \(photoCount)") { model.beginBatch(ids: ids, tool: .resize) }
      Button("Convert \(photoCount)") { model.beginConversion(ids: ids) }
      #if os(macOS)
      Button("Open \(photoCount) as Layers") { Task { await model.openPhotosAsDocument(ids) } }
      #endif
      Button("Create GIF from \(photoCount)") { model.startGIF(ids: ids) }
      Button("Create Collage from \(photoCount)") {
        model.switchWorkflow(.collages); model.newCollage(sourceIDs: ids)
      }
      Button("Export & Share \(photoCount)") {
        let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Exports")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          model.export(to: folder, targetIDs: Set(ids)) { model.beginSharing($0) }
        } catch { model.issues.append(error.localizedDescription) }
      }
      Divider()
      Button("Remove \(photoCount) from Workspace", role: .destructive) { model.removeFromWorkspace(ids) }
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
        Text(selectionTitle(context)).font(.headline).fixedSize(horizontal: false, vertical: true)
        if let guidance = selectionGuidance(context) { Text(guidance).font(.caption).fixedSize(horizontal: false, vertical: true) }
        Text(selectionSummary).font(.caption).fixedSize(horizontal: false, vertical: true)
        if typeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 8) { contextButtons(context) }
        } else { HStack { Spacer(); contextButtons(context) } }

      }
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          HStack { filterMenu; clearFilterButton }
          searchField
        }
      } else { HStack { filterMenu; clearFilterButton; searchField } }
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
  func selectionTitle(_ context: GIFSelectionContext) -> String {
    switch context.task {
    case .gif:
      return context.replacingFrame != nil ? "Choose a replacement photo" : context.adding ? "Add photos to your GIF" : "Choose photos for your GIF"
    case .collage: return "Choose photos for your collage"
    case .collageAdd: return "Add photos to your collage"
    case .edit: return "Choose a photo to edit"
    case .retouch: return "Choose a photo to retouch"
    case .censor: return "Choose a photo to censor"
    case .batch: return "Choose photos for batch editing"
    case .convert: return "Choose photos to convert"
    case .resize: return "Choose photos to resize"
    }
  }
  func primaryTitle(_ context: GIFSelectionContext) -> String {
    let count = model.selection.count
    let photos = "\(count) \(count == 1 ? "Photo" : "Photos")"
    switch context.task {
    case .gif:
      return context.replacingFrame != nil ? "Replace Photo" : context.adding ? "Add " + photos : "Create GIF from " + photos
    case .collage: return "Create Collage from " + photos
    case .collageAdd: return "Add " + photos
    case .edit: return "Edit Photo"
    case .retouch: return "Retouch Photo"
    case .censor: return "Censor Photo"
    case .batch: return "Batch Edit " + photos
    case .convert: return "Convert " + photos
    case .resize: return "Resize " + photos
    }
  }
  var selectionSummary: String {
    let hidden = model.selection.subtracting(Set(model.filtered.map(\.id))).count
    return "\(model.selection.count) selected" + (hidden == 0 ? "" : " · \(hidden) hidden by filters")
  }
  func selectionGuidance(_ context: GIFSelectionContext) -> String? {
    let count = model.selection.count
    if context.task == .edit || context.task == .retouch || context.task == .censor || context.replacingFrame != nil {
      return "Choose one photo."
    }
    if context.task == .gif {
      let existing = context.adding ? (model.gifProject?.frames.count ?? 0) : 0
      if count + existing > 1000 {
        let remaining = max(0, 1000 - existing)
        return "GIFs support up to 1,000 frames. Choose no more than \(remaining) \(remaining == 1 ? "photo" : "photos")."
      }
    }
    if context.task == .collage || context.task == .collageAdd {
      let existing = context.task == .collageAdd ? model.collage.cells.count : 0
      if count + existing > CollageProject.maximumCells {
        let remaining = max(0, CollageProject.maximumCells - existing)
        return "Collages support up to \(CollageProject.maximumCells.formatted()) photos. Choose no more than \(remaining.formatted()) \(remaining == 1 ? "photo" : "photos")."
      }
    }
    return nil
  }
  @ViewBuilder func contextButtons(_ context: GIFSelectionContext) -> some View {
    Button("Cancel") { model.finishGIFSelection(cancel: true) }.fixedSize(horizontal: false, vertical: true)
    Button(primaryTitle(context)) { model.finishGIFSelection(cancel: false) }
      .buttonStyle(.borderedProminent).disabled(!model.selectionContextValid).fixedSize(horizontal: false, vertical: true)
  }
  var searchField: some View { TextField("Search photos", text: $model.query).accessibilityHint("Search filenames and locally recognised content").textFieldStyle(.roundedBorder) }
  @ViewBuilder var clearFilterButton: some View {
    if model.hasHiddenWorkspaceFilters {
      Button("Clear", systemImage: "xmark.circle") { model.showAllWorkspacePhotos() }
        .labelStyle(.iconOnly).comfortableHitTarget()
        .accessibilityLabel("Clear search and filters")
        .help("Clear search and filters; keep selection")
    }
  }
  var filterMenu: some View {
    Menu(model.activeWorkspaceFilterCount == 0 ? "Filters" : "Filters (\(model.activeWorkspaceFilterCount))", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Workspace filter", selection: $model.library) { ForEach(LibraryScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Date", selection: $model.workspaceFilter.period) { ForEach(WorkspaceFilter.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Orientation", selection: $model.workspaceFilter.orientation) { ForEach(WorkspaceFilter.Orientation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Format", selection: $model.workspaceFilter.format) {
            Text("Any format").tag("")
            ForEach(Array(Set(model.photoInfo.values.map(\.format))).sorted(), id: \.self) { Text($0.replacingOccurrences(of: "public.", with: "").uppercased()).tag($0) }
          }
          Picker("Sort", selection: $model.workspaceFilter.sort) { ForEach(WorkspaceFilter.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Button("Clear filters") { model.showAllWorkspacePhotos() }
        }
  }

}

struct FilterBatchRequest: Identifiable {
  let id=UUID()
  struct Item { var source: SourceAsset; var configuration: ProcessingConfiguration }
  var items: [Item]
}
struct FilterBatchOutcome {
  var completed=0; var skipped=0; var failed=0; var cancelled=false
  var reasons: [String]=[]
  var retryIDs: Set<UUID>=[]
  var summary: String { "\(completed) completed · \(skipped) skipped · \(failed) failed" + (cancelled ? " · cancelled" : "") }
}
extension Workspace {
  func presentFilterBatch(_ ids: [UUID]) {
    let lookup=Dictionary(uniqueKeysWithValues:workspaceAssets.map {($0.id,$0)})
    var seen=Set<UUID>()
    let items=ids.compactMap { id -> FilterBatchRequest.Item? in
      guard seen.insert(id).inserted,let asset=lookup[id] else { return nil }
      return .init(source:asset,configuration:configuration(for:asset))
    }
    if !items.isEmpty { filterBatchRequest=FilterBatchRequest(items:items) }
  }
  /// Publish successfully validated instructions in one atomic project/history change.
  /// Cancellation keeps completed validations; revisions are rechecked at publication.
  func applyFilterBatch(_ request: FilterBatchRequest, presetID: String?, intensity: Double,
                        progress: (Int) -> Void) async -> FilterBatchOutcome {
    var result=FilterBatchOutcome(), valid:[FilterBatchRequest.Item]=[]
    guard intensity.isFinite, (0...1).contains(intensity), presetID.map({FilterCatalog.preset($0,version:1) != nil}) ?? true else {
      result.failed=request.items.count;result.reasons=["Filter unavailable or invalid intensity."];return result
    }
    for (index,item) in request.items.enumerated() {
      if Task.isCancelled { result.cancelled=true; break }
      do {
        if presetID != nil { try await processor.validateCreativeSource(item.source.url) }
        else { _ = try await processor.identify(item.source.url) }
        try Task.checkCancellation()
        valid.append(item)
      } catch is CancellationError { result.cancelled=true; break }
      catch { result.failed+=1; result.retryIDs.insert(item.source.id); result.reasons.append(item.source.name + ": " + error.localizedDescription) }
      progress(index+1)
      await Task.yield()
    }
    var next=edits
    for item in valid {
      guard assets.contains(where:{$0.id == item.source.id && $0.url == item.source.url}),
            next.configuration(for:item.source.id) == item.configuration else {
        result.skipped+=1; result.retryIDs.insert(item.source.id); result.reasons.append(item.source.name + ": changed after the operation began"); continue
      }
      var c=item.configuration
      var edit=c.filterEdit ?? FilterEdit(grainSeed:Self.filterSeed(item.source.id))
      edit.presetID=presetID;edit.recipeVersion=1;edit.intensity=min(1,max(0,intensity))
      c.filterEdit=edit;c.look=nil
      next.apply(ConfigurationPatch(values:c,fields:[.filterEdit,.look]),to:item.source.id)
      result.completed+=1
    }
    if result.completed > 0 { commit(next,title:"Apply Filter · \(result.completed) photos") }
    status=result.summary
    return result
  }
}
struct FilterBatchSheet: View {
  @Bindable var model: Workspace
  let request: FilterBatchRequest
  @State private var collection: FilterCollection = .essentials
  @State private var presetID: String? = "essentials.clean"
  @State private var intensity=0.7
  @State private var task: Task<Void,Never>?
  @State private var completed=0
  @State private var outcome: FilterBatchOutcome?
  @State private var running=false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Text("Replace the creative filter on \(request.items.count) photos.").font(.headline)
        Text("Crop, corrections, Auto Enhance, annotations and grain seeds are preserved.").font(.caption)
        Picker("Collection",selection:$collection) { ForEach(FilterCollection.allCases,id:\.self){Text($0.rawValue).tag($0)} }
        Picker("Filter",selection:$presetID) {
          Text("Original").tag(String?.none)
          ForEach(FilterCatalog.presets.filter{$0.collection == collection}) { Text($0.name).tag(Optional($0.id)) }
        }.onChange(of:collection) { _,c in presetID=FilterCatalog.presets.first{$0.collection == c}?.id }
        InspectorSlider(title:"Intensity",value:$intensity,range:0...1,percentage:true)
        Text((presetID.flatMap{FilterCatalog.preset($0,version:1)?.name} ?? "Original") + " · \(Int((intensity*100).rounded()))%")
        if running {
          ProgressView(value:Double(completed),total:Double(request.items.count))
          Button("Cancel Remaining") { task?.cancel() }
        } else if let outcome {
          Text(outcome.summary).accessibilityAddTraits(.updatesFrequently)
          ForEach(Array(outcome.reasons.enumerated()),id:\.offset) { Text($0.element).font(.caption) }
          if !outcome.retryIDs.isEmpty {
            Button("Retry Failed or Skipped…") {
              // Explicit retry captures fresh revisions only for the affected items.
              model.presentFilterBatch(request.items.filter { outcome.retryIDs.contains($0.source.id) }.map { $0.source.id })
            }
          }
        } else {
          Button("Apply Filter") {
            running=true
            task=Task {
              outcome=await model.applyFilterBatch(request,presetID:presetID,intensity:intensity) { completed=$0 }
              running=false
              if let outcome { AccessibilityNotification.Announcement(outcome.summary).post() }
            }
          }
        }
      }.disabled(model.running)
      .navigationTitle("Apply Filter to Selected").compactNavigationTitle()
      .toolbar { Button(running ? "Cancel" : "Done") { if running { task?.cancel() } else { dismiss() } } }
    }.frame(idealWidth:420,idealHeight:460)
      .interactiveDismissDisabled(running)
      .onDisappear { task?.cancel() }
  }
}
