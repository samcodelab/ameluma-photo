import SwiftUI
import FramepebbleCore
import ImageIO

struct GIFPreviewInput: Equatable {
  var project: GIFProject
  var sources: [SourceAsset]
  var allowed: Bool

  init(project: GIFProject, sources: [SourceAsset], allowed: Bool) {
    self.project = project
    let referencedIDs = Set(project.frames.map(\.sourceID))
    self.sources = sources.filter { referencedIDs.contains($0.id) }
    self.allowed = allowed
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    // The export filename has no effect on pixels or playback. Keep all other
    // project fields and referenced source revisions in the freshness identity.
    var left = lhs.project; var right = rhs.project
    left.name = ""; right.name = ""
    return left == right && lhs.sources == rhs.sources && lhs.allowed == rhs.allowed
  }
}

/// Owns only preview resources and freshness. Editing instructions stay in Workspace/Core.
@MainActor @Observable final class GIFPreviewSession {
  private(set) var input: GIFPreviewInput?
  private(set) var displayedFrameID: UUID?
  private(set) var preview: GIFPreview?
  private(set) var image: CGImage?
  private(set) var error: String?
  private(set) var failedFrameID: UUID?
  private(set) var preparing = false
  private var generation = UUID()
  private var displayGeneration = UUID()
  func invalidate() {
    generation = UUID(); displayGeneration = UUID()
    preview?.remove(); preview = nil; input = nil; displayedFrameID = nil; image = nil; error = nil; failedFrameID = nil; preparing = false
  }
  func prepare(project: GIFProject, sources: [SourceAsset] = [], allowed: Bool, build: () async throws -> GIFPreview) async {
    invalidate()
    input = GIFPreviewInput(project: project, sources: sources, allowed: allowed)
    guard allowed, !project.frames.isEmpty else { return }
    let token = generation; preparing = true
    do {
      let result = try await build()
      guard generation == token, !Task.isCancelled else { result.remove(); if generation == token { preparing = false }; return }
      preview = result; preparing = false
    } catch {
      guard generation == token else { return }
      preparing = false
      guard !(error is CancellationError), !Task.isCancelled else { return }
      self.error = error.localizedDescription
      if let failure = error as? GIFPreviewFailure { failedFrameID = failure.frameID }
    }
  }
  func image(for input: GIFPreviewInput, frameID: UUID?) -> CGImage? {
    guard self.input == input, displayedFrameID == frameID else { return nil }
    return image
  }
  func load(index: Int, project: GIFProject) async {
    displayGeneration = UUID(); let display = displayGeneration; let token = generation
    image = nil; displayedFrameID = nil
    guard let preview, preview.frames.indices.contains(index), project.frames.indices.contains(index) else { return }
    let url = preview.frames[index]
    let value = await Task.detached { () -> CGImage? in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }.value
    guard token == generation, display == displayGeneration, !Task.isCancelled else { return }
    image = value; displayedFrameID = project.frames[index].id
    if value == nil { error = "Could not load preview frame \(index + 1)."; failedFrameID = project.frames[index].id }
  }
}
