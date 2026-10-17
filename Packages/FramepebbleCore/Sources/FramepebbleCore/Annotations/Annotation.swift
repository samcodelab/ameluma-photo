import CoreGraphics
import CoreImage
import CoreText
import Foundation

public enum AnnotationTextAlignment: String, Codable, Sendable, CaseIterable {
  case leading, centre, trailing
}
public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
  case text, speechBubble, arrow, line, rectangle, ellipse, freehand, sticker, highlight, callout
  public var title: String {
    switch self {
    case .speechBubble: "Speech Bubble"
    case .freehand: "Freehand"
    case .callout: "Numbered Callout"
    default: rawValue.capitalized
    }
  }
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
  public var flipHorizontal = false
  public var stickerID: String?
  public var text = "Your caption"
  public var fontName = "HelveticaNeue-Medium"
  public var points: [NormalizedPoint] = []
  /// New arrows follow drag direction. nil preserves legacy top-left→bottom-right rendering.
  public var directionVersion: Int?
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case id, kind, x, y, width, height, rotation, opacity, lineWidth, colour, alignment, text, stickerID, flipHorizontal,
      fontName, points, directionVersion
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
    flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
    stickerID = try c.decodeIfPresent(String.self, forKey: .stickerID)
    text = try c.decodeIfPresent(String.self, forKey: .text) ?? text
    fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? fontName
    points = try c.decodeIfPresent([NormalizedPoint].self, forKey: .points) ?? points
    directionVersion = try c.decodeIfPresent(Int.self, forKey: .directionVersion)
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
  /// Numbers are semantic order, never burned into editable text. Deleting or
  /// reordering other objects cannot introduce gaps in screenshot callouts.
  public static func calloutNumbers(_ annotations: [Annotation]) -> [UUID: Int] {
    var result: [UUID: Int] = [:]
    for annotation in annotations where annotation.kind == .callout {
      result[annotation.id] = result.count + 1
    }
    return result
  }

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
    let numbers = calloutNumbers(annotations)
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
      if a.flipHorizontal { ctx.scaleBy(x: -1, y: 1) }
      ctx.translateBy(x: -r.midX, y: -r.midY)
      ctx.setStrokeColor(a.colour.cgColor)
      ctx.setLineWidth(a.lineWidth * min(size.width, size.height))
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      switch a.kind {
      case .sticker:
        guard let id = a.stickerID, let sticker = StickerCatalog.sticker(id) else { throw StickerError.unavailable }
        // Composite the entire sticker once: overlapping vector parts must not
        // accumulate the object opacity independently.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        StickerRenderer.draw(sticker, in: r, context: ctx)
        ctx.endTransparencyLayer()
      case .text, .speechBubble:
        if a.kind == .speechBubble {
          ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -4, dy: -4), cornerWidth: r.height * 0.15, cornerHeight: r.height * 0.15, transform: nil))
          ctx.move(to: CGPoint(x: r.midX, y: r.maxY + 4))
          ctx.addLine(to: CGPoint(x: r.midX - r.width * 0.12, y: r.maxY + r.height * 0.3))
          ctx.addLine(to: CGPoint(x: r.midX - r.width * 0.16, y: r.maxY + 4))
          ctx.strokePath()
        }
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
      case .highlight:
        ctx.setFillColor(a.colour.cgColor)
        ctx.fill(r)
      case .callout:
        let diameter = min(r.width, r.height)
        let circle = CGRect(x: r.midX-diameter/2, y: r.midY-diameter/2, width: diameter, height: diameter)
        ctx.setFillColor(a.colour.cgColor); ctx.fillEllipse(in: circle)
        let luminance = a.colour.red * 0.2126 + a.colour.green * 0.7152 + a.colour.blue * 0.0722
        let ink = CGColor(gray: luminance > 0.55 ? 0 : 1, alpha: 1)
        let font = CTFontCreateWithName(a.fontName as CFString, diameter * 0.55, nil)
        let string = NSAttributedString(string: String(numbers[a.id] ?? 1), attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink])
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let fit = min(1, diameter * 0.75 / max(1, bounds.width))
        ctx.translateBy(x: circle.midX, y: circle.midY)
        ctx.scaleBy(x: fit, y: -fit)
        ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, ctx)
      case .rectangle: ctx.stroke(r)
      case .ellipse: ctx.strokeEllipse(in: r)
      case .line, .arrow:
        guard a.directionVersion == nil || a.directionVersion == 1 else { throw ProcessingError.invalidConfiguration }
        let directed = a.directionVersion == 1 && a.points.count >= 2
        let start = directed ? CGPoint(x: r.minX + a.points[0].x * r.width, y: r.minY + a.points[0].y * r.height) : r.origin
        let last = a.points.last ?? NormalizedPoint(1,1)
        let end = directed ? CGPoint(x: r.minX + last.x * r.width, y: r.minY + last.y * r.height) : CGPoint(x:r.maxX,y:r.maxY)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        if a.kind == .arrow {
          let angle = atan2(end.y-start.y, end.x-start.x)
          let d = min(size.width, size.height) * 0.04
          ctx.move(
            to: CGPoint(x: end.x - d * cos(angle - .pi / 6), y: end.y - d * sin(angle - .pi / 6)))
          ctx.addLine(to: end)
          ctx.addLine(
            to: CGPoint(x: end.x - d * cos(angle + .pi / 6), y: end.y - d * sin(angle + .pi / 6)))
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
