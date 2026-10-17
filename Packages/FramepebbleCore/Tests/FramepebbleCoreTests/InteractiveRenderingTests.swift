import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import FramepebbleCore

final class InteractiveRenderingTests: XCTestCase {
  private func fixture(_ url:URL,width:Int=160,height:Int=100) throws {
    let context=CIContext()
    let gradient=try XCTUnwrap(CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:CGFloat(width),y:CGFloat(height)),"inputColor0":CIColor(red:0.1,green:0.2,blue:0.7),"inputColor1":CIColor(red:0.9,green:0.7,blue:0.2)])?.outputImage)
    let image=gradient.cropped(to:CGRect(x:0,y:0,width:width,height:height))
    let cg=try XCTUnwrap(context.createCGImage(image,from:image.extent))
    let destination=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(destination,cg,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
  func testPreviewCacheAndCheckpointRespectEditSourceAndPrivateMode() async throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    try fixture(url);defer { try? FileManager.default.removeItem(at:url) }
    let original=try Data(contentsOf:url),engine=ImageProcessor()
    var c=ProcessingConfiguration();c.nativeOutputSizing=true
    _=try await engine.render(url,configuration:c,previewMaximum:160)
    let first=await engine.lastRenderMetrics;XCTAssertEqual(first?.previewCacheHit,false)
    _=try await engine.render(url,configuration:c,previewMaximum:160)
    let second=await engine.lastRenderMetrics;XCTAssertEqual(second?.previewCacheHit,true)
    var stroke=RetouchStroke();stroke.mode = .clone;stroke.points=[NormalizedPoint(0.5,0.5)];stroke.source=NormalizedPoint(0.2,0.2)
    c.retouchStrokes=[stroke]
    _=try await engine.render(url,configuration:c,previewMaximum:160)
    stroke.id=UUID();stroke.points=[NormalizedPoint(0.6,0.6)];c.retouchStrokes.append(stroke)
    let incremental=try await engine.render(url,configuration:c,previewMaximum:160)
    let reused=await engine.lastRenderMetrics;XCTAssertEqual(reused?.reusedRetouchPrefix,true)
    let fresh=try await ImageProcessor().render(url,configuration:c,previewMaximum:160)
    let context=CIContext()
    func pixels(_ image:CGImage)->[UInt8] {
      var result=[UInt8](repeating:0,count:image.width*image.height*4)
      context.render(CIImage(cgImage:image),toBitmap:&result,rowBytes:image.width*4,bounds:CGRect(x:0,y:0,width:image.width,height:image.height),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
      return result
    }
    for (a,b) in zip(pixels(incremental),pixels(fresh)) { XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),1) }
    c.retouchStrokes.removeFirst()
    _=try await engine.render(url,configuration:c,previewMaximum:160)
    let removed=await engine.lastRenderMetrics;XCTAssertEqual(removed?.reusedRetouchPrefix,false)
    c.adjustments.exposure=0.5
    _=try await engine.render(url,configuration:c,previewMaximum:160)
    let edited=await engine.lastRenderMetrics;XCTAssertEqual(edited?.reusedRetouchPrefix,false)
    XCTAssertEqual(try Data(contentsOf:url),original)
    await engine.setPrivateMode(true)
    for _ in 0..<2 {
      _=try await engine.render(url,configuration:c,previewMaximum:160)
      let privateMetrics=await engine.lastRenderMetrics
      XCTAssertEqual(privateMetrics?.previewCacheHit,false);XCTAssertEqual(privateMetrics?.reusedRetouchPrefix,false)
    }
    await engine.setPrivateMode(false)
    try fixture(url,width:180)
    let changed=try await engine.render(url,configuration:c,previewMaximum:160)
    XCTAssertNotEqual(changed.height,fresh.height)
    let replaced=await engine.lastRenderMetrics;XCTAssertEqual(replaced?.previewCacheHit,false);XCTAssertEqual(replaced?.reusedRetouchPrefix,false)
  }

  /// Opt-in release benchmark. Synthetic 24 MP source, end-to-end engine calls, not pointer latency.
  func testReleaseInteractiveBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["AMELUMA_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    try fixture(url,width:6000,height:4000);defer { try? FileManager.default.removeItem(at:url) }
    let engine=ImageProcessor();var c=ProcessingConfiguration();c.nativeOutputSizing=true
    var timings:[String:[Double]]=[:]
    func measure(_ label:String,_ configuration:ProcessingConfiguration) async throws {
      _=try await engine.render(url,configuration:configuration,previewMaximum:1600)
      let metric=await engine.lastRenderMetrics
      timings[label,default:[]].append(try XCTUnwrap(metric).totalMilliseconds)
    }
    try await measure("cold",c)
    for _ in 0..<30 { try await measure("cached",c) }
    for i in 0..<30 { c.adjustments.exposure=Double(i)/100;try await measure("slider",c) }
    for i in 0..<12 {
      var stroke=RetouchStroke();stroke.mode = .clone;stroke.source=NormalizedPoint(0.2,0.2);stroke.points=[NormalizedPoint(0.5+Double(i)*0.01,0.5)]
      c.retouchStrokes.append(stroke);try await measure("clone_append",c)
    }
    for (name,values) in timings.sorted(by:{$0.key<$1.key}) {
      let sorted=values.sorted(),p95=sorted[min(sorted.count-1,Int(ceil(Double(sorted.count)*0.95))-1)]
      print("EDITOR_BENCHMARK \(name) count=\(values.count) median_ms=\(sorted[sorted.count/2]) p95_ms=\(p95)")
    }
  }
}
