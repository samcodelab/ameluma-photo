import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FramepebbleCore

@MainActor final class EditorDocumentTests:XCTestCase {
  func root() throws -> URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
  }
  func source(_ root:URL) throws -> URL {
    let space=try XCTUnwrap(CGColorSpace(name:CGColorSpace.sRGB))
    let c=try XCTUnwrap(CGContext(data:nil,width:16,height:12,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    c.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));c.fill(CGRect(x:0,y:0,width:8,height:12))
    c.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));c.fill(CGRect(x:8,y:0,width:8,height:12))
    let image=try XCTUnwrap(c.makeImage()),url=root.appendingPathComponent("source.png")
    let dest=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(dest,image,nil);XCTAssertTrue(CGImageDestinationFinalize(dest));return url
  }
  func rgba(_ image:CGImage,_ x:Int,_ y:Int) throws -> [UInt8] {
    var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
    let space=try XCTUnwrap(CGColorSpace(name:CGColorSpace.sRGB))
    try bytes.withUnsafeMutableBytes {b in
      let c=try XCTUnwrap(CGContext(data:b.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue));c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    }
    let i=(y*image.width+x)*4;return Array(bytes[i..<i+4])
  }
  func testEveryOriginalWatermarkTemplateUsesEditableLayersAndTransparentOutput() async throws {
    let templates = WatermarkTemplates.all
    XCTAssertEqual(templates.count, 12); XCTAssertEqual(Set(templates.map(\.id)).count, 12)
    let renderer = EditorDocumentRenderer()
    for template in templates {
      let document = template.document
      XCTAssertTrue(document.watermarkDesign == true); XCTAssertNil(document.background)
      XCTAssertGreaterThanOrEqual(document.layers.count, 2)
      try document.validateForExport()
      let image = try await renderer.render(document, resources: [:], maximum: 240)
      XCTAssertEqual(max(image.width, image.height), 240)
      XCTAssertEqual(try rgba(image, 0, 0)[3], 0, template.name)
      let roundTrip = try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(document))
      XCTAssertEqual(roundTrip, document)
    }
    var edited = templates[0].document
    edited.layers[0].x = 99
    XCTAssertNotEqual(edited, WatermarkTemplates.all[0].document)
  }
  func testWatermarkVectorOutputCanScaleWithoutChangingTheEditableDesign() async throws {
    let document = try XCTUnwrap(WatermarkTemplates.all.first?.document)
    let snapshot = document
    let renderer = EditorDocumentRenderer()
    let image = try await renderer.render(document, resources: [:], outputLongEdge: 2400)
    XCTAssertEqual(image.width, 2400); XCTAssertEqual(image.height, 520)
    XCTAssertEqual(document, snapshot); XCTAssertEqual(try rgba(image, 0, 0)[3], 0)
    do { _ = try await renderer.render(document, resources: [:], outputLongEdge: 20000); XCTFail("Pixel budget must be enforced") } catch {}
    do { _ = try await renderer.render(document, resources: [:], maximum: 200, outputLongEdge: 1200); XCTFail("Preview and output sizing must be unambiguous") } catch {}
  }

  func testTextTreatmentsAreVersionedEditableAndChangeRenderedPixels() async throws {
    var doc = EditorDocument(); doc.width = 240; doc.height = 100
    var text = EditorText(); text.text = "Ameluma"; text.fontSize = 34; text.colour = RGBAColour(1,1,1,1)
    var layer = EditorLayer(name: "Signature", content: .text(text)); layer.width = 240; layer.height = 100
    doc.layers = [layer]
    let renderer = EditorDocumentRenderer()
    let original = try await renderer.render(doc, resources: [:])
    text.outlineColour = RGBAColour(0,0,0,1); text.outlineWidth = 2; text.shadow = EditorTextShadow()
    doc.layers[0].content = .text(text)
    XCTAssertThrowsError(try doc.validate(), "Older readers must not silently discard new treatments")
    doc.version = 2
    let styled = try await renderer.render(doc, resources: [:])
    XCTAssertNotEqual(try ProcessingTests().pixels(original), try ProcessingTests().pixels(styled))
    XCTAssertEqual(try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(doc)), doc)
    text.outlineWidth = .nan; doc.layers[0].content = .text(text)
    XCTAssertThrowsError(try doc.validate())
  }

  func testPortablePackageSurvivesDeletedOriginalAndAtomicReplacement() async throws {
    let root=try root();defer{try? FileManager.default.removeItem(at:root)}
    let url=try source(root),original=try Data(contentsOf:url)
    let resource=EditorResource(name:"source.png",fileExtension:"png")
    var c=ProcessingConfiguration();c.nativeOutputSizing=true;c.format = .png
    var layer=EditorLayer(name:"Photo",content:.image(resourceID:resource.id,configuration:c));layer.width=16;layer.height=12
    var doc=EditorDocument();doc.width=20;doc.height=16;doc.resources=[resource];doc.layers=[layer]
    let store=EditorDocumentStore(),package=root.appendingPathComponent("Test.ameluma")
    try await store.save(doc,resources:[resource.id:url],to:package)
    XCTAssertEqual(try Data(contentsOf:url),original)
    let loaded=try await store.load(package);XCTAssertEqual(loaded,doc)
    try FileManager.default.removeItem(at:url)
    let managed=package.appendingPathComponent("Resources").appendingPathComponent(resource.filename)
    let image=try await EditorDocumentRenderer().render(loaded,resources:[resource.id:managed])
    XCTAssertEqual(image.width,20);XCTAssertEqual(image.height,16)
    XCTAssertEqual(try rgba(image,19,15)[3],0)
    doc.name="Updated";try await store.save(doc,resources:[resource.id:managed],to:package)
    let updated=try await store.load(package);XCTAssertEqual(updated.name,"Updated")
    XCTAssertEqual(try Data(contentsOf:managed),original)
  }
  func testFailedAndCancelledSaveRetainPreviousPackage() async throws {
    let root=try root();defer{try? FileManager.default.removeItem(at:root)}
    let store=EditorDocumentStore(),package=root.appendingPathComponent("Safe.ameluma")
    var doc=EditorDocument();try await store.save(doc,resources:[:],to:package)
    let original=try Data(contentsOf:package.appendingPathComponent("manifest.json"))
    doc.name="Do not publish"
    let task=Task {try Task.checkCancellation();try await store.save(doc,resources:[:],to:package)}
    task.cancel();do{try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}
    XCTAssertEqual(try Data(contentsOf:package.appendingPathComponent("manifest.json")),original)
    let resource=EditorResource(name:"missing",fileExtension:"png");doc.resources=[resource]
    do{try await store.save(doc,resources:[:],to:package);XCTFail("Expected missing resource")}catch{}
    XCTAssertEqual(try Data(contentsOf:package.appendingPathComponent("manifest.json")),original)
  }
  func testRejectsUnknownVersionUnsafePathsAndSymlinks() async throws {
    var doc=EditorDocument();doc.version=99;XCTAssertThrowsError(try doc.validate())
    doc.version=1;doc.resources=[EditorResource(name:"Bad",fileExtension:"../png")];XCTAssertThrowsError(try doc.validate())
    let root=try root();defer{try? FileManager.default.removeItem(at:root)}
    let resource=EditorResource(name:"Source",fileExtension:"png");doc.resources=[resource]
    let source=try source(root),package=root.appendingPathComponent("Bad.ameluma"),store=EditorDocumentStore()
    try await store.save(doc,resources:[resource.id:source],to:package)
    let owned=package.appendingPathComponent("Resources").appendingPathComponent(resource.filename)
    try FileManager.default.removeItem(at:owned);try FileManager.default.createSymbolicLink(at:owned,withDestinationURL:source)
    do{_ = try await store.load(package);XCTFail("Expected symlink rejection")}catch{}
  }
  func testDocumentHistoryRestoresSemanticIdentityAndInvalidEditsDoNotCommit() throws {
    let doc=EditorDocument();var history=EditorDocumentHistory(doc)
    var next=doc;next.layers=[EditorLayer(name:"Editable",content:.text(EditorText()))]
    let id=next.layers[0].id;try history.apply(next,title:"Add Text")
    var moved=next;moved.layers[0].x=100;try history.apply(moved,title:"Move Text")
    history.undo();XCTAssertEqual(history.current,next);XCTAssertEqual(history.current.layers[0].id,id)
    history.redo();XCTAssertEqual(history.current,moved)
    var invalid=moved;invalid.layers[0].opacity = .nan
    XCTAssertThrowsError(try history.apply(invalid,title:"Invalid"));XCTAssertEqual(history.current,moved)
    history.undo();var branch=history.current;branch.layers[0].name="Renamed";try history.apply(branch,title:"Rename")
    XCTAssertTrue(history.redoSteps.isEmpty)
  }
  func testLayerVisibilityOpacityTransformsAndBlendModes() async throws {
    var doc=EditorDocument();doc.width=20;doc.height=20
    var shape=EditorShape();shape.fill=RGBAColour(1,0,0,1);shape.strokeWidth=0
    var layer=EditorLayer(name:"Red",content:.shape(shape));layer.width=6;layer.height=4;layer.x=2;layer.y=3
    doc.layers=[layer];let renderer=EditorDocumentRenderer()
    let image=try await renderer.render(doc,resources:[:])
    XCTAssertEqual(try rgba(image,3,4),[255,0,0,255]);XCTAssertEqual(try rgba(image,0,0)[3],0)
    doc.layers[0].visible=false
    let hidden=try await renderer.render(doc,resources:[:]);XCTAssertEqual(try rgba(hidden,3,4)[3],0)
    doc.layers[0].visible=true;doc.layers[0].opacity=0.5
    let translucent=try await renderer.render(doc,resources:[:]);XCTAssertEqual(try rgba(translucent,3,4)[3],128,accuracy:1)
    doc.background=RGBAColour(1,1,1,1)
    for mode in EditorBlendMode.allCases {
      doc.layers[0].blendMode=mode;doc.layers[0].rotation=90
      let rendered=try await renderer.render(doc,resources:[:],maximum:10)
      XCTAssertEqual(rendered.width,10);XCTAssertEqual(rendered.height,10)
    }
  }
  func testFlattenedDocumentExportPreservesAlphaMatteCollisionAndSourceBytes() async throws {
    let root=try root();defer{try? FileManager.default.removeItem(at:root)}
    let original=try source(root),bytes=try Data(contentsOf:original)
    var doc=EditorDocument();doc.width=20;doc.height=20
    var shape=EditorShape();shape.fill=RGBAColour(1,0,0,1);shape.strokeWidth=0
    var layer=EditorLayer(name:"Shape",content:.shape(shape));layer.width=8;layer.height=8;doc.layers=[layer]
    try doc.validateForExport()
    let image=try await EditorDocumentRenderer().render(doc,resources:[:]),processor=ImageProcessor()
    var config=ProcessingConfiguration();config.format = .png
    var profile=ExportProfile();profile.suffix="";profile.namingTemplate="{name}"
    let first=try await processor.publish(image,asset:SourceAsset(url:original),configuration:config,to:root,profile:profile,flattenTransparency:true)
    let second=try await processor.publish(image,asset:SourceAsset(url:original),configuration:config,to:root,profile:profile,flattenTransparency:true)
    XCTAssertNotEqual(first.output,second.output)
    let png=try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(first.output) as CFURL,nil))
    let decoded=try XCTUnwrap(CGImageSourceCreateImageAtIndex(png,0,nil))
    XCTAssertEqual(decoded.width,20);XCTAssertEqual(decoded.height,20);XCTAssertEqual(try rgba(decoded,19,19)[3],0)
    config.format = .jpeg
    let jpeg=try await processor.publish(image,asset:SourceAsset(url:original),configuration:config,to:root,profile:profile,flattenTransparency:true)
    let source=try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(jpeg.output) as CFURL,nil))
    let matte=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
    let pixel=try rgba(matte,19,19);XCTAssertGreaterThan(pixel[0],250);XCTAssertGreaterThan(pixel[1],250);XCTAssertGreaterThan(pixel[2],250)
    XCTAssertEqual(try Data(contentsOf:original),bytes)
  }
  func testPrivacyReviewSurvivesSerializationAndBlocksOnlyVisibleOutput() throws {
    var doc=EditorDocument();let layer=EditorLayer(name:"Review",content:.text(EditorText()))
    doc.layers=[layer];doc.privacyReviewLayerIDs=[layer.id]
    let restored=try JSONDecoder().decode(EditorDocument.self,from:JSONEncoder().encode(doc))
    XCTAssertThrowsError(try restored.validateForExport())
    doc.layers[0].visible=false;XCTAssertNoThrow(try doc.validateForExport())
    doc.layers[0].visible=true;doc.privacyReviewLayerIDs=[];XCTAssertNoThrow(try doc.validateForExport())
  }
  func testBlendModesMatchOpaqueSRGBReferenceValues() async throws {
    var doc=EditorDocument();doc.width=4;doc.height=4;doc.background=RGBAColour(0.6,0.6,0.6,1)
    var shape=EditorShape();shape.fill=RGBAColour(0.25,0.25,0.25,1);shape.strokeWidth=0
    var layer=EditorLayer(name:"Blend",content:.shape(shape));layer.width=4;layer.height=4;doc.layers=[layer]
    let expected:[EditorBlendMode:Double]=[.normal:0.25,.multiply:0.15,.screen:0.7,.overlay:0.4,.darken:0.25,.lighten:0.6,.softLight:0.48,.hardLight:0.3]
    let renderer=EditorDocumentRenderer()
    for mode in EditorBlendMode.allCases {
      doc.layers[0].blendMode=mode
      let image=try await renderer.render(doc,resources:[:]),pixel=try rgba(image,2,2)
      let value=try XCTUnwrap(expected[mode])*255
      XCTAssertEqual(Double(pixel[0]),value,accuracy:2,mode.rawValue)
      XCTAssertEqual(pixel[0],pixel[1]);XCTAssertEqual(pixel[1],pixel[2]);XCTAssertEqual(pixel[3],255)
    }
  }
  func testMovingAndRenamingReuseContentButStylesInvalidate() async throws {
    var doc=EditorDocument();doc.width=100;doc.height=100
    var layer=EditorLayer(name:"One",content:.shape(EditorShape()));layer.width=20;layer.height=20;doc.layers=[layer]
    let renderer=EditorDocumentRenderer()
    _ = try await renderer.render(doc,resources:[:],maximum:100)
    doc.layers[0].x=20;doc.layers[0].name="Moved"
    _ = try await renderer.render(doc,resources:[:],maximum:100)
    let reused=await renderer.reusedLayers;XCTAssertEqual(reused,1)
    var shape=EditorShape();shape.fill=RGBAColour(1,0,0,1);doc.layers[0].content = .shape(shape)
    _ = try await renderer.render(doc,resources:[:],maximum:100)
    let changed=await renderer.reusedLayers;XCTAssertEqual(changed,0)
  }
  func testEditableTextShapeAndPreviewRoundTrip() async throws {
    let root=try root();defer{try? FileManager.default.removeItem(at:root)}
    var doc=EditorDocument();doc.width=240;doc.height=120
    var text=EditorText();text.text="Hello 🌿";text.fontSize=26;text.bold=true;text.underline=true
    var layer=EditorLayer(name:"Title",content:.text(text));layer.width=240;layer.height=120
    doc.layers=[layer];let package=root.appendingPathComponent("Text.ameluma"),store=EditorDocumentStore()
    try await store.save(doc,resources:[:],to:package)
    let restored=try await store.load(package);XCTAssertEqual(restored,doc)
    let renderer=EditorDocumentRenderer(),full=try await renderer.render(restored,resources:[:]),preview=try await renderer.render(restored,resources:[:],maximum:120)
    XCTAssertEqual(preview.width,120);XCTAssertEqual(preview.height,60)
    var nonempty=false
    for y in stride(from:0,to:120,by:4) {for x in stride(from:0,to:240,by:4) {if try rgba(full,x,y)[3]>0 {nonempty=true;break}}}
    XCTAssertTrue(nonempty,"Text must be rendered, not just saved as metadata")
  }
}
