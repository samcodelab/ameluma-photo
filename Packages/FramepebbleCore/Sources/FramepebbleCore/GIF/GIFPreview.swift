import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct GIFPreview: Sendable {
  public var directory: URL
  public var frames: [URL]
  public func remove() { try? FileManager.default.removeItem(at: directory) }
}
public actor GIFPreviewBuilder {
  private let renderer = GIFRenderer()
  public init() {}
  /// Disk-backed preview avoids retaining every decoded frame in memory.
  public func prepare(_ project: GIFProject, sources: [SourceAsset], privateMode: Bool = false) async throws -> GIFPreview {
    try project.validate()
    await renderer.setPrivateMode(privateMode)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Ameluma-GIF-Preview-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var complete = false
    defer { if !complete { try? FileManager.default.removeItem(at: folder) } }
    var urls: [URL] = []
    for (index, frame) in project.frames.enumerated() {
      try Task.checkCancellation()
      let image: CGImage
      do { image = try await renderer.renderFrame(frame, project: project, sources: sources, maximum: 480) }
      catch is CancellationError { throw CancellationError() }
      catch { throw GIFPreviewFailure(frameID: frame.id, index: index, reason: error.localizedDescription) }
      let url = folder.appendingPathComponent("\(index).png")
      try autoreleasepool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ProcessingError.encoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ProcessingError.encoding }
      }
      urls.append(url)
    }
    try Task.checkCancellation(); complete = true
    return GIFPreview(directory: folder, frames: urls)
  }
}

public struct GIFPreviewFailure: LocalizedError, Sendable {
  public var frameID: UUID
  public var index: Int
  public var reason: String
  public init(frameID: UUID, index: Int, reason: String) { self.frameID = frameID; self.index = index; self.reason = reason }
  public var errorDescription: String? { "Frame \(index + 1): " + reason }
}
