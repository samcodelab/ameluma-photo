import FramepebbleCore
import SwiftUI

struct LibrarySidebar: View {
  @Bindable var model: Workspace
  var openAutomations: (() -> Void)? = nil
  var body: some View {
    List {
      Section("Workspace") {
        Text(model.projectName).font(.headline).lineLimit(2)
        Button { model.projectsView = true } label: {
          Label { Text("Projects…") } icon: { Image(systemName: "folder").foregroundStyle(.primary) }
        }
        DemoWorkspaceButton(model: model)
        scopeButton(.all)
        scopeButton(.favourites)
        ForEach([LibraryScope.edited, .exceptions].filter { prominent($0) }, id: \.self) { scopeButton($0) }
        let secondary = [LibraryScope.edited, .exceptions, .review, .privacyReview].filter { !prominent($0) }
        if !secondary.isEmpty {
          DisclosureGroup("More Filters") {
            ForEach(secondary, id: \.self) { scopeButton($0) }
          }
        }
      }
      let reviews = [LibraryScope.review, .privacyReview].filter { prominent($0) }
      if !reviews.isEmpty {
        Section("Review") { ForEach(reviews, id: \.self) { scopeButton($0) } }
      }
      Section("Tools") {
        ForEach(StudioWorkflow.allCases, id: \.self) { workflow in
          #if os(iOS)
          if workflow != .automations { workflowButton(workflow) }
          #else
          if !model.isDemoWorkspace || workflow != .automations { workflowButton(workflow) }
          #endif
        }
      }
      Section("Quick Tasks") {
        Button { model.selectPhotos(for: .convert) } label: {
          Label { Text("Convert Photos") } icon: { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.primary) }
        }
        Button { model.selectPhotos(for: .resize) } label: {
          Label { Text("Resize Photos") } icon: { Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.primary) }
        }
      }.disabled(model.gifSelectionContext != nil || model.overlayEditor)
      if model.browsingLibrary {
      DisclosureGroup("Categories") {
        ForEach(Array(model.index.suggestedCategories.prefix(10)), id: \.0) { name, count in
          Button {
            model.showLibrary()
            model.query = name
          } label: {
            HStack {
              Label(
                name.replacingOccurrences(of: "_", with: " ").capitalized,
                systemImage: "sparkle.magnifyingglass")
              Spacer()
              Text("\(count)").font(.caption)
            }
          }
        }
        Text("\(model.index.records.count) / \(model.workspaceAssets.count) indexed locally").font(.caption2)
          .foregroundStyle(.secondary)
      }
      }
      DisclosureGroup("Help & Review") {
        Button("Help & Privacy", systemImage: "questionmark.circle") { model.helpPresented = true }
        Button("Check photo privacy…", systemImage: "checkmark.shield") {
          model.sensitiveReviewPresented = true
        }
      }
      DisclosureGroup("Presets") {
        ForEach(model.profiles) { profile in
          Button {
            model.switchWorkflow(.batch)
            model.applyPreset(profile)
          } label: {
            Label(profile.name, systemImage: "square.stack")
          }
        }
      }
    }.listStyle(.sidebar).buttonStyle(.plain)
      #if os(macOS)
      .environment(\.defaultMinListRowHeight, 28)
      #endif
  }
  func prominent(_ category: LibraryScope) -> Bool {
    count(category) > 0 || (model.browsingLibrary && model.library == category)
  }
  func scopeButton(_ category: LibraryScope) -> some View {
    Button { model.showLibrary(category, clearSearch: true) } label: {
      HStack {
        Label(category == .exceptions ? "Photo-specific edits" : category.rawValue, systemImage: symbol(category))
          .symbolRenderingMode(.monochrome)
        Spacer()
        Text("\(count(category))").font(.caption).foregroundStyle(.secondary)
      }.foregroundStyle(model.browsingLibrary && model.library == category ? Color.accentColor : Color.primary)
    }
  }
  func workflowButton(_ workflow: StudioWorkflow) -> some View {
    Button { model.switchWorkflow(workflow) } label: {
      Label { Text(workflow.rawValue) } icon: {
        Image(systemName: workflow.symbol).symbolRenderingMode(.monochrome)
          .foregroundStyle(!model.browsingLibrary && model.workflow == workflow ? Color.accentColor : Color.primary)
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .foregroundStyle(!model.browsingLibrary && model.workflow == workflow ? Color.accentColor : Color.primary)
    }
  }
  func symbol(_ category: LibraryScope) -> String {
    switch category {
    case .exceptions: "slider.horizontal.3"
    case .all: "photo.on.rectangle.angled"
    case .favourites: "heart"
    case .edited: "slider.horizontal.3"
    case .review: "exclamationmark.bubble"
    case .privacyReview: "checkmark.shield"
    }
  }
  func count(_ category: LibraryScope) -> Int {
    switch category {
    case .exceptions: model.workspaceAssets.filter { model.edits.overrides[$0.id] != nil }.count
    case .all: model.workspaceAssets.count
    case .favourites: model.workspaceAssets.filter { model.favourites.contains($0.id) }.count
    case .edited: model.workspaceAssets.filter { model.isEdited($0.id) }.count
    case .review: model.workspaceAssets.filter { model.proposals[$0.id]?.needsReview == true || model.privacyCoverageNeedsReview($0.id) }.count
    case .privacyReview: model.workspaceAssets.filter { model.sensitivity.flagged.contains($0.id) || model.privacyCoverageReviewIDs.contains($0.id) }.count
    }
  }
}
struct LibraryToolbar: View {
  @Bindable var model: Workspace
  var operationOnly: Binding<Bool>? = nil
  @AppStorage("workspace.showFilenames") private var showFilenames = true
  @AppStorage("workspace.showFavouriteButtons") private var showFavouriteButtons = false
  @State private var confirmReset = false
  @State private var confirmResetAll = false
  @State private var resetPurpose = "Restore Original Appearance"
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  var galleryInstruction: String {
    #if os(macOS)
    "Double-click a photo to edit. Right-click for photo actions."
    #else
    sizeClass == .compact
      ? (typeSize.isAccessibilitySize ? "Tap to edit. Select for a batch." : "Tap a photo to edit. Long-press for photo actions, or choose Select to build a batch.")
      : "Double-tap a photo to edit. Long-press for photo actions."
    #endif
  }
  @ViewBuilder var galleryHeading: some View {
    if model.browsingLibrary {
      #if os(macOS)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.library.rawValue).font(.headline)
        gallerySummary
      }
      #else
      if sizeClass == .compact {
        Text("\(model.filtered.count) \(model.filtered.count == 1 ? "photo" : "photos")").font(.subheadline).foregroundStyle(.secondary)
      } else { gallerySummary }
      #endif
    } else if sizeClass == .compact {
      OperationContextHeader(model: model)
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { OperationContextHeader(model: model); modePicker }
        OperationContextHeader(model: model)
      }
    }
  }
  var body: some View {
    VStack(spacing: 4) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { galleryHeading; Spacer(minLength: 4); selectionControls }
        VStack(alignment: .leading, spacing: 4) { galleryHeading; HStack { Spacer(); selectionControls } }
      }
      if (model.selecting || !model.selection.isEmpty) && (operationOnly == nil || model.batchSelectionNeedsExplanation) {
        Text(operationOnly == nil ? model.workspaceSelectionStatus : model.batchSelectionExplanation).font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !model.sensitivity.flagged.isEmpty {
        HStack {
          Label(
            "Photos to review: \(model.sensitivity.flagged.count)",
            systemImage: "exclamationmark.shield"
          ).font(.caption)
          Spacer()
          Button("Review") { model.sensitiveReviewPresented = true }
        }
      }
    }.padding(.horizontal, 16).padding(.vertical, 10)
      .sheet(isPresented: $model.historyPresented) { EditingHistoryView(model: model) }
      .confirmationDialog(resetPurpose + " for \(model.workspaceAssets.count) photos?", isPresented: $confirmResetAll, titleVisibility: .visible) {
        Button(resetPurpose, role: .destructive) {
          switch resetPurpose {
          case "Reset Batch Settings": model.resetBatchSettingsOnly()
          case "Remove Individual Overrides": model.removeAllIndividualOverrides()
          default: model.restoreLibraryOriginalAppearance()
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(resetPurpose == "Restore Original Appearance"
          ? "Restore the original appearance and native size of every imported photo, including photos hidden by filters and editor tabs. Masks, annotations and watermarks are removed. Format, quality and metadata protection are retained. Checked export profiles still transform exported files. Undo is available. Originals are untouched."
          : resetPurpose == "Reset Batch Settings"
          ? "Return shared settings to 1600 × 1200 Fit and JPEG. Individual overrides are retained and may still change each photo. Checked export profiles remain active. Undo is available."
          : "Remove every workspace photo’s individual edits, including masks, so all photos inherit the current batch settings. This does not restore original appearance. Checked export profiles remain active. Undo is available.")
      }
      .alert("Reset selected image edits?", isPresented: $confirmReset) {
        Button("Reset Edits", role: .destructive) { model.resetAllImageEdits(model.selection) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This removes individual overrides from selected photos so they inherit batch settings again. Batch changes remain applied. Undo can restore the overrides. Originals remain unchanged."
        )
      }
  }
  var resetAllButton: some View {
    Menu("Reset Changes…", systemImage: "arrow.counterclockwise") {
      ForEach(["Restore Original Appearance", "Reset Batch Settings", "Remove Individual Overrides"], id: \.self) { purpose in
        Button(purpose + "…", role: .destructive) { resetPurpose = purpose; confirmResetAll = true }
      }
    }.disabled(model.running || model.analysing || model.workspaceAssets.isEmpty)
      .help("Choose which changes to reset. Each action supports Undo.")
  }
  var gallerySummary: some View {
    Text(model.gallerySummary + (model.mode == .browse ? " · Originals" : " · Processed results"))
      .font(.caption).foregroundStyle(.secondary)
  }
  @ViewBuilder var previewSizeControl: some View {
        #if os(iOS)
          Menu {
            PreviewSizeMenu(model: model)
          } label: {
            Label("Size", systemImage: "square.grid.2x2")
          }.comfortableHitTarget().accessibilityLabel("Gallery preview size")
        #else
          PreviewSizeSlider(model: model).frame(maxWidth: 240)
        #endif
  }
  var undoRedoControls: some View {
    HStack {
        Button {
          model.undo()
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }.disabled(!model.canUndo).help("Undo").accessibilityLabel("Undo edit")
        Button {
          model.redo()
        } label: {
          Image(systemName: "arrow.uturn.forward")
        }.disabled(!model.canRedo).help("Redo").accessibilityLabel("Redo edit")
    }
  }
  @ViewBuilder var modePicker: some View {
    if typeSize.isAccessibilitySize {
      Picker("View", selection: $model.mode) {
        ForEach(WorkspaceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.menu)
    } else {
      Picker("Workspace view", selection: $model.mode) {
        ForEach(WorkspaceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 270)
    }
  }
  var selectionControls: some View {
    HStack {
      if model.gifSelectionContext == nil && sizeClass != .compact {
        Menu {
          WorkspaceActions(model: model, ids: model.selection.isEmpty ? model.current.map { [$0.id] } ?? [] : model.orderedSelection)
        } label: { Text("Actions") }.comfortableHitTarget().accessibilityLabel("Photo actions")
      }
      Button(model.selecting ? "Done" : "Select") { model.toggleSelectionMode() }.disabled(
        model.workspaceAssets.isEmpty || model.gifSelectionContext != nil)
      Menu {
        if sizeClass == .compact && model.gifSelectionContext == nil {
          WorkspaceActions(model: model, ids: model.selection.isEmpty ? model.current.map { [$0.id] } ?? [] : model.orderedSelection)
          Divider()
        }
        if typeSize.isAccessibilitySize {
          if model.browsingLibrary {
            Button("Open in Editor") { if let asset = model.current { model.openPhoto(asset) } }
              .disabled(model.current == nil)
            Button("Privacy") { if let asset = model.current { model.openOverlayEditor(for: asset) } }
              .disabled(model.current == nil)
            Button("Batch Edit Selected (\(model.selection.count))") { model.editSelectedBatch() }
              .disabled(model.selection.isEmpty)
          }
          Menu("Preview size") { PreviewSizeMenu(model: model) }
          Divider()
        }
        if !model.browsingLibrary {
          if let photo = model.current {
            Menu("Focused Photo: " + photo.name) {
              Button("Rotate This Photo", systemImage: "rotate.right") { model.rotatePhoto(photo.id) }
              Button("Refine This Photo", systemImage: "crop") { model.openPhoto(photo, refine: true) }
            }
          }
          resetAllButton
        }
        Menu("View", systemImage: "eye") {
          if !model.browsingLibrary {
            Picker("Preview", selection: $model.mode) {
              ForEach(WorkspaceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
          }
          if let operationOnly { Toggle("Show operation photos only", isOn: operationOnly) }
          Menu("Thumbnail size") { PreviewSizeMenu(model: model) }
          Toggle("Show filenames", isOn: $showFilenames)
          Toggle("Show favourite buttons", isOn: $showFavouriteButtons)
          #if os(iOS)
          if model.mode == .frame { Toggle("Reframe thumbnails", isOn: $model.thumbnailEditing) }
          #endif
          Text(frameHint)
        }
        Button("Undo edit") { model.undo() }.disabled(!model.canUndo)
        Button("Redo edit") { model.redo() }.disabled(!model.canRedo)
        Button("Undo History…", systemImage: "clock.arrow.circlepath") { model.historyPresented = true }
        Button("Projects…") { model.projectsView = true }
        Button("Privacy Review…") { model.sensitiveReviewPresented = true }
        Button("Select visible photos") { model.selectVisiblePhotos() }
        Button("Clear selection") { model.selection = [] }
        Divider()
        Button("Reset selected edits…", role: .destructive) { confirmReset = true }.disabled(
          model.selection.isEmpty)
        Button("Reset selected framing") { model.reset(model.selection) }.disabled(
          model.selection.isEmpty)
        Button("Reset Manual Framing for All Workspace Photos") { model.resetWorkspaceManualFraming() }
      } label: {
        Image(systemName: "ellipsis.circle")
      }.comfortableHitTarget().disabled(model.gifSelectionContext != nil).accessibilityLabel(sizeClass == .compact ? "Photo actions and view options" : "View and gallery options")
    }
  }
  var frameHint: String {
    #if os(macOS)
      "Drag a photo to reframe · Option-scroll to zoom · Double-click to refine"
    #else
      model.thumbnailEditing && sizeClass == .regular
        ? "Drag or pinch the selected photo. Tap another photo to select it; scroll outside the selected frame."
        : "Tap a photo, then Refine to drag or pinch without scrolling the gallery."
    #endif
  }
}
struct PreviewSizeMenu: View {
  @Bindable var model: Workspace
  var body: some View {
    ForEach([110, 190, 300, 440], id: \.self) { size in
      Button {
        model.tileSize = Double(size)
      } label: {
        Text(size == 110 ? "Small" : size == 190 ? "Medium" : size == 300 ? "Large" : "Extra Large")
      }
    }
  }
}
struct PreviewSizeSlider: View {
  @Bindable var model: Workspace
  var body: some View {
    HStack(spacing: 6) {
      Text("Preview size").font(.caption).foregroundStyle(.secondary)
      Button {
        model.tileSize = max(80, model.tileSize - 40)
      } label: {
        Image(systemName: "minus.magnifyingglass")
      }.buttonStyle(.plain).accessibilityLabel("Smaller previews")
      Slider(value: $model.tileSize, in: 80...480) { Text("Gallery preview size") }.labelsHidden()
        .frame(minWidth: 55).help("Changes display size, not exported dimensions")
      Button {
        model.tileSize = min(480, model.tileSize + 40)
      } label: {
        Image(systemName: "plus.magnifyingglass")
      }.buttonStyle(.plain).accessibilityLabel("Larger previews")
    }
  }
}
struct ImageTile: View {
  @Bindable var model: Workspace
  @AppStorage("workspace.showFilenames") private var showFilenames = true
  @AppStorage("workspace.showFavouriteButtons") private var showFavouriteButtons = false
  let asset: SourceAsset
  var displaySize: Double? = nil
  @Environment(\.horizontalSizeClass) private var sizeClass
  var tileDimension: Double { displaySize ?? model.tileSize }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ZStack(alignment: .topTrailing) {
        FramingSurface(
          model: model, asset: asset, interactive: allowsDirectFraming,
          guides: model.mode == .frame && model.selected == asset.id,
          original: model.mode == .browse, maximum: max(240, Int(tileDimension * 2))
        )
        .frame(height: tileHeight)
        #if os(macOS)
        .overlay(MacPhotoSelectionCapture(capturesPlainClicks: model.mode == .browse || model.selecting, onSelect: nativeSelect))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8).stroke(
            model.selection.contains(asset.id) ? Color.accentColor : model.selected == asset.id ? Color.secondary.opacity(0.5) : .clear,
            lineWidth: 1))
        if model.sensitivity.flagged.contains(asset.id)
          || model.proposals[asset.id]?.needsReview == true || model.privacyCoverageNeedsReview(asset.id)
          || model.isEdited(asset.id)
          || model.selection.contains(asset.id)
        {
          HStack(spacing: 4) {
            if model.sensitivity.flagged.contains(asset.id) {
              Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                .accessibilityLabel("Flagged for privacy review")
            }
            if model.proposals[asset.id]?.needsReview == true || model.privacyCoverageNeedsReview(asset.id) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(
                "Needs review")
            }
            if model.isEdited(asset.id) {
              Image(systemName: "slider.horizontal.3").help("Edited · batch or individual changes")
            }
            if model.configuration(for: asset).crop.framing == .manual {
              Image(systemName: "hand.draw").help("Manual framing")
            } else if let proposal = model.proposals[asset.id], proposal.crop.framing != .centre {
              Image(systemName: "sparkles").help("Vision framing proposal")
            }
            if model.selection.contains(asset.id) {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
          }.font(.caption).symbolRenderingMode(.hierarchical).padding(6).background(.regularMaterial, in: Capsule()).padding(7)
        }
      }
      if showFilenames { HStack {
        Text(asset.name).font(.caption).lineLimit(1).truncationMode(.middle)
          #if os(macOS)
          .overlay(MacPhotoSelectionCapture(capturesPlainClicks: true, onSelect: nativeSelect))
          #endif
        Spacer()
        if showFavouriteButtons || model.favourites.contains(asset.id) { Button {
          model.toggleFavourite(asset.id)
        } label: {
          Image(systemName: model.favourites.contains(asset.id) ? "heart.fill" : "heart")
            .foregroundStyle(model.favourites.contains(asset.id) ? .pink : .secondary)
        }.buttonStyle(.plain).accessibilityLabel("Favourite \(asset.name)") }
      } }
    }.padding(6)
    .onAppear { model.visibility(asset.id, visible: true) }.onDisappear {
      model.visibility(asset.id, visible: false)
    }
    .contentShape(Rectangle())
    #if os(macOS)
    .onTapGesture { if model.mode != .browse && !model.selecting { model.select(asset, extending: false, range: false) } }
    .onTapGesture(count: 2) { if model.gifSelectionContext == nil { model.openPhoto(asset, refine: !model.browsingLibrary) } else { model.select(asset) } }
    #else
    .onTapGesture(count: 2) { if model.gifSelectionContext == nil { model.openPhoto(asset, refine: !model.browsingLibrary) } else { model.select(asset) } }
    .onTapGesture {
      if model.browsingLibrary && sizeClass == .compact && !model.selecting { model.openPhoto(asset) }
      else { model.select(asset) }
    }
    #endif
    .accessibilityElement(children: .contain)
    .accessibilityLabel(asset.name)
    .accessibilityValue([
      model.batchInputIDs?.contains(asset.id) == true ? "Included in this operation" : nil,
      model.selection.contains(asset.id) ? "Selected" : nil,
      model.selected == asset.id ? "Active photo" : nil
    ].compactMap { $0 }.joined(separator: ", "))
    .accessibilityAction(named: model.favourites.contains(asset.id) ? "Remove favourite" : "Add favourite") { model.toggleFavourite(asset.id) }
    .accessibilityAction(named: "Select photo") { model.select(asset) }
    .accessibilityAction(named: "Refine framing") {
      model.openPhoto(asset, refine: true)
    }
    .contextMenu {
      if model.gifSelectionContext == nil {
      WorkspaceActions(model: model, ids: model.contextIDs(for: asset.id)).disabled(model.gifSelectionContext != nil)
      Divider()
      Text("This photo: " + asset.name)
      Button("Open in Editor", systemImage: "slider.horizontal.3") { model.openPhoto(asset) }
      Divider()
      #if os(macOS)
      Button("Export This Photo…", systemImage: "square.and.arrow.down") { MacWorkspace(model: model).exportImages(retry: false, targetIDs: [asset.id]) }.disabled(model.running)
      #endif
      Button("Export & Share This Photo…", systemImage: "square.and.arrow.up") { model.exportThisPhoto(asset.id) }.disabled(model.running)
      Button("Rotate This Photo Clockwise", systemImage: "rotate.right") { model.rotatePhoto(asset.id) }
      Button("Copy Chosen Edits from This Photo…") { model.copySourceID = asset.id }
      Button("Paste Chosen Edits to This Photo") { model.pasteEdits(to: [asset.id]) }.disabled(model.copiedEdits == nil)
      if model.selection.count > 1, model.selection.contains(asset.id) {
        Button("Paste Chosen Edits to \(model.selection.count) Selected Photos") { model.pasteEdits(to: model.selection) }.disabled(model.copiedEdits == nil)
      }
      Divider()
      Button(
        model.sensitivity.flagged.contains(asset.id)
          ? "Reveal & Edit with Privacy Tool…" : "Edit with Privacy Tool…", systemImage: "eye.slash"
      ) { model.openOverlayEditor(for: asset) }
      Button("Refine Framing", systemImage: "crop") {
        model.openPhoto(asset, refine: true)
      }
      Button("Smart · Replace This Photo’s Framing", systemImage: "sparkles") {
        model.selected = asset.id
        model.autoFrame(.smart, replaceManual: true, targetIDs: [asset.id])
      }
      Button("Flag for privacy review") { model.sensitivity.mark(asset.id, forReview: true) }
      Button("Privacy Review…") {
        model.selected = asset.id
        model.sensitiveReviewPresented = true
      }
      Button("Reset This Photo’s Framing to Batch") { model.reset([asset.id]) }
      Menu("Reset This Photo’s Overrides") {
        ForEach(EditCategory.allCases, id: \.self) { category in
          Button(category.rawValue + " → Inherit Batch") { model.resetCategories([category], ids: [asset.id]) }
        }
      }
      Button(model.favourites.contains(asset.id) ? "Remove Favourite" : "Favourite") {
        model.toggleFavourite(asset.id)
      }
      }
    }
  }
  #if os(macOS)
  func nativeSelect(_ extending: Bool, _ range: Bool, _ double: Bool) {
    if double { if model.gifSelectionContext == nil { model.openPhoto(asset, refine: !model.browsingLibrary) } else { model.select(asset) } }
    else { model.select(asset, extending: extending, range: range) }
  }
  #endif
  var allowsDirectFraming: Bool {
    #if os(iOS)
      sizeClass == .regular && model.thumbnailEditing && model.selected == asset.id
        && model.mode == .frame && !model.selecting
    #else
      model.mode == .frame && !model.selecting
    #endif
  }
  var tileHeight: CGFloat {
    let c = model.configuration(for: asset)
    if model.mode == .browse { return CGFloat(tileDimension * 0.8) }
    return CGFloat(tileDimension)
      / max(0.5, min(2.5, Double(max(1, c.width)) / Double(max(1, c.height))))
  }
}
struct ImageCollection: View {
  @Bindable var model: Workspace
  @State private var operationOnly = true
  var canFilterOperation: Bool { !model.browsingLibrary && model.workflow == .batch && model.gifSelectionContext == nil }
  var displayedAssets: [SourceAsset] { model.galleryPhotos(operationOnly: operationOnly) }
  var importAction: (() -> Void)? = nil
  @FocusState private var galleryFocused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(spacing: 0) {
      if model.mode != .compare {
        if model.gifSelectionContext == nil { LibraryToolbar(model: model, operationOnly: canFilterOperation ? $operationOnly : nil).fixedSize(horizontal: false, vertical: true) }
        WorkspaceFilterControls(model: model)
        Divider()
      }
      if model.workspaceAssets.isEmpty {
        ContentUnavailableView {
          Label(model.gifSelectionContext == nil ? "Your photo workspace" : "Choose photos · " + (model.gifSelectionContext?.task.rawValue ?? "Task"), systemImage: "photo.on.rectangle.angled")
        } description: {
          Text(model.gifSelectionContext == nil ? "Add some photos to start editing, creating or converting." : "Add photos to continue this task.")
        } actions: {
          if let importAction {
            Button("Add Photos", action: importAction).buttonStyle(.borderedProminent)
              .controlSize(.large)
          }
          if model.gifSelectionContext == nil { DemoWorkspaceButton(model: model) }
        }.frame(maxHeight: .infinity)
      } else if displayedAssets.isEmpty {
        ContentUnavailableView {
          Label("No matching photos", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
          Text(
            !model.query.isEmpty
              ? "No photos match the current search and filters. Search checks filenames and locally recognised content; some photos may still be waiting for content indexing."
              : model.workspaceFilter.period != .any || model.workspaceFilter.orientation != .any || !model.workspaceFilter.format.isEmpty
                ? "No photos match the current filters. Clear filters to see all workspace photos."
                : model.library == .privacyReview
                  ? "No photos are flagged for privacy review. Use a photo’s actions menu to flag it for review."
                  : "There are no photos in this view yet.")
        } actions: {
          Button("Show All Photos") {
            operationOnly = false
            model.showAllWorkspacePhotos()
          }
        }.frame(maxHeight: .infinity)
      } else if model.mode == .compare, let asset = model.current {
        CompareWorkspace(model: model, asset: asset, photos: displayedAssets)
      } else {
        GeometryReader { geometry in
          let requested = typeSize.isAccessibilitySize ? max(230, model.tileSize) : model.tileSize
          let size = min(requested, max(80, geometry.size.width - 32))
          ScrollView {
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: CGFloat(size)), spacing: 8)], spacing: 10
            ) {
              ForEach(displayedAssets) { asset in
                ImageTile(model: model, asset: asset, displaySize: size).id(asset.id)
              }
            }.padding(10)
          }
          #if os(macOS)
          .focusable().focused($galleryFocused).focusEffectDisabled()
          .onChange(of: model.galleryFocusToken) { _, _ in galleryFocused = true }
          .simultaneousGesture(TapGesture().onEnded { galleryFocused = true })
          .onKeyPress(.leftArrow) { model.navigate(-1); return .handled }
          .onKeyPress(.rightArrow) { model.navigate(1); return .handled }
          .onKeyPress(characters: CharacterSet(charactersIn: "a")) { key in
            if key.modifiers.contains(.command) { model.selectVisiblePhotos(); return .handled }
            return .ignored
          }
          #endif
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
extension Workspace {
  /// Comparison changes gallery focus only, never captured inputs or selection.
  func focusComparisonPhoto(_ id: UUID, in photos: [SourceAsset]) {
    guard photos.contains(where: { $0.id == id }) else { return }
    selected = id
  }
  func returnFromComparison() { mode = .browse }
}

struct CompareWorkspace: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  let photos: [SourceAsset]
  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Button("Back to Gallery", systemImage: "chevron.left") { model.returnFromComparison() }
          .comfortableHitTarget()
        Spacer()
        Text(asset.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      GeometryReader { geometry in
        let vertical = geometry.size.width < 560
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
          comparisonPanel("Before", original: true)
          comparisonPanel("After", original: false)
        }
      }
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          LazyHStack(spacing: 8) {
            ForEach(photos) { photo in
              Button { model.focusComparisonPhoto(photo.id, in: photos) } label: {
                VStack(spacing: 4) {
                  FramingSurface(model: model, asset: photo, interactive: false, original: true, maximum: 160)
                    .frame(width: 76, height: 56).clipped()
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(photo.id == asset.id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: photo.id == asset.id ? 2 : 1))
                  Text(photo.name).font(.caption2).lineLimit(1).frame(width: 76)
                }
              }.buttonStyle(.plain).id(photo.id)
                .accessibilityLabel("Compare " + photo.name)
                .accessibilityAddTraits(photo.id == asset.id ? [.isSelected] : [])
            }
          }.padding(2)
        }.frame(height: 82)
          .onAppear { proxy.scrollTo(asset.id, anchor: .center) }
          .onChange(of: asset.id) { _, id in proxy.scrollTo(id, anchor: .center) }
      }
    }.padding(12)
  }
  func comparisonPanel(_ title: String, original: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
      FramingSurface(model: model, asset: asset, interactive: false, original: original)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.primary.opacity(0.03))
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
/// Nonblocking routine completion feedback. Dismissal is local presentation state;
/// errors, progress and export results remain owned by their dedicated controls.
struct StatusNotice: View {
  @Bindable var model: Workspace
  var excludingSummary: String? = nil
  @State private var dismissedStatus: String?
  var body: some View {
    Group {
      if model.status != "Your photos. Your way." && model.status != excludingSummary
          && (dismissedStatus != model.status || !model.canDismissRoutineWorkspaceStatus) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(model.status).font(.caption).foregroundStyle(.secondary)
          if model.canDismissRoutineWorkspaceStatus {
            Spacer(minLength: 0)
            Button { dismissedStatus = model.status } label: { Image(systemName: "xmark") }
              .buttonStyle(.borderless).comfortableHitTarget()
              .accessibilityLabel("Dismiss completed activity message")
              .help("Dismiss this message")
          }
        }
      }
    }
    .onChange(of: model.status) { _, _ in dismissedStatus = nil }
    .onChange(of: model.isImporting) { _, importing in if importing { dismissedStatus = nil } }
    .onChange(of: model.sourceSessionID) { _, _ in dismissedStatus = nil }
  }
}

