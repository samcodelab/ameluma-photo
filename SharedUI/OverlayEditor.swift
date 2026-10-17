import FramepebbleCore
import SwiftUI

/// Discrete display-detail levels keep zoom requests bounded without changing edit geometry.
struct OverlayPreviewRequest: Equatable {
  var source: SourceAsset?
  var configuration: ProcessingConfiguration?
  var maximum: Int
  var retry: Int
  /// Compare only this session's retouch, never bypass current protective overlays.
  static func beforeRetouch(current: ProcessingConfiguration, original: ProcessingConfiguration) -> ProcessingConfiguration {
    var result = current; result.retouchStrokes = original.retouchStrokes
    return result
  }
  static func maximum(zoom: Double, retouch: Bool) -> Int {
    guard retouch, zoom.isFinite else { return 1000 }
    return zoom >= 2 ? 3200 : zoom > 1 ? 2000 : 1000
  }
}

enum OverlayCanvasInteraction { case edit, pan }

/// Direct drawing and numeric alternatives share the persisted final-output overlay models.
struct OverlayEditor: View {
  @Bindable var model: Workspace
  @State private var masking = true
  @State private var retouch = false
  @State private var retouchMode: RetouchMode = .heal
  @State private var brushDiameter = 0.03
  @State private var brushHardness = 0.5
  @State private var brushOpacity = 1.0
  @State private var samplingSource = false
  @State private var optionSampling = false
  @State private var retouchSource: NormalizedPoint?
  @State private var destinationAnchor: NormalizedPoint?
  @State private var alignedSource = true
  @State private var brushMessage: String?
  @State private var preparingStroke = false
  @State private var pendingStrokeTask: Task<Void, Never>?
  @Environment(\.scenePhase) private var scenePhase
  @State private var shape: OverlayShape = .freehand
  @State private var kind: AnnotationKind = .text
  @State private var effect: MaskEffect = .pixelate
  @State private var drawing: [NormalizedPoint] = []
  @State private var image: CGImage?
  @State private var selected: UUID?
  @State private var moveStart: NormalizedPoint?
  var embedded = false
  var session: OverlayEditingSession? {
    get { model.overlaySession }
    nonmutating set { model.overlaySession = newValue }
  }
  @State private var resizeStart: OverlayBounds?
  @State private var rotationStart: OverlayBounds?
  #if os(iOS)
  @State private var showInspector = false
  #else
  @State private var showInspector = true
  #endif
  @State private var compactOptions = false
  @State private var pendingTool: PhotoTool?
  @State private var editorWidth: CGFloat = 0
  @State private var editorHeight: CGFloat = 0
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var keepProportions = false
  @State private var canvasZoom: Double = 1
  @State private var canvasInteraction: OverlayCanvasInteraction = .edit
  @State private var comparingRetouch = false
  @State private var pinchStart: Double?
  @FocusState private var canvasFocused: Bool
  @State private var asset: SourceAsset?
  @State private var addingArea = true
  @State private var previewError: String?
  @State private var previewRetry = 0
  @State private var previewSuspended = false
  @State private var samplingImage: CGImage?
  @State private var samplingConfiguration: ProcessingConfiguration?
  @State private var samplingAsset: SourceAsset?
  @State private var renderedRequest: OverlayPreviewRequest?
  var previewRequest: OverlayPreviewRequest {
    OverlayPreviewRequest(source: !previewSuspended ? (asset.flatMap { original in model.assets.first { $0.id == original.id } } ?? asset) : nil,
      configuration: session.map { comparingRetouch && retouch ? OverlayPreviewRequest.beforeRetouch(current: $0.current, original: $0.original) : $0.current }, maximum: OverlayPreviewRequest.maximum(zoom: canvasZoom, retouch: retouch), retry: previewRetry)
  }
  @State private var renderedConfiguration: ProcessingConfiguration?
  @Environment(\.dismiss) private var dismiss
  var config: Binding<ProcessingConfiguration> {
    Binding(
      get: { session?.current ?? ProcessingConfiguration() },
      set: { session?.update($0) })
  }
  var draftToolName: String { retouch ? "Retouch" : masking ? "Privacy" : "Annotate" }
  var draftStatus: String { draftToolName + ((session?.hasChanges ?? false) ? " · Unapplied" : " · Draft") }
  var canApply: Bool {
    !comparingRetouch && !preparingStroke && session != nil && image != nil && previewError == nil && renderedConfiguration == session?.current && renderedRequest?.source == previewRequest.source && !previewSuspended
  }
  var effectChoice: Binding<MaskEffect> {
    Binding(
      get: {
        (addingArea ? nil : selected).flatMap { id in
          config.wrappedValue.masks.first { $0.id == id }?.effect
        } ?? effect
      },
      set: { value in
        effect = value
        if let selected, !addingArea,
          config.wrappedValue.masks.contains(where: { $0.id == selected })
        {
          var mask = maskBinding(selected).wrappedValue
          mask.effect = value
          maskBinding(selected).wrappedValue = mask
        }
      })
  }
  var shapeChoice: Binding<OverlayShape> {
    Binding(
      get: {
        (addingArea ? nil : selected).flatMap { id in
          config.wrappedValue.masks.first { $0.id == id }?.shape
        } ?? shape
      },
      set: { value in
        shape = value
        if let selected, !addingArea,
          config.wrappedValue.masks.contains(where: { $0.id == selected })
        {
          var mask = maskBinding(selected).wrappedValue
          mask.shape = value
          if value == .freehand && mask.points.count < 3 {
            mask.points = [
              NormalizedPoint(0, 0), NormalizedPoint(1, 0), NormalizedPoint(1, 1),
              NormalizedPoint(0, 1),
            ]
          }
          maskBinding(selected).wrappedValue = mask
        }
      })
  }
  var body: some View {
    NavigationStack {
      Group {
        if embedded {
          GeometryReader { geometry in
            HStack(spacing: 0) {
              VStack(spacing: 8) {
                canvasWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                  .overlay {
                    if usesSideInspector(geometry.size.width) && !showInspector && model.photoToolOptionsVisible {
                      FloatingToolOptions(title: draftToolName, toolIndex: retouch ? 4 : masking ? 6 : 5, pin: { showInspector = true }) {
                        contextualOptions
                      }
                    }
                  }
                if !usesSideInspector(geometry.size.width) {
                  ToolOptionsSurface { compactContextualOptions }
                    .frame(maxWidth: 660).frame(maxWidth: .infinity, alignment: .center).padding(.horizontal, 12).padding(.bottom, 8)
                }
                #if os(iOS)
                if !tabletRail {
                  PhotoEditorTools(model: model, selectedTool: retouch ? .retouch : (masking ? .privacy : .annotate), onSelect: selectTool)
                    .disabled(preparingStroke).padding(.horizontal, 8).background(.bar)
                }
                #endif
              }
              if showInspector && usesSideInspector(geometry.size.width) {
                Divider()
                VStack(spacing: 0) {
                  HStack { Text(retouch ? "Retouch" : (masking ? "Privacy" : "Annotate")).font(.headline); Spacer(); Button { showInspector = false } label: { Image(systemName: "sidebar.right") }.accessibilityLabel("Hide tool settings") }.padding(12)
                  Divider()
                  inspectorContent
                }.frame(width: EditorPanelLayout.inspectorWidth).editorInspectorSurface()
              }
              #if os(macOS)
              Divider()
              PhotoEditorTools(model: model, selectedTool: retouch ? .retouch : (masking ? .privacy : .annotate), onSelect: selectTool, vertical: true)
                .disabled(preparingStroke).frame(width: 48).padding(.vertical, 8).background(.bar)
              #else
              if tabletRail {
                Divider()
                PhotoEditorTools(model: model, selectedTool: retouch ? .retouch : (masking ? .privacy : .annotate), onSelect: selectTool, vertical: true).disabled(preparingStroke)
                  .frame(width: 56).padding(.vertical, 8).background(.bar)
              }
              #endif
            }
            .onAppear { editorWidth = geometry.size.width; editorHeight = geometry.size.height }
            .onChange(of: geometry.size) { _, size in editorWidth = size.width; editorHeight = size.height }
          }
        } else {
          HStack(spacing: 0) {
            VStack(spacing: 0) {
              canvasWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
              compactContextualOptions.padding(.horizontal, 8)
              if verticalSizeClass != .compact {
                PhotoEditorTools(model: model, selectedTool: retouch ? .retouch : (masking ? .privacy : .annotate), onSelect: selectTool)
                  .disabled(preparingStroke).padding(.horizontal, 8).background(.bar)
              }
            }
            if verticalSizeClass == .compact {
              PhotoEditorTools(model: model, selectedTool: retouch ? .retouch : (masking ? .privacy : .annotate), onSelect: selectTool, vertical: true)
                .disabled(preparingStroke).frame(width: 56).background(.bar)
            }
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle((model.isDemoWorkspace ? "Demo · " : "") + (asset?.name ?? "Editor")).compactNavigationTitle()
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #endif
        #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          HStack {
            Button("Cancel") { cancel() }.fixedSize(horizontal: true, vertical: false).keyboardShortcut(.cancelAction)
            if !typeSize.isAccessibilitySize { historyControls }
            if (embedded && editorWidth >= 700 || verticalSizeClass == .compact) && !typeSize.isAccessibilitySize {
              Text(asset?.name ?? "Photo").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(draftStatus).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            if embedded && !typeSize.isAccessibilitySize && retouch { Text("\(config.wrappedValue.retouchStrokes.count) \(config.wrappedValue.retouchStrokes.count == 1 ? "stroke" : "strokes")").font(.caption).foregroundStyle(.secondary) }
            else if embedded && !typeSize.isAccessibilitySize { Text(
              "\(config.wrappedValue.masks.count + config.wrappedValue.annotations.count) \(config.wrappedValue.masks.count + config.wrappedValue.annotations.count == 1 ? "editable object" : "editable objects")"
            ).font(.caption).foregroundStyle(.secondary) }
            Button("Apply") { apply() }.fixedSize(horizontal: true, vertical: false).buttonStyle(.borderedProminent).keyboardShortcut(
              .defaultAction
            ).disabled(
              !canApply)
          }.padding(12).background(.bar)
        }
        #endif
        #if os(iOS)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
          ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
              Text(asset?.name ?? "Editor").font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
              Text(draftStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: 240).accessibilityElement(children: .combine)
          }
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button { session?.undo(); reconcileSelection() } label: { Image(systemName: "arrow.uturn.backward") }
              .disabled(!(session?.canUndo ?? false)).accessibilityLabel("Undo draft edit")
            Button { session?.redo(); reconcileSelection() } label: { Image(systemName: "arrow.uturn.forward") }
              .disabled(!(session?.canRedo ?? false)).accessibilityLabel("Redo draft edit")
            Button("Apply") { apply() }.fontWeight(.semibold).disabled(!canApply)
          }
        }
        #endif
        .onAppear {
          model.photoToolOptionsVisible = true
          guard
            let source = session.flatMap({ draft in model.assets.first { $0.id == draft.sourceID } }
            ) ?? model.current
          else { return }
          asset = source
          masking = model.overlayStartsWithMasks
          retouch = model.overlayRetouch
          if session == nil {
            session = OverlayEditingSession(
              sourceID: source.id, configuration: model.configuration(for: source))
          }
          selected = masking ? session?.current.masks.first?.id : session?.current.annotations.first?.id
          addingArea = selected == nil
        }
        .task(id: previewRequest) {
          let request = previewRequest
          guard let source = request.source, let configuration = request.configuration else { return }
          if renderedRequest?.source != source { image = nil; renderedConfiguration = nil; renderedRequest = nil }
          previewError = nil
          do {
            try await Task.sleep(for: .milliseconds(80))
            // Keep automatic sample analysis at its established resolution. Display
            // magnification must not silently choose a different persisted sample.
            let canonical: CGImage
            if samplingAsset == source, samplingConfiguration == configuration, let samplingImage {
              canonical = samplingImage
            } else {
              canonical = try await model.processor.render(source.url, configuration: configuration, previewMaximum: 1000)
              try Task.checkCancellation()
              guard previewRequest == request else { return }
              samplingImage = canonical; samplingAsset = source; samplingConfiguration = configuration
            }
            let rendered = request.maximum == 1000 ? canonical : try await model.processor.render(
              source.url, configuration: configuration, previewMaximum: request.maximum, decodeMaximum: request.maximum)
            try Task.checkCancellation()
            guard previewRequest == request else { return }
            image = rendered
            renderedConfiguration = configuration
            renderedRequest = request
            previewError = nil
          } catch is CancellationError {} catch {
            guard previewRequest == request else { return }
            image = nil; renderedRequest = nil
            previewError = error.localizedDescription
          }
        }
        .onChange(of: comparingRetouch) { _, _ in drawing = [] }
        .onChange(of: model.overlayRetouch) { _, value in comparingRetouch = false; retouch = value; drawing = []; brushMessage = nil }
        .onChange(of: model.overlayStartsWithMasks) { _, value in masking = value }
        .onChange(of: masking) { _, value in model.overlayStartsWithMasks = value }
        .onChange(of: session?.current) { _, _ in
          if let selected, !config.wrappedValue.masks.contains(where: { $0.id == selected }),
            !config.wrappedValue.annotations.contains(where: { $0.id == selected })
          {
            self.selected = nil
          }
        }
        .onChange(of: masking) { _, hiding in
          let matches = hiding
            ? config.wrappedValue.masks.contains { $0.id == selected }
            : config.wrappedValue.annotations.contains { $0.id == selected }
          if !matches {
            selected = hiding ? config.wrappedValue.masks.first?.id : config.wrappedValue.annotations.first?.id
          }
          drawing = []
          addingArea = selected == nil
        }
        .onDisappear { pendingStrokeTask?.cancel(); image = nil; samplingImage = nil; samplingAsset = nil; samplingConfiguration = nil; renderedRequest = nil }
        .onChange(of: scenePhase) { _, phase in
          // Hosted native windows may have no active SwiftUI Scene. Suspend only
          // on an observed background transition, not the initial environment value.
          if phase == .active { previewSuspended = false }
          if phase == .background { previewSuspended = true; comparingRetouch = false }
          if phase == .background { pendingStrokeTask?.cancel(); drawing = []; image = nil; samplingImage = nil; samplingAsset = nil; samplingConfiguration = nil; renderedRequest = nil; renderedConfiguration = nil }
        }
        .interactiveDismissDisabled()
        #if os(macOS)
          .onExitCommand { cancel() }
          .onDeleteCommand { if canvasFocused && !addingArea && !retouch { deleteSelected() } }
        #endif
        }.sheet(isPresented: Binding(get: { compactOptions && !embedded }, set: { compactOptions = $0 })) {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if retouch { retouchControls; Divider(); retouchStrokeList }
            else { toolOptions; areaInspector; Divider(); objectList }
          }.padding(16).frame(maxWidth: .infinity)
        }.navigationTitle(retouch ? "Retouch Brush" : (masking ? "Privacy Options" : "Annotation Options")).compactNavigationTitle()
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { compactOptions = false } } }
      }.presentationDetents([.medium, .large])
    }.onChange(of: samplingSource) { _, sampling in
      if sampling && !embedded { compactOptions = false }
    }.confirmationDialog("Apply tool edits before switching?", isPresented: Binding(
      get: { pendingTool != nil }, set: { if !$0 { pendingTool = nil } }
    ), titleVisibility: .visible) {
      if let pendingTool {
        Button("Apply & Switch to " + pendingTool.rawValue) { finishToolSwitch(pendingTool, resolution: .apply) }
          .disabled(!canApply)
        Button("Discard Tool Edits & Switch", role: .destructive) { finishToolSwitch(pendingTool, resolution: .discard) }
      }
      Button("Keep Editing", role: .cancel) { pendingTool = nil }
    }.overlayEditorSize(embedded: embedded).overlay {
      if let asset { SensitivePreviewCover(model: model, ids: [asset.id]) }
    }
  }
  @ViewBuilder var historyControls: some View {
            Button {
              session?.undo()
              reconcileSelection()
            } label: {
              Image(systemName: "arrow.uturn.backward")
            }.disabled(!(session?.canUndo ?? false)).keyboardShortcut("z").accessibilityLabel(
              retouch ? "Undo retouch stroke" : "Undo area edit"
            ).help("Undo")
            Button {
              session?.redo()
              reconcileSelection()
            } label: {
              Image(systemName: "arrow.uturn.forward")
            }.disabled(!(session?.canRedo ?? false)).keyboardShortcut(
              "z", modifiers: [.command, .shift]
            ).accessibilityLabel(retouch ? "Redo retouch stroke" : "Redo area edit").help("Redo")
            if !retouch { Button(role: .destructive) {
              deleteSelected()
            } label: {
              Image(systemName: "trash")
            }.disabled(selected == nil).accessibilityLabel("Delete selected area").help(
              "Delete selected area") }
  }
  func selectTool(_ tool: PhotoTool) {
    if model.activatePhotoTool(tool) {
      model.photoToolOptionsVisible = true
      if tool == .privacy || tool == .annotate || tool == .retouch { comparingRetouch = false; retouch = tool == .retouch; masking = tool == .privacy
        #if os(iOS)
        showInspector = false
        #else
        showInspector = usesSideInspector(editorWidth)
        #endif
      }
    } else { pendingTool = tool }
  }
  func finishToolSwitch(_ tool: PhotoTool, resolution: Workspace.OverlayDraftResolution) {
    if model.activatePhotoTool(tool, resolvingDraft: resolution) { pendingTool = nil }
    else {
      pendingTool = nil
      previewError = "The photo changed while editing. Cancel and reopen to keep newer edits."
    }
  }
  var optionsPanel: some View {
            VStack(spacing: 0) {
              HStack {
                Text(retouch ? "Retouch Options" : (masking ? "Privacy Options" : "Annotation Options")).font(.headline)
                Spacer()
                Button("Done") { compactOptions = false }
              }.padding(16)
              Divider()
              inspectorContent
            }.frame(minWidth: 280, idealWidth: 320, maxWidth: 380, minHeight: 220, idealHeight: retouch ? 460 : (selected == nil ? 240 : 420), maxHeight: 560)
            .presentationCompactAdaptation(typeSize.isAccessibilitySize ? .sheet : .popover)
  }
  @ViewBuilder var compactContextualOptions: some View {
    if typeSize.isAccessibilitySize {
      // Large text must remain reachable without taking the canvas's whole height.
      // Detailed controls can scroll independently; the photo stays available above.
      ScrollView {
        contextualOptions.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
      }.frame(maxHeight: verticalSizeClass == .compact ? 110 : 220)
        .scrollIndicators(.visible)
    } else { contextualOptions }
  }
  var contextualOptions: some View {
    VStack(alignment: .leading, spacing: 4) {
      if !typeSize.isAccessibilitySize {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) { primaryOptions; secondaryOptions }
          VStack(alignment: .leading, spacing: 4) { primaryOptions; secondaryOptions }
        }
      } else {
        if retouch {
          Picker("Retouch mode", selection: $retouchMode) {
            ForEach(RetouchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.menu)
          brushSizeControl
        } else { ScrollView(.horizontal) { primaryOptions }.scrollIndicators(.visible).frame(minHeight: 52) }
        secondaryOptions
      }
      if comparingRetouch { Text("Before Retouch · protective overlays retained").font(.caption).foregroundStyle(.secondary) }
      if canvasInteraction == .pan { Text("Pan mode · drag to move the photo; tap Paint, Trace or Select to edit again.").font(.caption).foregroundStyle(.secondary) }
      if preparingStroke { ProgressView("Updating retouch…").font(.caption) }
      if retouch, let brushMessage { Text(brushMessage).font(.caption).foregroundStyle(.orange) }
      if !preparingStroke && brushMessage == nil {
        if retouch && config.wrappedValue.retouchStrokes.isEmpty {
          Text(samplingSource ? "Tap a clean area to sample it." : retouchMode == .clone && retouchSource == nil ? "Set a source, then brush over the area to replace." : "Brush over a small distraction. Undo is always available.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if masking && addingArea && shape == .freehand && config.wrappedValue.masks.isEmpty {
          Text("Trace around the area; lift to close it. Apply keeps the change; your original stays untouched.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
  var primaryOptions: some View {
    HStack(spacing: 12) {
      if retouch {
        Picker("Retouch mode", selection: $retouchMode) {
          ForEach(RetouchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
        brushSizeControl.frame(minWidth: 120, maxWidth: .infinity)
      } else {
        Picker("Interaction", selection: $addingArea) {
          Label("Draw", systemImage: "pencil.tip").tag(true)
          Label("Select", systemImage: "cursorarrow").tag(false)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
        if masking {
          Picker("Effect", selection: effectChoice) {
            ForEach(PrivacyToolDefaults.effects, id: \.self) { Text($0.rawValue).tag($0) }
          }.labelsHidden().fixedSize()
          Picker("Shape", selection: shapeChoice) {
            ForEach(PrivacyToolDefaults.shapes, id: \.self) { Text($0 == .freehand ? "Freeform" : $0.rawValue.capitalized).tag($0) }
          }.labelsHidden().fixedSize()
        } else if addingArea {
          Picker("Annotation", selection: $kind) {
            ForEach(AnnotationKind.allCases, id: \.self) { Text($0 == .freehand ? "Freeform" : $0.rawValue.capitalized).tag($0) }
          }.labelsHidden().fixedSize()
        }
      }
    }.padding(.horizontal, 4)
  }
  @ViewBuilder var secondaryOptions: some View {
    if typeSize.isAccessibilitySize {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading, spacing: 4) { secondaryOptionButtons }
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 4) { secondaryOptionButtons }.fixedSize(horizontal: true, vertical: false)
        ScrollView(.horizontal) { HStack(spacing: 4) { secondaryOptionButtons }.fixedSize(horizontal: true, vertical: false) }
          .frame(height: 48).scrollIndicators(.visible)
      }
    }
  }
  @ViewBuilder var secondaryOptionButtons: some View {
    Group {
      if retouch {
        Button { samplingSource.toggle() } label: {
          Image(systemName: "scope")
          if !typeSize.isAccessibilitySize { Text(samplingSource ? "Tap source" : retouchSource == nil ? (retouchMode == .heal ? "Auto Sample" : "Set Source") : "Sampled").fixedSize(horizontal: true, vertical: false) }
        }.comfortableHitTarget().foregroundStyle(.primary).accessibilityLabel(samplingSource ? "Tap source on the photo" : retouchSource == nil ? (retouchMode == .heal ? "Automatic sampling. Set a source" : "Set Clone source") : "Manual source sampled. Set another source")
        if retouchMode == .heal && retouchSource != nil {
          Button("Auto") { retouchSource = nil; destinationAnchor = nil; samplingSource = false }
            .comfortableHitTarget().accessibilityLabel("Use automatic Heal sampling")
        }
      }
      Button {
        #if os(iOS)
        compactOptions.toggle()
        #else
        if embedded && usesSideInspector(editorWidth) { showInspector.toggle() }
        else { compactOptions.toggle() }
        #endif
      } label: { Image(systemName: "slider.horizontal.3") }
        .comfortableHitTarget().accessibilityLabel("Detailed tool settings").accessibilityIdentifier("editor.overlayOptions")
        .popover(isPresented: Binding(get: { compactOptions && embedded }, set: { compactOptions = $0 }), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) { optionsPanel }
      Group {
        Menu {
          Button("Zoom In") { canvasZoom = min(4, canvasZoom * 1.25) }.disabled(canvasZoom >= 4)
          Button("Zoom Out") { canvasZoom = max(1, canvasZoom / 1.25) }.disabled(canvasZoom <= 1)
          Button("Fit Photo") { canvasZoom = 1 }
        } label: { Label(canvasZoom == 1 ? "Fit" : String(format: "%.1f×", canvasZoom), systemImage: "magnifyingglass") }
          .comfortableHitTarget().foregroundStyle(.primary).accessibilityLabel("View Zoom")
          .accessibilityValue(canvasZoom == 1 ? "Fit" : String(format: "%.1f times Fit", canvasZoom))
      }
      if retouch {
        Toggle(isOn: $comparingRetouch) {
          if typeSize.isAccessibilitySize { Label(comparingRetouch ? "After" : "Before", systemImage: "square.on.square").fixedSize(horizontal: true, vertical: false) }
          else { Image(systemName: "square.on.square") }
        }.toggleStyle(.button).disabled(preparingStroke)
          .comfortableHitTarget().accessibilityLabel("Compare this retouch session").foregroundStyle(.primary)
          .accessibilityValue(comparingRetouch ? "Before retouch; protective overlays retained" : "Edited")
          .help("Compare before this retouch session. Current masks, annotations and watermark remain visible.")
      }
      if canvasZoom > 1 {
        Button {
          drawing = []; moveStart = nil; resizeStart = nil; rotationStart = nil
          canvasInteraction = canvasInteraction == .pan ? .edit : .pan
        } label: {
          if typeSize.isAccessibilitySize {
            Label(canvasInteraction == .pan ? (retouch ? "Paint" : addingArea ? "Trace" : "Select") : "Pan", systemImage: canvasInteraction == .pan ? (retouch ? "paintbrush.pointed" : "pencil.tip") : "hand.draw")
          } else { Image(systemName: canvasInteraction == .pan ? (retouch ? "paintbrush.pointed" : "pencil.tip") : "hand.draw") }
        }.comfortableHitTarget()
          .accessibilityLabel(canvasInteraction == .pan ? "Return to editing the photo" : "Pan the photo without editing")
          .accessibilityValue(canvasInteraction == .pan ? "Pan mode" : "Editing mode")
          .help("Pan moves only your view. Crop, retouch and export instructions stay unchanged.")
      }
      if typeSize.isAccessibilitySize {
        Menu { historyControls } label: { Image(systemName: "clock.arrow.circlepath") }
          .comfortableHitTarget().accessibilityLabel("Draft history and delete")
      }
      if masking {
        Button { apply(crop: true) } label: { Image(systemName: "crop") }
          .comfortableHitTarget().disabled(!canApply).accessibilityLabel("Apply changes and crop to hide")
      }
      if embedded && usesSideInspector(editorWidth) {
        Button { model.photoToolOptionsVisible = false } label: { Image(systemName: "xmark") }
          .comfortableHitTarget().accessibilityLabel("Hide tool options; tap the active tool to show again")
      }
    }
  }
  var tabletRail: Bool {
    #if os(iOS)
    embedded && EditorPanelLayout.usesTabletRail(CGSize(width: editorWidth, height: editorHeight), accessibility: typeSize.isAccessibilitySize)
    #else
    false
    #endif
  }
  var samplingIndicator: NormalizedPoint? {
    guard let source = retouchSource else { return nil }
    guard let last = drawing.last else { return source }
    let anchor = alignedSource ? (destinationAnchor ?? drawing.first ?? last) : (drawing.first ?? last)
    return NormalizedPoint(source.x + last.x - anchor.x, source.y + last.y - anchor.y)
  }
  func sourceCoordinate(_ key: WritableKeyPath<NormalizedPoint, Double>) -> Binding<Double> {
    Binding(get: { retouchSource?[keyPath: key] ?? 0.5 }, set: { value in
      guard value.isFinite else { return }
      var point = retouchSource ?? NormalizedPoint(0.5, 0.5)
      point[keyPath: key] = min(1, max(0, value)); retouchSource = point; destinationAnchor = nil
    })
  }
  var brushSizeControl: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text("Size").font(.caption)
        Spacer(minLength: 4)
        TextField("Brush size percent", value: Binding(get: { brushDiameter * 100 }, set: { value in
          guard value.isFinite else { return }
          brushDiameter = min(0.25, max(0.005, value / 100))
        }), format: .number.precision(.fractionLength(0...1)))
          .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).monospacedDigit().frame(width: 64)
        Text("%").font(.caption)
      }
      Slider(value: $brushDiameter, in: 0.005...0.25)
        .accessibilityLabel("Brush diameter as percentage of shorter image edge")
    }
  }
  var retouchControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Retouch mode", selection: $retouchMode) {
        ForEach(RetouchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
      HStack {
        Button(samplingSource ? "Tap a source on the photo" : "Set Source", systemImage: "scope") { samplingSource.toggle() }
        if retouchMode == .heal && retouchSource != nil { Button("Auto") { retouchSource = nil; destinationAnchor = nil } }
      }
      if retouchMode == .clone && retouchSource == nil { Text("Set a source, then paint over the destination.").font(.caption).foregroundStyle(.secondary) }
      if let brushMessage { Text(brushMessage).font(.caption).foregroundStyle(.orange) }
      brushSizeControl
      HStack { Text("Hardness"); Spacer(); Text("\(Int(brushHardness * 100))%").monospacedDigit() }.font(.caption)
      Slider(value: $brushHardness, in: 0...1).accessibilityLabel("Brush hardness")
      HStack { Text("Opacity"); Spacer(); Text("\(Int(brushOpacity * 100))%").monospacedDigit() }.font(.caption)
      Slider(value: $brushOpacity, in: 0.05...1).accessibilityLabel("Brush opacity")
      Toggle("Aligned source", isOn: $alignedSource).disabled(retouchSource == nil).onChange(of: alignedSource) { _, _ in destinationAnchor = nil }
      if retouchSource != nil {
        Text(alignedSource ? "Source set · samples move with your brush" : "Source set · each stroke starts from this sample").font(.caption).foregroundStyle(.secondary)
        DisclosureGroup("Source Position") {
          HStack {
            Text("X")
            TextField("X", value: sourceCoordinate(\.x), format: .percent.precision(.fractionLength(1)))
              .accessibilityLabel("Sample source X")
            Text("Y")
            TextField("Y", value: sourceCoordinate(\.y), format: .percent.precision(.fractionLength(1)))
              .accessibilityLabel("Sample source Y")
          }.textFieldStyle(.roundedBorder)
        }
      }
      if preparingStroke || (previewError == nil && renderedConfiguration != session?.current) { ProgressView("Updating retouch preview…") }
    }.frame(minWidth: 230, maxWidth: 280)
  }
  var retouchStrokeList: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Draft history stays in the editor action bar (or accessibility menu).
      Text("Strokes (\(config.wrappedValue.retouchStrokes.count))").font(.headline)
      if !config.wrappedValue.retouchStrokes.isEmpty {
        Text("Check these strokes again if you change the crop or canvas.").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(config.wrappedValue.retouchStrokes.enumerated()), id: \.element.id) { index, stroke in
        HStack {
          Text("\(index + 1) · \(stroke.mode.rawValue)")
          Spacer()
          Button(role: .destructive) { var next = config.wrappedValue; next.retouchStrokes.removeAll { $0.id == stroke.id }; config.wrappedValue = next } label: { Image(systemName: "trash") }
            .accessibilityLabel("Remove stroke \(index + 1)")
        }
      }
    }
  }
  func commitRetouch() {
    guard !comparingRetouch, !drawing.isEmpty, let image = samplingImage, samplingConfiguration == session?.current, samplingAsset == previewRequest.source, let current = session?.current else { drawing = []; return }
    guard current.retouchStrokes.count < 200 else { brushMessage = "This photo has reached the 200-stroke limit. Remove an earlier stroke to continue."; drawing = []; return }
    if retouchMode == .clone && retouchSource == nil { brushMessage = "Set a source on the photo first."; drawing = []; return }
    var stroke = RetouchStroke(); stroke.mode = retouchMode; stroke.points = drawing
    stroke.diameter = brushDiameter; stroke.hardness = brushHardness; stroke.opacity = brushOpacity
    let source = retouchSource, anchor = destinationAnchor, aligned = alignedSource
    let sourceID = session?.sourceID
    let sampledAsset = samplingAsset
    drawing = []; preparingStroke = true
    pendingStrokeTask = Task {
      defer { preparingStroke = false; pendingStrokeTask = nil }
      do {
        guard let first = stroke.points.first else { return }
        if let source {
          let x = source.x + (aligned ? first.x - (anchor?.x ?? first.x) : 0)
          let y = source.y + (aligned ? first.y - (anchor?.y ?? first.y) : 0)
          guard (0...1).contains(x), (0...1).contains(y) else { brushMessage = "Source moved outside the photo. Set another source."; return }
          stroke.source = NormalizedPoint(x, y)
        } else { stroke.source = try await model.processor.retouchSource(image, at: first, diameter: stroke.diameter) }
        try Task.checkCancellation()
        guard session?.sourceID == sourceID, session?.current == current, previewRequest.source == sampledAsset, !previewSuspended, model.overlayEditor || !embedded else { return }
        var next = current; next.retouchStrokes.append(stroke); config.wrappedValue = next
        if destinationAnchor == nil && source != nil { destinationAnchor = first }
        brushMessage = nil
      } catch is CancellationError { }
      catch {
        brushMessage = source == nil ? "Couldn’t find a nearby sample. Set a source manually or use a smaller brush." : error.localizedDescription
      }
    }
  }
  func usesSideInspector(_ width: CGFloat) -> Bool {
    #if os(iOS)
    tabletRail
    #else
    EditorPanelLayout.supportsOverlayInspector(width: width, accessibility: typeSize.isAccessibilitySize)
    #endif
  }
  var inspectorContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        #if os(macOS)
        Text(addingArea ? "Tool Options" : "Selection").font(.headline)
        toolOptions
        #else
        if retouch { retouchControls }
        else if !embedded || tabletRail {
          Picker("Interaction", selection: $addingArea) {
            Text("Draw").tag(true); Text("Select").tag(false)
          }.pickerStyle(.segmented)
          toolOptions
          if addingArea && masking && shape == .freehand {
            Text("Trace around an area; lift to close the outline.").font(.caption).foregroundStyle(.secondary)
          }
          HStack { historyControls; Spacer() }
        }
        #endif
        if !retouch { areaInspector }
        Divider()
        if retouch { retouchStrokeList } else { objectList }
      }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  var canvasInset: CGFloat { retouch ? 12 : 35 }
  var canvasWorkspace: some View {
    VStack(spacing: 0) {
      GeometryReader { viewport in
        let ratio = image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1
        let width = max(1, min(viewport.size.width - canvasInset * 2, (viewport.size.height - canvasInset * 2) * ratio))
        ScrollView([.horizontal, .vertical]) {
          canvas.allowsHitTesting(canvasInteraction == .edit && !comparingRetouch)
            .frame(width: width * canvasZoom + canvasInset * 2, height: width / ratio * canvasZoom + canvasInset * 2)
            .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
        }.highPriorityGesture(MagnifyGesture().onChanged { value in
          if pinchStart == nil { pinchStart = canvasZoom }
          drawing = []
          canvasZoom = min(4, max(1, (pinchStart ?? 1) * value.magnification))
        }.onEnded { _ in drawing = []; pinchStart = nil })
          .onChange(of: canvasZoom) { _, zoom in if zoom <= 1 { canvasInteraction = .edit } }
          .onChange(of: samplingSource) { _, sampling in if sampling { canvasInteraction = .edit } }
      }
    }.background { EditorCanvasBackground() }
      .overlay(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 4) {
          #if os(iOS)
          if !embedded || (editorWidth > 0 && editorWidth < 600) {
            Text(draftStatus).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5)
              .background(.regularMaterial, in: Capsule())
          }
          #endif
          if image != nil && renderedRequest != previewRequest {
            Label("Updating preview…", systemImage: "clock").font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          }
        }.padding(8).allowsHitTesting(false)
      }
  }
  var objectList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Objects").font(.headline)
      if config.wrappedValue.masks.isEmpty && config.wrappedValue.annotations.isEmpty {
        Text("Draw on the canvas to create an object.").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(config.wrappedValue.masks.enumerated()), id: \.element.id) { index, mask in
        objectRow("Mask \(index + 1) · \(mask.effect.rawValue)", icon: "eye.slash", id: mask.id) {
          masking = true; selected = mask.id; addingArea = false
        }
      }
      ForEach(Array(config.wrappedValue.annotations.enumerated()), id: \.element.id) { index, item in
        objectRow("Annotation \(index + 1) · \(item.kind.rawValue.capitalized)", icon: "textformat", id: item.id) {
          masking = false; selected = item.id; addingArea = false
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func objectRow(_ title: String, icon: String, id: UUID, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        .background(selected == id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(.plain).contextMenu {
      Button("Delete", role: .destructive) { session?.removeArea(id); reconcileSelection() }
    }
  }
  var toolOptions: some View {
    VStack(spacing: 16) {
      if retouch { retouchControls }
      else {
      if masking {
        Picker(addingArea ? "New area effect" : "Selected area effect", selection: effectChoice) {
          ForEach(PrivacyToolDefaults.effects, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Shape", selection: shapeChoice) {
          ForEach(PrivacyToolDefaults.shapes, id: \.self) { Text($0 == .freehand ? "Freeform" : $0.rawValue.capitalized).tag($0) }
        }
      } else if addingArea {
        Picker("Annotation", selection: $kind) {
          ForEach(AnnotationKind.allCases, id: \.self) { Text($0 == .freehand ? "Freeform" : $0.rawValue.capitalized).tag($0) }
        }
      }
      }
    }
  }
  @ViewBuilder var canvas: some View {
    if let image {
      GeometryReader { proxy in
        ZStack {
          Image(decorative: image, scale: 1).resizable().frame(
            width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { resumeDrawingOnEmptyCanvas() }
          if !addingArea && !retouch {
            if masking {
              ForEach(config.wrappedValue.masks) { mask in
                movingArea(
                  id: mask.id, x: mask.x, y: mask.y, width: mask.width, height: mask.height,
                  rotation: mask.rotation, size: proxy.size)
              }
            } else {
              ForEach(config.wrappedValue.annotations) { annotation in
                movingArea(
                  id: annotation.id, x: annotation.x, y: annotation.y,
                  width: annotation.width, height: annotation.height,
                  rotation: annotation.rotation, size: proxy.size)
              }
            }
          }
          Path { p in
            for (i, point) in drawing.enumerated() {
              let q = CGPoint(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
              if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
          }.stroke(.blue.opacity(retouch ? 0.35 : 1), style: StrokeStyle(lineWidth: retouch ? min(proxy.size.width, proxy.size.height) * brushDiameter : 2, lineCap: .round, lineJoin: .round))
          if retouch, let cursor = drawing.last {
            Circle().stroke(.white, lineWidth: 1.5).shadow(color: .black, radius: 1)
              .frame(width: min(proxy.size.width, proxy.size.height) * brushDiameter, height: min(proxy.size.width, proxy.size.height) * brushDiameter)
              .position(x: cursor.x * proxy.size.width, y: cursor.y * proxy.size.height).allowsHitTesting(false)
          }
          if retouch, let source = samplingIndicator {
            Image(systemName: "scope").foregroundStyle(.white).shadow(color: .black, radius: 1)
              .position(x: source.x * proxy.size.width, y: source.y * proxy.size.height).allowsHitTesting(false)
          }
        }.coordinateSpace(name: "overlayCanvas").contentShape(Rectangle()).gesture(
          DragGesture(minimumDistance: 0).onChanged { value in
            guard canvasInteraction == .edit, !comparingRetouch, !preparingStroke, !retouch || renderedConfiguration == session?.current else { return }
            canvasFocused = true
            if retouch && (samplingSource || optionSampling) { return }
            let p = NormalizedPoint(
              min(1, max(0, value.location.x / proxy.size.width)),
              min(1, max(0, value.location.y / proxy.size.height)))
            if drawing.isEmpty {
              drawing = [
                NormalizedPoint(
                  min(1, max(0, value.startLocation.x / proxy.size.width)),
                  min(1, max(0, value.startLocation.y / proxy.size.height)))
              ]
            }
            if drawing.count < 2000 { drawing.append(p) }
          }.onEnded { value in
            guard canvasInteraction == .edit, !comparingRetouch, !preparingStroke, !retouch || renderedConfiguration == session?.current else { return }
            if retouch {
              if samplingSource || optionSampling {
                retouchSource = NormalizedPoint(min(1, max(0, value.location.x / proxy.size.width)), min(1, max(0, value.location.y / proxy.size.height)))
                destinationAnchor = nil; samplingSource = false; brushMessage = nil; drawing = []
              } else { commitRetouch() }
            } else { addDrawn(); drawing = [] }
          }, including: addingArea || retouch ? .all : .subviews)
      }.overlayCanvasSizing(aspect: CGFloat(image.width) / CGFloat(image.height), standalone: false)
        .padding(canvasInset).frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(retouch ? "Retouch canvas. Set a source or paint over the photo." : "Edited output. Use Draw to create areas and Select to move or resize them.")
        .accessibilityAction(named: retouch ? "Retouch centre" : "Draw centred area") {
          drawing = [NormalizedPoint(0.25, 0.25), NormalizedPoint(0.75, 0.25),
                     NormalizedPoint(0.75, 0.75), NormalizedPoint(0.25, 0.75)]
          if retouch { drawing = [NormalizedPoint(0.5, 0.5)]; commitRetouch() }
          else { addDrawn(); drawing = [] }
        }
        .accessibilityAction(named: "Set retouch source at centre") {
          retouchSource = NormalizedPoint(0.5, 0.5); destinationAnchor = nil; samplingSource = false
        }
        .accessibilityAction(named: "Move selected area left") { nudgeSelected(dx: -0.001, dy: 0) }
        .accessibilityAction(named: "Move selected area right") { nudgeSelected(dx: 0.001, dy: 0) }
        .accessibilityAction(named: "Move selected area up") { nudgeSelected(dx: 0, dy: -0.001) }
        .accessibilityAction(named: "Move selected area down") { nudgeSelected(dx: 0, dy: 0.001) }
        #if os(macOS)
          .focusable().focused($canvasFocused)
          .onModifierKeysChanged(mask: .option) { _, modifiers in optionSampling = modifiers.contains(.option) }
          .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat, .up]) { key in
            guard canvasInteraction == .edit, !retouch, selected != nil, !addingArea, key.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
            if key.phase == .up { session?.endInteraction(); return .handled }
            session?.beginInteraction()
            let step = key.modifiers.contains(.shift) ? 0.01 : 0.001
            let dx = key.key == .leftArrow ? -step : key.key == .rightArrow ? step : 0
            let dy = key.key == .upArrow ? -step : key.key == .downArrow ? step : 0
            if let selected { session?.moveArea(selected, dx: dx, dy: dy) }
            return .handled
          }
          .onChange(of: canvasFocused) { _, focused in
            if !focused { session?.endInteraction() }
          }
          .help("Arrow keys move the selected area. Hold Shift for larger steps.")
        #endif
    } else if let previewError {
      VStack(spacing: 12) {
        ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle", description: Text(previewError))
        Button("Retry Preview") { previewRetry += 1 }
        if let asset { Button("Locate or Replace Source…") { model.relinkSourceID = asset.id } }
        Text("Your tool edits remain in this draft. If the source changes, cancel and reopen before applying.")
          .font(.caption).foregroundStyle(.secondary)
      }.frame(minHeight: 200)
    } else {
      ProgressView().frame(height: 200)
    }
  }
  var areaInspector: some View {
    VStack(alignment: .leading, spacing: 16) {
      if selected != nil && !addingArea {
        Toggle("Keep proportions", isOn: $keepProportions)
          .help("Resize both dimensions together. On Mac, Shift-drag also keeps proportions.")
      }
      ForEach(Array(config.masks.wrappedValue.enumerated()), id: \.element.id) {
        position, mask in
        if selected == mask.id && !addingArea {
        DisclosureGroup(
          "Area \(position + 1) · \(mask.effect.rawValue)",
          isExpanded: Binding(
            get: { selected == mask.id },
            set: { expanded in
              selected = expanded ? mask.id : nil
              addingArea = !expanded
            })
        ) {
          if !embedded {
            Button("Select & move") { selected = mask.id; addingArea = false }
          }
          let b = maskBinding(mask.id)
          if mask.effect != .cover {
            Text("Effect strength")
            Slider(value: b.strength, in: 0...1, onEditingChanged: draftInteraction)
              .accessibilityLabel("Effect strength")
          }
          DisclosureGroup("Precise Transform") { geometry(b.x, b.y, b.width, b.height, b.rotation) }
          Button("Remove mask", role: .destructive) {
            session?.removeArea(mask.id)
            if selected == mask.id { selected = nil }
          }
        }
        }
      }
      ForEach(Array(config.annotations.wrappedValue.enumerated()), id: \.element.id) {
        position, annotation in
        if selected == annotation.id && !addingArea {
        DisclosureGroup(
          "Annotation \(position + 1) · \(annotation.kind.rawValue.capitalized)",
          isExpanded: Binding(
            get: { selected == annotation.id },
            set: { expanded in
              selected = expanded ? annotation.id : nil
              addingArea = !expanded
            })
        ) {
          if !embedded {
            Button("Select & move") { selected = annotation.id; addingArea = false }
          }
          let b = annotationBinding(annotation.id)
          if annotation.kind == .text {
            TextField("Text", text: b.text)
            Picker("Font", selection: b.fontName) {
              Text("Helvetica").tag("HelveticaNeue-Medium")
              Text("Helvetica Bold").tag("HelveticaNeue-Bold")
              Text("Avenir").tag("AvenirNext-Medium")
              Text("Times").tag("TimesNewRomanPSMT")
            }
            Picker("Alignment", selection: b.alignment) {
              ForEach(AnnotationTextAlignment.allCases, id: \.self) {
                Text($0.rawValue.capitalized).tag($0)
              }
            }
          }
          DisclosureGroup("Precise Transform") { geometry(b.x, b.y, b.width, b.height, b.rotation) }
          Text("Opacity")
          Slider(value: b.opacity, in: 0...1, onEditingChanged: draftInteraction)
            .accessibilityLabel("Opacity")
          if annotation.kind != .text {
            Text("Stroke width")
            Slider(value: b.lineWidth, in: 0.001...0.05, onEditingChanged: draftInteraction)
              .accessibilityLabel("Stroke width")
          }
          Picker("Colour", selection: b.colour) {
            Text("White").tag(RGBAColour(1, 1, 1, 1))
            Text("Black").tag(RGBAColour(0, 0, 0, 1))
            Text("Blue").tag(RGBAColour(0, 0.3, 1, 1))
            Text("Red").tag(RGBAColour(1, 0, 0, 1))
          }
          Button("Remove annotation", role: .destructive) {
            session?.removeArea(annotation.id)
            if selected == annotation.id { selected = nil }
          }
        }
      }
      }
      if masking && !retouch {
        DisclosureGroup("Privacy guidance") {
          Text("Use an opaque cover or crop for reliable concealment. Blur and pixelation can leave recognisable details. Exported masks are flattened; originals remain unchanged.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }
  func cancel() {
    drawing = []
    session?.cancel()
    model.pendingOverlayDestination = nil
    session = nil
    closeEditor()
  }
  func apply(crop: Bool = false) {
    guard canApply, var draft = session else { return }
    draft.endInteraction()
    if crop {
      var c = draft.current
      c.privacyExport = true
      c.metadata = .remove
      draft.update(c)
    }
    guard model.applyOverlaySession(draft) else {
      previewError = "The photo changed while editing. Cancel and reopen to keep newer edits."
      return
    }
    if crop { model.pendingOverlayDestination = .framing }
    session = nil
    closeEditor()
  }
  func closeEditor() {
    if embedded {
      model.overlayEditor = false
      Task {
        await Task.yield()
        model.finishOverlayPresentation()
      }
    } else {
      dismiss()
    }
  }
  func reconcileSelection() {
    if let selected, !config.wrappedValue.masks.contains(where: { $0.id == selected }),
      !config.wrappedValue.annotations.contains(where: { $0.id == selected })
    {
      self.selected = nil
    }
    drawing = []
  }
  func nudgeSelected(dx: Double, dy: Double) {
    guard let selected, !addingArea else { return }
    session?.endInteraction()
    session?.moveArea(selected, dx: dx, dy: dy)
  }
  func deleteSelected() {
    guard let selected else { return }
    session?.removeArea(selected)
    self.selected = nil
    drawing = []
  }
  var constrainResize: Bool {
    #if os(macOS)
    keepProportions || MacEditingModifiers.keepProportions
    #else
    keepProportions
    #endif
  }
  func movingArea(
    id: UUID, x: Double, y: Double, width: Double, height: Double, rotation: Double, size: CGSize
  ) -> some View {
    ZStack {
      Rectangle().fill(.clear).overlay(
        Rectangle().stroke(
          selected == id ? Color.blue : Color.white.opacity(0.7),
          style: StrokeStyle(lineWidth: selected == id ? 2 : 1, dash: [6, 4]))
      )
      .frame(width: width * size.width, height: height * size.height)
      .contentShape(Rectangle()).onTapGesture {
        selected = id
        canvasFocused = true
      }
      .gesture(
        DragGesture(minimumDistance: 3, coordinateSpace: .named("overlayCanvas")).onChanged {
          gesture in
          selected = id
          canvasFocused = true
          if moveStart == nil {
            moveStart = NormalizedPoint(x, y)
            session?.beginInteraction()
          }
          let newX = min(
            max(0, 1 - width), max(0, (moveStart?.x ?? x) + gesture.translation.width / size.width))
          let newY = min(
            max(0, 1 - height),
            max(0, (moveStart?.y ?? y) + gesture.translation.height / size.height))
          updateBounds(
            OverlayBounds(x: newX, y: newY, width: width, height: height, rotation: rotation),
            id: id)
        }.onEnded { _ in
          moveStart = nil
          session?.endInteraction()
        })
      if selected == id {
        GeometryReader { geometry in
          ForEach(OverlayResizeHandle.allCases, id: \.self) { handle in
            Circle().fill(.white).overlay(Circle().stroke(.blue, lineWidth: 2)).frame(
              width: 12, height: 12
            )
            .frame(width: 30, height: 30).comfortableHitTarget().contentShape(Rectangle())
            .position(
              x: 40 + handle.anchor.x * (geometry.size.width - 80),
              y: 40 + handle.anchor.y * (geometry.size.height - 80)
            )
            .gesture(
              DragGesture(minimumDistance: 1, coordinateSpace: .named("overlayCanvas")).onChanged {
                gesture in
                canvasFocused = true
                if resizeStart == nil {
                  resizeStart = OverlayBounds(
                    x: x, y: y, width: width, height: height, rotation: rotation)
                  session?.beginInteraction()
                }
                if let start = resizeStart {
                  updateBounds(
                    OverlayGeometry.resized(
                      start, handle: handle, translation: gesture.translation, viewport: size,
                      preserveAspect: constrainResize),
                    id: id)
                }
              }.onEnded { _ in
                resizeStart = nil
                session?.endInteraction()
              }
            )
            .accessibilityLabel("Resize area from \(handle.rawValue)")
          }
          Path { p in
            p.move(to: CGPoint(x: geometry.size.width / 2, y: 40))
            p.addLine(to: CGPoint(x: geometry.size.width / 2, y: 10))
          }.stroke(.blue, lineWidth: 1).allowsHitTesting(false)
          Image(systemName: "arrow.trianglehead.clockwise.rotate.90").font(
            .system(size: 14, weight: .semibold)
          ).foregroundStyle(.blue)
            .frame(width: 30, height: 30).background(.background, in: Circle()).overlay(
              Circle().stroke(.blue, lineWidth: 1)
            )
            .comfortableHitTarget()
            .position(x: geometry.size.width / 2, y: 10).contentShape(Circle())
            .gesture(
              DragGesture(minimumDistance: 1, coordinateSpace: .named("overlayCanvas")).onChanged {
                gesture in
                canvasFocused = true
                if rotationStart == nil {
                  rotationStart = OverlayBounds(
                    x: x, y: y, width: width, height: height, rotation: rotation)
                  session?.beginInteraction()
                }
                if let start = rotationStart {
                  updateBounds(
                    OverlayGeometry.rotated(
                      start, from: gesture.startLocation, to: gesture.location, viewport: size),
                    id: id)
                }
              }.onEnded { _ in
                rotationStart = nil
                session?.endInteraction()
              }
            )
            .accessibilityLabel(
              "Rotate selected area; precise rotation is also available in area options")

        }
      }
    }.frame(width: width * size.width + 80, height: height * size.height + 80).rotationEffect(
      .degrees(rotation)
    )
    .position(x: (x + width / 2) * size.width, y: (y + height / 2) * size.height).zIndex(
      selected == id ? 1 : 0
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(selected == id ? "Selected area" : "Privacy area")
    .accessibilityAction(named: "Select area") {
      selected = id
      addingArea = false
    }
    .contextMenu {
      Button("Delete Area", role: .destructive) {
        session?.removeArea(id)
        if selected == id { selected = nil }
      }
    }
  }
  func updateBounds(_ bounds: OverlayBounds, id: UUID) {
    if masking {
      var value = maskBinding(id).wrappedValue
      value.x = bounds.x
      value.y = bounds.y
      value.width = bounds.width
      value.height = bounds.height
      value.rotation = bounds.rotation
      maskBinding(id).wrappedValue = value
    } else {
      var value = annotationBinding(id).wrappedValue
      value.x = bounds.x
      value.y = bounds.y
      value.width = bounds.width
      value.height = bounds.height
      value.rotation = bounds.rotation
      annotationBinding(id).wrappedValue = value
    }
  }
  func draftInteraction(_ editing: Bool) {
    if editing { session?.beginInteraction() } else { session?.endInteraction() }
  }
  func geometry(
    _ x: Binding<Double>, _ y: Binding<Double>, _ w: Binding<Double>, _ h: Binding<Double>,
    _ r: Binding<Double>
  ) -> some View {
    VStack {
      coordinateField("Left (%)", x, 0...1)
      coordinateField("Top (%)", y, 0...1)
      coordinateField("Width (%)", w, 0.01...1)
      coordinateField("Height (%)", h, 0.01...1)
      LabeledContent("Rotation (°)") {
        TextField("Rotation degrees", value: r, format: .number.precision(.fractionLength(1)))
          .multilineTextAlignment(.trailing).frame(width: 80)
      }
    }
  }
  func coordinateField(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>)
    -> some View
  {
    LabeledContent(title) {
      TextField(
        title,
        value: Binding(
          get: { value.wrappedValue * 100 },
          set: {
            if $0.isFinite {
              value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0 / 100))
            }
          }), format: .number.precision(.fractionLength(1))
      )
      .multilineTextAlignment(.trailing).frame(width: 80)
    }
  }
  func maskBinding(_ id: UUID) -> Binding<PrivacyMask> {
    Binding(
      get: { config.wrappedValue.masks.first { $0.id == id } ?? PrivacyMask() },
      set: { value in
        var c = config.wrappedValue
        if let i = c.masks.firstIndex(where: { $0.id == id }) { c.masks[i] = value }
        config.wrappedValue = c
      })
  }
  func annotationBinding(_ id: UUID) -> Binding<Annotation> {
    Binding(
      get: { config.wrappedValue.annotations.first { $0.id == id } ?? Annotation() },
      set: { value in
        var c = config.wrappedValue
        if let i = c.annotations.firstIndex(where: { $0.id == id }) { c.annotations[i] = value }
        config.wrappedValue = c
      })
  }
  func addDrawn() {
    guard drawing.count >= 2 else { return }
    let xs = drawing.map(\.x)
    let ys = drawing.map(\.y)
    let x = xs.min() ?? 0.25
    let y = ys.min() ?? 0.25
    let w = max(0.01, (xs.max() ?? 0.75) - x)
    let h = max(0.01, (ys.max() ?? 0.75) - y)
    var c = config.wrappedValue
    if masking {
      c.privacyExport = true
      guard let m = PrivacyToolDefaults.mask(points: drawing, effect: effect, shape: shape) else { return }
      c.masks.append(m)
      selected = m.id
    } else {
      var a = Annotation()
      a.kind = kind
      a.x = x
      a.y = y
      a.width = w
      a.height = h
      a.points = drawing.map { NormalizedPoint(($0.x - x) / w, ($0.y - y) / h) }
      c.annotations.append(a)
      selected = a.id
    }
    config.wrappedValue = c
    addingArea = false
    canvasFocused = true
  }
  func resumeDrawingOnEmptyCanvas() {
    guard !addingArea else { return }
    // Carry the last selected tool settings into the next area without changing the existing edit.
    if let selected, let mask = config.wrappedValue.masks.first(where: { $0.id == selected }) {
      effect = mask.effect
      shape = mask.shape
    }
    if let selected, let annotation = config.wrappedValue.annotations.first(where: { $0.id == selected }) {
      kind = annotation.kind
    }
    selected = nil
    drawing = []
    addingArea = true
    canvasFocused = true
  }
}

extension View {
  @ViewBuilder fileprivate func overlayCanvasSizing(aspect: CGFloat, standalone: Bool) -> some View {
    if standalone { self.aspectRatio(aspect, contentMode: .fit).frame(maxHeight: 480) }
    else { self }
  }
  @ViewBuilder fileprivate func overlayEditorSize(embedded: Bool) -> some View {
    #if os(macOS)
      if embedded {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        self.frame(
          minWidth: 650, idealWidth: 800, maxWidth: 1000, minHeight: 600, idealHeight: 740,
          maxHeight: 900)
      }
    #else
      self.frame(minWidth: 320)
    #endif
  }
}
