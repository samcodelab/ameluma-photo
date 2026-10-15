import CoreGraphics
import CoreImage
import Foundation

public enum AnnotationTextAlignment: String, Codable, Sendable, CaseIterable {
  case leading, centre, trailing
}
public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
  case text, arrow, line, rectangle, ellipse, freehand
}
/// Normalised final-output geometry. Text uses the same CoreText stamp renderer as watermarks.
public struct Annotation: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var kind: AnnotationKind = .text
  public var x = 0.1
  public var y = 0.1
  public var width = 0.5
  public var height = 0.15
  public var rotation = 0.0
  public var opacity = 1.0
  public var lineWidth = 0.006
  public var colour = RGBAColour(1, 1, 1, 1)
  public var alignment: AnnotationTextAlignment = .leading
  public var text = "Your caption"
  public var fontName = "HelveticaNeue-Medium"
  public var points: [NormalizedPoint] = []
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case id, kind, x, y, width, height, rotation, opacity, lineWidth, colour, alignment, text,
      fontName, points
  }
  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
    kind = try c.decodeIfPresent(AnnotationKind.self, forKey: .kind) ?? kind
    x = try c.decodeIfPresent(Double.self, forKey: .x) ?? x
    y = try c.decodeIfPresent(Double.self, forKey: .y) ?? y
    width = try c.decodeIfPresent(Double.self, forKey: .width) ?? width
    height = try c.decodeIfPresent(Double.self, forKey: .height) ?? height
    rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? rotation
    opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
    lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? lineWidth
    colour = try c.decodeIfPresent(RGBAColour.self, forKey: .colour) ?? colour
    alignment = try c.decodeIfPresent(AnnotationTextAlignment.self, forKey: .alignment) ?? alignment
    text = try c.decodeIfPresent(String.self, forKey: .text) ?? text
    fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? fontName
    points = try c.decodeIfPresent([NormalizedPoint].self, forKey: .points) ?? points
  }

}
public struct CanvasStyle: Codable, Sendable, Equatable {
  public var shadow = false
  public var border = 0.0
  public var cornerRadius = 0.0
  public var borderColour = RGBAColour(1, 1, 1, 1)
  public init() {}
  private enum CodingKeys: String, CodingKey { case shadow, border, cornerRadius, borderColour }
  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? false
    border = try c.decodeIfPresent(Double.self, forKey: .border) ?? 0
    cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
    borderColour = try c.decodeIfPresent(RGBAColour.self, forKey: .borderColour) ?? borderColour
  }

}
public enum AnnotationRenderer {
  public static func apply(to image: CIImage, annotations: [Annotation], canvas: CanvasStyle) throws
    -> CIImage
  {
    guard annotations.count <= 200, canvas.border.isFinite, (0...0.2).contains(canvas.border),
      canvas.cornerRadius.isFinite, (0...0.5).contains(canvas.cornerRadius),
      [
        canvas.borderColour.red, canvas.borderColour.green, canvas.borderColour.blue,
        canvas.borderColour.alpha,
      ].allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else { throw ProcessingError.invalidConfiguration }
    let size = image.extent.size
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ProcessingError.encoding }
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    for a in annotations {
      try Task.checkCancellation()
      try PrivacyRenderer.validate(
        x: a.x, y: a.y, width: a.width, height: a.height, rotation: a.rotation)
      guard a.opacity.isFinite, (0...1).contains(a.opacity), a.lineWidth.isFinite,
        (0.001...0.1).contains(a.lineWidth), a.points.count <= 10000,
        a.points.allSatisfy({
          $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }),
        [a.colour.red, a.colour.green, a.colour.blue, a.colour.alpha].allSatisfy({
          $0.isFinite && (0...1).contains($0)
        })
      else { throw ProcessingError.invalidConfiguration }
      let r = CGRect(
        x: a.x * size.width, y: a.y * size.height, width: a.width * size.width,
        height: a.height * size.height)
      ctx.saveGState()
      ctx.setAlpha(a.opacity)
      ctx.translateBy(x: r.midX, y: r.midY)
      ctx.rotate(by: a.rotation * .pi / 180)
      ctx.translateBy(x: -r.midX, y: -r.midY)
      ctx.setStrokeColor(a.colour.cgColor)
      ctx.setLineWidth(a.lineWidth * min(size.width, size.height))
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      switch a.kind {
      case .text:
        guard !a.text.isEmpty, a.text.count <= 1024 else {
          throw ProcessingError.invalidConfiguration
        }
        var w = WatermarkConfiguration()
        w.text = a.text
        w.fontName = a.fontName
        w.colour = a.colour
        w.relativeWidth = a.width
        let stamp = try WatermarkRenderer.stamp(w, outputWidth: size.width)
        let ci = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ci.createCGImage(stamp, from: stamp.extent) else {
          throw ProcessingError.encoding
        }
        let factor = min(1, r.height / CGFloat(cg.height))
        let h = CGFloat(cg.height) * factor
        let width = CGFloat(cg.width) * factor
        let textX =
          r.minX
          + (a.alignment == .centre
            ? (r.width - width) / 2 : a.alignment == .trailing ? r.width - width : 0)
        ctx.translateBy(x: textX, y: r.minY + h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: h))
      case .rectangle: ctx.stroke(r)
      case .ellipse: ctx.strokeEllipse(in: r)
      case .line, .arrow:
        ctx.move(to: r.origin)
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.strokePath()
        if a.kind == .arrow {
          let angle = atan2(r.height, r.width)
          let d = min(size.width, size.height) * 0.04
          ctx.move(
            to: CGPoint(x: r.maxX - d * cos(angle - .pi / 6), y: r.maxY - d * sin(angle - .pi / 6)))
          ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
          ctx.addLine(
            to: CGPoint(x: r.maxX - d * cos(angle + .pi / 6), y: r.maxY - d * sin(angle + .pi / 6)))
          ctx.strokePath()
        }
      case .freehand:
        guard a.points.count >= 2 else { throw ProcessingError.invalidConfiguration }
        for (i, p) in a.points.enumerated() {
          let point = CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
          if i == 0 { ctx.move(to: point) } else { ctx.addLine(to: point) }
        }
        ctx.strokePath()
      }
      ctx.restoreGState()
    }
    let inset = canvas.border * min(size.width, size.height) / 2
    if canvas.border > 0 {
      ctx.setStrokeColor(canvas.borderColour.cgColor)
      ctx.setLineWidth(inset * 2)
      ctx.addPath(
        CGPath(
          roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset),
          cornerWidth: canvas.cornerRadius * min(size.width, size.height),
          cornerHeight: canvas.cornerRadius * min(size.width, size.height), transform: nil))
      ctx.strokePath()
    }
    guard let overlay = ctx.makeImage() else { throw ProcessingError.encoding }
    var result = CIImage(cgImage: overlay).composited(over: image)
    if canvas.cornerRadius > 0 {
      ctx.clear(CGRect(origin: .zero, size: size))
      ctx.setFillColor(CGColor(gray: 1, alpha: 1))
      ctx.addPath(
        CGPath(
          roundedRect: CGRect(origin: .zero, size: size),
          cornerWidth: canvas.cornerRadius * min(size.width, size.height),
          cornerHeight: canvas.cornerRadius * min(size.width, size.height), transform: nil))
      ctx.fillPath()
      guard let mask = ctx.makeImage() else { throw ProcessingError.encoding }
      result = result.applyingFilter(
        "CIBlendWithAlphaMask",
        parameters: [
          "inputBackgroundImage": CIImage(color: .clear).cropped(to: image.extent),
          "inputMaskImage": CIImage(cgImage: mask),
        ])
    }
    return result.cropped(to: image.extent)
  }
}
