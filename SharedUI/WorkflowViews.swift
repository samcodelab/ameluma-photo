import FramepebbleCore
import SwiftUI

struct CopyEditsChooser: View {
  @Bindable var model: Workspace
  @State private var categories: Set<EditCategory> = [.adjustments]
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Text("Copy from: " + (model.assets.first { $0.id == model.copySourceID }?.name ?? "Photo"))
        ForEach(EditCategory.allCases, id: \.self) { category in
          Toggle(
            category.rawValue,
            isOn: Binding(
              get: { categories.contains(category) },
              set: { if $0 { categories.insert(category) } else { categories.remove(category) } }))
        }
        Text(
          "Only checked categories will replace corresponding edits when pasted. Other edits remain intact."
        ).font(.caption).foregroundStyle(.secondary)
      }.navigationTitle("Copy Chosen Edits").toolbar {
        Button("Cancel") { dismiss() }
        Button("Copy") {
          if let id = model.copySourceID { model.copyEdits(from: id, categories: categories) }
          dismiss()
        }.disabled(categories.isEmpty)
      }
    }.frame(minWidth: 320, minHeight: 440)
  }
}
struct PhotoEditorWorkspace: View {
  @Bindable var model: Workspace
  var openSettings: (() -> Void)? = nil
  @State private var original = false
  @State private var restorePhotoID: UUID?
  @FocusState private var previewFocused: Bool
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(spacing: 12) {
      if let asset = model.current {
        editorTabs
        photoHeader(asset)
        if typeSize.isAccessibilitySize {
          Menu { toolActions(asset) } label: {
            Label("Tools", systemImage: "slider.horizontal.3").frame(minHeight: 44)
          }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Photo editing tools")
        } else {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { toolActions(asset) }.fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 8) {
              toolButton(.adjust, asset)
              toolButton(.crop, asset)
              if sizeClass != .compact { toolButton(.resize, asset) }
              Menu("More", systemImage: "ellipsis") {
                if sizeClass == .compact { toolButton(.resize, asset) }
                toolButton(.annotate, asset)
                toolButton(.privacy, asset)
                toolButton(.output, asset)
              }.accessibilityLabel("More photo tools")
            }
          }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
        }
        Group {
          if model.precision && !original {
            PhotoCropCanvas(model: model, asset: asset)
          } else {
            FramingSurface(model: model, asset: asset, interactive: false, original: original)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
          .focusable().focused($previewFocused)
          .simultaneousGesture(TapGesture().onEnded { previewFocused = true })
          .onKeyPress(.leftArrow) {
            guard !model.precision else { return .ignored }
            model.navigate(-1); return .handled
          }
          .onKeyPress(.rightArrow) {
            guard !model.precision else { return .ignored }
            model.navigate(1); return .handled
          }
        #endif
        ViewThatFits(in: .horizontal) {
          HStack {
            previewCaption.fixedSize(horizontal: true, vertical: false)
            Spacer()
            editTransferControls(asset)
          }
          VStack(alignment: .leading, spacing: 8) {
            previewCaption
            HStack { Spacer(); editTransferControls(asset) }
          }
        }

      } else {
        ContentUnavailableView(
          "Choose a photo", systemImage: "photo",
          description: Text("Open photos from the library to edit them in tabs."))
        Button("Open Photo Library", systemImage: "square.grid.2x2") { model.showLibrary() }
      }
    }.padding(16)
      .sheet(isPresented: $model.historyPresented) { EditingHistoryView(model: model) }
      .confirmationDialog("Restore Original?", isPresented: Binding(
        get: { restorePhotoID != nil }, set: { if !$0 { restorePhotoID = nil } }
      ), titleVisibility: .visible) {
        Button("Restore Original", role: .destructive) {
          if let id = restorePhotoID { model.restoreOriginalPhoto(id) }
          original = false
          restorePhotoID = nil
        }
        Button("Cancel", role: .cancel) { restorePhotoID = nil }
      } message: {
        Text("Restore this photo’s original appearance and dimensions? This removes adjustments, cropping, rotation, watermarks, annotations and privacy masks from this photo only. Export format, quality and metadata protection stay unchanged. Your original file is untouched, and you can Undo.")
      }
      .onChange(of: model.precision) { _, enabled in if enabled { original = false } }
      .onChange(of: model.current?.id) { _, _ in original = false }
  }
  var editorTabs: some View { PhotoDocumentTabs(model: model) }
  var previewLabel: String {
    if sizeClass == .compact { return original ? "Original" : model.precision ? "Cropping" : "Edited" }
    return original ? "Original · no edits" : model.precision
      ? "Crop view · drag boundaries or move the crop · overlays appear in Edited preview" : "Processed · current photo only"
  }
  @ViewBuilder func photoHeader(_ asset: SourceAsset) -> some View {
    if sizeClass == .compact || typeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Button { model.showLibrary() } label: { Image(systemName: "square.grid.2x2") }
            .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Back to gallery")
          Text(asset.name).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack {
          previousPhoto
          nextPhoto
          if let index = model.openEditorPhotos.firstIndex(where: { $0.id == asset.id }) {
            Text("\(index + 1) of \(model.openEditorPhotos.count)").font(.caption).lineLimit(1)
          }
          Spacer(minLength: 4)
          if typeSize.isAccessibilitySize {
            Toggle(isOn: $original) { Image(systemName: "square.on.square") }
              .toggleStyle(.button).frame(minWidth: 44, minHeight: 44)
              .accessibilityLabel("Compare with original").accessibilityValue(original ? "Original" : "Edited")
          } else {
            Toggle("Original", isOn: $original).toggleStyle(.button).fixedSize()
              .frame(minHeight: 44)
          }
        }
      }
    } else {
      HStack {
        Button("Gallery", systemImage: "square.grid.2x2") { model.showLibrary() }
        Divider().frame(height: 18)
        previousPhoto
        Text(asset.name).font(.headline).lineLimit(1)
        nextPhoto
        Spacer()
        Toggle("Original", isOn: $original).toggleStyle(.button)
      }
    }
  }
  var previousPhoto: some View {
    Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }
      .comfortableHitTarget().accessibilityLabel("Previous photo")
  }
  var nextPhoto: some View {
    Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }
      .comfortableHitTarget().accessibilityLabel("Next photo")
  }
  var previewCaption: some View {
    Label(previewLabel, systemImage: original ? "photo" : "slider.horizontal.3")
      .font(.caption).foregroundStyle(.secondary)
  }
  @ViewBuilder func editTransferControls(_ asset: SourceAsset) -> some View {
    if sizeClass == .compact || typeSize.isAccessibilitySize {
      Menu("Edits") { editMenuActions(asset) }
    } else {
      ViewThatFits(in: .horizontal) {
        HStack {
          Button("Copy Chosen Edits…") { model.copySourceID = asset.id }
          Button("Paste Chosen Edits") { model.pasteEdits(to: [asset.id]) }
            .disabled(model.copiedEdits == nil)
          restoreOriginalButton(asset)
        }.fixedSize(horizontal: true, vertical: false)
        Menu("Edits") { editMenuActions(asset) }
      }
    }
  }
  @ViewBuilder private func editMenuActions(_ asset: SourceAsset) -> some View {
    Button("Copy Chosen Edits…") { model.copySourceID = asset.id }
    Button("Paste Chosen Edits") { model.pasteEdits(to: [asset.id]) }
      .disabled(model.copiedEdits == nil)
    Divider()
    Button("Undo History…", systemImage: "clock.arrow.circlepath") { model.historyPresented = true }
    Button("Undo") { model.undo() }.disabled(!model.canUndo)
    Button("Redo") { model.redo() }.disabled(!model.canRedo)
    Divider()
    restoreOriginalButton(asset)
  }
  private func restoreOriginalButton(_ asset: SourceAsset) -> some View {
    Button("Restore Original…", systemImage: "arrow.uturn.backward") { restorePhotoID = asset.id }
      .disabled(model.running || model.overlayEditor)
      .help("Remove this photo’s edits and return to its original dimensions. Undo is available.")
  }
  @ViewBuilder private func toolActions(_ asset: SourceAsset) -> some View {
    ForEach(PhotoTool.allCases, id: \.self) { tool in toolButton(tool, asset) }
  }
  private func toolButton(_ tool: PhotoTool, _ asset: SourceAsset) -> some View {
    Button(tool == .crop && sizeClass == .compact ? "Crop" : tool.rawValue, systemImage: tool.symbol) {
      switch tool {
      case .adjust: model.choosePhotoInspector(.adjust); openSettings?()
      case .crop: original = false; model.precision = true
      case .resize: model.choosePhotoInspector(.resize); openSettings?()
      case .annotate: model.openOverlayEditor(for: asset, masking: false)
      case .privacy: model.openOverlayEditor(for: asset)
      case .output: model.choosePhotoInspector(.output); openSettings?()
      }
    }.tint(isActive(tool) ? .accentColor : .secondary)
      .accessibilityValue(isActive(tool) ? "Current tool" : "")
  }
  private func isActive(_ tool: PhotoTool) -> Bool {
    if model.precision { return tool == .crop }
    switch tool {
    case .adjust: return model.inspectorTask == .adjust
    case .resize: return model.inspectorTask == .resize
    case .output: return model.inspectorTask == .output
    default: return false
    }
  }
  private enum PhotoTool: String, CaseIterable {
    case adjust = "Adjust", crop = "Crop & Frame", resize = "Resize"
    case annotate = "Annotate", privacy = "Privacy", output = "Watermark & Format"
    var symbol: String {
      switch self {
      case .adjust: "slider.horizontal.3"
      case .crop: "crop"
      case .resize: "arrow.up.left.and.arrow.down.right"
      case .annotate: "textformat"
      case .privacy: "eye.slash"
      case .output: "square.and.arrow.down"
      }
    }
  }

}
struct ExportPlanView: View {
  @Bindable var model: Workspace
  @State private var preview = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(model.exportPlanSummary).font(.headline)
      ForEach(model.exportDisplayProfiles) { profile in
        let config = model.exportingRequests.first(where: { model.running && $0.profile.id == profile.id })?.configuration ??
          model.exportPreviewAsset.map { model.exportConfiguration(for: $0, profile: profile) }
          ?? profile.processing ?? model.settings
        VStack(alignment: .leading, spacing: 3) {
          Text(profile.name).font(.subheadline.weight(.medium))
          Text(
            "\(config.format.rawValue.uppercased()) · \(sizeSummary(config)) · \(profile.namingTemplate)"
          ).font(.caption)
          Text(
            profile.destination?.lastPathComponent ?? model.lastDestination?.lastPathComponent
              ?? "Choose a destination at export"
          ).font(.caption).foregroundStyle(.secondary)
          Button("Preview " + profile.name) {
            model.previewProfileID = profile.id
            preview = true
          }.disabled(model.running || model.exportPreviewAsset == nil)
        }
      }
    }.sheet(isPresented: $preview) { OutputPreview(model: model) }
  }
  func sizeSummary(_ config: ProcessingConfiguration) -> String {
    guard config.crop.mode == .preserveAspectRatio else { return "\(config.width) × \(config.height) px" }
    switch config.resizeBasis {
    case .width: return "\(config.width) px wide · proportional height"
    case .height: return "\(config.height) px high · proportional width"
    case .longestEdge: return "Longest edge \(config.width) px"
    case .percentage: return "\(config.percentage)% of source size"
    }
  }

}
struct OutputPreview: View {
  @Bindable var model: Workspace
  @State private var image: CGImage?
  @State private var bytes = 0
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss
  var profile: ExportProfile {
    model.activeProfiles.first { $0.id == model.previewProfileID } ?? model.activeProfiles[0]
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Text("Encoded output · " + profile.name).font(.headline)
        if let asset = model.exportPreviewAsset { Text(asset.name).font(.caption) }
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
          Text("\(image.width) × \(image.height) px · \(bytes) bytes").font(.caption)
        } else if let failure {
          ContentUnavailableView(
            "Output preview failed", systemImage: "exclamationmark.triangle",
            description: Text(failure))
        } else {
          ProgressView("Rendering and encoding final-resolution output…")
        }
        Text(
          "Uses the actual encoder and target-size search. Large outputs can take longer. No file is exported by this preview."
        ).font(.caption).foregroundStyle(.secondary)
      }.padding().navigationTitle("Output Preview").toolbar { Button("Done") { dismiss() } }
        .task {
          guard let asset = model.exportPreviewAsset else { return }
          do {
            let value = try await model.processor.encodedPreview(
              asset.url, configuration: model.exportConfiguration(for: asset, profile: profile))
            try Task.checkCancellation()
            image = value.image
            bytes = value.byteCount
          } catch is CancellationError {} catch { failure = error.localizedDescription }
        }
    }.frame(minWidth: 320, minHeight: 480)
  }
}

