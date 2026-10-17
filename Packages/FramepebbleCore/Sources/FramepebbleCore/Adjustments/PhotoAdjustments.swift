import CoreImage
import Foundation

public struct PhotoAdjustments: Codable, Sendable, Equatable {
  public var exposure = 0.0
  public var brightness = 0.0
  public var contrast = 1.0
  public var saturation = 1.0
  public var warmth = 0.0
  public var highlights = 1.0
  public var shadows = 0.0
  public var vibrance = 0.0
  public var tint = 0.0
  public var redHue = 0.0
  public var redSaturation = 0.0
  public var redLightness = 0.0
  public var orangeHue = 0.0
  public var orangeSaturation = 0.0
  public var orangeLightness = 0.0
  public var yellowHue = 0.0
  public var yellowSaturation = 0.0
  public var yellowLightness = 0.0
  public var greenHue = 0.0
  public var greenSaturation = 0.0
  public var greenLightness = 0.0
  public var aquaHue = 0.0
  public var aquaSaturation = 0.0
  public var aquaLightness = 0.0
  public var blueHue = 0.0
  public var blueSaturation = 0.0
  public var blueLightness = 0.0
  public var purpleHue = 0.0
  public var purpleSaturation = 0.0
  public var purpleLightness = 0.0
  public var magentaHue = 0.0
  public var magentaSaturation = 0.0
  public var magentaLightness = 0.0
  public var hasColourMix: Bool { [redHue, redSaturation, redLightness, orangeHue, orangeSaturation, orangeLightness, yellowHue, yellowSaturation, yellowLightness, greenHue, greenSaturation, greenLightness, aquaHue, aquaSaturation, aquaLightness, blueHue, blueSaturation, blueLightness, purpleHue, purpleSaturation, purpleLightness, magentaHue, magentaSaturation, magentaLightness].contains { $0 != 0 } }
  public init() {}
  private enum CodingKeys: String, CodingKey { case exposure, brightness, contrast, saturation, warmth, highlights, shadows, vibrance, tint, redHue, redSaturation, redLightness, orangeHue, orangeSaturation, orangeLightness, yellowHue, yellowSaturation, yellowLightness, greenHue, greenSaturation, greenLightness, aquaHue, aquaSaturation, aquaLightness, blueHue, blueSaturation, blueLightness, purpleHue, purpleSaturation, purpleLightness, magentaHue, magentaSaturation, magentaLightness }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0.0
    brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.0
    contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1.0
    saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1.0
    warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0.0
    highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 1.0
    shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0.0
    vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
    tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
    redHue = try c.decodeIfPresent(Double.self, forKey: .redHue) ?? 0
    redSaturation = try c.decodeIfPresent(Double.self, forKey: .redSaturation) ?? 0
    redLightness = try c.decodeIfPresent(Double.self, forKey: .redLightness) ?? 0
    orangeHue = try c.decodeIfPresent(Double.self, forKey: .orangeHue) ?? 0
    orangeSaturation = try c.decodeIfPresent(Double.self, forKey: .orangeSaturation) ?? 0
    orangeLightness = try c.decodeIfPresent(Double.self, forKey: .orangeLightness) ?? 0
    yellowHue = try c.decodeIfPresent(Double.self, forKey: .yellowHue) ?? 0
    yellowSaturation = try c.decodeIfPresent(Double.self, forKey: .yellowSaturation) ?? 0
    yellowLightness = try c.decodeIfPresent(Double.self, forKey: .yellowLightness) ?? 0
    greenHue = try c.decodeIfPresent(Double.self, forKey: .greenHue) ?? 0
    greenSaturation = try c.decodeIfPresent(Double.self, forKey: .greenSaturation) ?? 0
    greenLightness = try c.decodeIfPresent(Double.self, forKey: .greenLightness) ?? 0
    aquaHue = try c.decodeIfPresent(Double.self, forKey: .aquaHue) ?? 0
    aquaSaturation = try c.decodeIfPresent(Double.self, forKey: .aquaSaturation) ?? 0
    aquaLightness = try c.decodeIfPresent(Double.self, forKey: .aquaLightness) ?? 0
    blueHue = try c.decodeIfPresent(Double.self, forKey: .blueHue) ?? 0
    blueSaturation = try c.decodeIfPresent(Double.self, forKey: .blueSaturation) ?? 0
    blueLightness = try c.decodeIfPresent(Double.self, forKey: .blueLightness) ?? 0
    purpleHue = try c.decodeIfPresent(Double.self, forKey: .purpleHue) ?? 0
    purpleSaturation = try c.decodeIfPresent(Double.self, forKey: .purpleSaturation) ?? 0
    purpleLightness = try c.decodeIfPresent(Double.self, forKey: .purpleLightness) ?? 0
    magentaHue = try c.decodeIfPresent(Double.self, forKey: .magentaHue) ?? 0
    magentaSaturation = try c.decodeIfPresent(Double.self, forKey: .magentaSaturation) ?? 0
    magentaLightness = try c.decodeIfPresent(Double.self, forKey: .magentaLightness) ?? 0
  }
  public func validate() throws {
    guard exposure.isFinite, (-2...2).contains(exposure), brightness.isFinite,
      (-0.5...0.5).contains(brightness), contrast.isFinite, (0.5...1.5).contains(contrast),
      saturation.isFinite, (0...2).contains(saturation), warmth.isFinite, (-1...1).contains(warmth),
      highlights.isFinite, (0...1).contains(highlights), shadows.isFinite, (0...1).contains(shadows)
    else { throw ProcessingError.invalidConfiguration }
    guard [vibrance, tint, redHue, redSaturation, redLightness, orangeHue, orangeSaturation, orangeLightness, yellowHue, yellowSaturation, yellowLightness, greenHue, greenSaturation, greenLightness, aquaHue, aquaSaturation, aquaLightness, blueHue, blueSaturation, blueLightness, purpleHue, purpleSaturation, purpleLightness, magentaHue, magentaSaturation, magentaLightness].allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { throw ProcessingError.invalidConfiguration }
  }
  public func apply(to image: CIImage) throws -> CIImage {
    try validate()
    var result = image
    if exposure != 0 {
      result = result.applyingFilter("CIExposureAdjust", parameters: ["inputEV": exposure])
    }
    if brightness != 0 || contrast != 1 || saturation != 1 {
      result = result.applyingFilter(
        "CIColorControls",
        parameters: [
          "inputBrightness": brightness, "inputContrast": contrast, "inputSaturation": saturation,
        ])
    }
    if warmth != 0 {
      result = result.applyingFilter(
        "CITemperatureAndTint",
        parameters: [
          "inputNeutral": CIVector(x: 6500 + warmth * 1800, y: 0),
          "inputTargetNeutral": CIVector(x: 6500, y: 0),
        ])
    }
    if highlights != 1 || shadows != 0 {
      result = result.applyingFilter(
        "CIHighlightShadowAdjust",
        parameters: ["inputHighlightAmount": highlights, "inputShadowAmount": shadows])
    }
    if vibrance != 0 { result = result.applyingFilter("CIVibrance", parameters: ["inputAmount": vibrance]) }
    if tint != 0 {
      result = result.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: tint * 100), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
    }
    if hasColourMix {
      result = try ColourRenderer.mix(result, bands: [CIVector(x: redHue, y: redSaturation, z: redLightness), CIVector(x: orangeHue, y: orangeSaturation, z: orangeLightness), CIVector(x: yellowHue, y: yellowSaturation, z: yellowLightness), CIVector(x: greenHue, y: greenSaturation, z: greenLightness), CIVector(x: aquaHue, y: aquaSaturation, z: aquaLightness), CIVector(x: blueHue, y: blueSaturation, z: blueLightness), CIVector(x: purpleHue, y: purpleSaturation, z: purpleLightness), CIVector(x: magentaHue, y: magentaSaturation, z: magentaLightness)])
    }
    return result.cropped(to: image.extent)
  }
}
public enum QuickFix: String, CaseIterable, Sendable {
  case autoEnhance = "Auto Enhance"
  case lighting = "Improve Lighting"
  case colour = "Correct Colour"
  case straighten = "Straighten"
  case sharing = "Fit for Sharing"
}
