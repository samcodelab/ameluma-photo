import CoreGraphics
import CoreImage
import Foundation

public enum MaskEffect: String, Codable, Sendable, CaseIterable {
  case cover = "Solid Cover"
  case blur = "Blur"
  case pixelate = "Pixelate"
  case frosted = "Frosted"
}
public enum OverlayShape: String, Codable, Sendable, CaseIterable {
  case rectangle, ellipse, freehand
}
/// Normalised top-left FINAL output coordinates, after framing. Rotation is clockwise degrees.
public struct PrivacyMask: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var x = 0.25
  public var y = 0.25
  public var width = 0.5
  public var height = 0.5
  public var rotation = 0.0
  public var strength = 0.5
  public var shape: OverlayShape = .rectangle
  public var effect: MaskEffect = .cover
  public var points: [NormalizedPoint] = []
  public init() {}
}
public struct NormalizedPoint: Codable, Sendable, Equatable {
  public var x: Double
  public var y: Double
  public init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
}
public enum PrivacyRenderer {
  public static func path(
    shape: OverlayShape, rect: CGRect, points: [NormalizedPoint], output: CGSize
  ) -> CGPath {
    let path = CGMutablePath()
    switch shape {
    case .rectangle: path.addRect(rect)
    case .ellipse: path.addEllipse(in: rect)
    case .freehand:
      if let first = points.first {
        path.move(
          to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
          path.addLine(
            to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        path.closeSubpath()
      }
    }
    return path
  }
  public static func validate(x: Double, y: Double, width: Double, height: Double, rotation: Double)
    throws
  {
    guard [x, y, width, height, rotation].allSatisfy(\.isFinite), (0...1).contains(x),
      (0...1).contains(y), width > 0, width <= 1, height > 0, height <= 1, abs(rotation) <= 360
    else { throw ProcessingError.invalidConfiguration }
  }
  public static func apply(to source: CIImage, masks: [PrivacyMask]) throws -> CIImage {
    guard masks.count <= 200 else { throw ProcessingError.invalidConfiguration }
    var image = source
    let size = source.extent.size
    for mask in masks {
      try Task.checkCancellation()
      try validate(
        x: mask.x, y: mask.y, width: mask.width, height: mask.height, rotation: mask.rotation)
      guard mask.strength.isFinite, (0...1).contains(mask.strength), mask.points.count <= 10000,
        mask.points.allSatisfy({
          $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }), mask.shape != .freehand || mask.points.count >= 3
      else { throw ProcessingError.invalidConfiguration }
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let ctx = CGContext(
          data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
          bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { throw ProcessingError.encoding }
      ctx.setFillColor(CGColor(gray: 0, alpha: 1))
      ctx.fill(CGRect(origin: .zero, size: size))
      ctx.translateBy(x: 0, y: size.height)
      ctx.scaleBy(x: 1, y: -1)
      let rect = CGRect(
        x: mask.x * size.width, y: mask.y * size.height, width: mask.width * size.width,
        height: mask.height * size.height)
      ctx.translateBy(x: rect.midX, y: rect.midY)
      ctx.rotate(by: mask.rotation * .pi / 180)
      ctx.translateBy(x: -rect.midX, y: -rect.midY)
      ctx.addPath(path(shape: mask.shape, rect: rect, points: mask.points, output: size))
      ctx.setFillColor(CGColor(gray: 1, alpha: 1))
      ctx.fillPath()
      guard let cg = ctx.makeImage() else { throw ProcessingError.encoding }
      let effect: CIImage
      switch mask.effect {
      case .cover: effect = CIImage(color: .black).cropped(to: source.extent)
      case .blur:
        effect = image.clampedToExtent().applyingFilter(
          "CIGaussianBlur",
          parameters: ["inputRadius": max(1, mask.strength * min(size.width, size.height) * 0.08)]
        ).cropped(to: source.extent)
      case .pixelate:
        effect = image.applyingFilter(
          "CIPixellate",
          parameters: [
            "inputScale": max(2, mask.strength * min(size.width, size.height) * 0.1),
            "inputCenter": CIVector(x: 0, y: 0),
          ]
        ).cropped(to: source.extent)
      case .frosted:
        effect = image.clampedToExtent().applyingFilter(
          "CIGaussianBlur",
          parameters: ["inputRadius": max(2, mask.strength * min(size.width, size.height) * 0.08)]
        ).applyingFilter(
          "CIColorControls", parameters: ["inputSaturation": 0.1, "inputBrightness": 0.15]
        ).cropped(to: source.extent)
      }
      image = effect.applyingFilter(
        "CIBlendWithMask",
        parameters: ["inputBackgroundImage": image, "inputMaskImage": CIImage(cgImage: cg)]
      ).cropped(to: source.extent)
    }
    return image
  }
}
