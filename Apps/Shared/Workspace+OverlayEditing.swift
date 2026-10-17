import Foundation
import FramepebbleCore

extension Workspace {
  enum OverlayDraftResolution { case apply, discard }

  /// One toolbox routes explicit photo targets. Tool changes never change batch membership.
  /// A changed overlay draft requires an explicit resolution before leaving its tools.
  @discardableResult
  func activatePhotoTool(_ tool: PhotoTool, resolvingDraft resolution: OverlayDraftResolution? = nil) -> Bool {
    guard let asset = current else { return false }
    if colourReplacementAsset != nil { return tool == .replaceColour }
    if overlayEditor {
      if tool == .privacy || tool == .annotate || tool == .retouch {
        overlayRetouch = tool == .retouch
        overlayStartsWithMasks = tool == .privacy
        return true
      }
      if let draft = overlaySession, draft.hasChanges {
        guard let resolution else { return false }
        if resolution == .apply && !applyOverlaySession(draft) { return false }
      }
      overlaySession = nil
      pendingOverlayDestination = nil
      overlayEditor = false
    }
    beginEditorFeedback(.toolSwitch,for:asset,configuration:configuration(for:asset),label:tool.rawValue)
    // Crop is a tool, not a sticky mode underneath every subsequent tool.
    if tool != .crop { precision = false }
    switch tool {
    case .adjust: choosePhotoInspector(.adjust)
    case .filters: choosePhotoInspector(.filters)
    case .crop: precision = true
    case .resize: choosePhotoInspector(.resize)
    case .annotate: openOverlayEditor(for: asset, masking: false)
    case .replaceColour: openColourReplacement(asset)
    case .retouch: openOverlayEditor(for: asset, masking: false); overlayRetouch = true
    case .privacy: openOverlayEditor(for: asset)
    case .watermark: choosePhotoInspector(.watermark)
    case .output: choosePhotoInspector(.output)
    }
    return true
  }

  func showHideSomething() {
    showLibrary(.privacyReview, clearSearch: true)
    scope = .results
    selecting = false
    thumbnailEditing = false
    if let first = filtered.first { selected = first.id }
    status =
      "Flagged photos. Right-click or long-press a photo and choose Edit with Privacy Tool. You can also flag photos from Workspace."
  }
  func openOverlayEditor(for asset: SourceAsset, masking: Bool = true) {
    guard gifSelectionContext == nil else { return }
    analysisTask?.cancel()
    overlayRetouch = false
    overlayStartsWithMasks = masking
    openPhoto(asset)
    // Explicitly opening the editor is a request to view this photo.
    sensitivity.revealed.insert(asset.id)
    if overlaySession == nil {
      overlaySession=OverlayEditingSession(sourceID:asset.id,configuration:configuration(for:asset))
    }
    overlayEditor = true
  }
  @discardableResult func applyOverlaySession(_ session: OverlayEditingSession) -> Bool {
    guard let asset = assets.first(where: { $0.id == session.sourceID }) else {
      issues.append("This photo is no longer in the project. Your draft was not applied.")
      return false
    }
    guard configuration(for: asset) == session.original else {
      issues.append(
        "The photo changed while this editor was open. Cancel and reopen it to avoid replacing newer edits."
      )
      return false
    }
    guard session.hasChanges else { return true }
    setImageConfiguration(session.current, for: asset.id)
    return true
  }
  func finishOverlayPresentation() {
    guard let destination = pendingOverlayDestination else { return }
    pendingOverlayDestination = nil
    if destination == .framing {
      if let asset = current { openPhoto(asset, refine: true) }
    }
  }
}

extension Workspace {
  static func filterSeed(_ id: UUID) -> UInt32 {
    // FNV-1a over the persisted UUID, fixed wrapping arithmetic; seed then stored in FilterEdit.
    id.uuidString.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
  }
  func selectCreativeFilter(_ id: String?) {
    var next=edits
    for asset in targets {
      var c=configuration(for:asset)
      var edit=c.filterEdit ?? FilterEdit(grainSeed:Self.filterSeed(asset.id))
      edit.presetID=id; edit.recipeVersion=1
      c.filterEdit=edit; c.look=nil
      next.apply(ConfigurationPatch(values:c,fields:[.filterEdit,.look]),to:asset.id)
    }
    commit(next,title:id == nil ? "Original · remove creative filter" : "Photo Filter")
  }
  func setFilterIntensity(_ value: Double) {
    guard value.isFinite else { return }
    var next=edits
    for asset in targets {
      var c=configuration(for:asset)
      guard var edit=c.filterEdit else { continue }
      edit.intensity=min(1,max(0,value)); c.filterEdit=edit
      next.apply(ConfigurationPatch(values:c,fields:[.filterEdit]),to:asset.id)
    }
    commit(next,title:"Filter Intensity")
  }
  func setAutoEnhance(_ enabled: Bool, recalculate: Bool = false, targetIDs: Set<UUID>? = nil) {
    guard !quickFixRunning, !running, !overlayEditor else { return }
    let jobs=(targetIDs.map { ids in workspaceAssets.filter { ids.contains($0.id) } } ?? targets).map { ($0,configuration(for:$0)) }
    guard !jobs.isEmpty else { return }
    quickFixRunning=true; quickFixCompleted=0; quickFixTotal=jobs.count
    quickFixTask=Task {
      defer { quickFixRunning=false }
      var updates: [QuickFixUpdate]=[]
      do {
        for (asset,before) in jobs {
          try Task.checkCancellation()
          do {
            var c=before
            if enabled && (recalculate || c.autoEnhance == nil) { c.autoEnhance=try await processor.resolveAutoEnhance(asset.url,configuration:c) }
            if var edit=c.autoEnhance { edit.enabled=enabled; c.autoEnhance=edit }
            updates.append(QuickFixUpdate(asset:asset,before:before,after:c))
          } catch is CancellationError { throw CancellationError() }
          catch { issues.append(asset.name + ": " + error.localizedDescription) }
          quickFixCompleted+=1
        }
        try Task.checkCancellation()
        applyQuickFixUpdates(updates,title:recalculate ? "Recalculate Enhance" : "Auto Enhance")
        if enabled && updates.allSatisfy({$0.after.autoEnhance?.resolvedAdjustments.isEmpty == true}) { status="No enhancement needed." }
      } catch is CancellationError { status="Auto Enhance cancelled. No changes applied." }
      catch { issues.append(error.localizedDescription) }
    }
  }
}
