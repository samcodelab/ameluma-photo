import FramepebbleCore
import SwiftUI
import XCTest
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
@testable import FramepebbleMac
#else
import UIKit
@testable import FramepebbleiOS
#endif

@MainActor final class CreativeToolsCaptureTests: XCTestCase {
  func testEditorToolContinuityCaptures() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner=Workspace(directory:root.appendingPathComponent("Personal"))
    await owner.openDemoWorkspace(root:root.appendingPathComponent("Demo"))
    let model=try XCTUnwrap(owner.demoWorkspace)
    let asset=try XCTUnwrap(model.assets.first(where:{$0.name == "Coastal Hero.jpg"}))
    model.openPhoto(asset)
    let baseline=model.configuration(for:asset)
    #if os(macOS)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let host=NSHostingView(rootView:MacWorkspace(model:model).environment(\.colorScheme,.dark).environment(\.dynamicTypeSize,.large))
    window.contentView=host;window.orderFront(nil)
    defer { window.orderOut(nil);window.contentView=nil }
    #else
    let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
    let pad=UIDevice.current.userInterfaceIdiom == .pad
    let size=pad ? CGSize(width:1194,height:834):CGSize(width:390,height:844)
    let window=UIWindow(windowScene:scene);window.frame=CGRect(origin:.zero,size:size)
    let host=UIHostingController(rootView:MobileWorkspace(reviewModel:model).environment(\.horizontalSizeClass,pad ? .regular:.compact).environment(\.colorScheme,.light).environment(\.dynamicTypeSize,.large))
    window.rootViewController=host;window.makeKeyAndVisible();host.view.frame=window.bounds
    defer { window.isHidden=true;window.rootViewController=nil }
    #endif
    let requests=PhotoTool.allCases.map { ($0,false) }+[(PhotoTool.retouch,true),(.replaceColour,true),(.filters,true)]
    for (tool,largeText) in requests {
      #if os(macOS)
      host.rootView=MacWorkspace(model:model).environment(\.colorScheme,.dark).environment(\.dynamicTypeSize,largeText ? .accessibility3:.large)
      #else
      host.rootView=MobileWorkspace(reviewModel:model).environment(\.horizontalSizeClass,pad ? .regular:.compact).environment(\.colorScheme,.light).environment(\.dynamicTypeSize,largeText ? .accessibility3:.large)
      #endif
      // No changed draft is discarded here: capture state is intentionally unedited.
      if model.colourReplacementAsset != nil { model.colourReplacementAsset=nil;model.colourReplacementID=nil;model.overlayEditor=false }
      XCTAssertTrue(model.activatePhotoTool(tool,resolvingDraft:.discard))
      try await Task.sleep(for:.seconds(1))
      #if os(macOS)
      host.layoutSubtreeIfNeeded()
      let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      let attachment=XCTAttachment(data:try XCTUnwrap(bitmap.representation(using:.png,properties:[:])),uniformTypeIdentifier:UTType.png.identifier)
      #else
      host.view.layoutIfNeeded()
      var rendered=false
      let image=UIGraphicsImageRenderer(bounds:window.bounds).image { _ in rendered=window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
      XCTAssertTrue(rendered)
      let attachment=XCTAttachment(image:image)
      #endif
      attachment.name="Editor continuity — \(tool.rawValue)"+(largeText ? " — Large Text":"");attachment.lifetime = .keepAlways;add(attachment)
      XCTAssertEqual(model.current?.id,asset.id)
      XCTAssertEqual(model.configuration(for:asset),baseline,"Changing tools must not modify the photograph")
    }
    for metric in model.editorFeedbackMeasurements { print("EDITOR_CANVAS_SAMPLE tool=\(metric.label) milliseconds=\(metric.milliseconds) stages=\(metric.stages)") }
    let latencies=model.editorFeedbackMeasurements.map(\.milliseconds).sorted()
    if !latencies.isEmpty {
      let p95=latencies[min(latencies.count-1,Int(ceil(Double(latencies.count)*0.95))-1)]
      print("EDITOR_CANVAS_PREPARATION hosted_debug_count=\(latencies.count) median_ms=\(latencies[latencies.count/2]) p95_ms=\(p95)")
    }
    await model.stopWork();await owner.stopWork();model.persistenceTask?.cancel();owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at:root)
  }

  func testNativeCreativeToolsWithDemoPhoto() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner=Workspace(directory:root.appendingPathComponent("Personal"))
    await owner.openDemoWorkspace(root:root.appendingPathComponent("Demo"))
    let model=try XCTUnwrap(owner.demoWorkspace)
    let asset=try XCTUnwrap(model.assets.first(where:{$0.name == "Coastal Hero.jpg"}))
    model.openPhoto(asset)
    var edit=ColourReplacement();edit.source=RGBAColour(0.55,0.22,0.16,1);edit.replacement=RGBAColour(0.15,0.3,0.65,1);edit.range=0.22
    edit.points=[NormalizedPoint(0.27,0.44),NormalizedPoint(0.38,0.42),NormalizedPoint(0.47,0.49),NormalizedPoint(0.58,0.43),NormalizedPoint(0.70,0.46),NormalizedPoint(0.77,0.59),NormalizedPoint(0.70,0.64),NormalizedPoint(0.64,0.63),NormalizedPoint(0.61,0.75),NormalizedPoint(0.48,0.79),NormalizedPoint(0.27,0.78),NormalizedPoint(0.18,0.71),NormalizedPoint(0.20,0.56)]
    var config=model.configuration(for:asset);config.colourReplacements=[edit];model.setImageConfiguration(config,for:asset.id)
    #if os(macOS)
    let size=CGSize(width:1100,height:760)
    let window=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua)
    defer { window.contentView=nil;window.close() }
    func capture<V:View>(_ view:V,_ name:String) async throws {
      let host=NSHostingView(rootView:view.environment(\.colorScheme,.dark));window.contentView=host;host.frame=CGRect(origin:.zero,size:size)
      try await Task.sleep(for:.seconds(2));host.layoutSubtreeIfNeeded()
      let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));window.appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in:host.bounds,to:bitmap) }
      let attachment=XCTAttachment(data:try XCTUnwrap(bitmap.representation(using:.png,properties:[:])),uniformTypeIdentifier:UTType.png.identifier)
      attachment.name="Creative Tools — Mac "+name;attachment.lifetime = .keepAlways;add(attachment)
    }
    #else
    let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
    let pad=UIDevice.current.userInterfaceIdiom == .pad
    let size=pad ? CGSize(width:1194,height:834) : CGSize(width:390,height:844)
    let window=UIWindow(windowScene:scene);window.frame=CGRect(origin:.zero,size:size)
    defer { window.isHidden=true;window.rootViewController=nil }
    func capture<V:View>(_ view:V,_ name:String) async throws {
      let host=UIHostingController(rootView:view.environment(\.horizontalSizeClass,pad ? .regular:.compact).environment(\.colorScheme,.light))
      window.rootViewController=host;window.isHidden=false;host.view.frame=window.bounds
      try await Task.sleep(for:.seconds(2));host.view.layoutIfNeeded()
      var rendered=false
      let image=UIGraphicsImageRenderer(bounds:window.bounds).image { _ in rendered=window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
      XCTAssertTrue(rendered)
      let attachment=XCTAttachment(image:image);attachment.name="Creative Tools — "+(pad ? "iPad ":"iPhone ")+name;attachment.lifetime = .keepAlways;add(attachment)
    }
    #endif
    try await capture(StickerPicker(choose:{_ in}),"Stickers")
    try await capture(StickerPicker(collection:"Celebrate",choose:{_ in}),"Celebrate")
    try await capture(StickerPicker(collection:"Decorate",choose:{_ in}),"Decorate")
    try await capture(StickerPicker(choose:{_ in}).environment(\.dynamicTypeSize,.accessibility3),"Stickers Large Text")
    try await capture(ColourReplacementEditor(model:model,asset:asset,editingID:edit.id),"Replace Colour")
    try await capture(ScrollView { ColourMixControls(model:model,expanded:true).padding(16) }.frame(maxWidth:360),"Colour Mix")
    await model.stopWork();await owner.stopWork();model.persistenceTask?.cancel();owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at:root)
  }
}
