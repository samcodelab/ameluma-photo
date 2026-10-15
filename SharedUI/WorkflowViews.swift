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
        if categories.contains(.privacy) || categories.contains(.framing) {
          Text("Spatial edits use output-relative coordinates. Review mask coverage and framing on every destination photo.").font(.caption).foregroundStyle(.orange)
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
  @State private var heldOriginal = false
  @State private var originalBeforeHold = false
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
        if model.privacyCoverageNeedsReview(asset.id) {
          VStack(alignment: .leading, spacing: 6) {
            Label("Review privacy coverage after reframing", systemImage: "exclamationmark.shield").font(.headline)
            Text("The image moved beneath existing masks. Inspect the edited output before sharing.").font(.caption)
            Button("I’ve Checked the Mask Coverage") { model.confirmPrivacyCoverage(asset.id) }
              .disabled(original || model.precision)
          }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        if sizeClass != .compact { PhotoEditorTools(model: model, openSettings: openSettings) }
        Group {
          if model.precision && !original {
            PhotoCropCanvas(model: model, asset: asset)
          } else {
            if model.inspectorTask == .watermark && !original {
              WatermarkCanvas(model: model, asset: asset)
            } else { InspectablePhoto(model: model, asset: asset, original: original) }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
          .focusable().focused($previewFocused)
          .simultaneousGesture(TapGesture().onEnded { previewFocused = true })
          .onKeyPress("m", phases: [.down, .up]) { press in
            guard !model.precision else { return .ignored }
            if press.phase == .down { originalBeforeHold = original; heldOriginal = true; original = true }
            else if heldOriginal { original = originalBeforeHold; heldOriginal = false }
            return .handled
          }
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
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if sizeClass == .compact, model.current != nil {
          PhotoEditorTools(model: model, openSettings: openSettings).padding(8).background(.bar)
        }
      }
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
      .onChange(of: model.current?.id) { _, _ in original = false; heldOriginal = false }
  }
  var editorTabs: some View { PhotoDocumentTabs(model: model) }
  var previewLabel: String {
    if sizeClass == .compact { return original ? "Original" : model.precision ? "Cropping" : "Edited" }
    return original ? "Original · no edits" : model.precision
      ? "Crop view · drag boundaries or move the crop · overlays appear in Edited preview" : "Processed · current photo only"
  }
  @ViewBuilder func photoHeader(_ asset: SourceAsset) -> some View {
    if typeSize.isAccessibilitySize {
      HStack {
        Menu("Photo") {
          Button("Back to Gallery") { model.showLibrary() }
          previousPhoto; nextPhoto
          Toggle("Show Original", isOn: $original)
        }
        Text(asset.name).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
      }
    } else if sizeClass == .compact {
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
  @ViewBuilder var previewCaption: some View {
    if typeSize.isAccessibilitySize { Text(previewLabel).font(.caption).foregroundStyle(.secondary) }
    else { Label(previewLabel, systemImage: original ? "photo" : "slider.horizontal.3").font(.caption).foregroundStyle(.secondary) }
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
    Button(model.undoActionTitle) { model.undo() }.disabled(!model.canUndo)
    Button(model.redoActionTitle) { model.redo() }.disabled(!model.canRedo)
    Divider()
    restoreOriginalButton(asset)
  }
  private func restoreOriginalButton(_ asset: SourceAsset) -> some View {
    Button("Restore Original…", systemImage: "arrow.uturn.backward") { restorePhotoID = asset.id }
      .disabled(model.running || model.overlayEditor)
      .help("Remove this photo’s edits and return to its original dimensions. Undo is available.")
  }

}
struct ExportPlanView: View {
  @Bindable var model: Workspace
  @State private var preview = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(model.exportPlanSummary).font(.headline)
      if model.workflow == .batch && !model.exportProfiles.isEmpty {
        Button("Use Current Edits Only") { model.exportProfiles = []; model.persist() }
      }
      ForEach(model.exportDisplayProfiles) { profile in
        let config = model.exportingRequests.first(where: { model.running && $0.profile.id == profile.id })?.configuration ??
          model.exportPreviewAsset.map { model.exportConfiguration(for: $0, profile: profile) }
          ?? profile.processing ?? model.settings
        VStack(alignment: .leading, spacing: 3) {
          Text(profile.name).font(.subheadline.weight(.medium))
          Text(
            "\(config.format.rawValue.uppercased()) · \(sizeSummary(config)) · \(profile.namingTemplate)"
          ).font(.caption)
          if let asset = model.exportPreviewAsset {
            Text("Example: " + ImageProcessor.proposedFilename(asset: asset, profile: profile, format: config.format)).font(.caption).textSelection(.enabled)
          }
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
  @State private var sampleIndex = 0
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss
  var profile: ExportProfile {
    model.activeProfiles.first { $0.id == model.previewProfileID } ?? model.activeProfiles[0]
  }
  var sample: SourceAsset? {
    let targets = model.targets
    return targets.isEmpty ? model.exportPreviewAsset : targets[min(max(0, sampleIndex), targets.count - 1)]
  }
  struct ProofKey: Equatable { var asset: SourceAsset?; var profile: ExportProfile; var configuration: ProcessingConfiguration }
  var proofKey: ProofKey { ProofKey(asset: sample, profile: profile, configuration: sample.map { model.exportConfiguration(for: $0, profile: profile) } ?? model.settings) }
  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Text("Encoded output · " + profile.name).font(.headline)
        Picker("Output profile", selection: $model.previewProfileID) {
          ForEach(model.activeProfiles) { item in Text(item.name).tag(Optional(item.id)) }
        }
        HStack {
          Button("Previous") { sampleIndex = max(0, sampleIndex - 1) }.disabled(sampleIndex == 0)
          Text(sample?.name ?? "Photo").font(.caption).lineLimit(2)
          Button("Next") { sampleIndex = min(max(0, model.targets.count - 1), sampleIndex + 1) }.disabled(sampleIndex + 1 >= model.targets.count)
        }
        if let image {
          PixelZoomViewer(image: image)
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
        .onAppear { if model.previewProfileID == nil { model.previewProfileID = model.activeProfiles.first?.id } }
        .task(id: proofKey) {
          image = nil; bytes = 0; failure = nil
          let key = proofKey
          guard let asset = key.asset else { return }
          do {
            let value = try await model.processor.encodedPreview(
              asset.url, configuration: key.configuration)
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
  @State private var findingPhotos = false
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @ViewBuilder var body: some View {
    Group {
    if sizeClass == .compact || typeSize.isAccessibilitySize {
      HStack {
        Menu {
          ForEach(model.openEditorPhotos) { photo in
            Button { model.activateEditorTab(photo.id) } label: {
              Label(photo.name, systemImage: model.current?.id == photo.id ? "checkmark" : "photo")
            }
          }
          Divider()
          Button("Find Open Photo…", systemImage: "magnifyingglass") { findingPhotos = true }
          Button("Open Another Photo…", systemImage: "plus") { model.showLibrary() }
        } label: {
          Label(typeSize.isAccessibilitySize ? "Photos (\(model.editorTabs.count))" : "Open Photos (\(model.editorTabs.count))", systemImage: "square.on.square")
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
          LazyHStack(spacing: 4) {
            ForEach(model.openEditorPhotos) { photo in
              HStack(spacing: 6) {
                Button { model.activateEditorTab(photo.id) } label: {
                  HStack(spacing: 6) {
                    FramingSurface(model: model, asset: photo, interactive: false, maximum: 100).frame(width: 32, height: 26).clipped()
                    Text(photo.name).lineLimit(1).frame(maxWidth: 150).comfortableHitTarget()
                  }
                }.accessibilityValue(model.current?.id == photo.id ? "Active tab" : "")
                Button { model.closeEditorTab(photo.id) } label: {
                  Image(systemName: "xmark").font(.caption)
                }.comfortableHitTarget().accessibilityLabel("Close " + photo.name + "; keep edits")
                  .help("Close tab. Edits remain in the project.")
              }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 9)
                .background(model.current?.id == photo.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottom) {
                  if model.current?.id == photo.id { Capsule().fill(Color.accentColor).frame(height: 2) }
                }.id(photo.id).help(photo.name)
                .draggable("ameluma-tab:" + photo.id.uuidString)
                .dropDestination(for: String.self) { values, _ in
                  guard let value = values.first, value.hasPrefix("ameluma-tab:"), let source = UUID(uuidString: String(value.dropFirst(12))) else { return false }
                  model.moveEditorTab(source, before: photo.id); return true
                }
                .contextMenu {
                  Button("Close Photo") { model.closeEditorTab(photo.id) }
                  Button("Close Other Photos") { model.closeOtherEditorTabs(keeping: photo.id) }
                }
            }
            Button { findingPhotos = true } label: { Image(systemName: "list.bullet") }
              .accessibilityLabel("Find open photo documents")
            Button { model.showLibrary() } label: { Image(systemName: "plus") }
              .comfortableHitTarget().accessibilityLabel("Open another photo from library")
          }
        }.onChange(of: model.current?.id) { _, id in
          if let id { proxy.scrollTo(id, anchor: .center) }
        }
      }.fixedSize(horizontal: false, vertical: true)
    }
    }.sheet(isPresented: $findingPhotos) { OpenPhotoDocuments(model: model) }
  }
}

struct OpenPhotoDocuments: View {
  @Bindable var model: Workspace
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        ForEach(model.openEditorPhotos.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { asset in
          Button {
            model.activateEditorTab(asset.id); dismiss()
          } label: {
            HStack {
              FramingSurface(model: model, asset: asset, interactive: false, maximum: 160).frame(width: 64, height: 48)
              Text(asset.name)
              Spacer()
              if model.current?.id == asset.id { Image(systemName: "checkmark") }
            }
          }.buttonStyle(.plain).contextMenu {
            Button("Close Photo") { model.closeEditorTab(asset.id) }
            Button("Close Other Photos") { model.closeOtherEditorTabs(keeping: asset.id); dismiss() }
          }
        }
      }.searchable(text: $query, prompt: "Find an open photo").navigationTitle("Open Photos")
        .toolbar { Button("Done") { dismiss() } }
    }.frame(minWidth: 320, minHeight: 440)
  }
}

struct PhotoEditorTools: View {
  @Bindable var model: Workspace
  var openSettings: (() -> Void)? = nil
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @ViewBuilder var body: some View {
    if let asset = model.current {
      Group {
        if typeSize.isAccessibilitySize {
          Menu("Tools", systemImage: "slider.horizontal.3") { toolActions(asset) }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else if sizeClass == .compact {
          HStack(spacing: 6) {
            compactToolButton(.adjust, asset); compactToolButton(.crop, asset); compactToolButton(.privacy, asset)
            Menu {
              toolButton(.resize, asset); toolButton(.annotate, asset)
              toolButton(.watermark, asset); toolButton(.output, asset)
            } label: {
              VStack(spacing: 4) { Image(systemName: "ellipsis.circle"); Text("Tools").font(.caption).lineLimit(1) }
                .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain)
          }
        } else {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { toolActions(asset) }.fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 8) {
              toolButton(.adjust, asset); toolButton(.crop, asset); toolButton(.resize, asset)
              Menu("More", systemImage: "ellipsis") {
                toolButton(.annotate, asset); toolButton(.privacy, asset)
                toolButton(.watermark, asset); toolButton(.output, asset)
              }.accessibilityLabel("More photo tools")
            }
          }
        }
      }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  @ViewBuilder private func toolActions(_ asset: SourceAsset) -> some View {
    ForEach(PhotoTool.allCases, id: \.self) { tool in toolButton(tool, asset) }
  }
  private func toolButton(_ tool: PhotoTool, _ asset: SourceAsset) -> some View {
    Button(tool == .crop && sizeClass == .compact ? "Crop" : tool.rawValue, systemImage: tool.symbol) {
      activateTool(tool, asset)
    }.tint(isActive(tool) ? .accentColor : .secondary)
      .accessibilityValue(isActive(tool) ? "Current tool" : "")
  }
  private func compactToolButton(_ tool: PhotoTool, _ asset: SourceAsset) -> some View {
    Button { activateTool(tool, asset) } label: {
      VStack(spacing: 4) {
        Image(systemName: tool.symbol)
        Text(tool == .crop ? "Crop" : tool.rawValue).font(.caption).lineLimit(1)
      }.frame(maxWidth: .infinity, minHeight: 44).padding(4)
        .background(isActive(tool) ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).foregroundStyle(isActive(tool) ? Color.accentColor : Color.primary)
      .accessibilityValue(isActive(tool) ? "Current tool" : "")
  }
  private func activateTool(_ tool: PhotoTool, _ asset: SourceAsset) {
    switch tool {
    case .adjust: model.choosePhotoInspector(.adjust); openSettings?()
    case .crop: model.precision = true
    case .resize: model.choosePhotoInspector(.resize); openSettings?()
    case .annotate: model.openOverlayEditor(for: asset, masking: false)
    case .privacy: model.openOverlayEditor(for: asset)
    case .watermark: model.choosePhotoInspector(.watermark); openSettings?()
    case .output: model.choosePhotoInspector(.output); openSettings?()
    }
  }
  private func isActive(_ tool: PhotoTool) -> Bool {
    if model.overlayEditor { return model.overlayStartsWithMasks ? tool == .privacy : tool == .annotate }
    if model.precision { return tool == .crop }
    switch tool {
    case .adjust: return model.inspectorTask == .adjust
    case .resize: return model.inspectorTask == .resize
    case .watermark: return model.inspectorTask == .watermark
    case .output: return model.inspectorTask == .output
    default: return false
    }
  }

}
enum PhotoTool: String, CaseIterable {
    case adjust = "Adjust", crop = "Crop & Frame", resize = "Resize"
    case annotate = "Annotate", privacy = "Privacy", watermark = "Watermark", output = "Export Settings"
    var symbol: String {
      switch self {
      case .adjust: "slider.horizontal.3"
      case .crop: "crop"
      case .resize: "arrow.up.left.and.arrow.down.right"
      case .annotate: "textformat"
      case .privacy: "eye.slash"
      case .watermark: "signature"
      case .output: "square.and.arrow.down"
      }
    }
  }
