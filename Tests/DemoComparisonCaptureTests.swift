import FramepebbleCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
#if os(macOS)
import AppKit
@testable import FramepebbleMac
#else
import UIKit
@testable import FramepebbleiOS
#endif

/// Repeatable comparison evidence from the bundled demo, never a personal workspace.
@MainActor final class DemoComparisonCaptureTests: XCTestCase {
  func testPhotoFilterPanelWithDemoSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner = Workspace(directory: root.appendingPathComponent("Owner"), startInLibrary: true)
    await owner.openDemoWorkspace(root: root.appendingPathComponent("Demo"))
    let model = try XCTUnwrap(owner.demoWorkspace)
    let source = try XCTUnwrap(model.assets.first { $0.name == "Lorikeet Hero Clean.jpg" })
    model.openPhoto(source)
    let original = model.configuration(for: source)
    #if os(macOS)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: ScrollView { PhotoLooksPicker(model: model).padding(16) }.environment(\.colorScheme, .dark))
    window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: 380, height: 360)
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .seconds(2))
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
    #else
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
    let host = UIHostingController(rootView: NavigationStack { ScrollView { PhotoLooksPicker(model: model).padding(16) }.navigationTitle("Photo Filters") })
    window.rootViewController = host; window.isHidden = false
    defer { window.isHidden = true; window.rootViewController = nil }
    try await Task.sleep(for: .seconds(2))
    host.view.layoutIfNeeded()
    var rendered = false
    let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    XCTAssertTrue(rendered)
    let attachment = XCTAttachment(image: screenshot)
    #endif
    attachment.name = "Photo Filters — native panel"; attachment.lifetime = .keepAlways; add(attachment)
    let sourceBytes = try Data(contentsOf: source.url)
    for look in [PhotoLook?.none] + PhotoLook.allCases.map(Optional.some) {
      var config = original; config.look = look; config.lookStrength = 1
      let image = try await model.processor.render(source.url, configuration: config, previewMaximum: 480, decodeMaximum: 768)
      let data = NSMutableData()
      let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      let proof = XCTAttachment(data: data as Data, uniformTypeIdentifier: UTType.png.identifier)
      proof.name = "Filter Proof — " + (look?.title ?? "Original"); proof.lifetime = .keepAlways; add(proof)
    }
    XCTAssertEqual(try Data(contentsOf: source.url), sourceBytes)

    XCTAssertEqual(model.configuration(for: source), original, "Loading filter previews must not edit the photo")
    await model.stopWork(); await owner.stopWork()
    model.persistenceTask?.cancel(); owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at: root)
  }
  func testDemoWorkspaceComparisonCaptures() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("demo-comparison-" + UUID().uuidString)
    let owner = Workspace(directory: root.appendingPathComponent("Personal"), startInLibrary: true)
    await owner.openDemoWorkspace(root: root.appendingPathComponent("Demo"))
    let model = try XCTUnwrap(owner.demoWorkspace, owner.issues.joined(separator: "; "))
    XCTAssertEqual(model.workspaceAssets.count, 30)
    let hero = try XCTUnwrap(model.assets.first { $0.name == "Lorikeet Hero Clean.jpg" })
    let landscape = try XCTUnwrap(model.assets.first { $0.name == "Tidal Rocks.jpg" })
    #if os(macOS)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingView(rootView: MacWorkspace(model: model)
      .environment(\.workspaceOwner, owner)
      .environment(\.colorScheme, .dark))
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    defer { window.contentView = nil; window.close() }
    func capture(_ name: String, portrait: Bool = false) async throws {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(1400))
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      window.appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
      let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
      attachment.name = "Demo — Mac " + name; attachment.lifetime = .keepAlways; add(attachment)
      XCTAssertEqual(host.bounds.size, CGSize(width: 1440, height: 900))
    }
    #else
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    let pad = UIDevice.current.userInterfaceIdiom == .pad
    defer { window.isHidden = true; window.rootViewController = nil }
    let host = UIHostingController(rootView: MobileWorkspace(reviewModel: owner)
      .environment(\.horizontalSizeClass, pad ? .regular : .compact)
      .environment(\.verticalSizeClass, .regular)
      .environment(\.dynamicTypeSize, .large)
      .environment(\.colorScheme, .light))
    host.traitOverrides.horizontalSizeClass = pad ? .regular : .compact
    host.traitOverrides.verticalSizeClass = .regular
    window.rootViewController = host; window.isHidden = false
    func capture(_ name: String, portrait: Bool = false) async throws {
      let size = pad ? (portrait ? CGSize(width: 834, height: 1194) : CGSize(width: 1194, height: 834)) : CGSize(width: 390, height: 844)
      window.frame = CGRect(origin: .zero, size: size)
      host.view.frame = window.bounds
      host.view.setNeedsLayout(); host.view.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(1600))
      host.view.layoutIfNeeded()
      if !pad && model.overlayEditor {
        func hasPresentation(_ controller: UIViewController) -> Bool {
          controller.presentedViewController != nil || controller.children.contains(where: hasPresentation)
        }
        XCTAssertTrue(hasPresentation(host), "Capture the presented editor, not the underlying gallery")
      }
      var rendered = false
      print("Demo capture \(name): window=\(window.bounds), host=\(host.view.bounds), insets=\(host.view.safeAreaInsets)")
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      XCTAssertTrue(rendered)
      let attachment = XCTAttachment(image: image)
      attachment.name = "Demo — " + (pad ? "iPad " : "iPhone ") + name + (portrait && pad ? " portrait" : "")
      attachment.lifetime = .keepAlways; add(attachment)
    }
    #endif
    model.showLibrary()
    try await capture("Browse")
    model.openPhoto(landscape); model.openPhoto(hero); model.choosePhotoInspector(.adjust)
    try await capture("Hero Adjust")
    #if os(iOS)
    if UIDevice.current.userInterfaceIdiom == .pad { try await capture("Hero Adjust", portrait: true) }
    #endif
    model.choosePhotoInspector(.filters)
    try await capture("Hero Filters")
    #if os(iOS)
    if UIDevice.current.userInterfaceIdiom == .pad { try await capture("Hero Filters", portrait: true) }
    #endif
    model.choosePhotoInspector(.adjust)
    model.openPhoto(landscape)
    try await capture("Landscape Adjust")
    if let landscapeHero = model.assets.first(where: { $0.name == "Coastal Hero Landscape.jpg" }) {
      model.openPhoto(landscapeHero)
      try await capture("Landscape Hero Adjust")
    }
    model.openPhoto(hero)
    XCTAssertTrue(model.activatePhotoTool(.retouch))
    try await capture("Hero Retouch")
    #if os(iOS)
    if UIDevice.current.userInterfaceIdiom == .pad { try await capture("Hero Retouch", portrait: true) }
    #endif
    XCTAssertTrue(model.activatePhotoTool(.privacy))
    try await capture("Hero Privacy")
    XCTAssertTrue(model.activatePhotoTool(.adjust, resolvingDraft: .discard))
    let batch = Array(model.assets.filter { $0.name != "Coastal Hero Landscape.jpg" }.prefix(8))
    model.selection = Set(batch.map(\.id))
    model.beginBatch(ids: batch.map(\.id))
    model.mode = .browse
    try await capture("Batch Browse")
    model.mode = .frame
    try await capture("Batch Frame")
    model.mode = .compare
    try await capture("Batch Compare")
    model.mode = .frame
    #if os(iOS)
    if UIDevice.current.userInterfaceIdiom == .pad { try await capture("Batch Frame", portrait: true) }
    #endif
    XCTAssertEqual(model.batchInputIDs, Set(batch.map(\.id)))
    let batchInputs = model.batchInputIDs
    let photoEdits = model.edits
    model.startGIF(ids: batch.prefix(3).map(\.id))
    let gifFrames = try XCTUnwrap(model.gifProject).frames
    try await capture("GIF")
    XCTAssertEqual(model.gifProject?.frames, gifFrames, "Presentation must not change independent frame settings")
    model.switchWorkflow(.collages)
    model.ensureCollageDocument()
    var composition = model.collage
    composition.arrange(batch.prefix(3).map(\.id), layout: .magazine)
    model.changeCollage(composition)
    try await capture("Collage")
    XCTAssertEqual(model.collage, composition)
    XCTAssertEqual(model.batchInputIDs, batchInputs)
    XCTAssertEqual(model.edits, photoEdits)
    await model.stopWork(); await owner.stopWork()
    model.persistenceTask?.cancel(); owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at: root)
  }
}

