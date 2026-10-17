import Foundation
import CryptoKit
import ImageIO
import XCTest
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif
import FramepebbleCore

@MainActor final class DemoWorkspaceTests: XCTestCase {
    private var resourceBundle: Bundle {
        let testBundle = Bundle(for: Self.self)
        return testBundle.url(forResource: "DemoWorkspace", withExtension: nil) == nil ? .main : testBundle
    }
    /// Check the installed application resources, not the test bundle fallback.
    func testAppBundleShipsSameDemoOnEveryPlatform() async throws {
        let (manifest, photos) = try DemoPhotoManifest.load(from: .main)
        XCTAssertEqual(manifest.photos.count, 27)
        for name in ["01-coastal-hero.jpg", "27-coastal-hero-landscape.jpg"] {
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
        XCTAssertEqual(manifest.photos.count, 27)
        for photo in manifest.photos {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(folder.appendingPathComponent(photo.filename) as CFURL, nil))
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil), photo.filename)
        }
        XCTAssertEqual(manifest.photos.first?.filename, "01-coastal-hero.jpg")
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
        XCTAssertEqual(demo.assets.count, 27)
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
        XCTAssertEqual(restored.assets.count, 27)
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
        legacy.sources.removeAll { $0.name == "Coastal Hero Landscape.jpg" }
        let first = try XCTUnwrap(legacy.sources.first)
        legacy.name = "Edited demo"
        legacy.edits.settings.width = 789
        try await demo.store.save(legacy, to: demo.projectURL)
        try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
        let updated = try await demo.store.load(demo.projectURL)
        XCTAssertEqual(updated.sources.count, 27)
        XCTAssertEqual(updated.sources.first?.id, first.id)
        XCTAssertEqual(updated.name, "Edited demo")
        XCTAssertEqual(updated.edits.settings.width, 789)
        try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
        var removed = try await demo.store.load(demo.projectURL)
        XCTAssertEqual(removed.sources.count, 27)
        removed.sources.removeAll { $0.name == "Coastal Hero Landscape.jpg" }
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
