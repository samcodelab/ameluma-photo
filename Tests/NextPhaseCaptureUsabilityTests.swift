import XCTest
import SwiftUI
import FramepebbleCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
@testable import FramepebbleMac
#else
import UIKit
@testable import FramepebbleiOS
#endif

@MainActor final class NextPhaseCaptureUsabilityTests:XCTestCase {
  func testReviewedAnnotationsRecipeBuilderAndContextActionsCaptures() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner=Workspace(directory:root.appendingPathComponent("Personal"))
    await owner.openDemoWorkspace(root:root.appendingPathComponent("Demo"))
    let model=try XCTUnwrap(owner.demoWorkspace),photo=try XCTUnwrap(model.assets.first {$0.name=="Tidal Rocks.jpg"})
    model.openPhoto(photo);model.selection=Set(model.assets.suffix(3).map(\.id));model.selectionOrder=model.assets.suffix(3).map(\.id)
    model.openOverlayEditor(for:photo,masking:false)
    var draft=try XCTUnwrap(model.overlaySession),configuration=draft.current
    var highlight=Annotation();highlight.kind = .highlight;highlight.x=0.25;highlight.y=0.5;highlight.width=0.35;highlight.height=0.1;highlight.colour=RGBAColour(1,0.85,0,1);highlight.opacity=0.3
    var first=Annotation();first.kind = .callout;first.x=0.2;first.y=0.3;first.width=0.07;first.height=0.12;first.colour=RGBAColour(0.1,0.35,0.95,1)
    var second=first;second.id=UUID();second.x=0.7;second.y=0.6
    var arrow=Annotation();arrow.kind = .arrow;arrow.directionVersion=1;arrow.x=0.4;arrow.y=0.2;arrow.width=0.25;arrow.height=0.25;arrow.points=[NormalizedPoint(1,0),NormalizedPoint(0,1)];arrow.colour=RGBAColour(1,1,1,1)
    configuration.annotations += [highlight,first,second,arrow];draft.update(configuration);model.overlaySession=draft
    #if os(macOS)
    let window=NSWindow(contentRect:CGRect(x:0,y:0,width:1280,height:800),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua)
    let host=NSHostingView(rootView:AnyView(MacWorkspace(model:model).environment(\.colorScheme,.dark)));window.contentView=host;window.orderFront(nil)
    defer {window.orderOut(nil);window.contentView=nil}
    #else
    let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
    let pad=UIDevice.current.userInterfaceIdiom == .pad
    let window=UIWindow(windowScene:scene);window.frame=CGRect(origin:.zero,size:pad ? CGSize(width:1194,height:834):CGSize(width:390,height:844))
    let host=UIHostingController(rootView:AnyView(MobileWorkspace(reviewModel:model).environment(\.horizontalSizeClass,pad ? .regular:.compact)))
    window.rootViewController=host;window.makeKeyAndVisible();host.view.frame=window.bounds
    defer {window.isHidden=true;window.rootViewController=nil}
    #endif
    func capture(_ name:String) async throws {
      try await Task.sleep(for:.seconds(2))
      #if os(macOS)
      host.layoutSubtreeIfNeeded();let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      let attachment=XCTAttachment(data:try XCTUnwrap(bitmap.representation(using:.png,properties:[:])),uniformTypeIdentifier:UTType.png.identifier)
      #else
      host.view.layoutIfNeeded();var success=false
      let image=UIGraphicsImageRenderer(bounds:window.bounds).image {_ in success=window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)}
      XCTAssertTrue(success);let attachment=XCTAttachment(image:image)
      #endif
      attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    try await capture("Reviewed editable annotations")
    model.overlaySession=nil;model.overlayEditor=false
    let request=model.makeRecipeRequest(ids:[photo.id])
    #if os(macOS)
    window.setContentSize(CGSize(width:820,height:730))
    #endif
    #if os(macOS)
    host.rootView=AnyView(RecipeBuilder(model:model,request:request).environment(\.scenePhase,.active).environment(\.colorScheme,.dark).id("recipe"))
    #else
    host.rootView=AnyView(RecipeBuilder(model:model,request:request).environment(\.scenePhase,.active).id("recipe"))
    #endif
    try await Task.sleep(for:.seconds(5))
    try await capture("Visual recipe builder")
    #if os(macOS)
    window.setContentSize(CGSize(width:560,height:600))
    host.rootView=AnyView(UniversalActionsView(model:model,request:UniversalActionRequest(context:model.actionContext)).environment(\.colorScheme,.dark).id("actions"))
    #else
    host.rootView=AnyView(UniversalActionsView(model:model,request:UniversalActionRequest(context:model.actionContext)).id("actions"))
    #endif
    try await capture("Context-aware universal actions")
    #if os(macOS)
    window.setContentSize(CGSize(width:560,height:320))
    host.rootView=AnyView(UniversalActionsView(model:model,request:UniversalActionRequest(context:model.actionContext),initialQuery:"resize to 1920").environment(\.colorScheme,.dark).id("parameter"))
    #else
    host.rootView=AnyView(UniversalActionsView(model:model,request:UniversalActionRequest(context:model.actionContext),initialQuery:"resize to 1920").id("parameter"))
    #endif
    try await capture("Parameterized resize action")
    #if !os(macOS)
    host.rootView=AnyView(RecipeBuilder(model:model,request:request).environment(\.scenePhase,.active).environment(\.dynamicTypeSize,.accessibility2).id("large-recipe"))
    try await Task.sleep(for:.seconds(5))
    try await capture("Recipe builder large text")
    host.rootView=AnyView(UniversalActionsView(model:model,request:UniversalActionRequest(context:model.actionContext),initialQuery:"convert to png").environment(\.dynamicTypeSize,.accessibility2).id("large-actions"))
    try await capture("Universal actions large text")
    #endif
    XCTAssertEqual(model.selection.count,3);XCTAssertEqual(model.current?.id,photo.id)
    await model.stopWork();await owner.stopWork();model.persistenceTask?.cancel();owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at:root)
  }
}
