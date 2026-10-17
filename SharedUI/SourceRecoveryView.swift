import SwiftUI
import FramepebbleCore

struct SourceRecoveryView: View {
  @Bindable var model: Workspace
  let sourceID: UUID
  @State private var choosingFile = false
  @State private var working = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Section("Locate Source Photo") {
          Text(model.assets.first { $0.id == sourceID }?.name ?? "Missing source").font(.headline)
          Text("Choose the matching photo. Editing instructions stay attached; affected photos and creations will need framing and mask review.")
          Button("Choose Photo…", systemImage: "folder") { choosingFile = true }.disabled(working || model.running || model.gifExporting || model.collageGenerating)
          if working { ProgressView("Updating source…") }
          if let failure { Text(failure).foregroundStyle(.red) }
        }
        Section("Used by") {
          if model.workspaceAssets.contains(where: { $0.id == sourceID }) { Label("Workspace photo", systemImage: "photo") }
          ForEach(affectedGIFs) { gif in Label(gif.name + " · GIF", systemImage: "photo.stack") }
          ForEach(model.savedCollages.filter { $0.project.cells.contains { $0.sourceID == sourceID } || $0.project.mosaicReferenceID == sourceID }) { collage in
            Label(collage.name + " · Collage", systemImage: "rectangle.split.2x2")
          }
        }
      }.navigationTitle("Source Recovery").compactNavigationTitle()
        .toolbar { Button("Cancel") { dismiss() }.disabled(working) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: ImageProcessor.importTypes) { result in
          switch result {
          case .success(let url):
            working = true
            Task {
              let issueCount = model.issues.count
              guard model.assets.contains(where: { $0.id == sourceID }) else { working = false; failure = "This source is no longer in the project."; return }
              model.relinkSourceID = sourceID
              await model.relinkSource(url)
              working = false
              if model.issues.count > issueCount { failure = model.issues.last }
              else if model.relinkSourceID == nil { dismiss() }
              else { failure = "The source could not be updated. Finish active work and try again." }
            }
          case .failure(let error): if !error.isUserCancellation { failure = error.localizedDescription }
          }
        }
    }.frame(minWidth: 300)
    #if os(macOS)
    .frame(minHeight: 360)
    #endif
  }
  var affectedGIFs: [GIFProject] {
    var result = model.archivedGIFs
    if let current = model.gifProject { result.removeAll { $0.id == current.id }; result.append(current) }
    return result.filter { $0.frames.contains { $0.sourceID == sourceID } }
  }
}
