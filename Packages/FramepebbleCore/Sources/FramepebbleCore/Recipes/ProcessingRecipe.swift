import Foundation
import CoreGraphics

public enum RecipeStage: String, Codable, CaseIterable, Sendable {
  case corrections = "Corrections", resize = "Resize", filter = "Filter", watermark = "Watermark", output = "Output"
}
/// Reusable intent only: no source ID, crop position, overlay, retouch stroke,
/// colour trace, resolved Auto Enhance, grain seed or output destination is stored.
public struct ProcessingRecipe: Identifiable, Codable, Equatable, Sendable {
  public var version = 1
  public var id = UUID()
  public var name = "New Recipe"
  public var enabled: Set<RecipeStage> = [.resize, .output]
  public var longestEdge = 1920
  public var allowUpscaling = false
  public var exposure = 0.0
  public var contrast = 1.0
  public var saturation = 1.0
  public var warmth = 0.0
  public var presetID: String?
  public var filterVersion = 1
  public var intensity = 0.7
  public var watermark = WatermarkConfiguration()
  public var format: OutputFormat = .jpeg
  public var quality = 0.85
  public var metadata: MetadataPolicy = .remove
  public init() {}
  public func validate() throws {
    guard version == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
      (1...20000).contains(longestEdge), exposure.isFinite, (-2...2).contains(exposure),
      contrast.isFinite, (0.5...1.5).contains(contrast), saturation.isFinite, (0...2).contains(saturation),
      warmth.isFinite, (-1...1).contains(warmth), intensity.isFinite, (0...1).contains(intensity),
      quality.isFinite, (0.1...1).contains(quality), !enabled.isEmpty else { throw ProcessingError.invalidConfiguration }
    if enabled.contains(.filter), let presetID, FilterCatalog.preset(presetID, version: filterVersion) == nil { throw CreativeFilterError.unavailable }
    if enabled.contains(.watermark) {
      guard watermark.enabled, watermark.relativeWidth.isFinite, (0.02...1).contains(watermark.relativeWidth),
        watermark.opacity.isFinite, (0...1).contains(watermark.opacity), watermark.rotation.isFinite, abs(watermark.rotation)<=360,
        watermark.margin.isFinite, (0...0.4).contains(watermark.margin), watermark.offsetX.isFinite, abs(watermark.offsetX)<=1,
        watermark.offsetY.isFinite, abs(watermark.offsetY)<=1,
        [watermark.colour.red,watermark.colour.green,watermark.colour.blue,watermark.colour.alpha].allSatisfy({$0.isFinite && (0...1).contains($0)}),
        watermark.kind == .text ? !watermark.text.isEmpty && watermark.text.count<=1024 : watermark.imageURL?.isFileURL == true
      else { throw ProcessingError.invalidConfiguration }
    }
  }
  public var stages: [RecipeStage] { RecipeStage.allCases.filter { enabled.contains($0) } }
  /// Compile into the established processor's configuration, preserving every
  /// unrelated photo edit. Canonical stage order is visible in the builder.
  public func configuration(for input: ProcessingConfiguration, sourceSize: CGSize, grainSeed: UInt32) throws -> ProcessingConfiguration {
    try validate()
    var result = input
    if enabled.contains(.corrections) {
      result.adjustments.exposure = exposure; result.adjustments.contrast = contrast
      result.adjustments.saturation = saturation; result.adjustments.warmth = warmth
    }
    if enabled.contains(.resize) {
      guard sourceSize.width>0, sourceSize.height>0 else { throw ProcessingError.invalidImage }
      let edited = ImageProcessor.outputSize(source: ImageProcessor.transformedSize(sourceSize, configuration: input), configuration: input)
      let factor = Double(longestEdge) / max(edited.width, edited.height)
      let scale = allowUpscaling ? factor : min(1, factor)
      result.width = max(1, Int((edited.width * scale).rounded()))
      result.height = max(1, Int((edited.height * scale).rounded()))
      result.nativeOutputSizing = false
      // Preserve source framing and the finished photo's aspect ratio, including
      // existing native-sized crops. Resize is never an implicit new crop.
      if result.crop.mode == .preserveAspectRatio {
        result.resizeBasis = .longestEdge; result.width = max(result.width,result.height)
      }
      result.preventUpscaling = !allowUpscaling
    }
    if enabled.contains(.filter) {
      var filter = FilterEdit(presetID: presetID, intensity: intensity, grainSeed: input.filterEdit?.grainSeed ?? grainSeed)
      filter.recipeVersion = filterVersion
      result.filterEdit = filter; result.look = nil
    }
    if enabled.contains(.watermark) { result.watermark = watermark }
    if enabled.contains(.output) {
      result.format = format; result.quality = quality; result.targetBytes = nil
      result.minimumQuality = min(result.minimumQuality,quality); result.metadata = metadata
    }
    return result
  }
}
