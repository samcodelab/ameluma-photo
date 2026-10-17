import Foundation
import FramepebbleCore

extension Workspace {
    /// Close preserves a saved project and every source it needs.
    func closeProject() async { await newProject(); library = .all; query = ""; scope = .all }

    /// References in saved projects/presets protect their snapshots. If any saved
    /// document cannot be read, cleanup stops rather than risking recoverable work.
    func clearImportedPhotos() async {
        guard !clearingWorkspace else { return }
        clearingWorkspace = true
        expireWorkspaceRemovalUndo()
        sourceSessionID = UUID()
        defer { clearingWorkspace = false }
        await stopWork(); latestExport = nil
        await flush() // Publish the final cancelled-import arrivals before resetting.
        do {
            let folder = directory.deletingLastPathComponent().appendingPathComponent("Projects")
            let cleanup = SourceStorageCleanup()
            // Read large saved projects off the main actor; fail closed on unreadable data.
            let reusable: [String: Data] = ["profiles": try JSONEncoder().encode(profiles), "watermarks": try JSONEncoder().encode(watermarkPresets)]
            let objects = try reusable.mapValues { try JSONSerialization.jsonObject(with: $0) }
            let retained = try await cleanup.retainedSnapshotNames(projects: folder, reusableConfiguration: JSONSerialization.data(withJSONObject: objects))
            projectName = "Untitled Project"; batchInputIDs = nil
            resetEditorTabs()
            resetCollageDocuments()
            gifProject = nil; archivedGIFs = []; gifSelectionContext = nil
            hiddenSourceIDs = []; assets = []; selected = nil; selection = []; selecting = false
            edits = EditingSnapshot(); history = EditingHistory(); favourites = []
            sensitivity = SensitiveReviewState(); privacyCoverageReviewIDs = []; proposals = [:]; index = ClassificationIndex()
            results = []; pendingExports = []; collage = CollageProject(); collageOutputs = []
            collageUndo = []; collageRedo = []; library = .all; query = ""; scope = .all
            precision = false; overlayEditor = false; collageEditor = false
            duplicates = DuplicateIndex()
            // Save the empty session successfully BEFORE removing any snapshots.
            try await store.save(document(), to: projectURL)
            let removed = try await cleanup.removeUnreferenced(in: directory, retaining: retained)
            await processor.setPrivateMode(true)
            await editorProcessor.setPrivateMode(true)
            await processor.setPrivateMode(privateEditing)
            await editorProcessor.setPrivateMode(privateEditing)
            status = "Workspace cleared. Removed \(removed) unused local copies. Saved projects and exported files remain; originals are untouched."
        } catch {
            issues.append("Local cleanup could not finish: \(error.localizedDescription). No original files were targeted.")
        }
    }
}
