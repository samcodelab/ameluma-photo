import FramepebbleCore
import SwiftUI

struct CopyEditsChooser: View {
  @Bindable var model: Workspace
  @State private var categories: Set<EditCategory> = [.adjustments]
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Text("Copy from: " + (model.workspaceAssets.first { $0.id == model.copySourceID }?.name ?? "Photo"))
        ForEach(EditCategory.allCases, id: \.self) { category in
          Toggle(
            category.rawValue,
            isOn: Binding(
              get: { categories.contains(category) },
              set: { if $0 { categories.insert(category) } else { categories.remove(category) } }))
        }
        if categories.contains(.privacy) || categories.contains(.framing) || categories.contains(.retouch) {
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
    }.frame(minWidth: 320)
    #if os(macOS)
    .frame(minHeight: 440)
    #endif
  }
}
struct PhotoEditorWorkspace: View {
  @Bindable var model: Workspace
  var openSettings: (() -> Void)? = nil
  var showsToolbox = true
  var anchoredOptions = false
  var showsQuickControls = true
  @State private var inlineControls = true
  @State private var original = false
  @State private var heldOriginal = false
  @State private var originalBeforeHold = false
  @State private var restorePhotoID: UUID?
  @State private var expandedCrop = false
  @State private var filterSettings = false
  @State private var layoutViewport = EditorPanelViewport()
  @FocusState private var previewFocused: Bool
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  var body: some View {
    GeometryReader { geometry in
    // Keyboard resizing must not remove the form containing the focused field.
    let viewportHeight = layoutViewport.height(fallback: geometry.size.height)
    let expanded = EditorPanelLayout.expandedControls(height: viewportHeight, accessibility: typeSize.isAccessibilitySize)
    #if os(macOS)
    let bottomToolbox = false
    #else
    let bottomToolbox = verticalSizeClass != .compact && !EditorPanelLayout.usesTabletRail(geometry.size, accessibility: typeSize.isAccessibilitySize)
    #endif
    VStack(spacing: 4) {
      if let asset = model.current {
        #if os(macOS)
        if typeSize.isAccessibilitySize { photoHeader(asset).padding(.horizontal, 8) }
        else { documentBar(asset).padding(.horizontal, 8) }
        #endif
        if model.privacyCoverageNeedsReview(asset.id) {
          VStack(alignment: .leading, spacing: 6) {
            Label("Review privacy coverage after reframing", systemImage: "exclamationmark.shield").font(.headline)
            Text("The image moved beneath existing masks. Inspect the edited output before sharing.").font(.caption)
            Button("I’ve Checked the Mask Coverage") { model.confirmPrivacyCoverage(asset.id) }
              .disabled(original || model.precision)
          }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }

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
        .background { EditorCanvasBackground() }
        .overlay(alignment: .topLeading) {
          if original {
            Label("Original preview", systemImage: "square.on.square")
              .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
              .background(.regularMaterial, in: Capsule()).padding(12)
              .accessibilityLabel("Previewing original. Your edits are retained.")
              .allowsHitTesting(false)
          }
        }
        .overlay {
          if showsQuickControls && model.photoToolOptionsVisible && !bottomToolbox && sizeClass != .compact && model.inspectorTask == .adjust && !model.precision && !typeSize.isAccessibilitySize && !original {
            FloatingToolOptions(title: "Adjust", toolIndex: 0, pin: openSettings) {
              SettingsEditor(model: model, focused: true, task: .adjust, showsContext: false,
                compactPanel: true, focusedAdjustment: true, adjustmentDetails: openSettings,
                dismissAdjustment: { model.photoToolOptionsVisible = false })
            }
          }
        }
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
        if showsToolbox && (sizeClass == .compact || (bottomToolbox && (model.inspectorTask == .adjust || model.inspectorTask == .filters) && !model.precision)) && ((inlineControls && model.photoToolOptionsVisible) || model.precision) && !expanded && model.inspectorTask != .filters {
          VStack(spacing: 0) {
            if model.precision || (model.inspectorTask != .adjust && model.inspectorTask != .filters) {
            HStack {
              Text(model.precision ? "Crop" : model.inspectorTask.rawValue).font(.headline)
              Spacer()
              if !model.precision, model.inspectorTask == .adjust, openSettings != nil {
                Button { openSettings?() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                  .comfortableHitTarget().accessibilityLabel("All adjustment controls")
              }
              Button { inlineControls = false; if model.precision { model.precision = false } } label: { Image(systemName: "xmark") }
                .comfortableHitTarget().accessibilityLabel("Close tool controls")
            }.padding(.horizontal, 12)
            }
            if !model.precision && model.inspectorTask == .filters { EmptyView() }
            else if !model.precision && model.inspectorTask == .adjust {
              SettingsEditor(model: model, focused: true, showsContext: false, compactPanel: true, focusedAdjustment: true, adjustmentDetails: openSettings, horizontalAdjustment: true)
            }
            else if model.precision { ScrollView { PrecisionEditor(model: model, showsHeader: false, showsPreview: false).padding(12) } }
            else { SettingsEditor(model: model, focused: true, showsContext: false, compactPanel: true, focusedAdjustment: model.inspectorTask == .adjust) }
          }.frame(height: model.inspectorTask == .adjust && !model.precision ? min(76, viewportHeight * 0.22) : model.inspectorTask == .filters ? min(sizeClass == .compact ? 210 : 240, viewportHeight * 0.32) : min(200, viewportHeight * 0.29)).background(.bar)
        }


      } else {
        ContentUnavailableView(
          "Choose a photo", systemImage: "photo",
          description: Text("Choose a photo from your workspace to start editing."))
        Button("Open Workspace", systemImage: "square.grid.2x2") { model.showLibrary() }
      }
    }
      #if os(iOS)
      .toolbar {
        if let asset = model.current {
          ToolbarItem(placement: .principal) {
            Text(asset.name)
              .font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
              .frame(maxWidth: sizeClass == .compact ? 160 : 320)
              .accessibilityLabel(asset.name + (model.isDemoWorkspace ? ", Demo Workspace" : ""))
          }
          ToolbarItemGroup(placement: .topBarTrailing) {
            if !typeSize.isAccessibilitySize {
              Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .comfortableHitTarget().disabled(!model.canUndo).accessibilityLabel(model.undoActionTitle)
              if sizeClass != .compact { Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.comfortableHitTarget().disabled(!model.canRedo).accessibilityLabel(model.redoActionTitle) }
            }
            if !typeSize.isAccessibilitySize {
              Toggle(isOn: $original) { Label("Compare Original", systemImage: "square.on.square") }
                .toggleStyle(.button).comfortableHitTarget()
                .accessibilityLabel("Show original without any visual edits").accessibilityValue(original ? "Original" : "Edited")
                .help("Compare all visual edits with the source photo")
            }
            Menu {
              if typeSize.isAccessibilitySize { Toggle("Show Original", isOn: $original) }
              editMenuActions(asset)
            } label: { Image(systemName: "ellipsis.circle") }
              .accessibilityLabel("Photo edits and history")
          }
        }
      }
      #endif
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if showsToolbox, verticalSizeClass != .compact, model.current != nil {
          if model.inspectorTask == .filters && !model.precision {
            if typeSize.isAccessibilitySize {
              HStack {
                Button { model.choosePhotoInspector(.adjust) } label: { Image(systemName: "chevron.left") }.comfortableHitTarget().accessibilityLabel("Back to editing tools")
                Button("Filter settings…") { filterSettings = true }.frame(maxWidth: .infinity)
              }.padding(8).background(.bar)
            } else {
              PhotoLooksPicker(model: model, compact: true, replacesToolbox: true)
                .padding(.horizontal, 8).padding(.vertical, 4).background(.bar)
            }
          } else {
          PhotoEditorTools(model: model, openSettings: {
            if expanded && model.precision { expandedCrop = true }
            else if expanded { openSettings?() }
            else if sizeClass == .compact || bottomToolbox { inlineControls = true }
            else if model.inspectorTask != .adjust || model.precision { openSettings?() }
          }, anchoredOptions: anchoredOptions).padding(.horizontal, 8).padding(.vertical, 4).background(.bar)
          }
        }
      }
      .safeAreaInset(edge: .trailing, spacing: 0) {
        if sizeClass == .compact, verticalSizeClass == .compact, model.current != nil {
          PhotoEditorTools(model: model, openSettings: {
            if model.precision { expandedCrop = true } else { openSettings?() }
          }).frame(width: 56).padding(4).background(.bar)
        }
      }
      .sheet(isPresented: $model.historyPresented) { EditingHistoryView(model: model) }
      .sheet(isPresented: $filterSettings) {
        NavigationStack {
          ScrollView { PhotoLooksPicker(model: model).padding(12) }
            .navigationTitle("Filters").compactNavigationTitle()
            .toolbar { Button("Done") { filterSettings = false } }
        }
      }
      .sheet(isPresented: $expandedCrop) {
        NavigationStack {
          ScrollView { PrecisionEditor(model: model, showsHeader: false, showsPreview: false).padding() }
            .navigationTitle("Crop").compactNavigationTitle()
            .toolbar { Button("Done") { expandedCrop = false } }
        }
      }
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
      .onAppear { layoutViewport.observe(geometry.size) }
      .onChange(of: geometry.size.width) { _, _ in layoutViewport.observe(geometry.size) }
    }
  }
  func documentBar(_ asset: SourceAsset) -> some View {
    HStack(spacing: 6) {
      Button { model.showLibrary() } label: { Image(systemName: "square.grid.2x2") }
        .comfortableHitTarget().accessibilityLabel("Back to Workspace")
      editorTabs.frame(maxWidth: .infinity)
      EditorHistoryButtons(model: model)
      editTransferControls(asset).labelStyle(.iconOnly)
      Toggle("Preview Original", isOn: $original).toggleStyle(.button).comfortableHitTarget()
        .help("Show the source photo without visual edits; exports keep your edits")
    }
  }
  var editorTabs: some View { PhotoDocumentTabs(model: model) }
  var previewLabel: String {
    if sizeClass == .compact { return original ? "Original" : model.precision ? "Cropping" : "Edited" }
    return original ? "Original · no edits" : model.precision
      ? "Crop view · drag boundaries or move the crop · overlays appear in Edited preview" : "Processed · current photo only"
  }
  @ViewBuilder func photoHeader(_ asset: SourceAsset) -> some View {
    if sizeClass == .compact || typeSize.isAccessibilitySize {
      HStack(spacing: 8) {
        Menu {
          Button("Back to Workspace", systemImage: "square.grid.2x2") { model.showLibrary() }
          ForEach(model.openEditorPhotos) { photo in Button(photo.name) { model.activateEditorTab(photo.id) } }
          Divider()
          previousPhoto; nextPhoto
          Button("Open Another Photo…") { model.showLibrary() }
          Button("Close This Photo; Keep Edits") { model.closeEditorTab(asset.id) }
          if typeSize.isAccessibilitySize { Toggle("Show Original", isOn: $original) }
          Divider()
          editMenuActions(asset)
        } label: { Text(typeSize.isAccessibilitySize ? "Photo" : asset.name).font(.subheadline.weight(.medium)).lineLimit(1) }
          .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
          .layoutPriority(1).accessibilityLabel("Photo and edit actions, current photo " + asset.name)
        Spacer(minLength: 4)
        EditorHistoryButtons(model: model)
        if !typeSize.isAccessibilitySize {
          Toggle(isOn: $original) { Label("Compare Original", systemImage: "square.on.square") }
            .toggleStyle(.button).comfortableHitTarget()
            .accessibilityLabel("Show original without any visual edits").accessibilityValue(original ? "Original" : "Edited")
                .help("Compare all visual edits with the source photo")
        }
      }
    } else {
      HStack {
        Button("Workspace", systemImage: "square.grid.2x2") { model.showLibrary() }
        Divider().frame(height: 18)
        previousPhoto
        nextPhoto
        Spacer()
        EditorHistoryButtons(model: model)
        editTransferControls(asset).labelStyle(.iconOnly)
        Toggle("Preview Original", isOn: $original).toggleStyle(.button)
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
  func editTransferControls(_ asset: SourceAsset) -> some View {
    Menu("Edits", systemImage: "ellipsis.circle") { editMenuActions(asset) }
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
    if config.nativeOutputSizing == true { return "Source dimensions · existing crop retained" }
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
    }.frame(minWidth: 320)
    #if os(macOS)
    .frame(minHeight: 480)
    #endif
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
    #if os(macOS)
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
                    Text(photo.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 130)
                  }
                }.accessibilityValue(model.current?.id == photo.id ? "Active tab" : "")
                Button { model.closeEditorTab(photo.id) } label: {
                  Image(systemName: "xmark").font(.caption)
                }.comfortableHitTarget().accessibilityLabel("Close " + photo.name + "; keep edits")
                  .help("Close tab. Edits remain in the project.")
              }.buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 4)
                .background(model.current?.id == photo.id ? Color.accentColor.opacity(0.1) : .clear)
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
    #else
    EmptyView()
    #endif
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
    }.frame(minWidth: 320)
    #if os(macOS)
    .frame(minHeight: 440)
    #endif
  }
}

