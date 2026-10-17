import XCTest
import CoreImage
import ImageIO
@testable import FramepebbleCore

final class CreativeFilterTests: XCTestCase {
  func values(_ image: CIImage, context: CIContext) -> [Float] {
    var p=[Float](repeating:0,count:Int(image.extent.width*image.extent.height)*4)
    p.withUnsafeMutableBytes { context.render(image,toBitmap:$0.baseAddress!,rowBytes:Int(image.extent.width)*16,bounds:image.extent,format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) }
    return p
  }
  func testCatalogOrderVersionAndUnknownPreservation() throws {
    XCTAssertEqual(FilterCatalog.presets.count,24)
    XCTAssertEqual(Set(FilterCatalog.presets.map(\.id)).count,24)
    for c in FilterCollection.allCases { XCTAssertEqual(FilterCatalog.presets.filter{$0.collection == c}.count,6) }
    XCTAssertEqual(FilterCatalog.presets.first?.id,"essentials.clean")
    XCTAssertEqual(FilterCatalog.presets.last?.id,"mono.warm_paper")
    var c=ProcessingConfiguration(); c.filterEdit=FilterEdit(presetID:"future.saved",intensity:0.31,grainSeed:123)
    XCTAssertEqual(try JSONDecoder().decode(ProcessingConfiguration.self,from:JSONEncoder().encode(c)),c)
    let input=CIImage(color:.gray).cropped(to:CGRect(x:0,y:0,width:4,height:4))
    XCTAssertThrowsError(try CreativeFilterRenderer.apply(c.filterEdit,to:input,fullSize:input.extent.size))
    c.filterEdit?.presetID="essentials.clean"; c.filterEdit?.recipeVersion=99
    XCTAssertThrowsError(try CreativeFilterRenderer.apply(c.filterEdit,to:input,fullSize:input.extent.size))
  }
  func testAllRecipesEndpointsBlendDeterminismAndAlpha() throws {
    let input=CIImage(color:CIColor(red:0.58,green:0.36,blue:0.22,alpha:0.65)).cropped(to:CGRect(x:0,y:0,width:24,height:16))
    let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.sRGB)!, .workingFormat:CIFormat.RGBAh])
    let original=values(input,context:context)
    for preset in FilterCatalog.presets {
      let zero=try CreativeFilterRenderer.apply(FilterEdit(presetID:preset.id,intensity:0,grainSeed:42),to:input,fullSize:input.extent.size)
      XCTAssertEqual(values(zero,context:context),original)
      let full=try CreativeFilterRenderer.apply(FilterEdit(presetID:preset.id,intensity:1,grainSeed:42),to:input,fullSize:input.extent.size)
      let middle=try CreativeFilterRenderer.apply(FilterEdit(presetID:preset.id,intensity:0.7,grainSeed:42),to:input,fullSize:input.extent.size)
      let f=values(full,context:context),m=values(middle,context:context)
      XCTAssertEqual(f,values(full,context:context),preset.id)
      XCTAssertNotEqual(f,original,preset.id)
      for i in stride(from:0,to:f.count,by:4) {
        XCTAssertEqual(f[i+3],original[i+3],accuracy:0.002,preset.id)
        for channel in 0..<3 { XCTAssertEqual(m[i+channel],original[i+channel]*0.3+f[i+channel]*0.7,accuracy:0.003,preset.id) }
        if preset.collection == .monochrome && preset.id != "mono.warm_paper" {
          XCTAssertEqual(f[i],f[i+1],accuracy:0.002,preset.id); XCTAssertEqual(f[i+1],f[i+2],accuracy:0.002,preset.id)
        }
      }
    }
  }
  func testExportPreviewAndSourcePreservation() async throws {
    let helper=ProcessingTests(); let source=try helper.fixture(width:80,height:40,orientation:6)
    let bytes=try Data(contentsOf:source)
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:folder) }
    let processor=ImageProcessor(); var c=ProcessingConfiguration(); c.width=40;c.height=80;c.format = .png
    c.filterEdit=FilterEdit(presetID:"film.amber",grainSeed:726)
    let preview=try await processor.render(source,configuration:c,previewMaximum:160)
    let result=try await processor.export(SourceAsset(url:source),configuration:c,to:folder)
    let encoded=try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(result.output) as CFURL,nil))
    let reopened=try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded,0,nil))
    XCTAssertEqual(reopened.width,40);XCTAssertEqual(reopened.height,80)
    XCTAssertEqual(try PhotoLookTests().pixel(preview),try PhotoLookTests().pixel(reopened))
    XCTAssertEqual(try Data(contentsOf:source),bytes)
    let resolved=try await processor.resolveAutoEnhance(source,configuration:c)
    XCTAssertEqual(try JSONDecoder().decode(AutoEnhanceEdit.self,from:JSONEncoder().encode(resolved)),resolved)
  }
  func testTransparentAndInvalidIntensity() throws {
    let input=CIImage(color:.clear).cropped(to:CGRect(x:0,y:0,width:4,height:4))
    let context=CIContext()
    for p in FilterCatalog.presets {
      let output=try CreativeFilterRenderer.apply(FilterEdit(presetID:p.id),to:input,fullSize:input.extent.size)
      XCTAssertTrue(values(output,context:context).allSatisfy{$0 == 0})
    }
    XCTAssertThrowsError(try CreativeFilterRenderer.apply(FilterEdit(presetID:"essentials.clean",intensity:.nan),to:input,fullSize:input.extent.size))
  }
}

