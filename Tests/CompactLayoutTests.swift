import FramepebbleCore
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import FramepebbleiOS

/// Safe native hierarchy captures on Simulator; never captures the user's desktop or library.
@MainActor final class CompactLayoutTests: XCTestCase {
  func testPhotoEditorAtCompactAndAccessibilitySizes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = Workspace(directory: root)
    let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.22, green: 0.45, blue: 0.65, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
    context.move(to: CGPoint(x: 0, y: 0)); context.addLine(to: CGPoint(x: 400, y: 450))
    context.addLine(to: CGPoint(x: 800, y: 0)); context.closePath(); context.fillPath()
    let image = try XCTUnwrap(context.makeImage())
    for number in 1...6 {
      let url = model.directory.appendingPathComponent("Holiday landscape \(number).png")
      let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
        UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      model.assets.append(SourceAsset(url: url))
    }
    model.selected = model.assets[0].id
    model.switchWorkflow(.photo)
    model.openPhoto(model.assets[1])
    model.openPhoto(model.assets[0])
    XCTAssertEqual(model.editorTabs.count, 2)
    model.choosePhotoInspector(.adjust)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    defer { model.persistenceTask?.cancel(); window.isHidden = true; window.rootViewController = nil }
    func capture<V: View>(_ name: String, view: V, type: DynamicTypeSize, scheme: ColorScheme, scrollY: CGFloat? = nil, requirePhoto: Bool = false, regular: Bool = false, viewport: CGSize = CGSize(width: 390, height: 844)) async throws {
      window.frame = CGRect(origin: .zero, size: viewport)
      let controller = UIHostingController(rootView:
        NavigationStack { view }.environment(\.horizontalSizeClass, regular ? .regular : .compact)
          .environment(\.verticalSizeClass, viewport.height < 500 ? .compact : .regular)
          .environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme))
      window.rootViewController = controller
      window.isHidden = false
      controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(600))
      controller.view.layoutIfNeeded()
      if let scrollY {
        func firstScrollView(_ view: UIView) -> UIScrollView? {
          if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { return scroll }
          return view.subviews.lazy.compactMap { firstScrollView($0) }.first
        }
        let scroll = try XCTUnwrap(firstScrollView(controller.view))
        scroll.setContentOffset(CGPoint(x: 0, y: min(scrollY, max(0, scroll.contentSize.height - scroll.bounds.height))), animated: false)
        controller.view.layoutIfNeeded()
      }
      let renderer = UIGraphicsImageRenderer(bounds: controller.view.bounds)
      var rendered = false
      let screenshot = renderer.image { _ in
        rendered = controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
      }
      XCTAssertTrue(rendered, "The native hierarchy must render, rather than attaching a blank image")
      XCTAssertGreaterThan(screenshot.size.width, 300)
      if requirePhoto {
        let pixelsWide = 120, pixelsHigh = 240
        var pixels = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)
        try pixels.withUnsafeMutableBytes { bytes in
          let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: pixelsWide, height: pixelsHigh,
            bitsPerComponent: 8, bytesPerRow: pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.draw(try XCTUnwrap(screenshot.cgImage), in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        }
        let sourcePixels = stride(from: 0, to: pixels.count, by: 4).filter { index in
          let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
          let sky = (30...90).contains(r) && (80...150).contains(g) && (130...200).contains(b) && b > g + 10
          let hillside = (30...90).contains(r) && (120...190).contains(g) && (50...130).contains(b) && g > r + 30 && g > b + 30
          return sky || hillside
        }.count
        XCTAssertGreaterThan(Double(sourcePixels) / Double(pixelsWide * pixelsHigh), name.hasPrefix("Retouch — phone") ? 0.15 : 0.06,
          "\(name): the source photo must retain meaningful visible area")
      }
      if name.hasPrefix("Review —") { try screenshot.pngData()?.write(to: root.appendingPathComponent(name.replacingOccurrences(of: " /", with: "_") + ".png")) }
      let attachment = XCTAttachment(image: screenshot)
      attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    // Fresh review captures use the complete native shell and explicit, known scope.
    let reviewIsPad = UIDevice.current.userInterfaceIdiom == .pad
    let reviewSize = reviewIsPad ? CGSize(width: 1194, height: 834) : CGSize(width: 390, height: 844)
    let reviewPlatform = reviewIsPad ? "iPad" : "iPhone"
    model.showLibrary(.all)
    try await capture("Comparison — \(reviewPlatform) Browse", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: reviewIsPad, viewport: reviewSize)
    model.openPhoto(model.assets[0]); model.choosePhotoInspector(.adjust)
    try await capture("Comparison — \(reviewPlatform) Edit", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: reviewIsPad, viewport: reviewSize)
    model.selection = Set(model.assets.prefix(3).map(\.id))
    model.beginBatch(ids: model.assets.prefix(3).map(\.id))
    try await capture("Comparison — \(reviewPlatform) Batch", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: reviewIsPad, viewport: reviewSize)
    if reviewIsPad {
      try await capture("Comparison — iPad Batch portrait", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: true, viewport: CGSize(width: 834, height: 1194))
    }
    model.openPhoto(model.assets[0]); model.choosePhotoInspector(.adjust)
    model.selection = []
    model.scope = .all
    try await capture("Pixel inspection — compact controls", view: PixelZoomViewer(image: image), type: .large, scheme: .light, requirePhoto: true)
    model.choosePhotoInspector(.filters)
    try await capture("Filters — replacement toolbox", view: PhotoEditorWorkspace(model: model), type: .large, scheme: .light, requirePhoto: true)
    try await capture("Filters — accessible replacement toolbox", view: PhotoEditorWorkspace(model: model), type: .accessibility3, scheme: .light, requirePhoto: true)
    model.choosePhotoInspector(.adjust)
    try await capture("Phone Photo Editor — light", view: PhotoEditorWorkspace(model: model), type: .large, scheme: .light)
    try await capture("Phone Photo Editor — accessibility", view: PhotoEditorWorkspace(model: model), type: .accessibility3, scheme: .dark)
    try await capture("Phone adjustments — accessibility", view: SettingsEditor(model: model, focused: true), type: .accessibility3, scheme: .dark, scrollY: 450)
    try await capture("Phone Photo Editor — largest text", view: PhotoEditorWorkspace(model: model), type: .accessibility5, scheme: .dark, requirePhoto: true)
    try await capture("Panels — full native editing shell", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light)
    try await capture("Recheck — small phone Editor", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, requirePhoto: true, viewport: CGSize(width: 320, height: 568))
    try await capture("Recheck — landscape Editor", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, requirePhoto: true, viewport: CGSize(width: 844, height: 390))
    model.choosePhotoInspector(.watermark)
    model.updateField(\.watermark.enabled, value: true, fields: [.watermark_enabled])
    try await capture("Panels — watermark controls", view: SettingsEditor(model: model, focused: true), type: .large, scheme: .light)
    model.choosePhotoInspector(.adjust)
    model.showLibrary(.all)
    model.tileSize = 110
    try await capture("Phone gallery — light", view: ImageCollection(model: model), type: .large, scheme: .light)
    try await capture("Phone gallery — accessibility", view: ImageCollection(model: model), type: .accessibility3, scheme: .dark)
    try await capture("Phone gallery — largest text", view: ImageCollection(model: model), type: .accessibility5, scheme: .dark, requirePhoto: true)
    model.rotatePhoto(model.assets[0].id)
    try await capture("Phone Undo History — accessibility", view: EditingHistoryView(model: model), type: .accessibility3, scheme: .dark)
    XCTAssertTrue(model.browsingLibrary)
    XCTAssertEqual(model.assets.count, 6)
    model.startGIF(ids: model.assets.prefix(3).map(\.id))
    try await capture("Panels — full native GIF shell", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light)
    try await capture("Phone GIF Creator", view: GIFEditor(model: model, importAction: {}), type: .large, scheme: .light)
    try await capture("Recheck — landscape GIF", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, viewport: CGSize(width: 844, height: 390))
    try await capture("Phone GIF Creator accessibility", view: GIFEditor(model: model, importAction: {}), type: .accessibility3, scheme: .dark)
    try await capture("iPad GIF Creator", view: GIFEditor(model: model, importAction: {}), type: .large, scheme: .light, regular: true, viewport: CGSize(width: 1024, height: 768))
    model.archiveCurrentGIF(); let savedGIF = try XCTUnwrap(model.gifProject); model.gifProject = nil
    try await capture("Review — empty GIF with saved creations", view: GIFEditor(model: model, importAction: {}), type: .large, scheme: .light)
    model.openGIF(savedGIF)
    let missingID = savedGIF.frames[1].sourceID
    if let index = model.assets.firstIndex(where: { $0.id == missingID }) { model.assets[index].url = root.appendingPathComponent("Missing-photo.png") }
    try await capture("Review — GIF missing-frame recovery", view: GIFEditor(model: model, importAction: {}), type: .large, scheme: .light)
    if let index = model.assets.firstIndex(where: { $0.id == missingID }) { model.assets[index].url = model.directory.appendingPathComponent("Holiday landscape 2.png") }
    model.selectPhotos(for: .convert)
    try await capture("Review — Convert selection large text", view: ImageCollection(model: model), type: .accessibility3, scheme: .dark)
    model.select(model.assets[0]); model.finishGIFSelection(cancel: false)
    try await capture("Review — native-size Convert", view: SettingsEditor(model: model), type: .large, scheme: .light)
    model.switchWorkflow(.collages);model.selection=Set(model.assets.map(\.id));model.ensureCollageDocument()
    model.newCollage(template:CollageTemplate.catalog[1])
    try await capture("Phone collage tabs",view:CollageEditor(model:model),type:.large,scheme:.light)
    try await capture("Recheck — landscape Collage", view: CollageEditor(model: model), type: .large, scheme: .light, viewport: CGSize(width: 844, height: 390))
    try await capture("Phone collage layout gallery",view:CollageGallery(model:model),type:.large,scheme:.light)
    let populatedCollage = model.collage
    var emptyCollage = populatedCollage; emptyCollage.cells = []; model.changeCollage(emptyCollage)
    try await capture("Recheck — empty collage", view: CollageEditor(model: model), type: .large, scheme: .light)
    model.changeCollage(populatedCollage)
    model.openPhoto(model.assets[0])
    model.choosePhotoInspector(.adjust)
    if UIDevice.current.userInterfaceIdiom == .pad {
      model.conversionInputIDs = nil
      model.switchWorkflow(.batch)
      model.mode = .frame
      try await capture("iPad space — Batch portrait", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: true, viewport: CGSize(width: 834, height: 1194))
      let source = model.assets[0]
      model.openOverlayEditor(for: source)
      try await capture("iPad space — Privacy portrait", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, requirePhoto: true, regular: true, viewport: CGSize(width: 834, height: 1194))
      model.overlayEditor = false
      model.finishOverlayPresentation()
      model.overlaySession = nil
      var configuration = model.configuration(for: source)
      configuration.masks = [PrivacyMask()]
      model.setImageConfiguration(configuration, for: source.id)
      model.openOverlayEditor(for: source)
      try await capture("iPad space — Privacy selection portrait", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, requirePhoto: true, regular: true, viewport: CGSize(width: 834, height: 1194))
      try await capture("iPad space — Privacy landscape", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, requirePhoto: true, regular: true, viewport: CGSize(width: 1194, height: 834))
      model.overlayEditor = false
      model.finishOverlayPresentation()
      model.overlaySession = nil
      model.openPhoto(source)
      try await capture("Panels — iPad full shell landscape", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: true, viewport: CGSize(width: 1194, height: 834))
      try await capture("Panels — iPad full shell portrait", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .dark, regular: true, viewport: CGSize(width: 834, height: 1194))
      try await capture("Panels — iPad narrow full shell", view: MobileWorkspace(reviewModel: model), type: .accessibility3, scheme: .light, regular: true, viewport: CGSize(width: 600, height: 900))
      XCTAssertTrue(model.activatePhotoTool(.retouch))
      try await capture("Retouch — iPad landscape toolbox", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: true, viewport: CGSize(width: 1194, height: 834))
      try await capture("Retouch — iPad portrait toolbox", view: MobileWorkspace(reviewModel: model), type: .large, scheme: .light, regular: true, viewport: CGSize(width: 834, height: 1194))
      model.overlayEditor = false; model.overlaySession = nil; model.openPhoto(source)
    }
    try await capture("iPad-width editor and inspector components", view: HStack(spacing: 0) {
      PhotoEditorWorkspace(model: model)
      Divider()
      SettingsEditor(model: model, focused: true).frame(width: 340)
    }, type: .large, scheme: .light, regular: true, viewport: CGSize(width: 1024, height: 768))
    try await capture("Narrow iPad-width editor components", view: PhotoEditorWorkspace(model: model), type: .large, scheme: .dark, regular: true, viewport: CGSize(width: 600, height: 900))
    // Give the new Retouch layout an original-aspect photo, rather than the earlier test's rotated Fit canvas.
    model.restoreOriginalPhoto(model.assets[0].id)
    model.overlaySession = nil; model.openOverlayEditor(for: model.assets[0], masking: false); model.overlayRetouch = true
    try await capture("Retouch — phone controls", view: OverlayEditor(model: model), type: .large, scheme: .light, requirePhoto: true)
    try await capture("Context — phone landscape Retouch", view: OverlayEditor(model: model), type: .large, scheme: .light, requirePhoto: true, viewport: CGSize(width: 844, height: 390))
    try await capture("Context — phone large text Retouch", view: OverlayEditor(model: model), type: .accessibility3, scheme: .dark, requirePhoto: true)
    model.overlayEditor = false; model.overlaySession = nil
    model.openOverlayEditor(for: model.assets[0])
    try await capture("Polish — phone Privacy canvas", view: OverlayEditor(model: model), type: .large, scheme: .light, requirePhoto: true)
    try await capture("Review — large text Privacy history", view: OverlayEditor(model: model), type: .accessibility3, scheme: .dark, requirePhoto: true)
    model.overlayEditor = false; model.overlaySession = nil

    try await capture("Everyday — start", view: MobileWorkspace(reviewModel: model, startsAtHome: true), type: .large, scheme: .light)
    try await capture("Everyday — start large text", view: MobileWorkspace(reviewModel: model, startsAtHome: true), type: .accessibility3, scheme: .dark)
    let exporter = Workspace(directory: root.appendingPathComponent("finish"))
    let finishSource = try XCTUnwrap(model.assets.first)
    exporter.assets = [finishSource]; exporter.selected = finishSource.id
    let destination = root.appendingPathComponent("finished")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    exporter.export(to: destination, targetIDs: [finishSource.id])
    await exporter.task?.value
    let completion = try XCTUnwrap(exporter.latestExport)
    XCTAssertEqual(completion.outputs.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: completion.outputs[0].path))
    try await capture("Everyday — export finish", view: ExportCompletionView(model: exporter, output: completion).padding(), type: .large, scheme: .light)
    try await capture("Everyday — export finish large text", view: ExportCompletionView(model: exporter, output: completion).padding(), type: .accessibility3, scheme: .dark)
    exporter.persistenceTask?.cancel()

  }
}
