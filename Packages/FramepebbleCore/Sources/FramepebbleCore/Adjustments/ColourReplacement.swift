import CoreImage
import CoreGraphics
import Foundation
import Vision
import CoreVideo

/// A local, nondestructive colour edit in normalized final-photo coordinates.
/// Deliberately separate from protective privacy masks and their review semantics.
public struct ColourReplacement: Codable, Equatable, Sendable, Identifiable {
  public static let maximumEdits = 16
  public var id = UUID()
  public var points: [NormalizedPoint] = []
  /// Optional fields retain legacy selection rendering when absent in saved documents.
  public var excludedContours: [[NormalizedPoint]]?
  public var constrainFeatherToSelection: Bool? = true
  public var source = RGBAColour(0.8, 0.2, 0.2, 1)
  public var replacement = RGBAColour(0.15, 0.35, 0.85, 1)
  public var range = 0.25
  public var intensity = 1.0
  public var feather = 0.006
  public init() {}
  public func validate() throws {
    guard points.count >= 3, points.count <= 10000,
      points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
      range.isFinite, (0.01...1).contains(range), intensity.isFinite, (0...1).contains(intensity),
      feather.isFinite, (0...0.05).contains(feather),
      [source.red,source.green,source.blue,source.alpha,replacement.red,replacement.green,replacement.blue,replacement.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ProcessingError.invalidConfiguration }
    let holes = excludedContours ?? []
    guard holes.count <= 64, holes.reduce(0, { $0 + $1.count }) <= 10000,
      holes.allSatisfy({ $0.count >= 3 && $0.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) }) else { throw ProcessingError.invalidConfiguration }
    let area = points.indices.reduce(0.0) { sum, i in let n = points[(i+1)%points.count];return sum+points[i].x*n.y-n.x*points[i].y }
    guard abs(area) > 0.00001 else { throw ProcessingError.invalidConfiguration }
  }
}
extension ColourRenderer {
  public static func replace(_ image: CIImage, edits: [ColourReplacement]) throws -> CIImage {
    guard edits.count <= ColourReplacement.maximumEdits else { throw ProcessingError.invalidConfiguration }
    var result = image
    for edit in edits {
      try Task.checkCancellation(); try edit.validate()
      guard edit.intensity > 0 else { continue }
      // Coverage maps are bounded independently of source dimensions and edit count.
      let scale = min(1, 2048 / max(image.extent.width, image.extent.height))
      let width = max(1, Int((image.extent.width * scale).rounded())), height = max(1, Int((image.extent.height * scale).rounded()))
      guard width > 0, height > 0, let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { throw ProcessingError.encoding }
      c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1)
      c.setFillColor(gray:0,alpha:1);c.fill(CGRect(x:0,y:0,width:width,height:height));c.setFillColor(gray:1,alpha:1)
      let path = CGMutablePath()
      for (i,p) in edit.points.enumerated() { let point = CGPoint(x:p.x*Double(width),y:p.y*Double(height)); if i==0 { path.move(to:point) } else { path.addLine(to:point) } }
      path.closeSubpath()
      c.saveGState(); c.addPath(path); c.clip(); c.addPath(path)
      for hole in edit.excludedContours ?? [] {
        let cutout = CGMutablePath()
        for (i, p) in hole.enumerated() {
          let point = CGPoint(x: p.x * Double(width), y: p.y * Double(height))
          if i == 0 { cutout.move(to: point) } else { cutout.addLine(to: point) }
        }
        cutout.closeSubpath(); c.addPath(cutout)
      }
      c.fillPath(using: .evenOdd); c.restoreGState()
      guard let bitmap = c.makeImage() else { throw ProcessingError.encoding }
      var mask = CIImage(cgImage:bitmap, options: [.colorSpace: NSNull()]).transformed(by:CGAffineTransform(scaleX:image.extent.width/CGFloat(width),y:image.extent.height/CGFloat(height))).transformed(by:CGAffineTransform(translationX:image.extent.minX,y:image.extent.minY))
      if edit.feather > 0 {
        let hardMask = mask
        mask = mask.clampedToExtent().applyingGaussianBlur(sigma:edit.feather*Double(min(image.extent.width,image.extent.height))).cropped(to:image.extent)
        if edit.constrainFeatherToSelection == true {
          mask = mask.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: hardMask])
        }
      }
      let from = CIVector(x:edit.source.red,y:edit.source.green,z:edit.source.blue)
      let to = CIVector(x:edit.replacement.red,y:edit.replacement.green,z:edit.replacement.blue)
      guard let space = CGColorSpace(name: CGColorSpace.sRGB), let input = result.matchedFromWorkingSpace(to: space),
        let output = try kernel("replaceColour").apply(extent:image.extent,arguments:[input,mask,from,to,edit.range,edit.intensity]),
        let matched = output.matchedToWorkingSpace(from: space) else { throw ColourToolError.kernel }
      result = matched
    }
    return result
  }
}

public struct ColourObjectOutline: Sendable {
  public var points: [NormalizedPoint]
  public var holes: [[NormalizedPoint]]
}

