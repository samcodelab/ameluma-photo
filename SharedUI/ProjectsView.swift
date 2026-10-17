import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers

/// One destination for choosing workspaces. File and maintenance actions stay secondary.
struct ProjectsView: View {
  @Bindable var model: Workspace
  @Environment(\.workspaceOwner) private var workspaceOwner
  @Environment(\.dismiss) private var dismiss
  @State private var projects: [URL] = []
  @State private var switching = false
  @State private var actionError: String?
  var owner: Workspace { workspaceOwner ?? model }
  var canSwitch: Bool { model.canSwitchDemoWorkspace && model.gifSelectionContext == nil && !switching }
  var body: some View {
    NavigationStack {
      List {
        Section("Current workspace") {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(model.isDemoWorkspace ? "Demo Workspace" : model.projectName).font(.headline)
              Text("\(model.workspaceAssets.count) photos · Autosaves on this device").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityLabel("Current workspace")
          }
        }
        Section("Switch workspace") {
          if model.isDemoWorkspace {
            Button {
              switchWorkspace { await owner.returnFromDemoWorkspace(); owner.showLibrary() }
            } label: {
              Label { VStack(alignment: .leading, spacing: 3) {
                Text(owner.projectName)
                Text("Your photos and edits").font(.caption).foregroundStyle(.secondary)
              } } icon: { Image(systemName: "photo.on.rectangle") }
            }.disabled(workspaceOwner == nil || !canSwitch)
          } else {
            Button {
              switchWorkspace { await owner.openDemoWorkspace(); owner.demoWorkspace?.showLibrary() }
            } label: {
              Label { VStack(alignment: .leading, spacing: 3) {
                Text("Demo Workspace")
                Text("Sample photos · edits kept separately").font(.caption).foregroundStyle(.secondary)
              } } icon: { Image(systemName: "photo.on.rectangle.angled") }
            }.disabled(!canSwitch)
          }
        }
        if !projects.isEmpty { Section("Saved workspace copies") {
          ForEach(projects, id: \.self) { url in
            Button {
              switchWorkspace { await model.openProject(url); model.showLibrary() }
            } label: { SavedProjectLabel(url: url, store: model.store) }
              .disabled(!canSwitch)
          }
        }
        }
        Section {
          if !model.isDemoWorkspace {
            Button("New Workspace…", systemImage: "plus") {
              switchWorkspace { await model.newProject(); model.showLibrary() }
            }.disabled(!canSwitch)
          }
          NavigationLink { WorkspaceFilesView(model: model) } label: { Label("Save & Open Files", systemImage: "folder") }
          NavigationLink { WorkspaceSettingsView(model: model) } label: { Label("Workspace Settings", systemImage: "gearshape") }
        }
        if let actionError { Section { Text(actionError).foregroundStyle(.red).font(.caption) } }
        if switching { Section { ProgressView("Opening workspace…") } }
        else if !canSwitch {
          Section { Text("Finish or cancel the current edit, selection or operation before switching workspaces.").font(.caption).foregroundStyle(.secondary) }
        }
      }.navigationTitle("Workspaces").compactNavigationTitle()
        .toolbar { Button("Done") { dismiss() } }
        .task { reload() }
    }
    .frame(minWidth: 320)
    #if os(macOS)
    .frame(width: 480, height: 540)
    #endif
  }
  func switchWorkspace(_ action: @escaping @MainActor () async -> Void) {
    guard canSwitch else { return }
    switching = true; actionError = nil
    Task {
      let issues = model.issues.count + (owner === model ? 0 : owner.issues.count)
      await action()
      switching = false
      if model.issues.count + (owner === model ? 0 : owner.issues.count) == issues { dismiss() }
      else { actionError = model.issues.last ?? owner.issues.last ?? "The workspace could not be opened. Your current work is preserved." }
    }
  }
  func reload() {
    let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Projects")
    do {
      projects = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    } catch {
      if FileManager.default.fileExists(atPath: folder.path) { model.issues.append("Saved workspaces could not be listed: " + error.localizedDescription) }
    }
  }
}

struct WorkspaceFilesView: View {
  @Bindable var model: Workspace
  @State private var saved: URL?
  @State private var open = false
  @State private var saving = false
  @State private var fileError: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Form {
      Section("Save a copy") {
        Text("Your current workspace saves automatically. Save a named snapshot to return to this version later.").font(.caption).foregroundStyle(.secondary)
        TextField("Workspace name", text: $model.projectName).onChange(of: model.projectName) { _, _ in model.persist() }
        Button(saving ? "Saving…" : "Save Workspace Copy") {
          saving = true
          Task { defer { saving = false }; do { saved = try await model.saveProjectCopy(); fileError = nil } catch { fileError = error.localizedDescription } }
        }.disabled(saving || !model.canSwitchDemoWorkspace)
        if let saved {
          Label("Copy saved", systemImage: "checkmark.circle")
          ShareLink(item: saved) { Label("Share Workspace Instructions…", systemImage: "square.and.arrow.up") }
        }
      }
      Section("Open a file") {
        Button("Open Workspace Instructions…", systemImage: "folder") { open = true }.disabled(!model.canSwitchDemoWorkspace)
        Text("Instructions reference local source photos; they do not include the photos and are not a self-contained cross-device project.").font(.caption).foregroundStyle(.secondary)
      }
      if let fileError { Section { Text(fileError).foregroundStyle(.red).font(.caption) } }
    }.navigationTitle("Save & Open Files")
      .fileImporter(isPresented: $open, allowedContentTypes: [.json]) { result in
        switch result {
        case .success(let url): Task { let count = model.issues.count; await model.openProject(url); if model.issues.count == count { model.showLibrary(); model.projectsView = false; dismiss() } else { fileError = model.issues.last } }
        case .failure(let error): if !error.isUserCancellation { fileError = error.localizedDescription }
        }
      }
  }
}