extension DemoComparisonCaptureTests {
  /// Generated bundled photographs only. A contact sheet per recipe compares 30/70/100%
  /// across portrait, landscape, foliage, interior, low-light and high-contrast samples.
  func testCreativeFilterValidationSheets() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("filter-proof-"+UUID().uuidString)
    let owner=Workspace(directory:root.appendingPathComponent("Owner"),startInLibrary:true)
    await owner.openDemoWorkspace(root:root.appendingPathComponent("Demo"))
    let model=try XCTUnwrap(owner.demoWorkspace)
    let preferred=["Coastal Hero.jpg","Tidal Rocks.jpg","Forest Path.jpg","Sunlit Interior.jpg","Rainy Night.jpg","Mountain Lake.jpg"]
    let samples=preferred.compactMap { name in model.assets.first{$0.name == name} }
    XCTAssertEqual(samples.count,6)
    let space=try XCTUnwrap(CGColorSpace(name:CGColorSpace.sRGB))
    let renderer=ImageProcessor()
    for preset in FilterCatalog.presets {
      let context=try XCTUnwrap(CGContext(data:nil,width:960,height:360,bitsPerComponent:8,bytesPerRow:960*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
      for (row,intensity) in [0.3,0.7,1.0].enumerated() {
        for (col,source) in samples.enumerated() {
          var c=model.configuration(for:source);c.filterEdit=FilterEdit(presetID:preset.id,intensity:intensity,grainSeed:Workspace.filterSeed(source.id))
          let image=try await renderer.render(source.url,configuration:c,previewMaximum:160,decodeMaximum:384)
          let scale=min(160/CGFloat(image.width),120/CGFloat(image.height))
          let w=CGFloat(image.width)*scale,h=CGFloat(image.height)*scale
          context.draw(image,in:CGRect(x:CGFloat(col)*160+(160-w)/2,y:CGFloat(2-row)*120+(120-h)/2,width:w,height:h))
        }
      }
      let data=NSMutableData();let dest=try XCTUnwrap(CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil))
      CGImageDestinationAddImage(dest,try XCTUnwrap(context.makeImage()),nil);XCTAssertTrue(CGImageDestinationFinalize(dest))
      let attachment=XCTAttachment(data:data as Data,uniformTypeIdentifier:"public.png")
      attachment.name="Creative Validation — "+preset.id;attachment.lifetime = .keepAlways;add(attachment)
    }
    await model.stopWork();await owner.stopWork();model.persistenceTask?.cancel();owner.persistenceTask?.cancel()
    try? FileManager.default.removeItem(at:root)
  }
}
