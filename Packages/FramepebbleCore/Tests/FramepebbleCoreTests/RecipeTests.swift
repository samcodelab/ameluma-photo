import XCTest
import CoreGraphics
import ImageIO
@testable import FramepebbleCore

final class RecipeTests:XCTestCase {
  func testReusableRecordCannotCapturePhotoSpecificInstructions() throws {
    var recipe=ProcessingRecipe();recipe.enabled=[.corrections,.filter,.output];recipe.presetID="film.faded"
    let data=try JSONEncoder().encode(recipe),json=try XCTUnwrap(String(data:data,encoding:.utf8))
    for field in ["crop","retouchStrokes","annotations","masks","colourReplacements","autoEnhance","grainSeed","sourceID","destination"] {XCTAssertFalse(json.contains("\""+field+"\""),field)}
    XCTAssertEqual(try JSONDecoder().decode(ProcessingRecipe.self,from:data),recipe)
    var source=ProcessingConfiguration();source.nativeOutputSizing=true
    source.crop.mode = .manualCrop;source.crop.centerX=0.7;source.crop.zoom=2
    source.masks=[PrivacyMask()];source.annotations=[Annotation()]
    source.autoEnhance=AutoEnhanceEdit();source.filterEdit=FilterEdit(grainSeed:123)
    source.adjustments.tint=0.2
    let result=try recipe.configuration(for:source,sourceSize:CGSize(width:4000,height:3000),grainSeed:987)
    XCTAssertEqual(result.crop,source.crop);XCTAssertEqual(result.masks,source.masks);XCTAssertEqual(result.annotations,source.annotations)
    XCTAssertEqual(result.autoEnhance,source.autoEnhance);XCTAssertEqual(result.filterEdit?.grainSeed,123)
    XCTAssertEqual(result.adjustments.tint,0.2);XCTAssertEqual(result.nativeOutputSizing,true)
    var other=source;other.filterEdit=FilterEdit(grainSeed:456)
    XCTAssertEqual(try recipe.configuration(for:other,sourceSize:CGSize(width:600,height:800),grainSeed:999).filterEdit?.grainSeed,456)
  }
  func testResizePreservesFinishedAspectAndManualFramingAndSparseSizingRoundTrips() throws {
    var recipe=ProcessingRecipe();recipe.enabled=[.resize];recipe.longestEdge=1000
    var source=ProcessingConfiguration();source.nativeOutputSizing=true;source.crop.mode = .fill
    source.width=1600;source.height=1200;source.crop.centerX=0.8;source.crop.zoom=1.5
    let size=CGSize(width:4000,height:3000)
    let output=try recipe.configuration(for:source,sourceSize:size,grainSeed:1)
    XCTAssertEqual(output.width,1000);XCTAssertEqual(output.height,750)
    XCTAssertEqual(output.crop,source.crop);XCTAssertEqual(output.nativeOutputSizing,false)
    let patch=ConfigurationPatch(from:source,to:output)
    XCTAssertTrue(patch.fields.contains(.nativeOutputSizing))
    let restored=try JSONDecoder().decode(ConfigurationPatch.self,from:JSONEncoder().encode(patch))
    XCTAssertEqual(restored.applying(to:source),output)
    source.nativeOutputSizing=nil
    let cleared=ConfigurationPatch(from:output,to:source)
    XCTAssertNil(try JSONDecoder().decode(ConfigurationPatch.self,from:JSONEncoder().encode(cleared)).applying(to:output).nativeOutputSizing)
  }
  func testConversionOnlyAndDisabledStepsDoNotChangeGeometryOrCorrections() throws {
    var recipe=ProcessingRecipe();recipe.enabled=[.output];recipe.format = .png
    var source=ProcessingConfiguration();source.crop.centerY=0.8;source.crop.zoom=3;source.adjustments.exposure=0.6
    source.nativeOutputSizing=true;source.quarterTurns=1
    let output=try recipe.configuration(for:source,sourceSize:CGSize(width:800,height:1200),grainSeed:1)
    XCTAssertEqual(output.crop,source.crop);XCTAssertEqual(output.adjustments,source.adjustments)
    XCTAssertEqual(output.nativeOutputSizing,true);XCTAssertEqual(output.quarterTurns,1)
    recipe.enabled=[.filter];recipe.presetID="missing.recipe"
    XCTAssertThrowsError(try recipe.validate())
    recipe.presetID=nil;recipe.version=99;XCTAssertThrowsError(try recipe.validate())
  }
  func testRecipeUsesSamePreviewExportAndProtectsOriginal() async throws {
    let helper=ProcessingTests(),source=try ProcessingTests().fixture()
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:source);try? FileManager.default.removeItem(at:folder)}
    let bytes=try Data(contentsOf:source)
    var input=ProcessingConfiguration();input.nativeOutputSizing=true;input.crop.mode = .preserveAspectRatio
    var recipe=ProcessingRecipe();recipe.enabled=[.resize,.filter,.output];recipe.longestEdge=200;recipe.allowUpscaling=true
    recipe.presetID="essentials.warm";recipe.format = .png
    let info=try WorkspacePhotoInfo.read(source)
    let config=try recipe.configuration(for:input,sourceSize:CGSize(width:info.width,height:info.height),grainSeed:7)
    let engine=ImageProcessor()
    let preview=try await engine.render(source,configuration:config,previewMaximum:500)
    let exported=try await engine.export(SourceAsset(url:source),configuration:config,to:folder)
    let encoded=try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(exported.output) as CFURL,nil))
    let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded,0,nil))
    XCTAssertEqual(max(image.width,image.height),200)
    XCTAssertEqual(try helper.pixels(image),try helper.pixels(preview));XCTAssertEqual(try Data(contentsOf:source),bytes)
  }
}
