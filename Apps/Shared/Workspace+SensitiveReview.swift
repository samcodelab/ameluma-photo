import Foundation
import FramepebbleCore

extension Workspace {
  func scanSensitiveImages(selectedOnly: Bool = false) {
    guard sensitivityTask == nil else { return }
    let jobs = selectedOnly ? assets.filter { selection.contains($0.id) } : assets
    sensitivityCompleted = 0
    sensitivityTotal = jobs.count
    sensitivityTask = Task {
      defer { sensitivityTask = nil }
      sensitivityAvailability = await sensitiveAnalyzer.availability()
      guard sensitivityAvailability.canAnalyze else { return }
      for asset in jobs {
        if Task.isCancelled { break }
        do {
          let before = try SourceFingerprint.read(asset.url)
          let image = try await sensitivityProcessor.analysisThumbnail(
            asset.url, configuration: ProcessingConfiguration(), maximum: 1200)
          let detected = try await sensitiveAnalyzer.analyze(image)
          try Task.checkCancellation()
          guard assets.contains(where: { $0.id == asset.id && $0.url == asset.url }),
            try SourceFingerprint.read(asset.url) == before
          else {
            sensitivity.invalidateFinding(asset.id)
            continue
          }
          sensitivity.record(detected, id: asset.id, fingerprint: before)
        } catch is CancellationError { break } catch {
          sensitivity.findings[asset.id].map { _ in sensitivity.invalidateFinding(asset.id) }
          sensitivityStatus =
            "Some images could not be checked. Review them manually; unflagged images are not guaranteed safe."
        }
        sensitivityCompleted += 1
      }
      if Task.isCancelled {
        sensitivityStatus = "Check cancelled. Completed findings remain for this session."
      } else if sensitivityStatus.isEmpty {
        sensitivityStatus =
          "Check finished. Review proposals; unflagged images are not guaranteed safe."
      }
    }
  }
  func openPrivacyEditor(_ destination: EditorDestination, asset: SourceAsset) {
    selected = asset.id
    sensitivity.revealed.insert(asset.id)
    pendingPrivacyEditor = destination
    sensitiveReviewPresented = false
  }
  func finishPrivacyReviewPresentation() {
    guard let next = pendingPrivacyEditor else { return }
    pendingPrivacyEditor = nil
    switch next {
    case .framing:
      if let asset = current { openPhoto(asset, refine: true) }
    case .overlays:
      if let asset = current { openOverlayEditor(for: asset, masking: true) }
    case .collage: collageEditor = true
    case .projects: projectsView = true
    }
  }
  func clearSensitivityReview() {
    sensitivityTask?.cancel()
    sensitivity = SensitiveReviewState()
    sensitivityStatus = ""
    if library == .privacyReview { library = .all }
  }
}
