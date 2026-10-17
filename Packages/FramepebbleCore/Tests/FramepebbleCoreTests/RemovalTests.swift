import XCTest
import CoreImage
import CoreGraphics
@testable import FramepebbleCore

final class RemovalTests: XCTestCase {
  private let context = CIContext(options:[.cacheIntermediates:false])
  private func bytes(_ image:CIImage) -> [UInt8] {
    var pixels=[UInt8](repeating:0,count:Int(image.extent.width*image.extent.height)*4)
    context.render(image,toBitmap:&pixels,rowBytes:Int(image.extent.width)*4,bounds:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
    return pixels
  }
  func testAsymmetricRemovalDoesNotMirrorContext() throws {
    let bounds=CGRect(x:0,y:0,width:160,height:200)
    let green=CIImage(color:CIColor(red:0.1,green:0.7,blue:0.2)).cropped(to:bounds)
    let branch=CIImage(color:CIColor(red:0.8,green:0.3,blue:0.1)).cropped(to:CGRect(x:0,y:35,width:160,height:20)).composited(over:green)
    let object=CIImage(color:CIColor(red:0.01,green:0.01,blue:0.01)).cropped(to:CGRect(x:76,y:25,width:8,height:40)).composited(over:branch)
    var stroke=RetouchStroke();stroke.mode = .remove;stroke.samplingVersion=1;stroke.diameter=0.09;stroke.hardness=1
    stroke.points=[NormalizedPoint(0.5,0.87),NormalizedPoint(0.5,0.67)]
    let actual=bytes(try RetouchRenderer.apply(to:object,strokes:[stroke],context:context)),expected=bytes(branch)
    for y in [30,40,45,50,60] {
      let i=(y*160+80)*4
      for ch in 0..<3 { XCTAssertEqual(Int(actual[i+ch]),Int(expected[i+ch]),accuracy:8,"y=\(y)") }
    }
    let roundtrip=CIImage(bitmapData:Data(bytes(branch)),bytesPerRow:160*4,size:CGSize(width:160,height:200),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
    XCTAssertEqual(bytes(roundtrip),bytes(branch))
  }
  func testRemovalContinuesBranchAndPreservesUnpaintedPixels() throws {
    let bounds=CGRect(x:0,y:0,width:180,height:180)
    let background=CIImage(color:CIColor(red:0.2,green:0.55,blue:0.3)).cropped(to:bounds)
    let branch=CIImage(color:CIColor(red:0.65,green:0.35,blue:0.1)).cropped(to:CGRect(x:0,y:80,width:180,height:20)).composited(over:background)
    let blemish=CIImage(color:CIColor(red:0.02,green:0.02,blue:0.02)).cropped(to:CGRect(x:86,y:60,width:8,height:60)).composited(over:branch)
    var stroke=RetouchStroke();stroke.mode = .remove;stroke.samplingVersion=1;stroke.diameter=0.09;stroke.hardness=1
    stroke.points=[NormalizedPoint(0.5,0.32),NormalizedPoint(0.5,0.68)]
    let result=try RetouchRenderer.apply(to:blemish,strokes:[stroke],context:context)
    let rendered=bytes(result),clean=bytes(branch),before=bytes(blemish)
    for y in [65,75,85,90,95,105,115] {
      let i=(y*180+90)*4
      for channel in 0..<3 { XCTAssertEqual(Int(rendered[i+channel]),Int(clean[i+channel]),accuracy:8,"Interrupted structure at y=\(y)") }
    }
    for y in 0..<180 { for x in 0..<180 where x<80 || x>100 {
      let i=(y*180+x)*4
      XCTAssertEqual(Array(rendered[i..<i+4]),Array(before[i..<i+4]))
    } }
    XCTAssertEqual(bytes(try RetouchRenderer.apply(to:blemish,strokes:[stroke],context:context)),rendered)
    XCTAssertEqual(try JSONDecoder().decode(RetouchStroke.self,from:JSONEncoder().encode(stroke)),stroke)
  }
  func testRemovalRejectsUnknownRecipeAndCancels() async throws {
    let image=CIImage(color:CIColor(red:0.4,green:0.5,blue:0.6)).cropped(to:CGRect(x:0,y:0,width:120,height:100))
    var stroke=RetouchStroke();stroke.mode = .remove;stroke.samplingVersion=99;stroke.points=[NormalizedPoint(0.5,0.5)]
    XCTAssertThrowsError(try RetouchRenderer.apply(to:image,strokes:[stroke],context:context))
    stroke.samplingVersion=1
    let captured=stroke,context=self.context
    let task=Task { try Task.checkCancellation(); return try RetouchRenderer.apply(to:image,strokes:[captured],context:context) }
    task.cancel()
    do { _=try await task.value;XCTFail("Cancelled removal completed") } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testRemovalHasNoEffectAtZeroOpacity() throws {
    let image=CIImage(color:CIColor(red:0.2,green:0.4,blue:0.8,alpha:0.5)).cropped(to:CGRect(x:0,y:0,width:40,height:30))
    var stroke=RetouchStroke();stroke.mode = .remove;stroke.samplingVersion=1;stroke.points=[NormalizedPoint(0.5,0.5)];stroke.opacity=0
    XCTAssertEqual(bytes(image),bytes(try RetouchRenderer.apply(to:image,strokes:[stroke],context:context)))
  }
  func testBirdRemovalDiagnostic() async throws {
    guard ProcessInfo.processInfo.environment["AMELUMA_REMOVAL_CORPUS"] == "1" else { throw XCTSkip("Opt-in repository photographic diagnostic") }
    var root=URL(fileURLWithPath:#filePath);for _ in 0..<5 { root.deleteLastPathComponent() }
    let url=root.appendingPathComponent("Resources/DemoWorkspace/Photos/28-rainbow-bird-hero.jpg")
    guard FileManager.default.fileExists(atPath:url.path) else { throw XCTSkip("Demo photograph unavailable") }
    let original=try Data(contentsOf:url),engine=ImageProcessor()
    var c=ProcessingConfiguration();c.nativeOutputSizing=true
    var claw=RetouchStroke();claw.mode = .remove;claw.samplingVersion=1;claw.diameter=0.065;claw.hardness=0.85
    claw.points=[NormalizedPoint(0.289,0.555),NormalizedPoint(0.300,0.600),NormalizedPoint(0.289,0.635)]
    var other=claw;other.id=UUID();other.points=[NormalizedPoint(0.370,0.601),NormalizedPoint(0.385,0.640),NormalizedPoint(0.376,0.674)]
    var tail=claw;tail.id=UUID();tail.diameter=0.12;tail.points=[NormalizedPoint(0.19,0.66),NormalizedPoint(0.16,0.75),NormalizedPoint(0.12,0.86),NormalizedPoint(0.09,0.94)]
    let output=FileManager.default.temporaryDirectory.appendingPathComponent("ameluma-removal-review",isDirectory:true)
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    for (name,strokes) in [("claws",[claw,other]),("tail",[tail])] {
      c.retouchStrokes=strokes
      let start=ProcessInfo.processInfo.systemUptime
      let cg=try await engine.render(url,configuration:c,previewMaximum:1200)
      let elapsed=(ProcessInfo.processInfo.systemUptime-start)*1000
      let destination=output.appendingPathComponent(name+".png")
      let encoder=try XCTUnwrap(CGImageDestinationCreateWithURL(destination as CFURL,"public.png" as CFString,1,nil))
      CGImageDestinationAddImage(encoder,cg,nil);XCTAssertTrue(CGImageDestinationFinalize(encoder))
      print("REMOVAL_CORPUS \(name) engine_ms=\(elapsed) image=\(destination.path)")
    }
    XCTAssertEqual(try Data(contentsOf:url),original)
  }

}
