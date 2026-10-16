import Foundation

public struct GIFFrame: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var sourceID: UUID
  public var duration = 0.5
  /// Additional framing of the finished photo; source masks and annotations remain attached.
  public var crop = CropConfiguration()
  /// Captured edits: workspace/batch edits cannot silently alter an existing animation.
  public var configuration: ProcessingConfiguration
  public init(sourceID: UUID, configuration: ProcessingConfiguration = ProcessingConfiguration()) {
    self.sourceID = sourceID; self.configuration = configuration
  }
  private enum CodingKeys: String, CodingKey { case id, sourceID, duration, crop, configuration }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sourceID = try c.decode(UUID.self, forKey: .sourceID)
    configuration = try c.decode(ProcessingConfiguration.self, forKey: .configuration)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5
    crop = try c.decodeIfPresent(CropConfiguration.self, forKey: .crop) ?? CropConfiguration()
  }
}
public struct GIFAnnotation: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var extendsToNewFrames = false
  public var annotation: Annotation
  /// nil means all frames, including subsequently added frames. Explicit IDs follow frames on reorder.
  public var frameIDs: Set<UUID>?
  public init(annotation: Annotation, frameIDs: Set<UUID>? = nil) { self.annotation = annotation; self.frameIDs = frameIDs }
}
public enum GIFFit: String, Codable, Sendable, CaseIterable { case fit = "Fit", fill = "Fill" }
public enum GIFPreset: String, Codable, Sendable, CaseIterable {
  case small = "Small File", balanced = "Balanced", best = "Best Quality"
  public var maximumDimension: Int { switch self { case .small: 480; case .balanced: 800; case .best: 1600 } }
}
public struct GIFProject: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var name = "My Animation"
  public var frames: [GIFFrame] = []
  public var width = 800
  public var height = 800
  public var fit: GIFFit = .fit
  public var background = RGBAColour(1, 1, 1, 1)
  public var annotations: [GIFAnnotation] = []
  /// 0 = forever; 1 = once; otherwise total plays.
  public var plays = 0
  public var speed = 1.0
  public var preset: GIFPreset = .balanced
  public init() {}
  public func timing(for frame: GIFFrame) -> Double {
    guard frame.duration.isFinite, speed.isFinite, speed > 0 else { return 0.5 }
    // GIF delays are centiseconds. Minimum 100 ms avoids decoder-specific short-delay clamping.
    return min(60, max(0.1, (frame.duration / speed * 100).rounded() / 100))
  }
  public var duration: Double { frames.reduce(0) { $0 + timing(for: $1) } }
  public func visibleAnnotations(on id: UUID) -> [Annotation] {
    annotations.filter { $0.frameIDs?.contains(id) ?? true }.map(\.annotation)
  }
  public mutating func setDuration(_ seconds: Double, ids: Set<UUID>? = nil) {
    guard seconds.isFinite else { return }
    for i in frames.indices where ids?.contains(frames[i].id) ?? true {
      frames[i].duration = min(60, max(0.1, (seconds * 100).rounded() / 100))
    }
  }
  public mutating func duplicate(_ id: UUID) {
    guard let index = frames.firstIndex(where: { $0.id == id }) else { return }
    var copy = frames[index]; copy.id = UUID(); frames.insert(copy, at: index + 1)
    for i in annotations.indices where annotations[i].frameIDs?.contains(id) == true { annotations[i].frameIDs?.insert(copy.id) }
  }
  public mutating func remove(_ ids: Set<UUID>) {
    frames.removeAll { ids.contains($0.id) }
    for i in annotations.indices { annotations[i].frameIDs?.subtract(ids) }
    annotations.removeAll { $0.frameIDs?.isEmpty == true }
  }
  public mutating func move(_ id: UUID, before target: UUID) {
    guard id != target, let from = frames.firstIndex(where: { $0.id == id }), frames.contains(where: { $0.id == target }) else { return }
    let value = frames.remove(at: from)
    if let to = frames.firstIndex(where: { $0.id == target }) { frames.insert(value, at: to) }
  }
  public func validate() throws {
    guard !frames.isEmpty, frames.count <= 1000, Set(frames.map(\.id)).count == frames.count,
      (16...2000).contains(width), (16...2000).contains(height), width * height <= 4_000_000,
      plays >= 0, plays <= 65535, speed.isFinite, (0.1...10).contains(speed),
      frames.allSatisfy({ $0.duration.isFinite && (0.1...60).contains($0.duration) && $0.crop.zoom.isFinite && (1...20).contains($0.crop.zoom) && $0.crop.centerX.isFinite && (0...1).contains($0.crop.centerX) && $0.crop.centerY.isFinite && (0...1).contains($0.crop.centerY) }),
      [background.red, background.green, background.blue, background.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      annotations.count <= 200 else { throw ProcessingError.invalidConfiguration }
  }
}