extension ImageProcessor {
  /// Local Vision instance selection. Only the tapped instance is returned; no whole-scene fallback.
  public func colourObjectOutline(_ image: CGImage, at point: NormalizedPoint, within boundary: [NormalizedPoint]? = nil) throws -> ColourObjectOutline {
    guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else { throw ProcessingError.invalidConfiguration }
    try Task.checkCancellation()
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try handler.perform([request])
    try Task.checkCancellation()
    guard let observation = request.results?.first else { throw ProcessingError.invalidImage }
    let instances = observation.instanceMask
    guard CVPixelBufferGetPixelFormatType(instances) == kCVPixelFormatType_OneComponent8 else { throw ProcessingError.invalidImage }
    CVPixelBufferLockBaseAddress(instances, .readOnly)
    let identifier: UInt8
    if let bytes = CVPixelBufferGetBaseAddress(instances)?.assumingMemoryBound(to: UInt8.self) {
      let x = min(CVPixelBufferGetWidth(instances)-1, Int(point.x * Double(CVPixelBufferGetWidth(instances))))
      let y = min(CVPixelBufferGetHeight(instances)-1, Int(point.y * Double(CVPixelBufferGetHeight(instances))))
      identifier = bytes[y * CVPixelBufferGetBytesPerRow(instances) + x]
    } else { identifier = 0 }
    CVPixelBufferUnlockBaseAddress(instances, .readOnly)
    guard identifier > 0, observation.allInstances.contains(Int(identifier)) else { throw ProcessingError.invalidImage }
    let mask = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: Int(identifier)), from: handler)
    try Task.checkCancellation()
    let contours = VNDetectContoursRequest(); contours.detectsDarkOnLight = false; contours.maximumImageDimension = 1024
    // Foreground instances can group fruit with adjacent leaves. Restrict edge finding
    // to the sampled colour family, then close tiny texture gaps before tracing.
    let sampleX = min(image.width-1, Int(point.x * Double(image.width)))
    let sampleY = min(image.height-1, Int(point.y * Double(image.height)))
    guard let pixel = image.cropping(to: CGRect(x: sampleX, y: sampleY, width: 1, height: 1)) else { throw ProcessingError.invalidImage }
    var bytes = [UInt8](repeating: 0, count: 4)
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { throw ProcessingError.encoding }
    let sampled = bytes.withUnsafeMutableBytes { storage -> Bool in
      guard let bitmap = CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      bitmap.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
    }
    guard sampled, bytes[3] > 0 else { throw ProcessingError.invalidImage }
    let alpha = Double(bytes[3])
    let reference = CIVector(x: Double(bytes[0])/alpha, y: Double(bytes[1])/alpha, z: Double(bytes[2])/alpha)
    guard let input = CIImage(cgImage: image).matchedFromWorkingSpace(to: srgb),
      let guidance = try ColourRenderer.kernel("colourSelection").apply(extent: input.extent, arguments: [input, reference]) else { throw ColourToolError.kernel }
    let radius = max(1, min(input.extent.width, input.extent.height) * 0.003)
    let closed = guidance.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
      .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius]).cropped(to: input.extent)
    let objectMask = CIImage(cvPixelBuffer: mask).applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: closed])
    if let boundary, !boundary.isEmpty {
      var selection = ColourReplacement(); selection.points = boundary; try selection.validate()
      let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
      guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ProcessingError.encoding }
      let path = CGMutablePath()
      for (i, p) in boundary.enumerated() {
        let q = CGPoint(x: p.x * Double(width), y: (1-p.y) * Double(height))
        if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
      }
      path.closeSubpath(); bitmap.addPath(path); bitmap.setFillColor(gray: 1, alpha: 1); bitmap.fillPath()
      guard let limit = bitmap.makeImage() else { throw ProcessingError.encoding }
      let clipped = objectMask.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: CIImage(cgImage: limit, options: [.colorSpace: NSNull()])])
      try VNImageRequestHandler(ciImage: clipped, orientation: .up).perform([contours])
    } else { try VNImageRequestHandler(ciImage: objectMask, orientation: .up).perform([contours]) }
    try Task.checkCancellation()
    let seed = CGPoint(x: point.x, y: 1 - point.y)
    guard let contour = contours.results?.first?.topLevelContours.first(where: { $0.normalizedPath.contains(seed) }) else { throw ProcessingError.invalidImage }
    func points(_ contour: VNContour) throws -> [NormalizedPoint] {
      let simple = try contour.polygonApproximation(epsilon: 0.0007)
      guard simple.pointCount <= 10000 else { throw ProcessingError.invalidConfiguration }
      return simple.normalizedPoints.map { NormalizedPoint(Double($0.x), 1 - Double($0.y)) }
    }
    let result = ColourObjectOutline(points: try points(contour), holes: try contour.childContours.filter {
      let bounds = $0.normalizedPath.boundingBox
      return $0.pointCount >= 3 && bounds.width * bounds.height >= 0.0005
    }.map { try points($0) })
    var edit = ColourReplacement(); edit.points = result.points; edit.excludedContours = result.holes
    try edit.validate()
    return result
  }
}
