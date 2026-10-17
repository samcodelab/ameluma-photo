import XCTest
import CoreImage
@testable import FramepebbleCore

final class FilterPerformanceTests: XCTestCase {
  /// Explicit opt-in: release-build measurements are evidence, not hardware-independent assertions.
  func testReleaseFilterMeasurements() async throws {
    guard ProcessInfo.processInfo.environment["AMELUMA_FILTER_BENCHMARK"] == "1" else { throw XCTSkip("Run explicitly in Release on declared hardware") }
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source=root.appendingPathComponent("Resources/DemoWorkspace/Photos/27-coastal-hero-landscape.jpg")
    let input=try XCTUnwrap(CIImage(contentsOf:source))
    let enlarged=input.transformed(by:CGAffineTransform(scaleX:6000/input.extent.width,y:4000/input.extent.height))
    let ctx=CIContext();let cg=try XCTUnwrap(ctx.createCGImage(enlarged,from:CGRect(x:0,y:0,width:6000,height:4000)))
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:folder) }
    let engine=ImageProcessor();let url=folder.appendingPathComponent("24mp.jpg")
    try await engine.encode(cg,format:.jpeg,quality:0.92).write(to:url,options:.atomic)
    let asset=SourceAsset(url:url);let service=FilterPreviewService(directory:folder.appendingPathComponent("cache"))
    var c=ProcessingConfiguration();c.width=6000;c.height=4000;c.format = .jpeg
    let clock=ContinuousClock()
    func ms(_ start: ContinuousClock.Instant) -> Double { let d=start.duration(to:clock.now).components;return Double(d.seconds)*1000+Double(d.attoseconds)/1e15 }
    var cold:[Double]=[],warm:[Double]=[],slider:[Double]=[],first:[Double]=[],collections:[Double]=[]
    for iteration in 0..<20 {
      let begin=clock.now
      let decoded=try await ImageProcessor().thumbnail(url,maximum:1600)
      XCTAssertNotNil(decoded.dataProvider?.data)
      cold.append(ms(begin))
      await service.purge([asset.id])
      let all=clock.now
      for (i,p) in FilterCatalog.presets.prefix(6).enumerated() {
        c.filterEdit=FilterEdit(presetID:p.id,grainSeed:7)
        _=try await service.preview(asset,configuration:c,maximum:280,privateMode:false)
        if i == 0 { first.append(ms(all)) }
      }
      collections.append(ms(all))
      let cached=clock.now
      for p in FilterCatalog.presets.prefix(6) {
        c.filterEdit=FilterEdit(presetID:p.id,grainSeed:7)
        _=try await service.preview(asset,configuration:c,maximum:280,privateMode:false)
      }
      warm.append(ms(cached))
      c.filterEdit=FilterEdit(presetID:"film.amber",intensity:Double(iteration+1)/21,grainSeed:7)
      let start=clock.now
      let rendered=try await engine.render(url,configuration:c,previewMaximum:1600,decodeMaximum:1600)
      XCTAssertNotNil(rendered.dataProvider?.data)
      slider.append(ms(start))
    }
    func p95(_ values:[Double]) -> Double { values.sorted()[Int(ceil(Double(values.count)*0.95))-1] }
    let measurements=["coldDecode1600P95ms":p95(cold),"firstUncachedTileP95ms":p95(first),"sixUncachedTilesP95ms":p95(collections),"sixCachedTilesP95ms":p95(warm),"slider1600P95msIncludingDecode":p95(slider)]
    print("AMELUMA_FILTER_PERFORMANCE " + String(data:try JSONSerialization.data(withJSONObject:measurements,options:[.sortedKeys]),encoding:.utf8)!)
    let dimensions = try await engine.identify(url)
    XCTAssertEqual(dimensions,CGSize(width:6000,height:4000))
  }
}
