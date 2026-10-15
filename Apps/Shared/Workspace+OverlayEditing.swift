import Foundation
import FramepebbleCore

extension Workspace {
  func showHideSomething() {
    showLibrary(.privacyReview, clearSearch: true)
    scope = .results
    selecting = false
    thumbnailEditing = false
    if let first = filtered.first { selected = first.id }
    status =
      "Flagged photos. Right-click or long-press a photo and choose Edit with Privacy Tool. You can also flag photos from All Images."
  }
  func openOverlayEditor(for asset: SourceAsset, masking: Bool = true) {
    analysisTask?.cancel()
    overlayStartsWithMasks = masking
    openPhoto(asset)
    // Explicitly opening the editor is a request to view this photo.
    sensitivity.revealed.insert(asset.id)
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
