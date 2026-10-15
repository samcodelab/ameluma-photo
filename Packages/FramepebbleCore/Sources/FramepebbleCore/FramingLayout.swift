import Foundation
import CoreGraphics

/// The shared affine layout for raster rendering, raw gesture display and subject guides.
/// All rectangles use top-left coordinates in original transformed source/output pixels.
public struct FramingLayout: Sendable {
    public var source: CGSize
    public var output: CGSize
    public var cropRect: CGRect
    public var contentRect: CGRect
    public var scaleX: CGFloat
    public var scaleY: CGFloat
    public init(source: CGSize, output: CGSize, configuration c: ProcessingConfiguration) {
        self.source = source; self.output = output
        if c.crop.mode == .fill || c.crop.mode == .manualCrop { cropRect = CropGeometry.rect(source: source, ratio: Double(output.width / max(1, output.height)), crop: c.crop) }
        else { cropRect = CGRect(origin: .zero, size: source) }
        let sx = output.width / max(0.0001, cropRect.width); let sy = output.height / max(0.0001, cropRect.height)
        scaleX = c.crop.mode == .stretch ? sx : min(sx, sy); scaleY = c.crop.mode == .stretch ? sy : scaleX
        if c.preventUpscaling { scaleX = min(scaleX, 1); scaleY = min(scaleY, 1) }
        var placement = WatermarkConfiguration(); placement.margin = 0; placement.anchor = c.crop.mode == .canvas ? c.canvasAlignment : .centre
        contentRect = WatermarkRenderer.placement(size: CGSize(width: cropRect.width * scaleX, height: cropRect.height * scaleY), output: output, configuration: placement)
    }
    public func sourceRectInOutput(_ rect: CGRect) -> CGRect {
        CGRect(x: contentRect.minX + (rect.minX - cropRect.minX) * scaleX, y: contentRect.minY + (rect.minY - cropRect.minY) * scaleY, width: rect.width * scaleX, height: rect.height * scaleY)
    }
    public func normalizedSubjectInOutput(_ rect: CGRect) -> CGRect {
        sourceRectInOutput(CGRect(x: rect.minX * source.width, y: rect.minY * source.height, width: rect.width * source.width, height: rect.height * source.height))
    }
}

extension CropGeometry {
  /// Source-pixel crop boundaries, independent of gesture device and display scale.
  public static func resized(_ rect: CGRect, source: CGSize, handle: OverlayResizeHandle,
                             translation: CGSize, preserveAspect: Bool) -> CGRect {
    guard source.width > 0, source.height > 0 else { return rect }
    let bounds = OverlayBounds(x: rect.minX / source.width, y: rect.minY / source.height,
      width: rect.width / source.width, height: rect.height / source.height)
    let changed = OverlayGeometry.resized(bounds, handle: handle, translation: translation,
      viewport: source, preserveAspect: preserveAspect)
    var result = CGRect(x: changed.x * source.width, y: changed.y * source.height,
      width: changed.width * source.width, height: changed.height * source.height)
    // The persisted zoom range is 1...20. Never preview a smaller crop than export can express.
    let ratio = result.width / max(0.001, result.height)
    let base = self.rect(source: source, ratio: ratio, crop: CropConfiguration())
    if result.width < base.width / 20 {
      let width = base.width / 20, height = base.height / 20
      result = CGRect(x: min(source.width - width, max(0, result.midX - width / 2)),
        y: min(source.height - height, max(0, result.midY - height / 2)), width: width, height: height)
    }
    return result
  }
}
