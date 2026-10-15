import FramepebbleCore
import SwiftUI

/// Direct drawing and numeric alternatives share the persisted final-output overlay models.
struct OverlayEditor: View {
  @Bindable var model: Workspace
  @State private var masking = true
  @State private var shape: OverlayShape = .rectangle
  @State private var kind: AnnotationKind = .text
  @State private var effect: MaskEffect = .cover
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
  @State private var showInspector = true
  @State private var keepProportions = false
  @State private var canvasZoom: Double = 1
  @FocusState private var canvasFocused: Bool
  @State private var asset: SourceAsset?
  @State private var addingArea = true
  @State private var previewError: String?
  @State private var renderedConfiguration: ProcessingConfiguration?
  @Environment(\.dismiss) private var dismiss
  var config: Binding<ProcessingConfiguration> {
    Binding(
      get: { session?.current ?? ProcessingConfiguration() },
      set: { session?.update($0) })
  }
  var canApply: Bool {
    session != nil && previewError == nil && renderedConfiguration == session?.current
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
          HStack(spacing: 0) {
            toolRail
            canvasWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
            if showInspector { Divider() }
            if showInspector {
              ScrollView {
                VStack(spacing: 16) {
                  Text(addingArea ? "Tool Options" : "Selection").font(.headline)
                  toolOptions
                  areaInspector
                  Divider()
                  objectList
                }.padding(12)
              }.frame(width: 300)
            }
          }
        } else {
          ScrollView {
            VStack(spacing: 16) {
              toolOptions
              canvas
              areaInspector
              objectList
            }.padding()
          }
        }
      }.navigationTitle(masking ? "Privacy" : "Annotate").compactNavigationTitle()
        .safeAreaInset(edge: .top, spacing: 0) {
          HStack {
            if embedded {
              Label(masking ? "Privacy" : "Annotate", systemImage: masking ? "eye.slash" : "textformat")
                .font(.headline)
              Text(asset?.name ?? model.current?.name ?? "Photo").lineLimit(1).foregroundStyle(.secondary)
              Divider().frame(height: 18)
            }
            if !embedded { Picker("Canvas tool", selection: $addingArea) {
              Label("Draw", systemImage: "pencil.tip").tag(true)
              Label("Select", systemImage: "cursorarrow").tag(false)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 190) }
            if embedded {
              Text(addingArea ? "Draw on the photo" : "Drag to move · Handles to resize and rotate")
                .font(.caption).foregroundStyle(.secondary)
            }
            Button {
              session?.undo()
              reconcileSelection()
            } label: {
              Image(systemName: "arrow.uturn.backward")
            }.disabled(!(session?.canUndo ?? false)).keyboardShortcut("z").accessibilityLabel(
              "Undo area edit"
            ).help("Undo")
            Button {
              session?.redo()
              reconcileSelection()
            } label: {
              Image(systemName: "arrow.uturn.forward")
            }.disabled(!(session?.canRedo ?? false)).keyboardShortcut(
              "z", modifiers: [.command, .shift]
            ).accessibilityLabel("Redo area edit").help("Redo")
            Button(role: .destructive) {
              deleteSelected()
            } label: {
              Image(systemName: "trash")
            }.disabled(selected == nil).accessibilityLabel("Delete selected area").help(
              "Delete selected area")
            Spacer(minLength: 0)
            if embedded {
              Button {
                showInspector.toggle()
              } label: {
                Image(systemName: "sidebar.right")
              }.accessibilityLabel(showInspector ? "Hide area options" : "Show area options")
            }
            if masking {
              Button {
                apply(crop: true)
              } label: {
                Label("Apply & Crop", systemImage: "crop")
              }.disabled(
                !canApply
              ).accessibilityLabel("Apply changes and crop to hide").help(
                "Apply draft and open crop editor")
            }
          }.padding(10).background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          HStack {
            Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
            Spacer()
            Text(
              "\(config.wrappedValue.masks.count + config.wrappedValue.annotations.count) \(config.wrappedValue.masks.count + config.wrappedValue.annotations.count == 1 ? "editable object" : "editable objects")"
            ).font(.caption).foregroundStyle(.secondary)
            Button("Apply") { apply() }.buttonStyle(.borderedProminent).keyboardShortcut(
              .defaultAction
            ).disabled(
              !canApply)
          }.padding(12).background(.bar)
        }
        .onAppear {
          guard
            let source = session.flatMap({ draft in model.assets.first { $0.id == draft.sourceID } }
            ) ?? model.current
          else { return }
          asset = source
          masking = model.overlayStartsWithMasks
          if session == nil {
            session = OverlayEditingSession(
              sourceID: source.id, configuration: model.configuration(for: source))
          }
          selected = masking ? session?.current.masks.first?.id : session?.current.annotations.first?.id
          addingArea = selected == nil
        }
        .task(id: session?.current) {
          guard let asset, let session else { return }
          do {
            try await Task.sleep(for: .milliseconds(40))
            let rendered = try await model.processor.render(
              asset.url, configuration: session.current, previewMaximum: 1000)
            try Task.checkCancellation()
            image = rendered
            renderedConfiguration = session.current
            previewError = nil
          } catch is CancellationError {} catch {
            image = nil
            previewError = error.localizedDescription
          }
        }
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
        .interactiveDismissDisabled()
        #if os(macOS)
          .onExitCommand { cancel() }
          .onDeleteCommand { if canvasFocused && !addingArea { deleteSelected() } }
        #endif
    }.toolbar {
      if embedded {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            cancel()
          } label: {
            Label("Close Editor", systemImage: "xmark")
          }.help("Close editor and discard unapplied changes")
        }
      }
    }.overlayEditorSize(embedded: embedded).overlay {
      if let asset { SensitivePreviewCover(model: model, ids: [asset.id]) }
    }
  }
  var canvasWorkspace: some View {
    VStack(spacing: 0) {
      GeometryReader { viewport in
        let ratio = image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1
        let width = max(1, min(viewport.size.width - 70, (viewport.size.height - 70) * ratio))
        ScrollView([.horizontal, .vertical]) {
          canvas.frame(width: width * canvasZoom + 70, height: width / ratio * canvasZoom + 70)
            .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
        }
      }
      HStack(spacing: 12) {
        Text(asset?.name ?? "Photo").lineLimit(1).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button { canvasZoom = max(1, canvasZoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
          .disabled(canvasZoom <= 1).accessibilityLabel("Zoom out")
        Text("\(Int(canvasZoom * 100))% of fit").font(.caption.monospacedDigit()).frame(width: 80)
        Button { canvasZoom = min(4, canvasZoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
          .disabled(canvasZoom >= 4).accessibilityLabel("Zoom in")
        Button("Fit") { canvasZoom = 1 }.help("Fit the photo to the workspace")
      }.padding(10).background(.bar)
    }
  }
  var toolRail: some View {
    VStack(spacing: 12) {
      editorTool("Select", icon: "cursorarrow", active: !addingArea) { addingArea = false }
      editorTool("Draw", icon: "pencil.tip", active: addingArea) { addingArea = true }
      Divider()
      editorTool("Privacy masks", icon: "eye.slash", active: masking) { masking = true }
      editorTool("Annotations", icon: "textformat", active: !masking) { masking = false }
      Spacer()
    }.padding(10).frame(width: 62).background(.bar)
  }
  func editorTool(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 19)).frame(width: 40, height: 40)
        .background(active ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(.plain).foregroundStyle(active ? Color.accentColor : Color.primary)
      .help(title).accessibilityLabel(title).accessibilityAddTraits(active ? .isSelected : [])
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
      if !embedded {
        Picker("Tool", selection: $masking) {
          Text("Privacy").tag(true)
          Text("Annotate").tag(false)
        }.pickerStyle(.segmented)
      }
      if masking {
        Picker(addingArea ? "New area effect" : "Selected area effect", selection: effectChoice) {
          ForEach(MaskEffect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Shape", selection: shapeChoice) {
          ForEach(OverlayShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
      } else if addingArea {
        Picker("Annotation", selection: $kind) {
          ForEach(AnnotationKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
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
          if !addingArea {
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
          }.stroke(.blue, lineWidth: 2)
        }.coordinateSpace(name: "overlayCanvas").contentShape(Rectangle()).gesture(
          DragGesture(minimumDistance: 3).onChanged { value in
            canvasFocused = true
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
          }.onEnded { _ in
            addDrawn()
            drawing = []
          }, including: addingArea ? .all : .subviews)
      }.aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit).frame(
        maxHeight: embedded ? .infinity : 480
      ).padding(35).frame(maxWidth: .infinity)
        .accessibilityLabel(
          "Edited output. Use Draw to create areas and Select to move or resize them."
        )
        .accessibilityAction(named: "Draw centred area") {
          drawing = [NormalizedPoint(0.25, 0.25), NormalizedPoint(0.75, 0.75)]
          addDrawn()
          drawing = []
        }
        .accessibilityAction(named: "Move selected area left") { nudgeSelected(dx: -0.001, dy: 0) }
        .accessibilityAction(named: "Move selected area right") { nudgeSelected(dx: 0.001, dy: 0) }
        .accessibilityAction(named: "Move selected area up") { nudgeSelected(dx: 0, dy: -0.001) }
        .accessibilityAction(named: "Move selected area down") { nudgeSelected(dx: 0, dy: 0.001) }
        #if os(macOS)
          .focusable().focused($canvasFocused)
          .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat, .up]) { key in
            guard selected != nil, !addingArea, key.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
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
      ContentUnavailableView(
        "Preview unavailable", systemImage: "exclamationmark.triangle",
        description: Text(previewError)
      ).frame(height: 200)
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
      DisclosureGroup("Privacy guidance") {
        Text("Use an opaque cover or crop for reliable concealment. Blur and pixelation can leave recognisable details. Exported masks are flattened; originals remain unchanged.")
          .font(.caption).foregroundStyle(.secondary)
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
      var m = PrivacyMask()
      m.x = x
      m.y = y
      m.width = w
      m.height = h
      m.effect = effect
      m.shape = shape
      m.points = drawing.map { NormalizedPoint(($0.x - x) / w, ($0.y - y) / h) }
      if m.shape == .freehand && drawing.count < 3 { m.shape = .rectangle }
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
      self.frame(minWidth: 320, minHeight: 500)
    #endif
  }
}