struct ExportStatus: View {
  @Bindable var model: Workspace
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let output = model.latestExport, !model.running { ExportCompletionView(model: model, output: output) }
      StatusNotice(model: model, excludingSummary: model.latestExport?.summary)
      if !model.removalUndoSourceIDs.isEmpty {
        Button("Undo Remove", systemImage: "arrow.uturn.backward") { model.undoWorkspaceRemoval() }
          .disabled(!model.canUndoWorkspaceRemoval)
          .accessibilityHint("Restore removed photos to the workspace without changing their edits")
      }
      #if os(iOS)
        if model.isImporting { ImportProgressView(model: model) }
      #endif
      if model.running {
        ProgressView(value: Double(model.completed), total: Double(max(1, model.total)))
        Button("Cancel export") {
          model.task?.cancel()
          model.collageTask?.cancel()
        }
      }
      if model.analysing {
        ProgressView(
          value: Double(model.analysisCompleted), total: Double(max(1, model.analysisTotal)))
        HStack {
          Text("Framing \(model.analysisCompleted) / \(model.analysisTotal)").font(.caption)
          Button("Cancel") { model.analysisTask?.cancel() }
        }
      }
      if !model.issues.isEmpty {
        DisclosureGroup("Issues (\(model.issues.count))") {
          ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
            Text(issue).font(.caption).foregroundStyle(.orange)
          }
          Button("Clear issues") { model.issues = [] }
        }
      }
      if !model.collageOutputs.isEmpty {
        Button("Review collage exports (\(model.collageOutputs.count))") {
          model.beginSharing(model.collageOutputs)
        }
      }
      if !model.results.isEmpty {
        DisclosureGroup("Export results (\(model.results.count))") {
          ForEach(model.results) { result in
            if result.output != nil {
              Button("Review & share \(result.source.name)") { if let url = result.output { model.beginSharing([url]) } }
            } else {
              Text("\(result.source.name): \(result.error ?? "Export interrupted")").font(.caption)
                .foregroundStyle(.orange)
            }
          }
        }
      }
    }
  }
}

extension View {
  @ViewBuilder func compactNavigationTitle() -> some View {
    #if os(iOS)
      self.navigationBarTitleDisplayMode(.inline)
    #else
      self
    #endif
  }
}

struct WorkspaceCurtain: ViewModifier {
  @Bindable var model: Workspace
  func body(content: Content) -> some View {
    content.overlay {
      if model.concealed {
        VStack {
          Button("Reveal workspace", systemImage: "eye") { model.concealed = false }.buttonStyle(
            .borderedProminent
          ).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        .accessibilityLabel("Workspace concealed")
      }
    }
  }
}
extension View {
  func privacyCurtain(model: Workspace) -> some View {
    modifier(WorkspaceCurtain(model: model)).disabled(model.clearingWorkspace)
  }
}

/// Adds touch target space without enlarging desktop controls.
extension View {
  @ViewBuilder func comfortableHitTarget() -> some View {
    #if os(iOS)
      self.frame(minWidth: 44, minHeight: 44)
    #else
      self
    #endif
  }
}
