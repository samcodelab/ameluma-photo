import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// Serial actor; one downsampled source/frame at a time. Image I/O may retain encoder state.
public actor GIFRenderer {
  private let processor = ImageProcessor()
  private let context = CIContext(options: [.cacheIntermediates: false])
  public init() {}
  public func renderFrame(_ frame: GIFFrame, project: GIFProject, sources: [SourceAsset], maximum: Int? = nil) async throws -> CGImage {
    try Task.checkCancellation()
    guard let source = sources.first(where: { $0.id == frame.sourceID }) else { throw GIFError.missingSource }
    var c = frame.configuration
    c.format = .png; c.colourPolicy = .sRGB; c.metadata = .remove
    let limit = min(maximum ?? max(project.width, project.height), max(project.width, project.height))
    guard limit > 0, (16...2000).contains(project.width), (16...2000).contains(project.height) else { throw ProcessingError.invalidConfiguration }
    // Complete captured photo edits first, including masks. Fitting the finished image
    // keeps privacy/annotation geometry attached to the content when the GIF canvas changes.
    let base = try await processor.render(source.url, configuration: c, previewMaximum: max(limit, 1200), decodeMaximum: max(limit * 2, 1200))
    return try autoreleasepool {
      let scale = min(1, Double(limit) / Double(max(project.width, project.height)))
      let size = CGSize(width: max(1, (Double(project.width) * scale).rounded()), height: max(1, (Double(project.height) * scale).rounded()))
      let factor = project.fit == .fit ? min(size.width / Double(base.width), size.height / Double(base.height)) : max(size.width / Double(base.width), size.height / Double(base.height))
      let image = CIImage(cgImage: base).transformed(by: CGAffineTransform(scaleX: factor, y: factor))
      let translated = image.transformed(by: CGAffineTransform(translationX: (size.width - image.extent.width) / 2, y: (size.height - image.extent.height) / 2))
      let bounds = CGRect(origin: .zero, size: size)
      var colour = project.background; colour.alpha = 1
      let background = CIImage(color: CIColor(cgColor: colour.cgColor)).cropped(to: bounds)
      let result = try AnnotationRenderer.apply(to: translated.composited(over: background).cropped(to: bounds), annotations: project.visibleAnnotations(on: frame.id), canvas: CanvasStyle())
      try Task.checkCancellation()
      guard let space = CGColorSpace(name: CGColorSpace.sRGB), let output = context.createCGImage(result, from: bounds, format: .RGBA8, colorSpace: space) else { throw ProcessingError.encoding }
      return output
    }
  }
  public func export(_ project: GIFProject, sources: [SourceAsset], directory: URL,
    progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> URL {
    try project.validate(); try Task.checkCancellation()
    guard directory.isFileURL else { throw ProcessingError.destination }
    let staging = directory.appendingPathComponent(".ameluma-gif-" + UUID().uuidString + ".tmp")
    // Reserve staging exclusively; never remove another process's file on failure.
    try StagingWriter.write(Data(), to: staging)
    defer { try? FileManager.default.removeItem(at: staging) }
    guard let destination = CGImageDestinationCreateWithURL(staging as CFURL, UTType.gif.identifier as CFString, project.frames.count, nil) else { throw ProcessingError.encoding }
    if project.plays != 1 {
      CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: project.plays == 0 ? 0 : project.plays - 1]] as CFDictionary)
    }
    for (index, frame) in project.frames.enumerated() {
      try Task.checkCancellation()
      let image = try await renderFrame(frame, project: project, sources: sources)
      try autoreleasepool {
        try Task.checkCancellation()
        let delay = project.timing(for: frame)
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
      }
      await progress(index + 1, project.frames.count)
    }
    try Task.checkCancellation()
    guard CGImageDestinationFinalize(destination) else { throw ProcessingError.encoding }
    try Task.checkCancellation()
    try validate(staging, project: project)
    let clean = project.name.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_" )).inverted).joined().prefix(80)
    let stem = clean.isEmpty ? "Animation" : String(clean)
    for suffix in 0..<10000 {
      try Task.checkCancellation()
      let output = directory.appendingPathComponent(stem + (suffix == 0 ? "" : "-\(suffix)") + ".gif")
      guard !sources.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == output.standardizedFileURL.resolvingSymlinksInPath() }) else { continue }
      let code = staging.withUnsafeFileSystemRepresentation { from in output.withUnsafeFileSystemRepresentation { to in renamex_np(from, to, UInt32(RENAME_EXCL)) } }
      if code == 0 { return output }
      if errno != EEXIST { throw ProcessingError.destination }
    }
    throw ProcessingError.destination
  }
  private func validate(_ url: URL, project: GIFProject) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) as String? == UTType.gif.identifier,
      CGImageSourceGetCount(source) == project.frames.count else { throw ProcessingError.validation }
    for (index, frame) in project.frames.enumerated() {
      try Task.checkCancellation()
      try autoreleasepool {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary),
          image.width == project.width, image.height == project.height,
          let p = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let gif = p[kCGImagePropertyGIFDictionary] as? [CFString: Any],
          let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double,
          abs(delay - project.timing(for: frame)) < 0.011 else { throw ProcessingError.validation }
      }
    }
  }
}
public enum GIFError: LocalizedError { case missingSource
  public var errorDescription: String? { "A GIF source photo is missing. Locate it in Projects → Relink, or replace the frame." }
}
