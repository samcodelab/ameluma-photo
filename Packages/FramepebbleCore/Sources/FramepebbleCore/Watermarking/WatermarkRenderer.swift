import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO

public enum WatermarkRenderer {
    public static func stamp(_ w: WatermarkConfiguration, outputWidth: CGFloat) throws -> CIImage {
        if w.kind == .image {
            guard let url = w.imageURL, url.isFileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(1, Int(outputWidth * w.relativeWidth))] as CFDictionary) else { throw ProcessingError.invalidImage }
            let image = CIImage(cgImage: cg); let scale = outputWidth * w.relativeWidth / image.extent.width
            return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let baseFont = CTFontCreateWithName(w.fontName as CFString, 100, nil)
        let attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): baseFont, .init(kCTForegroundColorAttributeName as String): w.colour.cgColor]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: w.text, attributes: attributes))
        var ascent: CGFloat = 0; var descent: CGFloat = 0; var leading: CGFloat = 0
        let length = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        guard length > 0 else { throw ProcessingError.invalidConfiguration }
        let scale = outputWidth * w.relativeWidth / length
        let width = max(1, Int(ceil(length * scale + 4))); let height = max(1, Int(ceil((ascent + descent + leading) * scale + 4)))
        guard width <= 20000, height <= 20000, width * height <= 16_000_000 else { throw ProcessingError.invalidConfiguration }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProcessingError.encoding }
        ctx.translateBy(x: 2, y: 2); ctx.scaleBy(x: scale, y: scale); ctx.textPosition = CGPoint(x: 0, y: descent); CTLineDraw(line, ctx)
        guard let cg = ctx.makeImage() else { throw ProcessingError.encoding }; return CIImage(cgImage: cg)
    }
    /// Anchor rectangles use top-left output coordinates and relative margins.
    public static func placement(size: CGSize, output: CGSize, configuration w: WatermarkConfiguration) -> CGRect {
        let col = w.anchor.rawValue % 3; let row = w.anchor.rawValue / 3
        let margin = CGFloat(w.margin) * min(output.width, output.height)
        let xs = [margin, (output.width - size.width) / 2, output.width - size.width - margin]
        let ys = [margin, (output.height - size.height) / 2, output.height - size.height - margin]
        return CGRect(x: xs[col] + CGFloat(w.offsetX) * output.width, y: ys[row] + CGFloat(w.offsetY) * output.height, width: size.width, height: size.height)
    }
    public static func apply(to image: CIImage, configuration w: WatermarkConfiguration) throws -> CIImage {
        guard w.enabled else { return image }
        guard w.relativeWidth.isFinite, (0.02...1).contains(w.relativeWidth), w.opacity.isFinite, (0...1).contains(w.opacity), w.margin.isFinite, (0...0.4).contains(w.margin), w.rotation.isFinite, abs(w.rotation) <= 360, w.offsetX.isFinite, abs(w.offsetX) <= 1, w.offsetY.isFinite, abs(w.offsetY) <= 1, [w.colour.red, w.colour.green, w.colour.blue, w.colour.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }), w.kind != .text || (!w.text.isEmpty && w.text.count <= 1024 && !w.fontName.isEmpty) else { throw ProcessingError.invalidConfiguration }
        var mark = try stamp(w, outputWidth: image.extent.width)
        mark = mark.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(w.rotation) * .pi / 180))
        mark = mark.transformed(by: CGAffineTransform(translationX: -mark.extent.minX, y: -mark.extent.minY))
        mark = mark.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: w.opacity)])
        var result = image
        if w.tiled {
            let dx = max(mark.extent.width * 1.8, image.extent.width * 0.05)
            let dy = max(mark.extent.height * 2.5, image.extent.height * 0.05)
            for y in stride(from: CGFloat(0), to: image.extent.height, by: dy) {
                for x in stride(from: CGFloat(0), to: image.extent.width, by: dx) { result = mark.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: result) }
            }
        } else {
            let p = placement(size: mark.extent.size, output: image.extent.size, configuration: w)
            result = mark.transformed(by: CGAffineTransform(translationX: p.minX, y: image.extent.height - p.maxY)).composited(over: result)
        }
        return result.cropped(to: image.extent)
    }
}
