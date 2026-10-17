import Foundation
import CoreGraphics
import CoreImage

public enum RetouchMode: String, Codable, CaseIterable, Sendable { case remove = "Remove", heal = "Heal", clone = "Clone" }
/// Final-output, top-left normalized coordinates. Each stroke captures its own brush and source offset.
public struct RetouchStroke: Codable, Equatable, Sendable, Identifiable {
  public var id = UUID()
  public var mode: RetouchMode = .heal
  /// Absent in older projects: preserve the original automatic sampling algorithm.
  public var samplingVersion: Int? = 2
  public var points: [NormalizedPoint] = []
  public var source: NormalizedPoint?
  public var diameter = 0.03
  public var hardness = 0.5
  public var opacity = 1.0
  public init() {}
}

public enum RetouchRenderer {
  private static let healing: Result<CIColorKernel, Error> = Result {
    let kernels = try CIKernel.kernels(withMetalString: """
      #include <CoreImage/CoreImage.h>
      using namespace metal;
      [[stitchable]] float4 amelumaHeal(coreimage::sample_t texture, coreimage::sample_t sourceLow, coreimage::sample_t destinationLow) {
          return float4(texture.rgb + destinationLow.rgb - sourceLow.rgb, texture.a);
      }
      """)
    guard let kernel = kernels.first as? CIColorKernel else { throw ProcessingError.encoding }
    return kernel
  }
  private static let boundaryHealing: Result<CIColorKernel, Error> = Result {
    let kernels = try CIKernel.kernels(withMetalString: """
      #include <CoreImage/CoreImage.h>
      using namespace metal;
      [[stitchable]] float4 amelumaBoundaryHeal(coreimage::sample_t texture, coreimage::sample_t sourceLow, coreimage::sample_t destinationWeighted, coreimage::sample_t weights) {
        float weight = max(weights.r, 0.0001f);
        return float4(texture.rgb + destinationWeighted.rgb / weight - sourceLow.rgb, texture.a);
      }
      """)
    guard let kernel = kernels.first as? CIColorKernel else { throw ProcessingError.encoding }
    return kernel
  }
  private static let weighting: Result<CIColorKernel, Error> = Result {
    let kernels = try CIKernel.kernels(withMetalString: """
      #include <CoreImage/CoreImage.h>
      using namespace metal;
      [[stitchable]] float4 amelumaHealingWeight(coreimage::sample_t image, coreimage::sample_t mask) {
        return image * mask.r;
      }
      """)
    guard let kernel = kernels.first as? CIColorKernel else { throw ProcessingError.encoding }
    return kernel
  }
  public static func apply(to source: CIImage, strokes: [RetouchStroke], context: CIContext, sourceMasks: [PrivacyMask] = []) throws -> CIImage {
    guard source.extent.width.isFinite, source.extent.height.isFinite,
      source.extent.width > 0, source.extent.height > 0, source.extent.width <= 20000, source.extent.height <= 20000,
      source.extent.width * source.extent.height <= 100_000_000,
      strokes.count <= 200 else { throw ProcessingError.invalidConfiguration }
    var image = source
    let bounds = source.extent, edge = min(bounds.width, bounds.height)
    for (index, stroke) in strokes.enumerated() {
      try Task.checkCancellation()
      guard !stroke.points.isEmpty, stroke.points.count <= 2000,
        [stroke.diameter, stroke.hardness, stroke.opacity].allSatisfy(\.isFinite),
        (0.00005...0.4).contains(stroke.diameter), (0...1).contains(stroke.hardness), (0...1).contains(stroke.opacity),
        stroke.points.allSatisfy({ valid($0) }), stroke.source.map(valid) ?? true
      else { throw ProcessingError.invalidConfiguration }
      guard let first = stroke.points.first else { continue }
      if stroke.opacity == 0 { continue }
      if stroke.mode == .remove {
        image = try LocalInpainting.apply(image, stroke: stroke, context: context, masks: sourceMasks)
        continue
      }
      let radius = max(0.5, edge * stroke.diameter / 2)
      func point(_ p: NormalizedPoint) -> CGPoint {
        CGPoint(x: bounds.minX + p.x * bounds.width, y: bounds.maxY - p.y * bounds.height)
      }
      let destination = point(first)
      let sample: CGPoint
      if let selected = stroke.source { sample = point(selected) }
      else {
        guard stroke.mode == .heal else { throw ProcessingError.invalidConfiguration }
        if stroke.samplingVersion == 3 { sample = try strokeSample(image, points: stroke.points.map(point), radius: radius, context: context) }
        else { sample = try (stroke.samplingVersion == 2 ? nearbySample(image, destination: destination, radius: radius, context: context) : legacyNearbySample(image, destination: destination, radius: radius, context: context)) }
      }
      let offset = CGAffineTransform(translationX: destination.x - sample.x, y: destination.y - sample.y)
      // Sampling must never copy uncensored pixels from beneath a visible privacy mask.
      let protectedSource = try PrivacyRenderer.apply(to: image, masks: sourceMasks)
      let sampled = protectedSource.transformed(by: offset)
      let path = CGMutablePath()
      path.move(to: destination)
      for p in stroke.points.dropFirst() { path.addLine(to: point(p)) }
      let locations = stroke.points.map(point)
      let xs = locations.map(\.x), ys = locations.map(\.y)
      let box = CGRect(x: xs.min() ?? destination.x, y: ys.min() ?? destination.y,
                       width: max(1, (xs.max() ?? destination.x) - (xs.min() ?? destination.x)),
                       height: max(1, (ys.max() ?? destination.y) - (ys.min() ?? destination.y)))
      let roi = box.insetBy(dx: -radius * 2, dy: -radius * 2).integral.intersection(bounds)
      guard !roi.isEmpty, roi.width <= 20000, roi.height <= 20000 else { continue }
      guard let bitmap = CGContext(data: nil, width: Int(roi.width), height: Int(roi.height), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ProcessingError.encoding }
      bitmap.translateBy(x: -roi.minX, y: -roi.minY)
      bitmap.setFillColor(gray: stroke.opacity, alpha: 1)
      bitmap.setStrokeColor(gray: stroke.opacity, alpha: 1)
      bitmap.setLineWidth(radius * 2); bitmap.setLineCap(.round); bitmap.setLineJoin(.round)
      if stroke.points.allSatisfy({ $0.x == first.x && $0.y == first.y }) { bitmap.fillEllipse(in: CGRect(x: destination.x-radius, y: destination.y-radius, width: radius*2, height: radius*2)) }
      else { bitmap.addPath(path); bitmap.strokePath() }
      guard let maskImage = bitmap.makeImage() else { throw ProcessingError.encoding }
      var mask = CIImage(cgImage: maskImage, options: stroke.samplingVersion == 3 ? [.colorSpace: NSNull()] : [:]).transformed(by: CGAffineTransform(translationX: roi.minX, y: roi.minY))
      if stroke.hardness < 1 { mask = mask.applyingGaussianBlur(sigma: (1 - stroke.hardness) * radius * 0.35) }
      let validSource = bounds.applying(offset).intersection(bounds)
      mask = mask.cropped(to: validSource.intersection(roi))
      var replacement = sampled
      if stroke.mode == .heal {
        if stroke.samplingVersion == 3 {
          let blur = max(1, radius * 0.85)
          let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)
          // Remove the painted pixels from low-frequency estimation: their unwanted
          // colour must not be blended straight back into the healed result.
          let coverage = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1/max(0.0001, stroke.opacity), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1/max(0.0001, stroke.opacity), z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1/max(0.0001, stroke.opacity), w: 0)])
            .composited(over: black).cropped(to: bounds)
          let excluded = coverage.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.01])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(1, radius * 0.15)])
          let unpainted = excluded.applyingFilter("CIColorInvert")
          guard let weighted = try weighting.get().apply(extent: bounds, arguments: [image, unpainted]) else { throw ProcessingError.encoding }
          let kernel = try boundaryHealing.get()
          guard let healed = kernel.apply(extent: roi, arguments: [sampled,
            protectedSource.clampedToExtent().applyingGaussianBlur(sigma: blur).transformed(by: offset),
            weighted.clampedToExtent().applyingGaussianBlur(sigma: blur),
            unpainted.clampedToExtent().applyingGaussianBlur(sigma: blur)]) else { throw ProcessingError.encoding }
          replacement = healed
        } else {
          let blur = max(1, radius * 0.65)
          let kernel = try healing.get()
          guard let healed = kernel.apply(extent: roi, arguments: [sampled,
            protectedSource.clampedToExtent().applyingGaussianBlur(sigma: blur).transformed(by: offset),
            image.clampedToExtent().applyingGaussianBlur(sigma: blur)]) else { throw ProcessingError.encoding }
          replacement = healed
        }
      }
      image = replacement.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]).cropped(to: bounds)
      // Bound the deferred filter graph for longer projects. No app-specific frameworks or full batch buffers.
      if (index + 1) % 8 == 0 {
        guard let flattened = context.createCGImage(image, from: bounds, format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)) else { throw ProcessingError.encoding }
        image = CIImage(cgImage: flattened).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
      }
    }
    try Task.checkCancellation()
    return image
  }
  public static func suggestedSource(in image: CGImage, at point: NormalizedPoint, diameter: Double, context: CIContext) throws -> NormalizedPoint {
    guard valid(point), diameter.isFinite, (0.00005...0.4).contains(diameter) else { throw ProcessingError.invalidConfiguration }
    let source = CIImage(cgImage: image)
    let sample = try nearbySample(source, destination: CGPoint(x: point.x * source.extent.width, y: (1-point.y) * source.extent.height),
      radius: max(0.5, min(source.extent.width, source.extent.height) * diameter / 2), context: context)
    return NormalizedPoint(sample.x / source.extent.width, 1 - sample.y / source.extent.height)
  }
  public static func suggestedSource(in image: CGImage, points: [NormalizedPoint], diameter: Double, context: CIContext) throws -> NormalizedPoint {
    guard !points.isEmpty, points.count <= 2000, points.allSatisfy(valid), diameter.isFinite, (0.00005...0.4).contains(diameter) else { throw ProcessingError.invalidConfiguration }
    let input = CIImage(cgImage: image), bounds = input.extent
    let source = try strokeSample(input, points: points.map { CGPoint(x: $0.x * bounds.width, y: (1-$0.y) * bounds.height) }, radius: max(0.5, min(bounds.width,bounds.height) * diameter / 2), context: context)
    return NormalizedPoint(source.x / bounds.width, 1 - source.y / bounds.height)
  }

  /// Match the entire painted path's boundary, rejecting translated samples that cross
  /// any part of the removal area. A single bounded readback serves every candidate.
  private static func strokeSample(_ image: CIImage, points: [CGPoint], radius: CGFloat, context: CIContext) throws -> CGPoint {
    guard let first = points.first else { throw ProcessingError.invalidConfiguration }
    let strideSize = max(1, points.count / 64)
    var path = stride(from: 0, to: points.count, by: strideSize).map { points[$0] }
    if path.last != points.last, let last = points.last { path.append(last) }
    let box = path.reduce(CGRect(origin: first, size: CGSize(width: 1, height: 1))) { $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1))) }
    let region = box.insetBy(dx: -radius*13, dy: -radius*13).intersection(image.extent)
    let scale = min(1, 512 / max(region.width, region.height))
    let width = max(1, Int(ceil(region.width*scale))), height = max(1, Int(ceil(region.height*scale)))
    var pixels = [Float](repeating: 0, count: width*height*4)
    let analysis = image.transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    context.render(analysis, toBitmap: &pixels, rowBytes: width*16, bounds: CGRect(x:0,y:0,width:width,height:height), format:.RGBAf, colorSpace:CGColorSpace(name:CGColorSpace.linearSRGB))
    func pixel(_ point: CGPoint) -> SIMD3<Float>? {
      guard region.contains(point), image.extent.contains(point) else { return nil }
      let x = min(width-1,max(0,Int((point.x-region.minX)*scale))), y = min(height-1,max(0,Int((point.y-region.minY)*scale)))
      let i = (y*width+x)*4
      guard pixels[i+3] > 0.95 else { return nil }
      return SIMD3(pixels[i],pixels[i+1],pixels[i+2])
    }
    func paintedDistance(_ p: CGPoint) -> CGFloat {
      var nearest = hypot(p.x-first.x,p.y-first.y)
      for (a,b) in zip(path,path.dropFirst()) {
        let dx=b.x-a.x,dy=b.y-a.y, length=dx*dx+dy*dy
        let t=length>0 ? min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) : 0
        nearest=min(nearest,hypot(p.x-a.x-t*dx,p.y-a.y-t*dy))
      }
      return nearest
    }
    let anchors = stride(from: 0, to: path.count, by: max(1,path.count/10)).map { path[$0] }
    var boundary: [(CGPoint,SIMD3<Float>)] = []
    for anchor in anchors { for index in 0..<12 {
      let angle=Double(index)*Double.pi/6
      let p=CGPoint(x:anchor.x+cos(angle)*radius*1.6,y:anchor.y+sin(angle)*radius*1.6)
      if paintedDistance(p)>radius*1.1,let colour=pixel(p) { boundary.append((p,colour)) }
    } }
    guard !boundary.isEmpty else { throw ProcessingError.invalidConfiguration }
    var best: CGPoint?, score = Float.infinity
    for distance in [3.0,4.5,6.5,9.0,12.0] { for direction in 0..<24 {
      try Task.checkCancellation()
      let angle=Double(direction)*Double.pi/12
      let dx=cos(angle)*radius*distance,dy=sin(angle)*radius*distance
      guard anchors.allSatisfy({ p in let q=CGPoint(x:p.x+dx,y:p.y+dy);return image.extent.insetBy(dx:radius,dy:radius).contains(q) && paintedDistance(q)>radius*2.5 }) else { continue }
      var error=Float(0),count=0
      for (p,target) in boundary {
        guard let candidate=pixel(CGPoint(x:p.x+dx,y:p.y+dy)) else { continue }
        let difference=candidate-target
        error += difference.x*difference.x+difference.y*difference.y+difference.z*difference.z;count += 1
      }
      guard count >= max(1,boundary.count*3/4) else { continue }
      let candidateScore=error/Float(count)+Float(distance)*0.00001
      if candidateScore<score { score=candidateScore;best=CGPoint(x:first.x+dx,y:first.y+dy) }
    } }
    guard let best else { throw ProcessingError.invalidConfiguration }
    return best
  }
  private static func valid(_ p: NormalizedPoint) -> Bool {
    p.x.isFinite && p.y.isFinite && (0...1).contains(p.x) && (0...1).contains(p.y)
  }
  /// Version 2: compare the material surrounding the blemish, never the blemish itself.
  /// One bounded linear-RGB analysis bitmap serves all candidates (no per-candidate GPU reads).
  private static func nearbySample(_ image: CIImage, destination: CGPoint, radius: CGFloat, context: CIContext) throws -> CGPoint {
    let region = CGRect(x: destination.x - radius * 7, y: destination.y - radius * 7,
                        width: radius * 14, height: radius * 14).intersection(image.extent)
    guard !region.isEmpty else { throw ProcessingError.invalidConfiguration }
    let scale = min(1, 256 / max(region.width, region.height))
    let width = max(1, Int(ceil(region.width * scale))), height = max(1, Int(ceil(region.height * scale)))
    let analysis = image.transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    var pixels = [Float](repeating: 0, count: width * height * 4)
    context.render(analysis, toBitmap: &pixels, rowBytes: width * 16,
      bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf,
      colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
    func pixel(_ point: CGPoint) -> [Float]? {
      guard image.extent.contains(point) else { return nil }
      let x = min(width - 1, max(0, Int((point.x - region.minX) * scale)))
      let y = min(height - 1, max(0, Int((point.y - region.minY) * scale)))
      let i = (y * width + x) * 4
      guard pixels[i+3] > 0.95 else { return nil }
      return Array(pixels[i..<i+3])
    }
    func signature(_ center: CGPoint, rings: [Double]) -> [Float]? {
      var samples: [[Float]] = []
      for ring in rings {
        for index in 0..<24 {
          let angle = Double(index) * .pi / 12
          if let colour = pixel(CGPoint(x: center.x + cos(angle) * radius * ring,
                                        y: center.y + sin(angle) * radius * ring)) { samples.append(colour) }
        }
      }
      guard samples.count >= 24 else { return nil }
      // Median resists isolated edges/highlights; spread rejects texture from another material.
      let median = (0..<3).map { channel in samples.map { $0[channel] }.sorted()[samples.count / 2] }
      let spread = (0..<3).map { channel in samples.reduce(Float(0)) { $0 + abs($1[channel] - median[channel]) } / Float(samples.count) }
      return median + spread
    }
    guard let target = signature(destination, rings: [1.35, 1.75]) else {
      return try legacyNearbySample(image, destination: destination, radius: radius, context: context)
    }
    var best: CGPoint?, bestScore = Float.infinity
    for distance in [2.6, 3.5, 4.5] {
      for direction in 0..<24 {
        try Task.checkCancellation()
        let angle = Double(direction) * .pi / 12
        let candidate = CGPoint(x: destination.x + cos(angle) * radius * distance,
                                y: destination.y + sin(angle) * radius * distance)
        guard image.extent.insetBy(dx: radius * 1.8, dy: radius * 1.8).contains(candidate),
              let material = signature(candidate, rings: [0.4, 0.8, 1.35]) else { continue }
        let colour = (0..<3).reduce(Float(0)) { $0 + pow(material[$1] - target[$1], 2) }
        let texture = (3..<6).reduce(Float(0)) { $0 + pow(material[$1] - target[$1], 2) }
        let score = colour + 0.5 * texture + Float(distance) * 0.00002
        if score < bestScore { bestScore = score; best = candidate }
      }
    }
    guard let best else { return try legacyNearbySample(image, destination: destination, radius: radius, context: context) }
    return best
  }
  /// Nearby color-compatible texture, excluding the painted stroke's initial neighbourhood.
  private static func legacyNearbySample(_ image: CIImage, destination: CGPoint, radius: CGFloat, context: CIContext) throws -> CGPoint {
    func mean(_ center: CGPoint) -> [Float] {
      let rect = CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2).intersection(image.extent)
      let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
      var pixel = [Float](repeating: 0, count: 4)
      context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
      return pixel
    }
    let target = mean(destination)
    var best: CGPoint?, score = Float.infinity
    for direction in 0..<8 {
      try Task.checkCancellation()
      let angle = Double(direction) * .pi / 4
      let candidate = CGPoint(x: destination.x + cos(angle) * radius * 2.1, y: destination.y + sin(angle) * radius * 2.1)
      guard image.extent.insetBy(dx: radius, dy: radius).contains(candidate) else { continue }
      let colour = mean(candidate)
      let distance = (0..<3).reduce(Float(0)) { $0 + pow(colour[$1] - target[$1], 2) }
      if distance < score { score = distance; best = candidate }
    }
    guard let best else { throw ProcessingError.invalidConfiguration }
    return best
  }
}
