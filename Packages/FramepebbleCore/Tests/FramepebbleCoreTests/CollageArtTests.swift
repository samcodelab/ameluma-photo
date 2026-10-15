import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FramepebbleCore

final class CollageArtTests: XCTestCase {
  func solid(_ red: CGFloat,_ green: CGFloat,_ blue: CGFloat) throws -> URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    let ctx=try XCTUnwrap(CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(red:red,green:green,blue:blue,alpha:1));ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    let destination=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(destination,try XCTUnwrap(ctx.makeImage()),nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    addTeardownBlock {try? FileManager.default.removeItem(at:url)}
    return url
  }
  func testTemplateCatalogUsesAllPhotosAndPreservesCellEdits() throws {
    XCTAssertEqual(CollageTemplate.catalog.count,74)
    XCTAssertEqual(Set(CollageTemplate.catalog.map(\.id)).count,74)
    let ids=(0..<37).map {_ in UUID()}
    for template in CollageTemplate.catalog {
      var p=CollageProject();p.arrange(ids,layout:.grid)
      p.cells[0].crop.zoom=2;p.cells[0].shape = .heart
      let old=p.cells[0]
      template.apply(to:&p,sources:ids)
      XCTAssertEqual(p.cells.count,37,template.name)
      XCTAssertEqual(Set(p.cells.map(\.sourceID)),Set(ids))
      XCTAssertEqual(p.cells[0].id,old.id)
      XCTAssertEqual(p.cells[0].crop.zoom,2)
      XCTAssertEqual(p.cells[0].shape,.heart)
      for cell in p.cells {XCTAssertTrue(cell.x.isFinite && cell.y.isFinite && cell.width>0 && cell.height>0)}
    }
  }
  func testShapeAndTextPartitionsHaveExactCountsAndCoverBothTextEnds() async throws {
    let builder=CollageArtBuilder(), source=UUID()
    for shape in [CollageShape.circle,.diamond,.heart,.text] {
      let p=try await builder.shape(project:CollageProject(),sources:[source],count:100,shape:shape,text:"HELLO")
      XCTAssertEqual(p.cells.count,100)
      XCTAssertEqual(p.silhouette,shape)
      XCTAssertTrue(p.cells.allSatisfy {$0.sourceID==source})
      let path=shape.path(in:CGRect(x:0,y:0,width:1,height:1),text:"HELLO")
      XCTAssertFalse(path.isEmpty)
      XCTAssertLessThan(p.cells.map(\.x).min() ?? 1,0.1)
      XCTAssertGreaterThan(p.cells.map {$0.x+$0.width}.max() ?? 0,0.9)
    }
  }
  func testShapeClippingAndThousandTileRenderKeepOriginalBytes() async throws {
    let url=try solid(1,0,0), bytes=try Data(contentsOf:url)
    let source=SourceAsset(url:url)
    var p=CollageProject();p.width=128;p.height=128;p.spacing=0
    p.background=RGBAColour(0,0,0,0)
    p.arrange([source.id],layout:.grid);p.cells[0].shape = .circle
    let processor=ImageProcessor()
    let circle=try await processor.renderCollage(p,sources:[source],edits:EditingSnapshot())
    let pixels=try ProcessingTests().pixels(circle)
    XCTAssertEqual(pixels[3],0)
    XCTAssertGreaterThan(pixels[(64*128+64)*4+3],240)
    p=try await CollageArtBuilder().shape(project:p,sources:[source.id],count:1000,shape:.heart,text:"")
    p.width=512;p.height=512;p.spacing=0
    let heart=try await processor.renderCollage(p,sources:[source],edits:EditingSnapshot(),previewMaximum:256)
    XCTAssertEqual(heart.width,256);XCTAssertEqual(heart.height,256)
    let alpha=try ProcessingTests().pixels(heart)
    XCTAssertEqual(alpha[3],0)
    XCTAssertEqual(try Data(contentsOf:url),bytes)
  }
  func testPhotomosaicUsesReferenceToneAndDistinctPhotosWhenReuseDisabled() async throws {
    let red=SourceAsset(url:try solid(1,0,0)), blue=SourceAsset(url:try solid(0,0,1))
    let reference=SourceAsset(url:try solid(1,0,0))
    var p=CollageProject();p.width=128;p.height=128
    let builder=CollageArtBuilder()
    let redResult=try await builder.photomosaic(project:p,sources:[red,blue],reference:reference,edits:EditingSnapshot(),count:4,allowReuse:true) {_ in}
    XCTAssertEqual(redResult.project.cells.count,4)
    XCTAssertTrue(redResult.project.cells.allSatisfy {$0.sourceID==red.id})
    let unique=try await builder.photomosaic(project:p,sources:[red,blue],reference:reference,edits:EditingSnapshot(),count:2,allowReuse:false) {_ in}
    XCTAssertEqual(Set(unique.project.cells.map(\.sourceID)),[red.id,blue.id])
    XCTAssertEqual(unique.project.mosaicReferenceID,reference.id)
  }
  func testNewCollageFieldsAndLegacyDocumentsRoundTrip() throws {
    var p=CollageProject();p.silhouette = .text;p.silhouetteText="HELLO"
    p.arrange([UUID()],layout:.grid);p.cells[0].shape = .diamond;p.silhouette = .text
    XCTAssertEqual(try JSONDecoder().decode(CollageProject.self,from:JSONEncoder().encode(p)),p)
    var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any])
    legacy.removeValue(forKey:"silhouette");legacy.removeValue(forKey:"silhouetteText")
    var cells=try XCTUnwrap(legacy["cells"] as? [[String:Any]]);cells[0].removeValue(forKey:"shape");legacy["cells"]=cells
    let old=try JSONDecoder().decode(CollageProject.self,from:JSONSerialization.data(withJSONObject:legacy))
    XCTAssertNil(old.silhouette);XCTAssertNil(old.cells[0].shape)
    var doc=ProjectDocument();doc.collage=old
    let saved=SavedCollage(name:"First",project:p);doc.collages=[saved];doc.openCollageIDs=[saved.id];doc.activeCollageID=saved.id
    let roundtrip=try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(doc))
    XCTAssertEqual(roundtrip.collages,[saved]);XCTAssertEqual(roundtrip.activeCollageID,saved.id)
  }
  func testArtGenerationCancellationAndInvalidText() async throws {
    let builder=CollageArtBuilder()
    let task=Task {try await builder.shape(project:CollageProject(),sources:[UUID()],count:1000,shape:.text,text:"HELLO")}
    task.cancel()
    do {_ = try await task.value;XCTFail("Expected cancellation")}catch {XCTAssertTrue(error is CancellationError)}
    do {_ = try await builder.shape(project:CollageProject(),sources:[UUID()],count:10,shape:.text,text:"");XCTFail()}catch {XCTAssertTrue(error is ProcessingError)}
  }
}