/// Installed view environment keeps phone and accessibility tab presentation adaptive,
/// including while the privacy/annotation draft uses the same document strip.
struct PhotoDocumentTabs: View {
  @Bindable var model: Workspace
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @ViewBuilder var body: some View {
    if sizeClass == .compact || typeSize.isAccessibilitySize {
      HStack {
        Menu {
          ForEach(model.openEditorPhotos) { photo in
            Button { model.activateEditorTab(photo.id) } label: {
              Label(photo.name, systemImage: model.current?.id == photo.id ? "checkmark" : "photo")
            }
          }
          Divider()
          Button("Open Another Photo…", systemImage: "plus") { model.showLibrary() }
        } label: {
          Label("Open Photos (\(model.editorTabs.count))", systemImage: "square.on.square")
        }.frame(minHeight: 44)
        Spacer()
        if let id = model.current?.id {
          Button { model.closeEditorTab(id) } label: { Image(systemName: "xmark") }
            .comfortableHitTarget().accessibilityLabel("Close photo; keep edits")
        }
      }
    } else {
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(model.openEditorPhotos) { photo in
              HStack(spacing: 6) {
                Button { model.activateEditorTab(photo.id) } label: {
                  Text(photo.name).lineLimit(1).frame(maxWidth: 180).comfortableHitTarget()
                }.accessibilityValue(model.current?.id == photo.id ? "Active tab" : "")
                Button { model.closeEditorTab(photo.id) } label: {
                  Image(systemName: "xmark").font(.caption)
                }.comfortableHitTarget().accessibilityLabel("Close " + photo.name + "; keep edits")
                  .help("Close tab. Edits remain in the project.")
              }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 9)
                .background(model.current?.id == photo.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottom) {
                  if model.current?.id == photo.id { Capsule().fill(Color.accentColor).frame(height: 2) }
                }.id(photo.id)
            }
            Button { model.showLibrary() } label: { Image(systemName: "plus") }
              .comfortableHitTarget().accessibilityLabel("Open another photo from library")
          }
        }.onChange(of: model.current?.id) { _, id in
          if let id { proxy.scrollTo(id, anchor: .center) }
        }
      }.fixedSize(horizontal: false, vertical: true)
    }
  }
}
