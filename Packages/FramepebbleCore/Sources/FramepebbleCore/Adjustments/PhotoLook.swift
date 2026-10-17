import CoreImage
import Foundation

/// Original, independently authored recipes using native colour adjustments.
/// No third-party presets, lookup tables, textures or brand emulations.
public enum PhotoLook: String, Codable, CaseIterable, Sendable {
  case gentle, warm, cool, vivid, softMono, boldMono
  public var title: String {
    switch self {
    case .gentle: "Gentle"
    case .warm: "Warm"
    case .cool: "Cool"
    case .vivid: "Vivid"
    case .softMono: "Soft Mono"
    case .boldMono: "Bold Mono"
    }
  }
  public var recipe: PhotoAdjustments {
    var value = PhotoAdjustments()
    switch self {
    case .gentle: value.contrast = 0.96; value.saturation = 0.94; value.shadows = 0.12
    case .warm: value.warmth = 0.32; value.contrast = 1.04; value.saturation = 1.05
    case .cool: value.warmth = -0.3; value.contrast = 1.03; value.saturation = 0.92
    case .vivid: value.contrast = 1.12; value.saturation = 1.3; value.highlights = 0.9
    case .softMono: value.saturation = 0; value.contrast = 0.88; value.shadows = 0.16
    case .boldMono: value.saturation = 0; value.contrast = 1.3; value.highlights = 0.85
    }
    return value
  }
  public func apply(to image: CIImage, strength: Double) throws -> CIImage {
    guard strength.isFinite, (0...1).contains(strength) else { throw ProcessingError.invalidConfiguration }
    try Task.checkCancellation()
    guard strength > 0 else { return image }
    let filtered = try recipe.apply(to: image)
    if strength == 1 { return filtered }
    guard let blend = CIFilter(name: "CIDissolveTransition", parameters: [
      kCIInputImageKey: image, kCIInputTargetImageKey: filtered, kCIInputTimeKey: strength
    ])?.outputImage else { throw ProcessingError.invalidConfiguration }
    return blend.cropped(to: image.extent)
  }
}