struct WorkspaceSettingsView: View {
  @Bindable var model: Workspace
  @State private var relink = false
  @State private var confirmClear = false
  @State private var storage: SourceStorageSummary?
  @State private var storageError: String?
  var body: some View {
    Form {
      if !model.isDemoWorkspace {
        Section("Name") { TextField("Workspace name", text: $model.projectName).onChange(of: model.projectName) { _, _ in model.persist() } }
      }
      Section("Source recovery") {
        if let source = model.assets.first(where: { $0.id == (model.relinkSourceID ?? model.selected) }) {
          Text(source.name).lineLimit(2)
          Button("Locate or Replace Source…", systemImage: "folder") { relink = true }
          Text("Edits stay attached. Review framing and protective coverage after replacing a source.").font(.caption).foregroundStyle(.secondary)
        } else { Text("Select a photo in the workspace to locate or replace its source.").font(.caption).foregroundStyle(.secondary) }
      }
      Section("Privacy & imports") {
        Toggle("Private Editing Mode", isOn: $model.privateEditing)
        Toggle("Skip duplicate imports", isOn: $model.skipDuplicates)
        Text("Private mode avoids persistent preview thumbnails. Sources and recovery data remain on disk; this is not encryption or secure deletion.").font(.caption).foregroundStyle(.secondary)
        Button("Conceal Workspace", systemImage: "eye.slash") { model.concealed = true }
      }
      Section("Storage") {
        LabeledContent("Workspace photos", value: "\(model.workspaceAssets.count)")
        LabeledContent("Sources kept for creations", value: "\(model.hiddenSourceIDs.count)")
        if let storage {
          LabeledContent("Working copies", value: ByteCountFormatter.string(fromByteCount: storage.totalBytes, countStyle: .file))
        }
        Button("Free Unused Working Copies") {
          Task { do { let count = try await model.freeUnusedWorkingCopies(); model.status = "Freed \(count) unused working copies."; await refreshStorage() } catch { storageError = error.localizedDescription } }
        }.disabled(!model.canSwitchDemoWorkspace)
        Text("Originals and sources needed by current or saved creations are preserved.").font(.caption).foregroundStyle(.secondary)
        if let storageError { Text(storageError).font(.caption).foregroundStyle(.red) }
      }
      Section {
        Button("Clear Workspace & Creations…", role: .destructive) { confirmClear = true }.disabled(!model.canSwitchDemoWorkspace)
      }
    }.navigationTitle("Workspace Settings")
      .task { await refreshStorage() }
      .fileImporter(isPresented: $relink, allowedContentTypes: ImageProcessor.importTypes) { result in
        switch result {
        case .success(let url): Task { await model.relinkSource(url) }
        case .failure(let error): if !error.isUserCancellation { model.issues.append(error.localizedDescription) }
        }
      }
      .alert("Clear photos, edits and creations?", isPresented: $confirmClear) {
        Button("Clear Workspace & Creations", role: .destructive) { Task { await model.clearImportedPhotos(); await refreshStorage() } }
        Button("Cancel", role: .cancel) {}
      } message: { Text("This clears the current workspace. Originals, exported files and saved workspace copies remain. Save a workspace copy first to preserve the current edits and creations.") }
  }
  func refreshStorage() async {
    do {
      let cleanup = SourceStorageCleanup()
      let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Projects")
      let retained = try await cleanup.retainedSnapshotNames(projects: folder, reusableConfiguration: JSONEncoder().encode(model.document()))
      storage = try await cleanup.summary(in: model.directory, retaining: retained)
      storageError = nil
    } catch is CancellationError {} catch { storageError = "Storage accounting unavailable: " + error.localizedDescription }
  }
}

struct SavedProjectLabel: View {
  let url: URL
  let store: ProjectStore
  @State private var name: String?
  @State private var unavailable = false
  @State private var modified: Date?
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name ?? (unavailable ? "Project instructions unavailable" : "Loading project name…"))
      if let modified { Text(modified, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
    }.task(id: url) {
      do { name = try await store.load(url).name; modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
      catch is CancellationError {} catch { unavailable = true }
    }
  }
}
