import XCTest
import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if os(macOS)
import AppKit
@testable import FramepebbleMac
#else
import UIKit
@testable import FramepebbleiOS
#endif

@MainActor final class WatermarkDesignUsabilityTests: XCTestCase {
  func testLibraryOwnsLogoAndAppliedSnapshotSurvivesDesignChangesAndCleanup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
    let source = root.appendingPathComponent("Original.png")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let originalBytes = try Data(contentsOf: source)
    let a = SourceAsset(url: source), b = SourceAsset(url: source)
    model.assets = [a,b]; model.openPhoto(a)
    var configuration = model.configuration(for: a)
    configuration.adjustments.exposure = 0.4; configuration.watermark.relativeWidth = 0.4
    configuration.watermark.opacity = 0.8; configuration.watermark.tiled = true
    model.setImageConfiguration(configuration, for: a.id)
    let untouched = model.configuration(for: b)
    let selected = model.selection; let inputs = model.batchInputIDs
    model.newWatermarkDesign(try XCTUnwrap(WatermarkTemplates.all.first))
    let session = try XCTUnwrap(model.activeEditorDocument)
    await session.addImages([(source, ProcessingConfiguration())], fitCanvas: false, names: ["Logo"])
    let libraryURL = try await model.watermarkDesignLibrary.save(session.document, resources: session.resources)
    let savedDesigns = try await model.watermarkDesignLibrary.list()
    let saved = try XCTUnwrap(savedDesigns.first)
    XCTAssertEqual(saved.url.standardizedFileURL.path, libraryURL.standardizedFileURL.path)
    let applied = await model.applyWatermarkDesign(saved, ids: [a.id, a.id, UUID()])
    XCTAssertTrue(applied)
    let captured = model.configuration(for: a)
    let stamp = try XCTUnwrap(captured.watermark.imageURL)
    let stampBytes = try Data(contentsOf: stamp)
    XCTAssertEqual(captured.adjustments, configuration.adjustments)
    XCTAssertEqual(captured.watermark.relativeWidth, 0.4); XCTAssertTrue(captured.watermark.tiled)
    XCTAssertEqual(model.configuration(for: b), untouched)
    XCTAssertEqual(model.selection, selected); XCTAssertEqual(model.batchInputIDs, inputs)
    model.undo(); XCTAssertEqual(model.configuration(for: a), configuration)
    model.redo(); XCTAssertEqual(model.configuration(for: a), captured)
    session.changeLayer("Change Logo") { $0.opacity = 0.1 }
    _ = try await model.watermarkDesignLibrary.save(session.document, resources: session.resources)
    XCTAssertEqual(try Data(contentsOf: stamp), stampBytes, "Applied designs are immutable snapshots")
    let restored = Workspace(directory: root)
    let library = try await restored.watermarkDesignLibrary.list()
    XCTAssertEqual(library.count, 1); XCTAssertEqual(library[0].document, session.document)
    // Saved project ownership protects the applied stamp during workspace cleanup.
    _ = try await model.saveProjectCopy()
    await model.clearImportedPhotos()
    XCTAssertTrue(FileManager.default.fileExists(atPath: stamp.path))
    let portable = try await EditorDocumentStore().load(libraryURL)
    let resourceURLs = Dictionary(uniqueKeysWithValues: portable.resources.map { ($0.id, libraryURL.appendingPathComponent("Resources").appendingPathComponent($0.filename)) })
    _ = try await EditorDocumentRenderer().render(portable, resources: resourceURLs, maximum: 100)
    let importedURL = try await restored.watermarkDesignLibrary.importDesign(libraryURL)
    XCTAssertNotEqual(importedURL, libraryURL)
    let importedDesigns = try await restored.watermarkDesignLibrary.list()
    XCTAssertEqual(importedDesigns.count, 2)
    try await restored.watermarkDesignLibrary.remove(try XCTUnwrap(importedDesigns.first { $0.url.standardizedFileURL.path == importedURL.standardizedFileURL.path }))
    XCTAssertEqual(try Data(contentsOf: stamp), stampBytes, "Deleting a reusable design cannot delete an applied stamp")
    XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    session.recoveryTask?.cancel(); await session.recoveryTask?.value
    restored.persistenceTask?.cancel()
  }

  func testCancelledApplicationNeverCommitsAndInvalidDesignDoesNotReplaceLibraryEntry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let photo = SourceAsset(url: root.appendingPathComponent("Photo.png"))
    model.assets = [photo]; model.openPhoto(photo)
    let document = try XCTUnwrap(WatermarkTemplates.all.first?.document)
    let url = try await model.watermarkDesignLibrary.save(document, resources: [:])
    let original = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
    var invalid = document; invalid.background = RGBAColour(1,1,1,1)
    do { _ = try await model.watermarkDesignLibrary.save(invalid, resources: [:]); XCTFail("Opaque design must not replace saved design") } catch {}
    XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), original)
    let before = model.edits
    let task = Task { await model.applyWatermarkDesign(SavedWatermarkDesign(document: document, url: url), ids: [photo.id]) }
    task.cancel(); let committed = await task.value
    XCTAssertFalse(committed); XCTAssertEqual(model.edits, before)
    let jobs = root.appendingPathComponent("WatermarkRenderJobs")
    XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: jobs.path).isEmpty) ?? true)
  }

  #if os(iOS)
  func testMobileSavedDesignLibraryCompactAndLargeTextCaptures() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    _ = try await model.watermarkDesignLibrary.save(try XCTUnwrap(WatermarkTemplates.all.first?.document), resources: [:])
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let pad = UIDevice.current.userInterfaceIdiom == .pad
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: pad ? CGSize(width: 834, height: 1194) : CGSize(width: 390, height: 844))
    let host = UIHostingController(rootView: WatermarkDesignsView(model: model, targetIDs: [UUID()]).environment(\.horizontalSizeClass, pad ? .regular : .compact).environment(\.dynamicTypeSize, .large))
    window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
    defer { window.isHidden = true; window.rootViewController = nil }
    for large in [false, true] {
      host.rootView = WatermarkDesignsView(model: model, targetIDs: [UUID()]).environment(\.horizontalSizeClass, pad ? .regular : .compact).environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
      try await Task.sleep(for: .seconds(1)); host.view.layoutIfNeeded()
      var rendered = false
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
      XCTAssertTrue(rendered)
      let attachment = XCTAttachment(image: image); attachment.name = "Watermark library — " + (pad ? "iPad" : "iPhone") + (large ? " — Large Text" : "")
      attachment.lifetime = .keepAlways; add(attachment)
    }
  }
  #endif

  #if os(macOS)
  func testWatermarkDesignerAndLibraryCaptures() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    model.newWatermarkDesign(try XCTUnwrap(WatermarkTemplates.all.first { $0.id == "frame" }))
    let session = try XCTUnwrap(model.activeEditorDocument)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingView(rootView: AnyView(DocumentEditorWorkspace(model: model, session: session).environment(\.colorScheme, .dark)))
    window.contentView = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentView = nil }
    for library in [false, true] {
      if library {
        window.setContentSize(CGSize(width: 640, height: 700))
        host.rootView = AnyView(WatermarkDesignsView(model: model, targetIDs: []).environment(\.colorScheme, .dark))
      }
      try await Task.sleep(for: .seconds(2)); host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
      let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: UTType.png.identifier)
      attachment.name = library ? "Watermark template library" : "Watermark layered designer"
      attachment.lifetime = .keepAlways; add(attachment)
    }
    session.recoveryTask?.cancel(); await session.recoveryTask?.value
  }
  #endif
}
