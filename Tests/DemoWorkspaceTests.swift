import Foundation
import CryptoKit
import ImageIO
import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif
import FramepebbleCore

@MainActor final class DemoWorkspaceTests: XCTestCase {
    func testWorkspaceSwitcherUsesGalleryWithoutChangingSelectionOrBatchInputs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = Workspace(directory: root)
        defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
        let a = SourceAsset(url: root.appendingPathComponent("one.jpg"))
        let b = SourceAsset(url: root.appendingPathComponent("two.jpg"))
        model.assets = [a, b]; model.selection = [a.id, b.id]; model.batchInputIDs = [b.id]
        model.openPhoto(a)
        let edits = model.edits
        let selection = model.selection
        model.presentWorkspaceSwitcher()
        XCTAssertTrue(model.browsingLibrary)
        XCTAssertTrue(model.projectsView)
        XCTAssertEqual(model.selection, selection)
        XCTAssertEqual(model.batchInputIDs, [b.id])
        XCTAssertEqual(model.edits, edits)
        model.projectsView = false; model.overlayEditor = true
        model.presentWorkspaceSwitcher()
        XCTAssertFalse(model.projectsView)
        model.overlayEditor = false
        model.selectPhotos(for: .gif)
        model.presentWorkspaceSwitcher()
        XCTAssertFalse(model.projectsView, "A contextual photo picker cannot silently change workspaces")
        await model.stopWork()
    }

    #if os(macOS)
    func testWorkspaceSwitcherNativeLayout() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let owner = Workspace(directory: root)
        owner.projectName = "My Photos"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: ProjectsView(model: owner).environment(\.workspaceOwner, owner).environment(\.colorScheme, .dark))
        window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: 480, height: 540)
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        window.appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "Workspace Switcher"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(bitmap.pixelsWide, Int(480 * (window.backingScaleFactor)))
        window.contentView = nil; window.close()
        await owner.stopWork(); owner.persistenceTask?.cancel()
        try? FileManager.default.removeItem(at: root)
    }
    #endif

    func testNativeCitrusObjectSelectionDiagnostic() async throws {
        let (_, photos) = try DemoPhotoManifest.load(from: resourceBundle)
        let processor = ImageProcessor()
        let image = try await processor.thumbnail(photos.appendingPathComponent("11-citrus-still-life.jpg"), maximum: 1000)
        let seed = NormalizedPoint(0.73, 0.68)
        do {
            let boundary = [NormalizedPoint(0.54,0.47), NormalizedPoint(0.94,0.47), NormalizedPoint(0.94,0.87), NormalizedPoint(0.54,0.87)]
            let outline = try await processor.colourObjectOutline(image, at: seed, within: boundary)
            var edit = ColourReplacement(); edit.points = outline.points; edit.excludedContours = outline.holes
            try edit.validate()
            let path = CGMutablePath()
            for (i, p) in outline.points.enumerated() { if i == 0 { path.move(to: CGPoint(x: p.x, y: p.y)) } else { path.addLine(to: CGPoint(x: p.x, y: p.y)) } }
            path.closeSubpath()
            XCTAssertTrue(path.contains(CGPoint(x: seed.x, y: seed.y)))
            XCTAssertFalse(path.contains(CGPoint(x: 0.05, y: 0.95)))
            XCTAssertFalse(path.contains(CGPoint(x: 0.56, y: 0.75)), "The table beside the orange must stay outside its refined boundary")
            XCTAssertFalse(path.contains(CGPoint(x: 0.25, y: 0.30)), "The other orange is not part of this operation")
            #if os(macOS)
            edit.source = RGBAColour(0.8, 0.2, 0.05, 1); edit.range = 0.25
            let rendered = try ColourRenderer.replace(CIImage(cgImage: image), edits: [edit])
            let result = try XCTUnwrap(CIContext().createCGImage(rendered, from: rendered.extent))
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "Citrus Refined Recolour"; attachment.lifetime = .keepAlways; add(attachment)
            #endif
            print("CITRUS OBJECT OUTLINE \(outline.points.count) points, \(outline.holes.count) holes")
        } catch {
            #if targetEnvironment(simulator)
            throw XCTSkip("Simulator foreground selection unavailable: " + error.localizedDescription)
            #else
            throw error
            #endif
        }
    }

    #if os(macOS)
    func testRetouchNativeMouseVerification() async throws {
        guard ProcessInfo.processInfo.environment["SIMCTL_CHILD_AMELUMA_NATIVE_BRUSH_CHECK"] == "1" || ProcessInfo.processInfo.environment["AMELUMA_NATIVE_BRUSH_CHECK"] == "1" else { throw XCTSkip("Interactive native mouse verification is opt-in") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = Workspace(directory: root)
        let (_, photos) = try DemoPhotoManifest.load(from: resourceBundle)
        let asset = try await model.processor.importSnapshot(photos.appendingPathComponent("23-warm-cast-kitchen.jpg"), to: model.directory)
        model.assets = [asset]; model.openPhoto(asset); model.activatePhotoTool(.retouch)
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1100,height: 760), styleMask: [.titled,.closable], backing: .buffered, defer: false)
        window.title = "Retouch Mouse Verification"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OverlayEditor(model: model, embedded: true))
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<1200 {
            if (model.overlaySession?.current.retouchStrokes.last?.points.count ?? 0) > 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let strokes = model.overlaySession?.current.retouchStrokes ?? []
        XCTAssertFalse(strokes.isEmpty, "A real mouse drag must commit a stroke")
        XCTAssertEqual(strokes.last?.samplingVersion, 3)
        XCTAssertGreaterThan(strokes.last?.points.count ?? 0, 1, "A drag must retain its path, not become a stationary dab")
        window.contentView = nil; window.close()
        await model.stopWork(); model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root)
    }
    #endif

    private var resourceBundle: Bundle {
        let testBundle = Bundle(for: Self.self)
        return testBundle.url(forResource: "DemoWorkspace", withExtension: nil) == nil ? .main : testBundle
    }
    /// Check the installed application resources, not the test bundle fallback.
    func testAppBundleShipsSameDemoOnEveryPlatform() async throws {
        let (manifest, photos) = try DemoPhotoManifest.load(from: .main)
        XCTAssertEqual(manifest.photos.count, 30)
        for name in ["01-coastal-hero.jpg", "27-coastal-hero-landscape.jpg", "28-rainbow-bird-hero.jpg", "29-golden-light-portrait.jpg", "30-lorikeet-hero-clean.jpg"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: photos.appendingPathComponent(name).path))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("app-demo-" + UUID().uuidString)
        let personal = Workspace(directory: root.appendingPathComponent("Personal"))
        await personal.openDemoWorkspace(root: root.appendingPathComponent("Demo"), bundle: .main)
        let demo = try XCTUnwrap(personal.demoWorkspace, personal.issues.joined(separator: "; "))
        XCTAssertEqual(demo.workspaceAssets.map(\.name), manifest.photos.map { $0.title + ".jpg" })
        XCTAssertTrue(personal.assets.isEmpty)
        await personal.returnFromDemoWorkspace()
        await personal.stopWork(); personal.persistenceTask?.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    func testFreshPhotoGeometryRoundTripsAndLegacyFixedCanvasStaysFixed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("demo-sizing-" + UUID().uuidString)
        let model = Workspace(directory: root)
        addTeardownBlock {
            await model.stopWork(); await MainActor.run { model.persistenceTask?.cancel() }
            try? FileManager.default.removeItem(at: root)
        }
        let (_, photos) = try DemoPhotoManifest.load(from: resourceBundle)
        let urls = [photos.appendingPathComponent("01-coastal-hero.jpg"), photos.appendingPathComponent("02-tidal-rocks.jpg")]
        let originalHashes = try urls.map { SHA256.hash(data: try Data(contentsOf: $0)) }
        for url in urls { model.assets.append(try await model.processor.importSnapshot(url, to: model.directory)) }
        for photo in model.assets {
            model.openPhoto(photo)
            let native = try await model.processor.identify(photo.url)
            let rendered = try await model.processor.render(photo.url, configuration: model.configuration(for: photo))
            XCTAssertEqual(CGSize(width: rendered.width, height: rendered.height), native)
            XCTAssertFalse(model.isEdited(photo.id), "Neutral source-size defaults are not a visual edit")
        }
        let portrait = model.assets[0]
        model.openPhoto(portrait)
        model.updateField(\.adjustments.exposure, value: 0.25, fields: [.adjustments_exposure])
        XCTAssertTrue(model.isEdited(portrait.id))
        await model.flush()
        let saved = try await model.store.load(model.projectURL)
        XCTAssertEqual(saved.edits.settings.crop.mode, .preserveAspectRatio)
        XCTAssertEqual(saved.edits.settings.resizeBasis, .percentage)
        XCTAssertEqual(saved.edits.configuration(for: portrait.id).adjustments.exposure, 0.25)
        let restored = Workspace(directory: root)
        await restored.start()
        XCTAssertEqual(restored.edits, saved.edits)
        XCTAssertEqual(ImageProcessor.outputSize(source: CGSize(width: 1024, height: 1536), configuration: restored.configuration(forID: portrait.id)), CGSize(width: 1024, height: 1536))
        await restored.stopWork(); restored.persistenceTask?.cancel()
        var legacy = ProjectDocument()
        legacy.sources = model.assets
        legacy.edits.settings.width = 640; legacy.edits.settings.height = 480
        legacy.edits.settings.adjustments.exposure = 0.4
        let legacyURL = root.appendingPathComponent("Legacy.json")
        try await model.store.save(legacy, to: legacyURL)
        await model.openProject(legacyURL)
        XCTAssertEqual(model.edits, legacy.edits, "Opening a saved project must not adopt new defaults")
        model.openPhoto(portrait)
        let rendered = try await model.processor.render(portrait.url, configuration: model.configuration(for: portrait))
        XCTAssertEqual(rendered.width, 640); XCTAssertEqual(rendered.height, 480)
        XCTAssertEqual(try urls.map { SHA256.hash(data: try Data(contentsOf: $0)) }, originalHashes)
    }

    func testBundledCollectionIsCompleteAndDecodable() throws {
        let (manifest, folder) = try DemoPhotoManifest.load(from: resourceBundle)
        XCTAssertEqual(manifest.photos.count, 30)
        for photo in manifest.photos {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(folder.appendingPathComponent(photo.filename) as CFURL, nil))
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil), photo.filename)
        }
        XCTAssertEqual(manifest.hero, "30-lorikeet-hero-clean.jpg")
        XCTAssertEqual(manifest.photos.first?.filename, manifest.hero)
    }

    func testDemoIsolationRestorationAndReturnPreservePersonalEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let personal = Workspace(directory: root, startInLibrary: true)
        personal.projectName = "Personal work"
        var settings = personal.settings; settings.width = 987; personal.settings = settings
        await personal.flush()
        let before = try Data(contentsOf: personal.projectURL)
        await personal.openDemoWorkspace(bundle: resourceBundle)
        let demo = try XCTUnwrap(personal.demoWorkspace, personal.issues.joined(separator: "; "))
        XCTAssertTrue(demo.isDemoWorkspace)
        XCTAssertEqual(demo.assets.count, 30)
        XCTAssertNotEqual(demo.projectURL, personal.projectURL)
        XCTAssertTrue(demo.assets.allSatisfy { $0.url.deletingLastPathComponent() == demo.directory })
        XCTAssertEqual(personal.assets.count, 0)
        XCTAssertEqual(personal.settings.width, 987)
        let first = try XCTUnwrap(demo.assets.first)
        let hashBefore = SHA256.hash(data: try Data(contentsOf: first.url))
        var c = demo.configuration(for: first); c.quarterTurns = 1
        demo.setImageConfiguration(c, for: first.id)
        await personal.returnFromDemoWorkspace()
        XCTAssertNil(personal.demoWorkspace)
        XCTAssertEqual(personal.projectName, "Personal work")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(contentsOf: personal.projectURL)) as? NSDictionary, try JSONSerialization.jsonObject(with: before) as? NSDictionary)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: first.url)), hashBefore)
        await personal.openDemoWorkspace(bundle: resourceBundle)
        let restored = try XCTUnwrap(personal.demoWorkspace)
        XCTAssertEqual(restored.assets.count, 30)
        XCTAssertEqual(restored.assets.first?.id, first.id)
        XCTAssertEqual(restored.configuration(for: first).quarterTurns, 1)
        await personal.returnFromDemoWorkspace()
        await personal.stopWork()
    }

    func testPartialSeedFailureDoesNotPublishSessionOrCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = Workspace(directory: root, isDemoWorkspace: true)
        let (manifest, bundledPhotos) = try DemoPhotoManifest.load(from: resourceBundle)
        let broken = root.appendingPathComponent("Incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let first = try XCTUnwrap(manifest.photos.first)
        try FileManager.default.copyItem(at: bundledPhotos.appendingPathComponent(first.filename), to: broken.appendingPathComponent(first.filename))
        do {
            try await demo.seedDemoWorkspace(manifest: manifest, photos: broken)
            XCTFail("Missing photos must fail atomically")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: demo.projectURL.path))
            XCTAssertTrue(demo.assets.isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: demo.directory.path).isEmpty)
        }
    }

    func testLandscapeAdditionPreservesLegacyEditsAndDoesNotReappearAfterRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = Workspace(directory: root, isDemoWorkspace: true)
        let (manifest, photos) = try DemoPhotoManifest.load(from: resourceBundle)
        try await demo.seedDemoWorkspace(manifest: manifest, photos: photos)
        var legacy = try await demo.store.load(demo.projectURL)
        let addedNames = Set(manifest.photos.filter { (manifest.additions ?? []).contains($0.filename) }.map { $0.title + ".jpg" })
        legacy.sources.removeAll { addedNames.contains($0.name) }
        let first = try XCTUnwrap(legacy.sources.first)
        legacy.name = "Edited demo"
        legacy.edits.settings.width = 789
        try await demo.store.save(legacy, to: demo.projectURL)
        try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
        let updated = try await demo.store.load(demo.projectURL)
        XCTAssertEqual(updated.sources.count, 30)
        XCTAssertEqual(updated.sources.first?.id, first.id)
        XCTAssertEqual(updated.name, "Edited demo")
        XCTAssertEqual(updated.edits.settings.width, 789)
        try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
        var removed = try await demo.store.load(demo.projectURL)
        XCTAssertEqual(removed.sources.count, 30)
        removed.sources.removeAll { addedNames.contains($0.name) }
        try await demo.store.save(removed, to: demo.projectURL)
        try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
        let afterRemoval = try await demo.store.load(demo.projectURL)
        XCTAssertEqual(afterRemoval.sources.count, 26)
    }

    func testSwitchingIsBlockedDuringDraftOrProcessing() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let personal = Workspace(directory: root)
        personal.overlayEditor = true
        await personal.openDemoWorkspace(bundle: resourceBundle)
        XCTAssertNil(personal.demoWorkspace)
        personal.overlayEditor = false; personal.running = true
        XCTAssertFalse(personal.canSwitchDemoWorkspace)
    }
}