extension CreativeFilterTests {
  func testPreviewCacheRevisionPrivateModeAndPurge() async throws {
    let source=try ProcessingTests().fixture(width:80,height:40)
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let service=FilterPreviewService(directory:folder)
    let asset=SourceAsset(url:source)
    var c=ProcessingConfiguration();c.width=80;c.height=40;c.filterEdit=FilterEdit(presetID:"film.amber",grainSeed:7)
    let a=try await service.preview(asset,configuration:c,maximum:80,privateMode:false)
    let b=try await service.preview(asset,configuration:c,maximum:80,privateMode:false)
    XCTAssertEqual(try PhotoLookTests().pixel(a),try PhotoLookTests().pixel(b))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,1)
    c.filterEdit?.intensity=0.3
    _=try await service.preview(asset,configuration:c,maximum:80,privateMode:true)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,1)
    _=try await service.preview(asset,configuration:c,maximum:80,privateMode:false)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,2)
    try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(3)],ofItemAtPath:source.path)
    _=try await service.preview(asset,configuration:c,maximum:80,privateMode:false)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,3)
    await service.purge([asset.id])
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,0)
    let task=Task { try Task.checkCancellation(); return try await service.preview(asset,configuration:c,maximum:81,privateMode:false) }
    task.cancel()
    do { _=try await task.value; XCTFail("Cancelled work must not publish") } catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
  }
}

extension CreativeFilterTests {
  func testZeroIntensityMatchesFullPipelineAndWideGamutOutput() async throws {
    let input=CIImage(color:CIColor(red:0.4,green:0.3,blue:0.1,alpha:0.7)).cropped(to:CGRect(x:0,y:0,width:40,height:30))
    let context=CIContext();let space=try XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3))
    let cg=try XCTUnwrap(context.createCGImage(input,from:input.extent,format:.RGBA8,colorSpace:space))
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    defer { try? FileManager.default.removeItem(at:url) }
    let dest=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil))
    CGImageDestinationAddImage(dest,cg,nil);XCTAssertTrue(CGImageDestinationFinalize(dest))
    let engine=ImageProcessor();var c=ProcessingConfiguration();c.width=40;c.height=30;c.format = .png;c.background=RGBAColour(0,0,0,0)
    c.adjustments.exposure=0.2
    let original=try await engine.render(url,configuration:c)
    c.filterEdit=FilterEdit(presetID:"cinema.dramatic",intensity:0,grainSeed:76)
    let zero=try await engine.render(url,configuration:c)
    XCTAssertEqual(original.dataProvider?.data as Data?,zero.dataProvider?.data as Data?)
    c.filterEdit?.intensity=0.7
    let result=try await engine.render(url,configuration:c)
    XCTAssertEqual(result.colorSpace?.name,CGColorSpace.sRGB)
    XCTAssertEqual(try PhotoLookTests().pixel(result)[3],try PhotoLookTests().pixel(original)[3])
    c.colourPolicy = .preserve
    let preserved=try await engine.render(url,configuration:c)
    XCTAssertEqual(preserved.colorSpace?.name,CGColorSpace.displayP3)
  }
}

extension CreativeFilterTests {
  func testEnhancementRejectsUnknownFiltersAndWrongParameterTypes() throws {
    let input=CIImage(color:.gray).cropped(to:CGRect(x:0,y:0,width:4,height:4))
    var wrong=SerializedAdjustment(name:"CIToneCurve");wrong.numbers=["inputPoint0":0.3]
    XCTAssertThrowsError(try AutoEnhanceEdit(resolvedAdjustments:[wrong]).apply(to:input))
    XCTAssertThrowsError(try AutoEnhanceEdit(resolvedAdjustments:[SerializedAdjustment(name:"CIAffineTransform")]).apply(to:input))
    var good=SerializedAdjustment(name:"CIExposureAdjust");good.numbers=["inputEV":0.3]
    XCTAssertNoThrow(try AutoEnhanceEdit(resolvedAdjustments:[good]).apply(to:input))
    var disabled=AutoEnhanceEdit(enabled:false,resolvedAdjustments:[wrong])
    XCTAssertNoThrow(try disabled.apply(to:input));disabled.enabled=true
    XCTAssertThrowsError(try disabled.apply(to:input))
  }
  func testCreativeExportCancellationLeavesEditsAndSourceUntouched() async throws {
    let source=try ProcessingTests().fixture()
    let bytes=try Data(contentsOf:source)
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:dir) }
    let engine=ImageProcessor();var c=ProcessingConfiguration();c.filterEdit=FilterEdit(presetID:"film.amber",grainSeed:45)
    let snapshot=c
    let task=Task { [snapshot, source, engine, dir] in try Task.checkCancellation();return try await engine.export(SourceAsset(url:source),configuration:snapshot,to:dir) };task.cancel()
    do { _=try await task.value;XCTFail("Cancelled export must not publish") } catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:dir.path),[])
    XCTAssertEqual(try Data(contentsOf:source),bytes);XCTAssertEqual(c,snapshot)
  }
}
