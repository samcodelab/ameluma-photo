import XCTest
import CoreImage
@testable import FramepebbleCore

final class ColourToolsTests: XCTestCase {
  func pixels(_ image: CIImage, context override: CIContext? = nil) -> [Float] {
    let context = override ?? CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .workingFormat: CIFormat.RGBAh])
    var result = [Float](repeating: 0, count: Int(image.extent.width * image.extent.height) * 4)
    result.withUnsafeMutableBytes { context.render(image, toBitmap: $0.baseAddress!, rowBytes: Int(image.extent.width) * 16, bounds: image.extent, format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) }
    return result
  }
  func testLegacyAdjustmentsDecodeAndColourFieldsPatchIndependently() throws {
    let old = Data(#"{"exposure":0.2,"brightness":0,"contrast":1,"saturation":0.8,"warmth":0.1,"highlights":1,"shadows":0}"#.utf8)
    let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: old)
    XCTAssertEqual(decoded.vibrance, 0); XCTAssertEqual(decoded.redHue, 0)
    XCTAssertEqual(decoded.saturation, 0.8)
    var base = ProcessingConfiguration(); base.adjustments.blueSaturation = 0.4; base.adjustments.redLightness = 0.2
    var changed = base; changed.adjustments.redHue = 0.3
    let patch = ConfigurationPatch(from: base, to: changed)
    XCTAssertEqual(patch.fields, [.adjustments_redHue])
    let restored = try JSONDecoder().decode(ConfigurationPatch.self, from: JSONEncoder().encode(patch))
    var other = ProcessingConfiguration(); other.adjustments.redLightness = -0.2; other.adjustments.blueSaturation = -0.3
    let applied = restored.applying(to: other)
    XCTAssertEqual(applied.adjustments.redHue, 0.3)
    XCTAssertEqual(applied.adjustments.redLightness, -0.2); XCTAssertEqual(applied.adjustments.blueSaturation, -0.3)
    XCTAssertEqual(try JSONDecoder().decode(ProcessingConfiguration.self, from: JSONEncoder().encode(changed)), changed)
  }
  func testColourMixTargetsHuePreservesAlphaAndLeavesNeutralPixels() throws {
    let extent = CGRect(x: 0, y: 0, width: 2, height: 2)
    let red = CIImage(color: CIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.7)).cropped(to: extent)
    let blue = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.8, alpha: 0.7)).cropped(to: extent)
    let grey = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.7)).cropped(to: extent)
    var adjustments = PhotoAdjustments()
    XCTAssertEqual(pixels(try adjustments.apply(to: red)), pixels(red))
    adjustments.redHue = 1
    let changed = pixels(try adjustments.apply(to: red)), original = pixels(red)
    XCTAssertGreaterThan(changed[1], original[1] + 0.1)
    XCTAssertEqual(changed[3], original[3], accuracy: 0.002)
    for input in [blue, grey] {
      let output = pixels(try adjustments.apply(to: input)), before = pixels(input)
      for i in output.indices { XCTAssertEqual(output[i], before[i], accuracy: 0.003) }
    }
    adjustments.redHue = .nan
    XCTAssertThrowsError(try adjustments.apply(to: red))
  }
}