extension CollageArtTests {
  func testReferenceRegionsProduceRedLeftBlueRightAndAThousandEditableTiles() async throws {
    let red=SourceAsset(url:try solid(1,0,0)),blue=SourceAsset(url:try solid(0,0,1))
    let reference=SourceAsset(url:try solid(1,0,0))
    let ctx=try XCTUnwrap(CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));ctx.fill(CGRect(x:0,y:0,width:32,height:64))
    ctx.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));ctx.fill(CGRect(x:32,y:0,width:32,height:64))
    let out=try XCTUnwrap(CGImageDestinationCreateWithURL(reference.url as CFURL,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(out,try XCTUnwrap(ctx.makeImage()),nil);XCTAssertTrue(CGImageDestinationFinalize(out))
    let builder=CollageArtBuilder()
    var p=CollageProject();p.width=512;p.height=512
    let result=try await builder.photomosaic(project:p,sources:[red,blue],reference:reference,edits:EditingSnapshot(),count:4,allowReuse:true) {_ in}
    XCTAssertEqual(result.project.cells.map(\.sourceID),[red.id,blue.id,red.id,blue.id])
    let many=try await builder.photomosaic(project:p,sources:[red,blue],reference:reference,edits:EditingSnapshot(),count:1000,allowReuse:true) {_ in}
    XCTAssertEqual(many.project.cells.count,1000)
    let image=try await ImageProcessor().renderCollage(many.project,sources:[red,blue],edits:EditingSnapshot())
    XCTAssertEqual(image.width,512);XCTAssertEqual(image.height,512)
  }
}
