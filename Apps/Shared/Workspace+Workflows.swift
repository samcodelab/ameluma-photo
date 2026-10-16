import Foundation
import FramepebbleCore

enum StudioWorkflow: String, CaseIterable {
  case batch = "Batch Edit"
  case photo = "Editor"
  case gif = "Create GIF"
  case collages = "Collages"
  case automations = "Automations"
  var symbol: String {
    switch self {
    case .batch: "square.stack.3d.up"
    case .photo: "photo"
    case .gif: "photo.stack"
    case .collages: "rectangle.split.2x2"
    case .automations: "folder.badge.gearshape"
    }
  }
}
extension Workspace {
  func switchWorkflow(_ workflow: StudioWorkflow) {
    guard !overlayEditor, gifSelectionContext == nil else { return }
    rememberEditorTool()
    let wasBrowsing = browsingLibrary
    if !wasBrowsing && self.workflow == .batch { batchGalleryMode = mode }
    self.workflow = workflow
    browsingLibrary = false
    if workflow == .batch { mode = batchGalleryMode }
    precision = false
    reconcileVisibleSelection()
    if workflow == .photo {
      if let id = editorPhotoID, editorTabs.contains(id) {
        precision = editorTools[id]?.precision ?? false
        inspectorTask = editorTools[id]?.inspector ?? .adjust
      }
      else if let asset = filtered.first(where: { $0.id == activePhotoID }) { openPhoto(asset) }
    }
  }
  /// Library navigation changes presentation only, never processing settings or batch inputs.
  func showLibrary(_ category: LibraryScope? = nil, clearSearch: Bool = false) {
    guard !overlayEditor else { return }
    rememberEditorTool()
    if !browsingLibrary && workflow == .batch { batchGalleryMode = mode }
    browsingLibrary = true
    precision = false
    thumbnailEditing = false
    mode = .browse
    if clearSearch { query = "" }
    if let category { library = category }
    reconcileVisibleSelection()
  }
  var openEditorPhotos: [SourceAsset] {
    let ids = Set(editorTabs)
    let lookup = Dictionary(uniqueKeysWithValues: assets.lazy.filter { ids.contains($0.id) }.map { ($0.id, $0) })
    return editorTabs.compactMap { lookup[$0] }
  }
  func rememberEditorTool() {
    if workflow == .photo && !browsingLibrary, let id = editorPhotoID {
      editorTools[id] = (precision, inspectorTask)
    }
  }
  func activateEditorTab(_ id: UUID) {
    guard editorTabs.contains(id), assets.contains(where: { $0.id == id }), !overlayEditor else { return }
    rememberEditorTool()
    editorPhotoID = id
    let tool = editorTools[id]
    precision = tool?.precision ?? false
    inspectorTask = tool?.inspector ?? .adjust
    persist()
  }
  /// Tabs own presentation only; the project retains every committed edit after closing.
  func closeEditorTab(_ id: UUID) {
    guard !overlayEditor, let index = editorTabs.firstIndex(of: id) else { return }
    rememberEditorTool()
    editorTabs.remove(at: index)
    if editorPhotoID == id {
      editorPhotoID = nil
      if !editorTabs.isEmpty { activateEditorTab(editorTabs[min(index, editorTabs.count - 1)]) }
      else { showLibrary() }
    }
    persist()
  }
  func restoreEditorTabs(_ document: ProjectDocument) {
    let valid = Set(workspaceAssets.map(\.id))
    var seen: Set<UUID> = []
    editorTabs = document.editorTabIDs.filter { valid.contains($0) && seen.insert($0).inserted }
    editorPhotoID = document.activeEditorPhotoID.flatMap { editorTabs.contains($0) ? $0 : nil } ?? editorTabs.first
    editorTools = [:]
    if !assets.contains(where: { $0.id == activePhotoID }) { activePhotoID = assets.first?.id }
    precision = false
    inspectorTask = .adjust
  }
  func resetEditorTabs() { editorTabs = []; editorPhotoID = nil; editorTools = [:]; activePhotoID = nil }
  func openPhoto(_ asset: SourceAsset, refine: Bool = false) {
    guard assets.contains(where: { $0.id == asset.id }), !overlayEditor, gifSelectionContext == nil else { return }
    // Precision editing a batch exception does not change the surrounding batch scope.
    if refine && !browsingLibrary && workflow == .batch {
      selected = asset.id; precision = true; return
    }
    rememberEditorTool()
    if !browsingLibrary && workflow == .batch { batchGalleryMode = mode }
    editorPhotoID = nil
    workflow = .photo
    browsingLibrary = false
    if !editorTabs.contains(asset.id) { editorTabs.append(asset.id) }
    activateEditorTab(asset.id)
    if refine { precision = true }
  }
  func editSelectedBatch() {
    guard !selection.isEmpty else { return }
    beginBatch(ids: orderedSelection)
    selecting = true
  }
  /// Choosing an inspector changes only the visible tool, never the current photo's edits.
  func choosePhotoInspector(_ task: InspectorTask) {
    precision = false
    inspectorTask = task
  }
  var photoCanvasAllowsFraming: Bool { workflow == .photo && !browsingLibrary && precision && !overlayEditor }
  var workspaceTitle: String { browsingLibrary ? library.rawValue : workflow.rawValue }
  func reconcileVisibleSelection() {
    let visible = filtered
    let ids = Set(visible.map(\.id))
    selection.formIntersection(Set(workspaceAssets.map(\.id)))
    if !(activePhotoID.map { ids.contains($0) } ?? false) { activePhotoID = visible.first?.id }
    if let anchor = selectionAnchor, !ids.contains(anchor) { selectionAnchor = nil }
  }
  func select(_ asset: SourceAsset, extending: Bool, range: Bool) {
    guard filtered.contains(where: { $0.id == asset.id }) else { return }
    galleryFocusToken += 1
    if range, let anchor = selectionAnchor,
      let from = filtered.firstIndex(where: { $0.id == anchor }),
      let to = filtered.firstIndex(where: { $0.id == asset.id })
    {
      let ids = Set(filtered[min(from, to)...max(from, to)].map(\.id))
      if extending { selection.formUnion(ids) } else { selection = ids }
      selecting = true
      scope = .selected
    } else if extending {
      if !selection.insert(asset.id).inserted { selection.remove(asset.id) }
      selecting = true
      scope = .selected
      selectionAnchor = asset.id
    } else {
      // Activate a member without silently shrinking an explicit batch.
      if !selecting || !selection.contains(asset.id) { selection = [asset.id] }
      selectionAnchor = asset.id
    }
    selected = asset.id
  }
  func rotateTargets() {
    if workflow == .batch && scope == .all {
      updateField(\.quarterTurns, value: settings.quarterTurns + 1, fields: [.quarterTurns])
    } else {
      var next = edits
      for asset in targets {
        var config = configuration(for: asset)
        config.quarterTurns += 1
        next.apply(ConfigurationPatch(values: config, fields: [.quarterTurns]), to: asset.id)
      }
      commit(next)
    }
  }
  /// Reset processing settings for the whole shared photo library, not only
  /// visible results. Photos, compositions, recipes and saved profiles survive.
  func resetAllProcessingChanges() {
    guard !running, !analysing, !overlayEditor else { return }
    endInteraction()
    var next = EditingSnapshot()
    for id in hiddenSourceIDs { next.apply(ConfigurationPatch(values: configuration(forID: id), fields: Set(ConfigurationField.allCases)), to: id) }
    commit(next, title: "Reset All Changes · \(assets.count) photos")
    proposals.removeAll()
    precision = false
    status = "Batch defaults and all individual photo edits reset. Undo restores them. Photos and originals remain untouched."
  }
  var editScopeHeading: String {
    if workflow == .photo { return "Editing this photo" }
    if batchInputIDs != nil { return "Editing \(targets.count) saved batch inputs" }
    switch scope {
    case .all: return "Editing all \(workspaceAssets.count) workspace photos"
    case .selected: return "Editing \(targets.count) selected \(targets.count == 1 ? "photo" : "photos")"
    case .results: return "Editing \(targets.count) matching \(targets.count == 1 ? "photo" : "photos")"
    case .individual: return "Editing this photo"
    }
  }
  func resetBatchSettingsOnly() {
    guard !running, !analysing, !overlayEditor else { return }
    var next = edits; next.settings = ProcessingConfiguration()
    commit(next, title: "Reset Batch Settings · individual overrides retained")
  }
  func restoreLibraryOriginalAppearance() {
    guard !running, !analysing, !overlayEditor else { return }
    var next = edits
    for asset in workspaceAssets { next.restoreOriginalAppearance(for: asset.id) }
    commit(next, title: "Restore Original Appearance · \(assets.count) photos")
    proposals.removeAll()
  }
  func removeAllIndividualOverrides() {
    guard !running, !analysing, !overlayEditor else { return }
    var next = edits; next.overrides = next.overrides.filter { hiddenSourceIDs.contains($0.key) }
    commit(next, title: "Remove All Individual Overrides")
    proposals.removeAll()
  }
  func moveEditingHistory(to id: UUID) {
    guard !running, !analysing, !overlayEditor else { return }
    endInteraction()
    let before = edits
    history.move(to: id)
    edits = history.current
    flagChangedFraming(before)
    persist()
  }
  func restoreFullImageCrop(_ id: UUID) async {
    guard !browsingLibrary, !overlayEditor, !running, current?.id == id,
      let asset = assets.first(where: { $0.id == id }) else { return }
    let before = configuration(for: asset)
    do {
      let size = try await processor.identify(asset.url)
      guard !browsingLibrary, !overlayEditor, !running, current?.id == id,
        configuration(for: asset) == before,
        assets.contains(where: { $0.id == id && $0.url == asset.url }) else { return }
      var next = edits
      next.restoreFullImageCrop(for: id, sourceSize: size)
      commit(next)
      proposals.removeValue(forKey: id)
      status = "Full image restored at original size. Other edits are retained. Undo is available."
    } catch { issues.append("Could not reset this crop: " + error.localizedDescription) }
  }
  func applyPhotoCrop(_ rectangle: CGRect, sourceSize: CGSize, id: UUID, keepOutputSize: Bool = false) {
    guard workflow == .photo, !browsingLibrary, !overlayEditor, !running,
      current?.id == id, assets.contains(where: { $0.id == id }),
      rectangle.width > 0, rectangle.height > 0 else { return }
    var value = configuration(forID: id)
    value.crop = CropGeometry.crop(selecting: rectangle, source: sourceSize, existing: value.crop)
    let height = Double(value.width) / (value.crop.aspectRatio ?? 1)
    guard height.isFinite else { return }
    if !keepOutputSize { value.height = max(1, min(20000, Int(min(20000, max(1, height.rounded()))))) }
    applyChange(ConfigurationPatch(values: value, fields: [
      .crop_mode, .crop_framing, .crop_centerX, .crop_centerY, .crop_zoom, .crop_aspectRatio, .height
    ]), ids: [id])
  }
  func restoreOriginalPhoto(_ id: UUID) {
    guard workflow == .photo, !browsingLibrary, !overlayEditor, !running,
      current?.id == id, assets.contains(where: { $0.id == id }) else { return }
    var next = edits
    next.restoreOriginalAppearance(for: id)
    commit(next)
    proposals.removeValue(forKey: id)
    precision = false
    inspectorTask = .adjust
    status = "Original appearance and dimensions restored for this photo. Undo is available; export options are unchanged."
  }
  func rotatePhoto(_ id: UUID) {
    guard assets.contains(where: { $0.id == id }) else { return }
    var config = configuration(forID: id)
    config.quarterTurns += 1
    applyChange(ConfigurationPatch(values: config, fields: [.quarterTurns]), ids: [id])
  }
  func copyEdits(from id: UUID, categories: Set<EditCategory>) {
    copiedEdits = ConfigurationPatch(
      values: configuration(forID: id), fields: Set(ConfigurationField.allCases)
    ).choosing(categories)
    status = "Copied \(categories.count) edit categories from the clicked photo."
  }
  func pasteEdits(to ids: Set<UUID>) {
    guard let copiedEdits else { return }
    applyChange(copiedEdits, ids: ids.intersection(Set(workspaceAssets.map(\.id))))
  }
  var activeProfiles: [ExportProfile] {
    let selected = workflow == .photo ? [] : profiles.filter { exportProfiles.contains($0.id) }
    if !selected.isEmpty { return selected }
    return [currentEditsProfile]
  }
  var exportDisplayProfiles: [ExportProfile] {
    guard running, !exportingRequests.isEmpty else { return activeProfiles }
    var seen: Set<UUID> = []
    return exportingRequests.compactMap { seen.insert($0.profile.id).inserted ? $0.profile : nil }
  }
  var currentEditsProfile: ExportProfile {
    var profile = ExportProfile()
    profile.id = defaultProfileID
    profile.name = "Current edits"
    profile.namingTemplate = namingTemplate
    return profile
  }
  func exportConfiguration(for asset: SourceAsset, profile: ExportProfile)
    -> ProcessingConfiguration
  {
    let source = configuration(for: asset)
    guard let variant = profile.processing else { return source }
    var config = ConfigurationPatch(from: ProcessingConfiguration(), to: source)
      .choosing([.adjustments, .orientation, .privacy, .annotations]).applying(to: variant)
    config.masks =
      source.masks + variant.masks.filter { mask in !source.masks.contains { $0.id == mask.id } }
    config.annotations =
      source.annotations
      + variant.annotations.filter { item in !source.annotations.contains { $0.id == item.id } }
    config.privacyExport = source.privacyExport || variant.privacyExport
    if let patch = edits.overrides[asset.id]?.patch {
      config = patch.choosing([.adjustments, .orientation, .watermark, .framing]).applying(
        to: config)
    } else if let override = edits.overrides[asset.id] {
      config.crop = override.crop
    }
    return config
  }
  func plannedRequests(targetIDs: Set<UUID>? = nil) -> [ExportRequest] {
    let sources = targetIDs.map { ids in workspaceAssets.filter { ids.contains($0.id) } } ?? targets
    let active = targetIDs == nil ? activeProfiles : [currentEditsProfile]
    return sources.flatMap { asset in
      active.map {
        ExportRequest(
          source: asset, configuration: exportConfiguration(for: asset, profile: $0), profile: $0)
      }
    }
  }
  var exportPreviewAsset: SourceAsset? {
    let inputs = targets
    if let current, inputs.contains(where: { $0.id == current.id }) { return current }
    return inputs.first
  }
  static func planSummary(photos: Int, files: Int, profiles: Int) -> String {
    "\(photos) \(photos == 1 ? "photo" : "photos") → \(files) \(files == 1 ? "file" : "files") · \(profiles) \(profiles == 1 ? "profile" : "profiles")"
  }
  var exportPlanSummary: String {
    if running, let exportingPlanSummary { return exportingPlanSummary }
    return Self.planSummary(photos: targets.count, files: targets.count * activeProfiles.count, profiles: activeProfiles.count)
  }
  var actionLabel: String { workflow == .photo ? "This Photo" : "Batch (\(targets.count) \(targets.count == 1 ? "photo" : "photos"))" }
  func exportThisPhoto(_ id: UUID) {
    let folder = directory.deletingLastPathComponent().appendingPathComponent(
      "Exports", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      export(to: folder, targetIDs: [id]) { self.beginSharing($0) }
    } catch { issues.append(error.localizedDescription) }
  }
}

