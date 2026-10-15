import FramepebbleCore
import SwiftUI

struct LibrarySidebar: View {
  @Bindable var model: Workspace
  var openAutomations: (() -> Void)? = nil
  var body: some View {
    List {
      Section {
        HStack(spacing: 10) {
          PebbleMark()
          VStack(alignment: .leading) {
            Text("Ameluma Photo").font(.headline)
            Text("Your photos. Your way.").font(.caption2).foregroundStyle(.secondary)
          }
        }.padding(.vertical, 8)
      }
      Section("Photo Library") {
        Button("Projects & Clear Photos…", systemImage: "folder") { model.projectsView = true }
        ForEach(LibraryScope.allCases, id: \.self) { category in
          Button {
            model.showLibrary(category, clearSearch: true)
          } label: {
            HStack {
              Label(category.rawValue, systemImage: symbol(category))
              Spacer()
              Text("\(count(category))").font(.caption).foregroundStyle(.secondary)
            }.foregroundStyle(model.browsingLibrary && model.library == category ? Color.accentColor : Color.primary)
          }
        }
      }
      Section("Workspaces") {
        ForEach(StudioWorkflow.allCases, id: \.self) { workflow in
          #if os(iOS)
          if workflow != .automations { workflowButton(workflow) }
          #else
          workflowButton(workflow)
          #endif
        }
      }
      Section("Smart Search") {
        TextField("Recognised content", text: $model.query)
          .onChange(of: model.query) { _, _ in model.showLibrary() }
        if !model.query.isEmpty {
          Button("Clear search", systemImage: "xmark.circle") { model.query = "" }
        }
        ForEach(model.index.suggestedCategories, id: \.0) { name, count in
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
        Text("\(model.index.records.count) / \(model.assets.count) indexed locally").font(.caption2)
          .foregroundStyle(.secondary)
      }
      Section {
        Button("Help & Privacy", systemImage: "questionmark.circle") { model.helpPresented = true }
      }
      Section {
        Button("Check photo privacy…", systemImage: "checkmark.shield") {
          model.sensitiveReviewPresented = true
        }
      }
      Section("Presets") {
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
  }
  func workflowButton(_ workflow: StudioWorkflow) -> some View {
    Button { model.switchWorkflow(workflow) } label: {
      Label(workflow.rawValue, systemImage: workflow.symbol).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .foregroundStyle(!model.browsingLibrary && model.workflow == workflow ? Color.accentColor : Color.primary)
    }
  }
  func symbol(_ category: LibraryScope) -> String {
    switch category {
    case .all: "photo.on.rectangle.angled"
    case .favourites: "heart"
    case .edited: "slider.horizontal.3"
    case .review: "exclamationmark.bubble"
    case .privacyReview: "checkmark.shield"
    }
  }
  func count(_ category: LibraryScope) -> Int {
    switch category {
    case .all: model.assets.count
    case .favourites: model.favourites.count
    case .edited: model.assets.filter { model.isEdited($0.id) }.count
    case .review: model.proposals.values.filter(\.needsReview).count
    case .privacyReview: model.sensitivity.flagged.count
    }
  }
}
struct LibraryToolbar: View {
  @Bindable var model: Workspace
  @State private var confirmReset = false
  @State private var confirmResetAll = false
  @State private var resetPurpose = "Restore Original Appearance"
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  var galleryInstruction: String {
    #if os(macOS)
    "Double-click a photo to edit. Right-click for privacy tools."
    #else
    sizeClass == .compact
      ? (typeSize.isAccessibilitySize ? "Tap to edit. Select for a batch." : "Tap a photo to edit. Long-press for privacy tools, or choose Select to build a batch.")
      : "Double-tap a photo to edit. Long-press for privacy tools."
    #endif
  }
  @ViewBuilder var galleryHeading: some View {
    if model.browsingLibrary {
      Text(model.library.rawValue).font(.title2.weight(.semibold))
    } else { modePicker }
  }
  var body: some View {
    VStack(spacing: 10) {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          galleryHeading
          HStack { Spacer(); selectionControls }
        }
      } else {
      ViewThatFits(in: .horizontal) {
        HStack {
          galleryHeading
          Spacer()
          selectionControls
        }
        VStack(alignment: .leading, spacing: 10) {
          galleryHeading
          HStack {
            Spacer()
            selectionControls
          }
        }
      }
      }
      if !model.browsingLibrary && model.workflow == .batch {
        VStack(alignment: .leading, spacing: 4) {
          Label(model.editScopeHeading, systemImage: "person.2").font(.headline)
          if model.scope == .all && !model.selection.isEmpty {
            Text("All imported photos are targeted, including photos outside this filter.").font(.caption).foregroundStyle(.secondary)
            Button("Edit Only Selected Photos (\(model.selection.count))") { model.scope = .selected }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      if typeSize.isAccessibilitySize {
        gallerySummary.frame(maxWidth: .infinity, alignment: .leading)
      } else {
        HStack {
          gallerySummary
          Spacer(minLength: 8)
          previewSizeControl
          undoRedoControls
        }
      }
      if !model.browsingLibrary && model.workflow == .batch {
        ViewThatFits(in: .horizontal) {
          HStack {
            Button("Undo History…", systemImage: "clock.arrow.circlepath") { model.historyPresented = true }
            Spacer()
            resetAllButton
          }
          VStack(alignment: .leading, spacing: 8) {
            Button("Undo History…", systemImage: "clock.arrow.circlepath") { model.historyPresented = true }
            resetAllButton
          }
        }.disabled(model.running || model.analysing)
      }
      if model.browsingLibrary && !typeSize.isAccessibilitySize {
        ViewThatFits(in: .horizontal) {
          HStack {
            Button("Edit Photo", systemImage: "slider.horizontal.3") {
              if let asset = model.current { model.openPhoto(asset) }
            }.disabled(model.current == nil)
            Button("Privacy", systemImage: "eye.slash") {
              if let asset = model.current { model.openOverlayEditor(for: asset) }
            }.disabled(model.current == nil)
            Spacer()
            Button("Batch Edit Selected (\(model.selection.count))") { model.editSelectedBatch() }
              .disabled(model.selection.isEmpty)
          }
          Menu("Photo actions") {
            Button("Edit Photo") { if let asset = model.current { model.openPhoto(asset) } }
              .disabled(model.current == nil)
            Button("Privacy") { if let asset = model.current { model.openOverlayEditor(for: asset) } }
              .disabled(model.current == nil)
            Button("Batch Edit Selected (\(model.selection.count))") { model.editSelectedBatch() }
              .disabled(model.selection.isEmpty)
          }
        }
        Text(galleryInstruction)
          .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
      }
      #if os(iOS)
        if sizeClass == .regular && model.mode == .frame && !model.selecting {
          Button(model.thumbnailEditing ? "Done Reframing" : "Reframe thumbnails") {
            model.thumbnailEditing.toggle()
          }
        }
      #endif
      if model.mode == .frame && !model.selecting {
        Text(frameHint).font(.caption).foregroundStyle(.secondary).frame(
          maxWidth: .infinity, alignment: .leading)
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
      .confirmationDialog(resetPurpose + " for \(model.assets.count) photos?", isPresented: $confirmResetAll, titleVisibility: .visible) {
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
          ? "Restore the original appearance and native size of every imported photo, including hidden photos and editor tabs. Masks, annotations and watermarks are removed. Format, quality and metadata protection are retained. Checked export profiles still transform exported files. Undo is available. Originals are untouched."
          : resetPurpose == "Reset Batch Settings"
          ? "Return shared settings to 1600 × 1200 Fit and JPEG. Individual overrides are retained and may still change each photo. Checked export profiles remain active. Undo is available."
          : "Remove every photo’s individual edits, including masks, so all photos inherit the current batch settings. This does not restore original appearance. Checked export profiles remain active. Undo is available.")
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
    }.disabled(model.running || model.analysing || model.assets.isEmpty)
      .help("Choose which changes to reset. Each action supports Undo.")
  }
  var gallerySummary: some View {
    Text((model.browsingLibrary ? "" : model.editScopeHeading + " · ") + model.gallerySummary + (model.mode == .browse ? " · Originals" : " · Processed results"))
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
      Button(model.selecting ? "Done" : "Select") { model.toggleSelectionMode() }.disabled(
        model.assets.isEmpty)
      Menu {
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
          Button("Undo edit") { model.undo() }.disabled(!model.canUndo)
          Button("Redo edit") { model.redo() }.disabled(!model.canRedo)
          Divider()
        }
        Button("Undo History…", systemImage: "clock.arrow.circlepath") { model.historyPresented = true }
        Button("Projects & Clear Photos…") { model.projectsView = true }
        Button("Privacy Review…") { model.sensitiveReviewPresented = true }
        Button("Select visible photos") { model.selectVisiblePhotos() }
        Button("Clear selection") { model.selection = [] }
        Divider()
        Button("Reset selected edits…", role: .destructive) { confirmReset = true }.disabled(
          model.selection.isEmpty)
        Button("Reset selected framing") { model.reset(model.selection) }.disabled(
          model.selection.isEmpty)
        Button("Reset all manual framing") {
          model.reset(Set(model.edits.overrides.filter { $0.value.crop.framing == .manual }.keys))
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }.comfortableHitTarget().accessibilityLabel("Gallery actions")
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
  let asset: SourceAsset
  var displaySize: Double? = nil
  @Environment(\.horizontalSizeClass) private var sizeClass
  var tileDimension: Double { displaySize ?? model.tileSize }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
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
            model.selected == asset.id ? Color.accentColor : model.selection.contains(asset.id) ? Color.accentColor.opacity(0.45) : .clear,
            lineWidth: model.selected == asset.id ? 3 : 1.5))
        if model.sensitivity.flagged.contains(asset.id)
          || model.proposals[asset.id]?.needsReview == true
          || model.isEdited(asset.id)
          || (model.selection.contains(asset.id) && model.selecting)
        {
          HStack(spacing: 4) {
            if model.sensitivity.flagged.contains(asset.id) {
              Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                .accessibilityLabel("Flagged for privacy review")
            }
            if model.proposals[asset.id]?.needsReview == true {
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
            if model.selected == asset.id { Image(systemName: "circle.inset.filled").help("Active photo") }
            if model.selection.contains(asset.id), model.selecting {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
          }.font(.caption).padding(6).background(.regularMaterial, in: Capsule()).padding(7)
        }
      }
      HStack {
        Text(asset.name).font(.caption).lineLimit(1)
          #if os(macOS)
          .overlay(MacPhotoSelectionCapture(capturesPlainClicks: true, onSelect: nativeSelect))
          #endif
        Spacer()
        Button {
          model.toggleFavourite(asset.id)
        } label: {
          Image(systemName: model.favourites.contains(asset.id) ? "heart.fill" : "heart")
            .foregroundStyle(model.favourites.contains(asset.id) ? .pink : .secondary)
        }.buttonStyle(.plain).accessibilityLabel("Favourite \(asset.name)")
      }
    }.padding(6).background(
      model.selected == asset.id ? Color.accentColor.opacity(0.06) : Color.clear,
      in: RoundedRectangle(cornerRadius: 12)
    )
    .onAppear { model.visibility(asset.id, visible: true) }.onDisappear {
      model.visibility(asset.id, visible: false)
    }
    .contentShape(Rectangle())
    #if os(macOS)
    .onTapGesture { if model.mode != .browse && !model.selecting { model.select(asset, extending: false, range: false) } }
    .onTapGesture(count: 2) { model.openPhoto(asset, refine: !model.browsingLibrary) }
    #else
    .onTapGesture(count: 2) { model.openPhoto(asset, refine: !model.browsingLibrary) }
    .onTapGesture {
      if model.browsingLibrary && sizeClass == .compact && !model.selecting { model.openPhoto(asset) }
      else { model.select(asset) }
    }
    #endif
    .accessibilityElement(children: .contain)
    .accessibilityLabel(asset.name)
    .accessibilityAction(named: "Select photo") { model.select(asset) }
    .accessibilityAction(named: "Refine framing") {
      model.openPhoto(asset, refine: true)
    }
    .contextMenu {
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
  #if os(macOS)
  func nativeSelect(_ extending: Bool, _ range: Bool, _ double: Bool) {
    if double { model.openPhoto(asset, refine: !model.browsingLibrary) }
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
  var importAction: (() -> Void)? = nil
  @FocusState private var galleryFocused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(spacing: 0) {
      LibraryToolbar(model: model).fixedSize(horizontal: false, vertical: true)
      Divider()
      if model.assets.isEmpty {
        ContentUnavailableView {
          Label("Add your photos", systemImage: "photo.on.rectangle.angled")
        } description: {
          Text("Import photos or drop files and folders here. Your originals stay unchanged.")
        } actions: {
          if let importAction {
            Button("Import Photos…", action: importAction).buttonStyle(.borderedProminent)
              .controlSize(.large)
          }
        }.frame(maxHeight: .infinity)
      } else if model.filtered.isEmpty {
        ContentUnavailableView {
          Label("No matching photos", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
          Text(
            model.library == .privacyReview
              ? "No photos are flagged. Show All Photos, then right-click or long-press a photo to flag it for privacy review or edit Privacy. Automatic checks are available only when Apple’s capability and system settings allow them."
              : model.query.isEmpty
                ? "There are no photos in this category yet."
                : "Search uses recognised labels. Some photos may still be waiting for indexing.")
        } actions: {
          Button("Show All Photos") {
            model.library = .all
            model.query = ""
          }
        }.frame(maxHeight: .infinity)
      } else if model.mode == .compare, let asset = model.current {
        CompareWorkspace(model: model, asset: asset)
      } else {
        GeometryReader { geometry in
          let requested = typeSize.isAccessibilitySize ? max(230, model.tileSize) : model.tileSize
          let size = min(requested, max(80, geometry.size.width - 32))
          ScrollView {
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: CGFloat(size)), spacing: 12)], spacing: 16
            ) {
              ForEach(model.filtered) { asset in
                ImageTile(model: model, asset: asset, displaySize: size).id(asset.id)
              }
            }.padding(16)
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
struct CompareWorkspace: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  @State private var reveal = 0.5
  var body: some View {
    VStack {
      GeometryReader { g in
        ZStack {
          FramingSurface(model: model, asset: asset, interactive: false)
          FramingSurface(model: model, asset: asset, interactive: false, original: true).mask(
            alignment: .leading
          ) { Rectangle().frame(width: g.size.width * reveal) }
          Rectangle().fill(.white).frame(width: 1).position(
            x: g.size.width * reveal, y: g.size.height / 2)
          HStack {
            Text("Before")
            Spacer()
            Text("After")
          }.font(.caption.weight(.medium)).padding(10).background(.regularMaterial).frame(
            maxHeight: .infinity, alignment: .top)
        }
      }
      Slider(value: $reveal, in: 0...1) { Text("Comparison position") }
      HStack {
        Button("Previous") { model.navigate(-1) }
        Spacer()
        Text(asset.name).font(.caption)
        Spacer()
        Button("Next") { model.navigate(1) }
      }
    }.padding()
  }
}
struct ExportStatus: View {
  @Bindable var model: Workspace
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.status).font(.caption).foregroundStyle(.secondary)
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
