import SwiftUI
import FramepebbleCore
import UniformTypeIdentifiers

struct WatermarkDesignsView: View {
  @Bindable var model: Workspace
  /// Captured when the inspector opens the library, unaffected by subsequent selection.
  let targetIDs: [UUID]
  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var importDesign = false
  @State private var designs: [SavedWatermarkDesign] = []
  @State private var error: String?
  @State private var applying = false
  @State private var application: Task<Void, Never>?
  @State private var refresh = 0
  @State private var deleting: SavedWatermarkDesign?
  var targetSummary: String { "\(targetIDs.count) \(targetIDs.count == 1 ? "Photo" : "Photos")" }
  var body: some View {
    VStack(spacing: 0) {
      let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
      header {
        Text("Watermark Designs").font(.title2.bold())
        if !typeSize.isAccessibilitySize { Spacer() }
        if applying { ProgressView().controlSize(.small) }
        Button(applying ? "Cancel" : "Done") { application?.cancel(); dismiss() }
      }.padding(20)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(targetIDs.isEmpty ? "Create or import a reusable design. Open a photo or batch to apply it." : "Replace watermark content on \(targetSummary.lowercased()). Placement settings stay unchanged.")
            .font(.callout).foregroundStyle(.secondary)
          if let error { Label(error, systemImage: "exclamationmark.triangle"); Button("Retry") { refresh += 1 } }
          let sectionHeader = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
          sectionHeader {
            Text("Your Designs").font(.headline)
            if !typeSize.isAccessibilitySize { Spacer() }
            Button("Import Design…") { importDesign = true }
          }
          if designs.isEmpty {
            #if os(macOS)
            Text("Choose a template below, customise it, then Save Design.").foregroundStyle(.secondary)
            #else
            Text("Import a saved Ameluma watermark design to get started.").foregroundStyle(.secondary)
            #endif
          }
          ForEach(designs) { design in
            let vertical = sizeClass == .compact || typeSize.isAccessibilitySize
            let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())
            layout {
              WatermarkDesignThumbnail(document: design.document, package: design.url).frame(width: 144)
              VStack(alignment: .leading) {
                Text(design.document.name).font(.headline)
                Text("\(design.document.layers.count) editable elements").font(.caption).foregroundStyle(.secondary)
              }
              if !vertical { Spacer() }
              #if os(macOS)
              Button("Edit") { Task { await model.editWatermarkDesign(design); dismiss() } }
              #endif
              Button("Apply to \(targetSummary)") {
                applying = true
                application = Task {
                  let success = await model.applyWatermarkDesign(design, ids: targetIDs)
                  applying = false
                  if success && !Task.isCancelled { dismiss() }
                  else if !Task.isCancelled { error = model.issues.last ?? model.status }
                }
              }.disabled(targetIDs.isEmpty || applying)
            }.contextMenu {
              Button("Delete Saved Design…", role: .destructive) { deleting = design }
            }
          }
          #if os(macOS)
          Divider(); Text("Start a Design").font(.headline)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 16) {
            ForEach(WatermarkTemplates.all) { template in
              Button { model.newWatermarkDesign(template); dismiss() } label: {
                VStack(alignment: .leading, spacing: 6) {
                  WatermarkDesignThumbnail(document: template.document, package: nil)
                  Text(template.name).font(.headline)
                  Text(template.category).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
              }.buttonStyle(.plain).accessibilityLabel("Create \(template.name) watermark, \(template.category)")
            }
          }
          #else
          Text("Multi-element design authoring is currently available on Mac. Saved designs can be applied here.").font(.caption).foregroundStyle(.secondary)
          #endif
        }.padding(20)
      }
      .disabled(applying)
      .task(id: refresh) {
        do { designs = try await model.watermarkDesignLibrary.list(); error = nil }
        catch { self.error = "Could not read saved designs: " + error.localizedDescription }
      }
    }
    .background(.background)
    .frame(minWidth: 320, idealWidth: 640, minHeight: 400, idealHeight: 650)
    .confirmationDialog("Delete saved watermark design?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
      if let design = deleting {
        Button("Delete “\(design.document.name)”", role: .destructive) {
          Task {
            do { try await model.watermarkDesignLibrary.remove(design); refresh += 1; deleting = nil }
            catch { self.error = error.localizedDescription }
          }
        }
      }
    } message: { Text("Applied watermarks and exported images will remain unchanged.") }
    .fileImporter(isPresented: $importDesign, allowedContentTypes: [UTType(exportedAs: "com.broadframestudio.ameluma.document", conformingTo: .package)]) { result in
      guard case .success(let url) = result else {
        if case .failure(let failure) = result { error = failure.localizedDescription }
        return
      }
      Task {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { _ = try await model.watermarkDesignLibrary.importDesign(url); refresh += 1 }
        catch { self.error = "Could not import design: " + error.localizedDescription }
      }
    }
    .onDisappear { application?.cancel() }
  }
}
private enum WatermarkPreviewRenderer { static let shared = EditorDocumentRenderer() }
struct WatermarkDesignThumbnail: View {
  let document: EditorDocument
  let package: URL?
  @State private var image: CGImage?
  @State private var failed = false
  var body: some View {
    ZStack {
      Color(white: 0.18)
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit().padding(8) }
      else if failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.white) }
      else { ProgressView().controlSize(.small) }
    }.frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 4))
    .accessibilityLabel(document.name + (failed ? ", preview unavailable" : ""))
    .task(id: document) {
      do {
        let resources = Dictionary(uniqueKeysWithValues: document.resources.compactMap { resource -> (UUID, URL)? in
          package.map { (resource.id, $0.appendingPathComponent("Resources").appendingPathComponent(resource.filename)) }
        })
        let rendered = try await WatermarkPreviewRenderer.shared.render(document, resources: resources, maximum: 360)
        try Task.checkCancellation(); image = rendered; failed = false
      } catch is CancellationError {} catch { failed = true }
    }
  }
}
