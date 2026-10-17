import Foundation
import CoreImage
import CoreGraphics

public enum RemovalError: Error, LocalizedError {
  case insufficientContext, regionTooLarge
  public var errorDescription: String? {
    switch self {
    case .insufficientContext: "There isn’t enough clean surrounding texture. Try a smaller area, or use Clone to guide the repair."
    case .regionTooLarge: "Remove smaller sections separately for a more reliable result."
    }
  }
}

/// Version 1 local exemplar reconstruction. Fixed search order; no random or network input.
/// Synthesizes only the marked region from unmarked patches. Analysis is capped at 768px;
/// the final blend retains every pixel outside the brush and the destination alpha.
/// This is texture/edge continuation, not semantic or generative reconstruction.
enum LocalInpainting {
  static func apply(_ image: CIImage, stroke: RetouchStroke, context: CIContext, masks: [PrivacyMask]) throws -> CIImage {
    guard stroke.samplingVersion == 1 else { throw ProcessingError.invalidConfiguration }
    let bounds = image.extent, edge = min(bounds.width, bounds.height)
    let radius = max(0.5, edge * stroke.diameter / 2)
    let points = stroke.points.map { CGPoint(x: bounds.minX + $0.x*bounds.width, y: bounds.maxY - $0.y*bounds.height) }
    guard let first = points.first else { throw ProcessingError.invalidConfiguration }
    let box = points.reduce(CGRect(origin: first, size: CGSize(width: 1, height: 1))) { $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1))) }
    let roi = box.insetBy(dx: -max(32,radius*10), dy: -max(32,radius*10)).integral.intersection(bounds)
    let scale = min(1, 768 / max(roi.width,roi.height))
    let width = max(1,Int(ceil(roi.width*scale))), height = max(1,Int(ceil(roi.height*scale)))
    let sx = CGFloat(width)/roi.width, sy = CGFloat(height)/roi.height
    guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ProcessingError.encoding }
    bitmap.scaleBy(x: sx, y: sy); bitmap.translateBy(x: -roi.minX, y: -roi.minY)
    bitmap.setFillColor(gray: 1, alpha: 1); bitmap.setStrokeColor(gray: 1, alpha: 1)
    bitmap.setLineWidth(radius*2); bitmap.setLineCap(.round); bitmap.setLineJoin(.round)
    if points.count == 1 || points.allSatisfy({ $0 == first }) { bitmap.fillEllipse(in: CGRect(x:first.x-radius,y:first.y-radius,width:radius*2,height:radius*2)) }
    else { bitmap.move(to:first); for point in points.dropFirst() { bitmap.addLine(to:point) }; bitmap.strokePath() }
    guard let cgMask = bitmap.makeImage() else { throw ProcessingError.encoding }
    let mask = CIImage(cgImage:cgMask,options:[.colorSpace:NSNull()])
    let protected = try PrivacyRenderer.apply(to:image,masks:masks)
    let analysis = protected.transformed(by:CGAffineTransform(translationX:-roi.minX,y:-roi.minY)).transformed(by:CGAffineTransform(scaleX:sx,y:sy))
    let space = CGColorSpace(name:CGColorSpace.sRGB)!
    var pixels = [UInt8](repeating:0,count:width*height*4)
    var coverage = [UInt8](repeating:0,count:width*height*4)
    let rect = CGRect(x:0,y:0,width:width,height:height)
    context.render(analysis,toBitmap:&pixels,rowBytes:width*4,bounds:rect,format:.RGBA8,colorSpace:space)
    context.render(mask,toBitmap:&coverage,rowBytes:width*4,bounds:rect,format:.RGBA8,colorSpace:nil)
    let original = pixels
    var unknown = (0..<width*height).map { coverage[$0*4] > 0 }
    var confidence=unknown.map { $0 ? Float(0):Float(1) }
    let targets = unknown.indices.filter { unknown[$0] }
    guard !targets.isEmpty else { return image }
    guard targets.count < width*height/2 else { throw RemovalError.regionTooLarge }
    let patch = min(32,max(5,Int(radius*scale*1.2)))
    let fillRadius=max(2,patch/3)
    // Integral image disallows source patches containing any original removal pixels.
    let stride = width+1
    var integral = [Int](repeating:0,count:(width+1)*(height+1))
    for y in 0..<height { for x in 0..<width {
      let bad = unknown[y*width+x] || original[(y*width+x)*4+3] < 250
      integral[(y+1)*stride+x+1] = (bad ? 1:0)+integral[y*stride+x+1]+integral[(y+1)*stride+x]-integral[y*stride+x]
    } }
    func clean(_ x:Int,_ y:Int) -> Bool {
      guard x >= patch, y >= patch, x+patch < width, y+patch < height else { return false }
      let x0=x-patch,y0=y-patch,x1=x+patch+1,y1=y+patch+1
      return integral[y1*stride+x1]-integral[y0*stride+x1]-integral[y1*stride+x0]+integral[y0*stride+x0] == 0
    }
    let step = max(2,max(width,height)/64)
    var sources: [(Int,Int)] = []
    for y in Swift.stride(from:patch,to:height-patch,by:step) {
      for x in Swift.stride(from:patch,to:width-patch,by:step) { if clean(x,y) { sources.append((x,y)) } }
    }
    guard !sources.isEmpty else { throw RemovalError.insufficientContext }
    func luminance(_ index:Int) -> Float { Float(pixels[index*4])*0.2126 + Float(pixels[index*4+1])*0.7152 + Float(pixels[index*4+2])*0.0722 }
    var remaining = targets.count, iterations = 0
    while remaining > 0 {
      try Task.checkCancellation()
      iterations += 1
      guard iterations <= 8192 else { throw RemovalError.regionTooLarge }
      var chosen: Int?, priority = -Float.infinity
      for index in targets where unknown[index] {
        let x=index%width,y=index/width
        var known=0,confidenceSum:Float=0,gx:Float=0,gy:Float=0,strongest:Float=0
        for (dx,dy) in [(0,-1),(-1,0),(1,0),(0,1)] {
          let xx=x+dx,yy=y+dy
          if xx>0 && xx+1<width && yy>0 && yy+1<height && !unknown[yy*width+xx] {
            known += 1
            let q=yy*width+xx;confidenceSum += confidence[q]
            if !unknown[q-1] && !unknown[q+1] && !unknown[q-width] && !unknown[q+width] {
              let dx=luminance(q+1)-luminance(q-1),dy=luminance(q+width)-luminance(q-width)
              let strength=dx*dx+dy*dy
              if strength>strongest { strongest=strength;gx=dx;gy=dy }
            }
          }
        }
        func missing(_ x:Int,_ y:Int)->Float { x>=0 && x<width && y>=0 && y<height && unknown[y*width+x] ? 1:0 }
        let nx=missing(x+1,y)-missing(x-1,y),ny=missing(x,y+1)-missing(x,y-1)
        // Continue isophotes through the fill front, rather than extending background
        // across a high-contrast branch merely because it has more texture.
        let score=(confidenceSum/4)*(abs(gx*ny-gy*nx)/255+0.001)
        if known>0 && score>priority { priority=score;chosen=index }
      }
      guard let target=chosen else { throw RemovalError.insufficientContext }
      let tx=target%width,ty=target/width
      var samples: [(Int,Int,Int)] = []
      let samplingStep=max(1,patch/8)
      for dy in Swift.stride(from:-patch,through:patch,by:samplingStep) { for dx in Swift.stride(from:-patch,through:patch,by:samplingStep) {
        let x=tx+dx,y=ty+dy
        if x>=0 && x<width && y>=0 && y<height && !unknown[y*width+x] { samples.append((dx,dy,(y*width+x)*4)) }
      } }
      guard !samples.isEmpty else { throw RemovalError.insufficientContext }
      func error(_ x:Int,_ y:Int,_ limit:Float) -> Float {
        var total:Float=0
        for (dx,dy,i) in samples {
          let j=((y+dy)*width+x+dx)*4
          let r=Float(pixels[i])-Float(original[j]),g=Float(pixels[i+1])-Float(original[j+1]),b=Float(pixels[i+2])-Float(original[j+2])
          total += (r*r+g*g+b*b)*max(0.05,confidence[i/4])
          if total>limit { break }
        }
        return total
      }
      var best=sources[0],bestError=Float.infinity
      for (i,candidate) in sources.enumerated() {
        if i%128 == 0 { try Task.checkCancellation() }
        let score=error(candidate.0,candidate.1,bestError)
        if score<bestError { bestError=score;best=candidate }
      }
      let coarse=best
      for y in max(patch,coarse.1-step)...min(height-patch-1,coarse.1+step) {
        for x in max(patch,coarse.0-step)...min(width-patch-1,coarse.0+step) where clean(x,y) {
          let score=error(x,y,bestError)
          if score<bestError { bestError=score;best=(x,y) }
        }
      }
      let fillConfidence=samples.reduce(Float(0)) { $0+confidence[$1.2/4] }/Float((patch*2+1)*(patch*2+1))
      for dy in -fillRadius...fillRadius { for dx in -fillRadius...fillRadius {
        let x=tx+dx,y=ty+dy
        guard x>=0 && x<width && y>=0 && y<height else { continue }
        let index=y*width+x
        if unknown[index] {
          let sample=((best.1+dy)*width+best.0+dx)*4
          for channel in 0..<3 { pixels[index*4+channel]=UInt8(Int(original[sample+channel])*Int(original[index*4+3])/255) }
          // Keep destination alpha; source patches must be opaque.
          unknown[index]=false;confidence[index]=max(0.05,fillConfidence);remaining-=1
        }
      } }
    }
    try Task.checkCancellation()
    let rebuilt = CIImage(bitmapData:Data(pixels),bytesPerRow:width*4,size:CGSize(width:width,height:height),format:.RGBA8,colorSpace:space)
      .transformed(by:CGAffineTransform(scaleX:1/sx,y:1/sy)).transformed(by:CGAffineTransform(translationX:roi.minX,y:roi.minY)).cropped(to:roi)
    var outputMask = mask.transformed(by:CGAffineTransform(scaleX:1/sx,y:1/sy)).transformed(by:CGAffineTransform(translationX:roi.minX,y:roi.minY))
    // Feather only inside the painted region, never outside it.
    if stroke.hardness < 1 {
      outputMask = outputMask.applyingGaussianBlur(sigma:max(0.25,(1-stroke.hardness)*radius*0.15))
        .applyingFilter("CIMinimumCompositing",parameters:[kCIInputBackgroundImageKey:outputMask])
    }
    outputMask = outputMask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:stroke.opacity,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:stroke.opacity,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:stroke.opacity,w:0)])
    return rebuilt.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:outputMask]).cropped(to:bounds)
  }
}
