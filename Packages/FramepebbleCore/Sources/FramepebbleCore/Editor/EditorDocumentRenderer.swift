import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Layer orchestration reuses the existing photo recipes and export encoder. It does not edit sources.
public actor EditorDocumentRenderer {
  private let processor=ImageProcessor()
  private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.sRGB)!, .workingFormat:CIFormat.RGBAh,.cacheIntermediates:false])
  private struct ContentKey:Equatable {
    var content:EditorLayerContent;var width:Double;var height:Double;var scale:Double
    var sourceURL:URL?;var fingerprint:SourceFingerprint?;var watermarkURL:URL?;var watermarkFingerprint:SourceFingerprint?
  }
  private var contentCache:[(key:ContentKey,image:CGImage)] = []
  public private(set) var reusedLayers=0
  public init() {}
  public func clearCaches() async {contentCache=[];await processor.clearInteractiveCaches()}

  public func render(_ document:EditorDocument, resources:[UUID:URL], maximum:Int? = nil, outputLongEdge:Int? = nil) async throws -> CGImage {
    try document.validate();try Task.checkCancellation()
    if let maximum, maximum<1 {throw EditorDocumentError.invalidDocument}
    if let outputLongEdge, !(1...20000).contains(outputLongEdge) || maximum != nil { throw EditorDocumentError.invalidDocument }
    // Explicit vector output sizing shares all layer rendering; previews still never upscale.
    let scale = outputLongEdge.map { Double($0) / Double(max(document.width, document.height)) }
      ?? min(1,Double(maximum ?? max(document.width,document.height))/Double(max(document.width,document.height)))
    guard Double(document.width)*Double(document.height)*scale*scale <= 50_000_000 else { throw EditorDocumentError.invalidDocument }
    let bounds=CGRect(x:0,y:0,width:max(1,(Double(document.width)*scale).rounded()),height:max(1,(Double(document.height)*scale).rounded()))
    var result=CIImage(color:CIColor(cgColor:Self.colour(document.background ?? RGBAColour()))).cropped(to:bounds)
    reusedLayers=0
    for layer in document.layers where layer.visible && layer.opacity>0 {
      try Task.checkCancellation()
      let sourceURL:URL?
      if case .image(let id,_) = layer.content {sourceURL=resources[id]}else{sourceURL=nil}
      let watermarkURL=layer.watermarkResourceID.flatMap{resources[$0]}
      let key=ContentKey(content:layer.content,width:layer.width,height:layer.height,scale:scale,sourceURL:sourceURL,
        fingerprint:try sourceURL.map{try SourceFingerprint.read($0)},watermarkURL:watermarkURL,watermarkFingerprint:try watermarkURL.map{try SourceFingerprint.read($0)})
      let content:CGImage
      if maximum != nil,let index=contentCache.firstIndex(where:{$0.key==key}) {
        let hit=contentCache.remove(at:index);content=hit.image;contentCache.append(hit);reusedLayers += 1
      }else {
      switch layer.content {
      case .image(let id,var configuration):
        guard let url=resources[id] else {throw EditorDocumentError.missingResource}
        if let watermark=layer.watermarkResourceID {
          guard let url=resources[watermark] else {throw EditorDocumentError.missingResource};configuration.watermark.imageURL=url
        }
        do {try await processor.validateCreativeSource(url);if let watermarkURL {try await processor.validateCreativeSource(watermarkURL)}}catch CreativeFilterError.hdr {throw EditorDocumentError.hdr}
        content=try await processor.render(url,configuration:configuration,previewMaximum:maximum == nil ? nil : max(1,Int(max(layer.width,layer.height)*scale)),decodeMaximum:maximum == nil ? nil : max(1200,Int(max(layer.width,layer.height)*scale)))
      case .text(let text): content=try Self.text(text,width:layer.width,height:layer.height,scale:scale)
      case .shape(let shape): content=try Self.shape(shape,width:layer.width,height:layer.height,scale:scale)
      }
      if maximum != nil,content.bytesPerRow*content.height<=32*1024*1024 {
        contentCache.append((key,content))
        while contentCache.count>24 || contentCache.reduce(0,{$0+$1.image.bytesPerRow*$1.image.height})>64*1024*1024 {contentCache.removeFirst()}
      }
      }
      let width=layer.width*scale,height=layer.height*scale
      var image=CIImage(cgImage:content).transformed(by:CGAffineTransform(scaleX:width/Double(content.width),y:height/Double(content.height)))
      image=image.transformed(by:CGAffineTransform(translationX:-width/2,y:-height/2))
        .transformed(by:CGAffineTransform(scaleX:layer.flipHorizontal ? -1:1,y:layer.flipVertical ? -1:1))
        .transformed(by:CGAffineTransform(rotationAngle:-layer.rotation * .pi/180))
        .transformed(by:CGAffineTransform(translationX:(layer.x+layer.width/2)*scale,y:bounds.height-(layer.y+layer.height/2)*scale))
      image=image.applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:layer.opacity)])
      let filter:String
      switch layer.blendMode {
      case .normal: filter="CISourceOverCompositing"
      case .multiply: filter="CIMultiplyBlendMode"
      case .screen: filter="CIScreenBlendMode"
      case .overlay: filter="CIOverlayBlendMode"
      case .darken: filter="CIDarkenBlendMode"
      case .lighten: filter="CILightenBlendMode"
      case .softLight: filter="CISoftLightBlendMode"
      case .hardLight: filter="CIHardLightBlendMode"
      }
      result=image.applyingFilter(filter,parameters:[kCIInputBackgroundImageKey:result]).cropped(to:bounds)
      // Materialize incrementally so an export graph cannot retain every decoded layer.
      guard let composed=context.createCGImage(result,from:bounds,format:.RGBAh,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else {throw ProcessingError.encoding}
      result=CIImage(cgImage:composed)
    }
    try Task.checkCancellation()
    guard let output=context.createCGImage(result,from:bounds,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else {throw ProcessingError.encoding}
    return output
  }
  private static func colour(_ value:RGBAColour)->CGColor {
    CGColor(colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!,components:[value.red,value.green,value.blue,value.alpha])!
  }
  private static func bitmap(width:Double,height:Double,scale:Double) throws -> CGContext {
    guard let space=CGColorSpace(name:CGColorSpace.sRGB),let c=CGContext(data:nil,width:max(1,Int((width*scale).rounded())),height:max(1,Int((height*scale).rounded())),bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw ProcessingError.encoding}
    c.scaleBy(x:scale,y:scale);return c
  }
  private static func text(_ value:EditorText,width:Double,height:Double,scale:Double) throws -> CGImage {
    let c=try bitmap(width:width,height:height,scale:scale)
    var font=CTFontCreateWithName(value.fontName as CFString,value.fontSize,nil)
    var traits:CTFontSymbolicTraits=[]
    if value.bold {traits.insert(.boldTrait)};if value.italic {traits.insert(.italicTrait)}
    if !traits.isEmpty,let variant=CTFontCreateCopyWithSymbolicTraits(font,0,nil,traits,traits) {font=variant}
    let alignment:CTTextAlignment = value.alignment == .leading ? .left : value.alignment == .centre ? .center:.right
    var align=alignment
    let paragraph=withUnsafePointer(to:&align) { pointer in
      var setting=CTParagraphStyleSetting(spec:.alignment,valueSize:MemoryLayout<CTTextAlignment>.size,value:pointer)
      return CTParagraphStyleCreate(&setting,1)
    }
    var attributes:[NSAttributedString.Key:Any]=[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):colour(value.colour),NSAttributedString.Key(kCTParagraphStyleAttributeName as String):paragraph]
    if value.underline {attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)]=1}
    if let outline = value.outlineColour, let width = value.outlineWidth, width > 0 {
      attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = colour(outline)
      attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -100 * width / value.fontSize
    }
    if let shadow = value.shadow {
      c.setShadow(offset: CGSize(width: shadow.offsetX, height: shadow.offsetY), blur: shadow.radius, color: colour(shadow.colour))
    }
    let string=NSAttributedString(string:value.text,attributes:attributes)
    let setter=CTFramesetterCreateWithAttributedString(string)
    let frame=CTFramesetterCreateFrame(setter,CFRange(location:0,length:0),CGPath(rect:CGRect(x:0,y:0,width:width,height:height),transform:nil),nil)
    CTFrameDraw(frame,c)
    guard let image=c.makeImage() else {throw ProcessingError.encoding};return image
  }
  private static func shape(_ value:EditorShape,width:Double,height:Double,scale:Double) throws -> CGImage {
    let c=try bitmap(width:width,height:height,scale:scale)
    let inset=min(min(width,height)/2,value.strokeWidth/2)
    let rect=CGRect(x:inset,y:inset,width:max(0,width-2*inset),height:max(0,height-2*inset))
    let path=CGMutablePath()
    switch value.kind {
    case .rectangle:path.addRect(rect)
    case .roundedRectangle:path.addRoundedRect(in:rect,cornerWidth:min(value.cornerRadius,rect.width/2),cornerHeight:min(value.cornerRadius,rect.height/2))
    case .ellipse:path.addEllipse(in:rect)
    case .line,.arrow:
      path.move(to:CGPoint(x:rect.minX,y:rect.maxY));path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY))
      if value.kind == .arrow {
        let angle=atan2(-rect.height,rect.width),length=min(30,min(width,height)*0.3)
        path.move(to:CGPoint(x:rect.maxX-length*cos(angle-0.5),y:rect.minY-length*sin(angle-0.5)))
        path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY));path.addLine(to:CGPoint(x:rect.maxX-length*cos(angle+0.5),y:rect.minY-length*sin(angle+0.5)))
      }
    }
    c.addPath(path);c.setLineWidth(value.strokeWidth);c.setStrokeColor(colour(value.stroke))
    if let fill=value.fill,value.kind != .line,value.kind != .arrow {c.setFillColor(colour(fill));c.drawPath(using:value.strokeWidth>0 ? .fillStroke:.fill)}
    else if value.strokeWidth>0 {c.strokePath()}
    guard let image=c.makeImage() else {throw ProcessingError.encoding};return image
  }
}
