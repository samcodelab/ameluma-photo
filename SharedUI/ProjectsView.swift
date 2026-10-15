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
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section("Current Workspace") {
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
          Button("Clear Imported Photos…", role: .destructive) { confirmClear = true }
            .disabled(model.clearingWorkspace)
          Text("Close saves your work. Clear removes current photos and edits, and frees unused local copies. Originals, exported images and copies needed by saved projects remain untouched.").font(.caption).foregroundStyle(.secondary)
          Button("Open project instructions…") { open = true }
          if model.current != nil {
            Button("Relink selected source…") { relink = true }
            Text("Choose the matching original. Existing edits remain attached; review the result.")
              .font(.caption)
          }
        }
        Section("Recent Projects") {
          ForEach(projects, id: \.self) { url in
            Button(url.deletingPathExtension().lastPathComponent) {
              Task {
                await model.openProject(url)
                dismiss()
              }
            }
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
      Button("Clear Imported Photos", role: .destructive) { Task { await model.clearImportedPhotos(); reload() } }
      Button("Cancel", role: .cancel) {}
    } message: { Text("This cannot be undone. Current unsaved edits will be discarded. Import and processing will stop. Only unused copies in Ameluma Photo’s local source storage are removed. Your originals, saved projects and exported files are preserved. Save a project copy first if you want to return to this work.") }
    .frame(minWidth: 320, minHeight: 440)
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