extension ColourToolsTests {
  func testReplacementSelectionKeepsFeatherInsideBoundaryAndPreservesHoles() throws {
    let source = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
    var edit = ColourReplacement(); edit.range = 1; edit.source = RGBAColour(0.8, 0.2, 0.1, 1); edit.feather = 0.03
    edit.points = [NormalizedPoint(0.2,0.2), NormalizedPoint(0.8,0.2), NormalizedPoint(0.8,0.8), NormalizedPoint(0.2,0.8)]
    edit.excludedContours = [[NormalizedPoint(0.4,0.4), NormalizedPoint(0.6,0.4), NormalizedPoint(0.6,0.6), NormalizedPoint(0.4,0.6)]]
    let original = pixels(source)
    let result = pixels(try ColourRenderer.replace(source, edits: [edit]))
    for (x,y) in [(19,50), (80,50), (50,50), (0,0)] {
      let i = (y * 100 + x) * 4
      for channel in 0..<4 { XCTAssertEqual(result[i+channel], original[i+channel], accuracy: 0.0001) }
    }
    XCTAssertGreaterThan(abs(result[(30*100+30)*4+2] - original[(30*100+30)*4+2]), 0.1)
    let restored = try JSONDecoder().decode(ColourReplacement.self, from: JSONEncoder().encode(edit))
    XCTAssertEqual(restored, edit)
    var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any])
    legacyObject.removeValue(forKey: "constrainFeatherToSelection"); legacyObject.removeValue(forKey: "excludedContours")
    let legacy = try JSONDecoder().decode(ColourReplacement.self, from: JSONSerialization.data(withJSONObject: legacyObject))
    XCTAssertNil(legacy.constrainFeatherToSelection, "Existing projects retain their original feather behavior")
    XCTAssertNil(legacy.excludedContours)
  }

  func testLocalReplacementPreservesOutsidePixelsTextureAndAlphaAndRoundTrips() throws {
    let left = CIImage(color:CIColor(red:0.8,green:0.1,blue:0.1,alpha:0.7)).cropped(to:CGRect(x:0,y:0,width:8,height:8))
    var edit = ColourReplacement()
    edit.source = RGBAColour(0.8,0.1,0.1,1);edit.replacement = RGBAColour(0.1,0.2,0.8,1);edit.range = 1;edit.feather = 0
    edit.points = [NormalizedPoint(0,0),NormalizedPoint(0.5,0),NormalizedPoint(0.5,1),NormalizedPoint(0,1)]
    let output = pixels(try ColourRenderer.replace(left,edits:[edit])), original = pixels(left)
    for y in 0..<8 { for x in 0..<8 {
      let i=(y*8+x)*4
      XCTAssertEqual(output[i+3],original[i+3],accuracy:0.002)
      if x >= 4 { for c in 0..<3 { XCTAssertEqual(output[i+c],original[i+c],accuracy:0.003) } }
      else { XCTAssertGreaterThan(output[i+2],output[i]+0.2) }
    } }
    edit.intensity = 0
    XCTAssertEqual(pixels(try ColourRenderer.replace(left,edits:[edit])),original)
    var config=ProcessingConfiguration();config.colourReplacements=[edit]
    XCTAssertEqual(try JSONDecoder().decode(ProcessingConfiguration.self,from:JSONEncoder().encode(config)),config)
    let patch=ConfigurationPatch(from:ProcessingConfiguration(),to:config)
    XCTAssertEqual(patch.fields,[.colourReplacements])
    XCTAssertEqual(try JSONDecoder().decode(ConfigurationPatch.self,from:JSONEncoder().encode(patch)),patch)
    edit.points=[NormalizedPoint(0,0)]
    XCTAssertThrowsError(try ColourRenderer.replace(left,edits:[edit]))
  }
  func testEveryOriginalStickerRendersAndUnknownStickerFailsVisibly() throws {
    XCTAssertEqual(StickerCatalog.stickers.count,60)
    XCTAssertEqual(Set(StickerCatalog.stickers.map(\.id)).count,60)
    let input=CIImage(color:.clear).cropped(to:CGRect(x:0,y:0,width:160,height:120))
    for sticker in StickerCatalog.stickers {
      var annotation=Annotation();annotation.kind = .sticker;annotation.stickerID=sticker.id
      annotation.x=0.05;annotation.y=0.05;annotation.width=0.9;annotation.height=0.9
      let image=try AnnotationRenderer.apply(to:input,annotations:[annotation],canvas:CanvasStyle())
      let rendered=pixels(image)
      XCTAssertTrue(stride(from:3,to:rendered.count,by:4).contains { rendered[$0] > 0.1 },sticker.id)
      XCTAssertEqual(try JSONDecoder().decode(Annotation.self,from:JSONEncoder().encode(annotation)),annotation)
    }
    var unknown=Annotation();unknown.kind = .sticker;unknown.stickerID="future.unavailable"
    XCTAssertThrowsError(try AnnotationRenderer.apply(to:input,annotations:[unknown],canvas:CanvasStyle()))
  }
}

extension ColourToolsTests {
  func testColourReplacementAndStickerSharePreviewExportAndProtectSource() async throws {
    let helper=ProcessingTests(),source=try helper.fixture()
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:source);try? FileManager.default.removeItem(at:directory) }
    let bytes=try Data(contentsOf:source)
    var config=ProcessingConfiguration();config.width=80;config.height=40;config.format = .png
    config.background=RGBAColour(0,0,0,0);config.adjustments.redHue=0.2;config.adjustments.vibrance=0.1
    var edit=ColourReplacement();edit.source=RGBAColour(1,0.2,0,1);edit.range=1;edit.feather=0
    edit.points=[NormalizedPoint(0,0),NormalizedPoint(1,0),NormalizedPoint(1,1),NormalizedPoint(0,1)]
    config.colourReplacements=[edit]
    var sticker=Annotation();sticker.kind = .sticker;sticker.stickerID="v1.dress.0";config.annotations=[sticker]
    let engine=ImageProcessor()
    let preview=try await engine.render(source,configuration:config,previewMaximum:100)
    let full=try await engine.render(source,configuration:config)
    XCTAssertEqual(try helper.pixels(preview),try helper.pixels(full))
    let result=try await engine.export(SourceAsset(url:source),configuration:config,to:directory)
    XCTAssertNil(result.error)
    XCTAssertNotNil(result.output)
    XCTAssertEqual(try Data(contentsOf:source),bytes)
    let saved=try JSONDecoder().decode(ProcessingConfiguration.self,from:JSONEncoder().encode(config))
    XCTAssertEqual(saved,config)
    let reopened=try await engine.render(source,configuration:saved)
    XCTAssertEqual(try helper.pixels(reopened),try helper.pixels(full))
  }
}

