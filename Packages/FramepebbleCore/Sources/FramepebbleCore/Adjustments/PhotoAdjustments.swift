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
  public init() {}
  public func validate() throws {
    guard exposure.isFinite, (-2...2).contains(exposure), brightness.isFinite,
      (-0.5...0.5).contains(brightness), contrast.isFinite, (0.5...1.5).contains(contrast),
      saturation.isFinite, (0...2).contains(saturation), warmth.isFinite, (-1...1).contains(warmth),
      highlights.isFinite, (0...1).contains(highlights), shadows.isFinite, (0...1).contains(shadows)
    else { throw ProcessingError.invalidConfiguration }
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
