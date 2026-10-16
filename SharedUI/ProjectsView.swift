import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
  @Bindable var model: Workspace
  @State private var open = false
  @State private var relink = false
  @State private var projects: [URL] = []
  @State private var saved: URL?
  @State private var confirmClear = false
  @State private var storage: SourceStorageSummary?
  @State private var storageError: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section("Current Project") {
          TextField("Project name", text: $model.projectName)
          Text(
            "\(model.assets.count) photos. Project files store editing instructions and source references, not embedded photographs."
          ).font(.caption)
          Button("Save project copy") {
            Task {
              do {
                saved = try await model.saveProjectCopy()
                reload()
              } catch { model.issues.append(error.localizedDescription) }
            }
          }
          if let saved {
            ShareLink(item: saved) {
              Label("Export project instructions", systemImage: "square.and.arrow.up")
            }
          }
          Button("New project") {
            Task {
              await model.newProject()
              reload()
            }
          }
          Button("Close Project") { Task { await model.closeProject(); reload() } }
          Text("Close saves your work. Clear removes current photos and edits, and frees unused local copies. Originals, exported images and copies needed by saved projects remain untouched.").font(.caption).foregroundStyle(.secondary)
          Button("Open project instructions…") { open = true }
          if model.current != nil || model.relinkSourceID != nil {
            Button("Relink " + (model.assets.first { $0.id == (model.relinkSourceID ?? model.selected) }?.name ?? "selected source") + "…") { relink = true }
            Text("Choose the matching original. Existing edits remain attached; review the result.")
              .font(.caption)
          }
        }
        Section("Local Source Storage") {
          Text("Workspace photos: \(model.workspaceAssets.count). Retained creation sources: \(model.hiddenSourceIDs.count). Removing a workspace photo keeps sources needed by creations.").font(.caption)
          Button("Free Unused Working Copies") { Task { do { let count = try await model.freeUnusedWorkingCopies(); model.status = "Freed \(count) unused working copies."; await refreshStorage() } catch { storageError = error.localizedDescription } } }.disabled(model.clearingWorkspace || model.isImporting || model.sourceAcquisitions > 0 || model.running || model.gifExporting || model.collageGenerating)
          Button("Clear Workspace & Creations…", role: .destructive) { confirmClear = true }
            .disabled(model.clearingWorkspace)
          if let storage {
            LabeledContent("Managed source copies", value: "\(storage.managedFiles)")
            LabeledContent("Source file sizes", value: ByteCountFormatter.string(fromByteCount: storage.totalBytes, countStyle: .file))
            LabeledContent("Retained by saved work", value: ByteCountFormatter.string(fromByteCount: storage.retainedBytes, countStyle: .file))
            Text("Clear may remove \(ByteCountFormatter.string(fromByteCount: storage.removableBytes, countStyle: .file)) of unreferenced copies. Originals and exported files are excluded. File sizes are not a guarantee of reclaimed disk space.").font(.caption).foregroundStyle(.secondary)
          } else if let storageError { Text(storageError).font(.caption) }
          else { ProgressView("Checking owned storage…") }
        }
        Section("Privacy & Imports") {
          Toggle("Private Editing Mode", isOn: $model.privateEditing)
          Toggle("Skip duplicate imports this session", isOn: $model.skipDuplicates)
          Text("Private mode avoids persistent preview thumbnails and disables the app’s memory thumbnail cache. Saved sources and project recovery remain on disk. It does not control system screenshots, backups or user-selected cloud folders, and is not secure deletion or encryption.").font(.caption).foregroundStyle(.secondary)
          Button("Conceal Workspace", systemImage: "eye.slash") { model.concealed = true }
        }
        Section("Recent Projects") {
          ForEach(projects, id: \.self) { url in
            Button {
              Task { await model.openProject(url); dismiss() }
            } label: { SavedProjectLabel(url: url, store: model.store) }
          }
        }
        Section {
          Text(
            "Private Editing Mode uses text-only project listings. Saving projects preserves recovery data; sources and backups are not securely erased."
          ).font(.caption)
        }
      }.navigationTitle("Projects").compactNavigationTitle().toolbar {
        Button("Done") { dismiss() }
      }.onAppear { reload() }
        .task(id: [model.assets.count, projects.count, model.profiles.count, model.watermarkPresets.count]) { await refreshStorage() }
        .fileImporter(isPresented: $open, allowedContentTypes: [.json]) { result in
          switch result {
          case .success(let url):
            Task {
              await model.openProject(url)
              dismiss()
            }
          case .failure(let error): model.issues.append(error.localizedDescription)
          }
        }
        .fileImporter(isPresented: $relink, allowedContentTypes: ImageProcessor.importTypes) {
          result in
          switch result {
          case .success(let url): Task { await model.relinkSource(url) }
          case .failure(let error): model.issues.append(error.localizedDescription)
          }
        }
    }.alert("Clear imported photos and edits?", isPresented: $confirmClear) {
      Button("Clear Workspace & Creations", role: .destructive) { Task { await model.clearImportedPhotos(); reload(); await refreshStorage() } }
      Button("Cancel", role: .cancel) {}
    } message: { Text("This removes current workspace photos, photo edits, GIFs and collages. Saved project copies, originals and exported files remain. To remove photos while keeping creations, use Remove from Workspace. Save a project copy first to preserve this work.") }
    .frame(minWidth: 320, minHeight: 440)
  }
  func refreshStorage() async {
    do {
      let cleanup = SourceStorageCleanup()
      let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Projects")
      let retained = try await cleanup.retainedSnapshotNames(projects: folder, reusableConfiguration: JSONEncoder().encode(model.document()))
      storage = try await cleanup.summary(in: model.directory, retaining: retained)
    } catch is CancellationError {} catch { storageError = "Storage accounting unavailable: " + error.localizedDescription }
  }
  func reload() {
    let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Projects")
    projects =
      ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
      ?? []).filter { $0.pathExtension == "json" }.sorted {
        $0.lastPathComponent > $1.lastPathComponent
      }
  }
}

struct SavedProjectLabel: View {
  let url: URL
  let store: ProjectStore
  @State private var name: String?
  @State private var unavailable = false
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name ?? (unavailable ? "Project instructions unavailable" : "Loading project name…"))
      Text(url.deletingPathExtension().lastPathComponent).font(.caption).foregroundStyle(.secondary)
    }.task(id: url) {
      do { name = try await store.load(url).name }
      catch is CancellationError {} catch { unavailable = true }
    }
  }
}