extension ColourToolsTests {
  func testRecolourMatchesFabricAcrossShadowsWithoutFlatteningLightness() throws {
    let dark=CIImage(color:CIColor(red:0.45,green:0.1,blue:0.08)).cropped(to:CGRect(x:0,y:0,width:4,height:4))
    let light=CIImage(color:CIColor(red:0.8,green:0.25,blue:0.2)).cropped(to:CGRect(x:4,y:0,width:4,height:4))
    let input=dark.composited(over:light).cropped(to:CGRect(x:0,y:0,width:8,height:4))
    var edit=ColourReplacement();edit.source=RGBAColour(0.6,0.17,0.12,1);edit.replacement=RGBAColour(0.15,0.3,0.65,1)
    edit.range=0.22;edit.feather=0;edit.points=[NormalizedPoint(0,0),NormalizedPoint(1,0),NormalizedPoint(1,1),NormalizedPoint(0,1)]
    let after=pixels(try ColourRenderer.replace(input,edits:[edit])),before=pixels(input)
    func lightness(_ p:[Float],_ x:Int)->Float { let c=Array(p[(x*4)..<(x*4+3)]);return (c.max()!+c.min()!)/2 }
    for x in [1,6] { XCTAssertGreaterThan(after[x*4+2],after[x*4]+0.15,"Both shadow and highlight should receive the blue hue") }
    XCTAssertEqual(lightness(after,6)-lightness(after,1),lightness(before,6)-lightness(before,1),accuracy:0.015)
  }
  func testStickerFlipAndOpacityArePersistedAndRendered() throws {
    let input=CIImage(color:.clear).cropped(to:CGRect(x:0,y:0,width:120,height:120))
    var a=Annotation();a.kind = .sticker;a.stickerID="v1.dress.0";a.x=0.05;a.y=0.05;a.width=0.9;a.height=0.9
    let before=pixels(try AnnotationRenderer.apply(to:input,annotations:[a],canvas:CanvasStyle()))
    a.flipHorizontal=true;a.opacity=0.4
    let after=pixels(try AnnotationRenderer.apply(to:input,annotations:[a],canvas:CanvasStyle()))
    XCTAssertNotEqual(before,after)
    XCTAssertLessThanOrEqual(stride(from:3,to:after.count,by:4).map{after[$0]}.max()!,0.405)
    XCTAssertEqual(try JSONDecoder().decode(Annotation.self,from:JSONEncoder().encode(a)),a)
  }
}

extension ColourToolsTests {
  func testSampledReplacementColourMatchesAcrossRenderingWorkingSpaces() throws {
    let source=CIImage(color:CIColor(red:0.8,green:0.1,blue:0.1)).cropped(to:CGRect(x:0,y:0,width:4,height:4))
    var edit=ColourReplacement();edit.source=RGBAColour(0.8,0.1,0.1,1);edit.replacement=RGBAColour(0.1,0.2,0.8,1);edit.range=1;edit.feather=0
    edit.points=[NormalizedPoint(0,0),NormalizedPoint(1,0),NormalizedPoint(1,1),NormalizedPoint(0,1)]
    let result=try ColourRenderer.replace(source,edits:[edit])
    let srgb=pixels(result),linear=pixels(result,context:CIContext(options:[.workingFormat:CIFormat.RGBAh]))
    for i in srgb.indices { XCTAssertEqual(srgb[i],linear[i],accuracy:0.006) }
    XCTAssertEqual(srgb[0],0.1,accuracy:0.01);XCTAssertEqual(srgb[1],0.2,accuracy:0.01);XCTAssertEqual(srgb[2],0.8,accuracy:0.01)
    XCTAssertThrowsError(try ColourRenderer.replace(source,edits:Array(repeating:edit,count:ColourReplacement.maximumEdits+1)))
  }
}

extension ColourToolsTests {
  func testPositiveTintMovesNeutralColourTowardMagentaAndPreservesAlpha() throws {
    let image=CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5,alpha:0.6)).cropped(to:CGRect(x:0,y:0,width:2,height:2))
    var edit=PhotoAdjustments();edit.tint=0.5
    let result=pixels(try edit.apply(to:image))
    XCTAssertGreaterThan((result[0]+result[2])/2,result[1])
    XCTAssertEqual(result[3],pixels(image)[3],accuracy:0.002)
  }
}