struct PhotoEditorTools: View {
  @Bindable var model: Workspace
  var openSettings: (() -> Void)? = nil
  var selectedTool: PhotoTool? = nil
  var onSelect: ((PhotoTool) -> Void)? = nil
  var vertical = false
  var anchoredOptions = false
  @State private var optionsTool: PhotoTool?
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @ViewBuilder var body: some View {
    if let asset = model.current {
      Group {
        if vertical {
          ScrollView {
            VStack(spacing: 6) { toolActions(asset) }.labelStyle(.iconOnly)
          }.frame(width: EditorPanelLayout.toolRailWidth)
        } else if typeSize.isAccessibilitySize {
          Menu("Tools", systemImage: "slider.horizontal.3") { toolActions(asset) }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else if sizeClass == .compact {
          let layout = verticalSizeClass == .compact ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
          layout {
            compactToolButton(.adjust, asset); compactToolButton(.filters, asset); compactToolButton(.crop, asset); compactToolButton(.retouch, asset)
            Menu {
              toolButton(.resize, asset); toolButton(.annotate, asset); toolButton(.privacy, asset)
              toolButton(.watermark, asset); toolButton(.output, asset)
            } label: {
              VStack(spacing: 4) { Image(systemName: secondaryTool?.symbol ?? "ellipsis.circle"); if verticalSizeClass != .compact { Text(secondaryTool?.rawValue ?? "Tools").font(.caption).lineLimit(1) } }
                .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain)
              .accessibilityLabel(secondaryTool.map { "\($0.rawValue), more photo tools" } ?? "More photo tools")
          }
        } else {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { toolActions(asset) }.labelStyle(.iconOnly).fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 8) {
              toolButton(.adjust, asset); toolButton(.filters, asset); toolButton(.crop, asset); toolButton(.resize, asset)
              Menu("More", systemImage: "ellipsis") {
                toolButton(.retouch, asset); toolButton(.annotate, asset); toolButton(.privacy, asset)
                toolButton(.watermark, asset); toolButton(.output, asset)
              }.accessibilityLabel(secondaryTool.map { "\($0.rawValue), more photo tools" } ?? "More photo tools")
            }
          }
        }
      }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private var secondaryTool: PhotoTool? {
    [PhotoTool.resize, .annotate, .privacy, .watermark, .output].first { isActive($0) }
  }
  @ViewBuilder private func toolActions(_ asset: SourceAsset) -> some View {
    ForEach(PhotoTool.allCases, id: \.self) { tool in toolButton(tool, asset) }
  }
  private func toolButton(_ tool: PhotoTool, _ asset: SourceAsset) -> some View {
    Button(tool == .crop && sizeClass == .compact ? "Crop" : tool.rawValue, systemImage: tool.symbol) {
      activateTool(tool, asset)
    }.buttonStyle(EditorToolButtonStyle(selected: isActive(tool)))
      .accessibilityAddTraits(isActive(tool) ? .isSelected : [])
      .accessibilityValue(isActive(tool) ? "Current tool" : "").toolNameHint(tool.rawValue)
      .popover(isPresented: Binding(get: { optionsTool == tool }, set: { if !$0 { optionsTool = nil } }),
               attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
        VStack(spacing: 0) {
          HStack { Text(tool.rawValue).font(.headline); Spacer(); Button("Done") { optionsTool = nil } }.padding(12)
          Divider()
          if tool == .crop { ScrollView { PrecisionEditor(model: model, showsHeader: false, showsPreview: false).padding(12) } }
          else { SettingsEditor(model: model, focused: true, showsContext: false, compactPanel: true) }
        }.frame(minWidth: 280, idealWidth: 320, maxWidth: 380, minHeight: 220, idealHeight: 380, maxHeight: 520)
          .presentationCompactAdaptation(typeSize.isAccessibilitySize ? .sheet : .popover)
      }
  }
  private func compactToolButton(_ tool: PhotoTool, _ asset: SourceAsset) -> some View {
    Button { activateTool(tool, asset) } label: {
      VStack(spacing: 4) {
        Image(systemName: tool.symbol)
        if verticalSizeClass != .compact { Text(tool == .crop ? "Crop" : tool.rawValue).font(.caption).lineLimit(1) }
      }.frame(maxWidth: .infinity, minHeight: 44).padding(4)

    }.buttonStyle(EditorToolButtonStyle(selected: isActive(tool)))
      .toolNameHint(tool.rawValue)
      .accessibilityLabel(tool == .crop ? "Crop" : tool.rawValue)
      .accessibilityValue(isActive(tool) ? "Current tool" : "")
      .accessibilityAddTraits(isActive(tool) ? .isSelected : [])
  }
  private func activateTool(_ tool: PhotoTool, _ asset: SourceAsset) {
    if let onSelect { onSelect(tool); return }
    if tool == .adjust && isActive(tool) && sizeClass == .compact && verticalSizeClass != .compact && !typeSize.isAccessibilitySize {
      model.photoToolOptionsVisible.toggle()
      if model.photoToolOptionsVisible { openSettings?() }
      return
    }
    guard model.activatePhotoTool(tool) else { return }
    model.photoToolOptionsVisible = true
    if tool != .annotate && tool != .privacy && tool != .retouch {
      if tool == .adjust || tool == .filters { openSettings?() }
      else if anchoredOptions { optionsTool = tool } else { openSettings?() }
    }
  }

  private func isActive(_ tool: PhotoTool) -> Bool {
    if let selectedTool { return selectedTool == tool }
    if model.overlayEditor { if model.overlayRetouch { return tool == .retouch }; return model.overlayStartsWithMasks ? tool == .privacy : tool == .annotate }
    if model.precision { return tool == .crop }
    switch tool {
    case .adjust: return model.inspectorTask == .adjust
    case .filters: return model.inspectorTask == .filters
    case .resize: return model.inspectorTask == .resize
    case .watermark: return model.inspectorTask == .watermark
    case .output: return model.inspectorTask == .output
    default: return false
    }
  }

}
enum PhotoTool: String, CaseIterable {
    case adjust = "Adjust", filters = "Filters", crop = "Crop & Frame", resize = "Resize"
    case retouch = "Retouch", annotate = "Annotate", privacy = "Privacy", watermark = "Watermark", output = "Output Settings"
    var symbol: String {
      switch self {
      case .adjust: "slider.horizontal.3"
      case .filters: "camera.filters"
      case .crop: "crop"
      case .resize: "arrow.up.left.and.arrow.down.right"
      case .retouch: "bandage"
      case .annotate: "textformat"
      case .privacy: "eye.slash"
      case .watermark: "signature"
      case .output: "gearshape"
      }
    }
  }
