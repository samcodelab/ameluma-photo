import Foundation
import FramepebbleCore

struct DemoPhotoManifest: Decodable {
    struct Photo: Decodable {
        let filename: String
        let title: String
        let category: String
        let exercise: String
    }
    let version: Int
    let photos: [Photo]
    let additions: [String]?

    static func load(from bundle: Bundle = .main) throws -> (Self, URL) {
        guard let root = bundle.url(forResource: "DemoWorkspace", withExtension: nil) else {
            throw DemoWorkspaceError.missingAssets
        }
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        guard manifest.version == 1, manifest.photos.count == 27,
              Set(manifest.photos.map(\.filename)).count == 27,
              manifest.photos.allSatisfy({ $0.filename == ($0.filename as NSString).lastPathComponent && $0.filename.hasSuffix(".jpg") }) else {
            throw DemoWorkspaceError.missingAssets
        }
        guard Set(manifest.additions ?? []).isSubset(of: Set(manifest.photos.map(\.filename))) else {
            throw DemoWorkspaceError.missingAssets
        }
        return (manifest, root.appendingPathComponent("Photos", isDirectory: true))
    }
}

enum DemoWorkspaceError: LocalizedError {
    case missingAssets
    var errorDescription: String? { "The demo photo collection is missing or incomplete. Reinstall the application or rebuild with Resources/DemoWorkspace included." }
}

extension Workspace {
    var canSwitchDemoWorkspace: Bool {
        !switchingDemo && !isImporting && !running && !gifExporting && !collageGenerating && !quickFixRunning && !clearingWorkspace && sourceAcquisitions == 0 && !overlayEditor
    }

    /// The personal model remains alive. No personal project is opened, cleared or reseeded.
    func openDemoWorkspace(root: URL? = nil, bundle: Bundle = .main) async {
        guard !isDemoWorkspace, demoWorkspace == nil, canSwitchDemoWorkspace else { return }
        switchingDemo = true
        defer { switchingDemo = false }
        do {
            let (manifest, photos) = try DemoPhotoManifest.load(from: bundle)
            await stopWork()
            let issueCount = issues.count
            await flush()
            guard issues.count == issueCount else { return }
            let demoRoot = root ?? directory.deletingLastPathComponent().appendingPathComponent("DemoWorkspace-v1", isDirectory: true)
            let demo = Workspace(directory: demoRoot, startInLibrary: true, isDemoWorkspace: true)
            if FileManager.default.fileExists(atPath: demo.projectURL.path) {
                try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
                await demo.start()
                guard demo.issues.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            } else {
                try await demo.seedDemoWorkspace(manifest: manifest, photos: photos)
                try await demo.addNewDemoPhotos(manifest: manifest, photos: photos)
                await demo.start()
            }
            projectsView = false
            demoWorkspace = demo
        } catch { issues.append("Could not open Demo Workspace: \(error.localizedDescription)") }
    }

    func returnFromDemoWorkspace() async {
        guard let demo = demoWorkspace, demo.canSwitchDemoWorkspace else { return }
        demo.switchingDemo = true
        defer { demo.switchingDemo = false }
        await demo.stopWork()
        let issueCount = demo.issues.count
        await demo.flush()
        guard demo.issues.count == issueCount else { return }
        demoWorkspace = nil
        startIndexing()
    }

    /// Apply shipped additions once, preserving the existing document and all photo edits.
    /// Receipts also respect a user's later decision to remove an added sample.
    func addNewDemoPhotos(manifest: DemoPhotoManifest, photos: URL) async throws {
        guard isDemoWorkspace else { return }
        for filename in manifest.additions ?? [] {
            let receipt = projectURL.deletingLastPathComponent().appendingPathComponent(".added-" + filename)
            guard !FileManager.default.fileExists(atPath: receipt.path),
                  let photo = manifest.photos.first(where: { $0.filename == filename }) else { continue }
            var doc = try await store.load(projectURL)
            if !doc.sources.contains(where: { $0.name == photo.title + ".jpg" }) {
                var asset = try await processor.importSnapshot(photos.appendingPathComponent(filename), to: directory)
                asset.name = photo.title + ".jpg"
                doc.sources.append(asset)
                do { try await store.save(doc, to: projectURL) }
                catch { try? FileManager.default.removeItem(at: asset.url); throw error }
            }
            // If writing the receipt fails, the saved source name prevents a duplicate on retry.
            try Data().write(to: receipt, options: .atomic)
        }
    }

    /// Decode and copy every original before publishing anything. A failed seed has no partial session.
    func seedDemoWorkspace(manifest: DemoPhotoManifest, photos: URL) async throws {
        guard isDemoWorkspace, assets.isEmpty else { return }
        var imported: [SourceAsset] = []
        do {
            for photo in manifest.photos {
                try Task.checkCancellation()
                var asset = try await processor.importSnapshot(photos.appendingPathComponent(photo.filename), to: directory)
                asset.name = photo.title + ".jpg"
                imported.append(asset)
            }
            var doc = ProjectDocument()
            doc.name = "Demo Workspace"
            doc.sources = imported
            doc.edits = Self.freshEditingSnapshot()
            doc.profiles = profiles
            try await store.save(doc, to: projectURL)
        } catch {
            for asset in imported { try? FileManager.default.removeItem(at: asset.url) }
            throw error
        }
    }
}
