import AppKit
import FramepebbleCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import FramepebbleMac

/// Renders the real SwiftUI workspace offscreen with generated, non-private sources.
/// Attachments aid visual review; they are not a substitute for live gesture validation.
@MainActor final class WorkspaceLayoutTests: XCTestCase {
  func testLibraryAndPhotoToolsAtNativeWindowSize() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = Workspace(directory: root, startInLibrary: true)
    for number in 1...8 {
      let url = model.directory.appendingPathComponent("Landscape \(number).png")
      let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(red: 0.22, green: 0.45, blue: 0.65, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
      context.setFillColor(CGColor(red: CGFloat(number)/12, green: 0.5, blue: 0.3, alpha: 1))
      context.move(to: CGPoint(x: 0, y: 0)); context.addLine(to: CGPoint(x: 400, y: 450))
      context.addLine(to: CGPoint(x: 800, y: 0)); context.closePath(); context.fillPath()
      context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.3, alpha: 1))
      context.fillEllipse(in: CGRect(x: 560, y: 420, width: 90, height: 90))
      let image = try XCTUnwrap(context.makeImage())
      let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
        UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      model.assets.append(SourceAsset(url: url))
    }
    model.selected = model.assets[0].id
    let hosting = NSHostingView(rootView: MacWorkspace(model: model).environment(\.colorScheme, .dark))
    let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    hosting.appearance = NSAppearance(named: .darkAqua)
    window.contentView = hosting
    hosting.frame = frame
    defer { model.persistenceTask?.cancel(); window.contentView = nil; window.close() }
    var expectedSize = frame.size
    func capture(_ name: String, view: NSView? = nil) async throws {
      let target = view ?? hosting
      target.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(500))
      target.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(target.bitmapImageRepForCachingDisplay(in: target.bounds))
      window.appearance?.performAsCurrentDrawingAppearance {
        target.cacheDisplay(in: target.bounds, to: bitmap)
      }
      let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      if name == "Mac GIF Creator" { try data.write(to: URL(fileURLWithPath: "/tmp/ameluma-gif-mac.png")) }
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
      attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
      XCTAssertEqual(target.bounds.width, expectedSize.width)
      XCTAssertEqual(target.bounds.height, expectedSize.height)
    }
    try await capture("Library gallery — dark")
    model.openPhoto(model.assets[1])
    model.openPhoto(model.assets[2])
    model.openPhoto(model.assets[0])
    XCTAssertEqual(model.editorTabs.count, 3)
    model.choosePhotoInspector(.adjust)
    try await capture("Photo Editor — Adjust")
    model.precision = true
    try await capture("Photo Editor — Crop on main canvas")
    model.openOverlayEditor(for: model.assets[0], masking: false)
    try await capture("Photo Editor — Annotate")
    model.overlayEditor = false
    model.showLibrary()
    XCTAssertTrue(model.browsingLibrary)
    XCTAssertEqual(model.assets.count, 8)
    window.appearance = NSAppearance(named: .aqua)
    hosting.appearance = NSAppearance(named: .aqua)
    hosting.rootView = MacWorkspace(model: model).environment(\.colorScheme, .light)
    expectedSize = NSSize(width: 1040, height: 700)
    window.setContentSize(expectedSize)
    hosting.frame = NSRect(origin: .zero, size: expectedSize)
    model.openPhoto(model.assets[0])
    model.choosePhotoInspector(.adjust)
    try await capture("Small Mac window — light Adjust")
    model.precision = true
    try await capture("Small Mac window — light Crop")
    model.switchWorkflow(.batch)
    var edited = model.settings; edited.adjustments.exposure = 0.5
    model.settings = edited
    model.rotatePhoto(model.assets[0].id)
    try await capture("Batch — History and Reset controls")
    let historyHost = NSHostingView(rootView: EditingHistoryView(model: model).environment(\.colorScheme, .light))
    historyHost.frame = NSRect(origin: .zero, size: expectedSize)
    window.contentView = historyHost
    try await capture("Undo History timeline", view: historyHost)
    model.startGIF(ids: model.assets.prefix(3).map(\.id))
    window.contentView = hosting
    try await capture("Mac GIF Creator")
    model.archiveCurrentGIF(); let savedGIF = try XCTUnwrap(model.gifProject); model.gifProject = nil
    try await capture("Review — Mac empty GIF saved creations")
    model.openGIF(savedGIF)
    if let index = model.assets.firstIndex(where: { $0.id == savedGIF.frames[1].sourceID }) { model.assets[index].url = root.appendingPathComponent("Missing-photo.png") }
    try await capture("Review — Mac missing GIF frame")
    if let index = model.assets.firstIndex(where: { $0.id == savedGIF.frames[1].sourceID }) { model.assets[index].url = model.directory.appendingPathComponent("Landscape 2.png") }
    model.selectPhotos(for: .convert)
    try await capture("Review — Mac contextual Convert")
    model.finishGIFSelection(cancel: true)
    model.selection=Set(model.assets.map(\.id))
    model.switchWorkflow(.collages);model.ensureCollageDocument()
    model.newCollage(template:CollageTemplate.catalog[0])
    model.generateCollageArt(shape:.text,text:"HELLO",sourceIDs:Set(model.assets.map(\.id)),count:100,referenceID:nil,reuse:true)
    await model.collageGenerationTask?.value
    let collageHost=NSHostingView(rootView:CollageEditor(model:model,embedded:true).environment(\.colorScheme,.light))
    collageHost.frame=NSRect(origin:.zero,size:expectedSize);window.contentView=collageHost
    try await Task.sleep(for:.seconds(2))
    try await capture("Collage tabs — HELLO 100 photo tiles",view:collageHost)
    let galleryHost=NSHostingView(rootView:CollageGallery(model:model).environment(\.colorScheme,.light))
    galleryHost.frame=NSRect(origin:.zero,size:expectedSize);window.contentView=galleryHost
    try await capture("Collage layout gallery",view:galleryHost)


  }
}
