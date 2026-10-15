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
        let skyPixels = stride(from: 0, to: pixels.count, by: 4).filter { index in
          let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
          return (30...90).contains(r) && (80...150).contains(g) && (130...200).contains(b) && b > g + 10
        }.count
        XCTAssertGreaterThan(Double(skyPixels) / Double(pixelsWide * pixelsHigh), 0.06,
          "The source photo must retain meaningful visible area at the largest text size")
      }
      let attachment = XCTAttachment(image: screenshot)
      attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    try await capture("Phone Photo Editor — light", view: PhotoEditorWorkspace(model: model), type: .large, scheme: .light)
    try await capture("Phone Photo Editor — accessibility", view: PhotoEditorWorkspace(model: model), type: .accessibility3, scheme: .dark)
    try await capture("Phone adjustments — accessibility", view: SettingsEditor(model: model, focused: true), type: .accessibility3, scheme: .dark, scrollY: 450)
    try await capture("Phone Photo Editor — largest text", view: PhotoEditorWorkspace(model: model), type: .accessibility5, scheme: .dark, requirePhoto: true)
    model.showLibrary(.all)
    model.tileSize = 110
    try await capture("Phone gallery — light", view: ImageCollection(model: model), type: .large, scheme: .light)
    try await capture("Phone gallery — accessibility", view: ImageCollection(model: model), type: .accessibility3, scheme: .dark)
    try await capture("Phone gallery — largest text", view: ImageCollection(model: model), type: .accessibility5, scheme: .dark, requirePhoto: true)
    model.rotatePhoto(model.assets[0].id)
    try await capture("Phone Undo History — accessibility", view: EditingHistoryView(model: model), type: .accessibility3, scheme: .dark)
    XCTAssertTrue(model.browsingLibrary)
    XCTAssertEqual(model.assets.count, 6)
    model.switchWorkflow(.collages);model.selection=Set(model.assets.map(\.id));model.ensureCollageDocument()
    model.newCollage(template:CollageTemplate.catalog[1])
    try await capture("Phone collage tabs",view:CollageEditor(model:model),type:.large,scheme:.light)
    try await capture("Phone collage layout gallery",view:CollageGallery(model:model),type:.large,scheme:.light)
    model.openPhoto(model.assets[0])
    model.choosePhotoInspector(.adjust)
    try await capture("iPad-width editor and inspector components", view: HStack(spacing: 0) {
      PhotoEditorWorkspace(model: model)
      Divider()
      SettingsEditor(model: model, focused: true).frame(width: 340)
    }, type: .large, scheme: .light, regular: true, viewport: CGSize(width: 1024, height: 768))
    try await capture("Narrow iPad-width editor components", view: PhotoEditorWorkspace(model: model), type: .large, scheme: .dark, regular: true, viewport: CGSize(width: 600, height: 900))


  }
}