extension Workspace {
  static let privacyCoverageReason = "Privacy coverage changed; inspect masks in the edited preview."
  func privacyCoverageNeedsReview(_ id: UUID) -> Bool {
    !configuration(forID: id).masks.isEmpty && privacyCoverageReviewIDs.contains(id)
  }
  func markPrivacyCoverageChanges(from previous: EditingSnapshot, to next: EditingSnapshot) {
    let spatial: Set<ConfigurationField> = [.width, .height, .resizeBasis, .percentage, .canvasAlignment, .preventUpscaling, .quarterTurns, .flipHorizontal, .flipVertical, .straighten, .crop_mode, .crop_centerX, .crop_centerY, .crop_zoom, .crop_aspectRatio, .crop_quarterTurns, .crop_flipHorizontal, .crop_flipVertical, .crop_straighten]
    let candidates: Set<UUID>
    if !previous.settings.masks.isEmpty || !next.settings.masks.isEmpty { candidates = Set(assets.map(\.id)) }
    else { candidates = Set(previous.overrides.keys).union(next.overrides.keys).union(privacyCoverageReviewIDs) }
    for id in candidates {
      let before = previous.configuration(for: id), after = next.configuration(for: id)
      if after.masks.isEmpty { privacyCoverageReviewIDs.remove(id); continue }
      guard !before.masks.isEmpty,
        !ConfigurationPatch(from: before, to: after).fields.isDisjoint(with: spatial) else { continue }
      privacyCoverageReviewIDs.insert(id)
    }
  }
  func confirmPrivacyCoverage(_ id: UUID) {
    privacyCoverageReviewIDs.remove(id)
    persist()
  }
  var undoActionTitle: String {
    if overlayEditor { return "Undo Area Edit" }
    if workflow == .gif && !browsingLibrary { return "Undo GIF Change" }
    if collageHasFocus { return "Undo · " + activeCollageName }
    return "Undo " + (history.steps.first(where: { $0.isCurrent })?.title ?? "Edit")
  }
  var redoActionTitle: String {
    if overlayEditor { return "Redo Area Edit" }
    if workflow == .gif && !browsingLibrary { return "Redo GIF Change" }
    if collageHasFocus { return "Redo · " + activeCollageName }
    return "Redo " + (history.steps.first(where: { $0.isRedo })?.title ?? "Edit")
  }
}

extension Workspace {
  func moveEditorTab(_ source: UUID, before target: UUID) {
    guard !overlayEditor, source != target, let index = editorTabs.firstIndex(of: source), editorTabs.contains(target) else { return }
    editorTabs.remove(at: index)
    if let destination = editorTabs.firstIndex(of: target) { editorTabs.insert(source, at: destination) }
    persist()
  }
  func closeOtherEditorTabs(keeping id: UUID) {
    guard !overlayEditor, editorTabs.contains(id) else { return }
    editorTabs = [id]; activateEditorTab(id); persist()
  }
}
