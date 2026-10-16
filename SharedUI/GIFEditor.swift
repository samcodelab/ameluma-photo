import SwiftUI
import FramepebbleCore
import ImageIO
#if os(macOS)
import AppKit
#endif

struct GIFEditor: View {
  @Bindable var model: Workspace
  var importAction: () -> Void
  @State private var selectedFrames: Set<UUID> = []
  @State private var frameIndex = 0
  @State private var playing = false
  @State private var playbackGeneration = 0
  @State private var preview: GIFPreview?
  @State private var image: CGImage?
  @State private var previewError: String?
  @State private var preparing = false
  @State private var previewAllowed = true
  @State private var duration = 0.5
  @State private var annotationID: UUID?
  @State private var draggedFrame: String?
  @State private var showNew = false
  @Environment(\.scenePhase) private var phase
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.self) private var environment
  @Environment(\.horizontalSizeClass) private var sizeClass
  private let previewBuilder = GIFPreviewBuilder()
  var project: GIFProject { model.gifProject ?? GIFProject() }
  var activeFrame: GIFFrame? { project.frames.indices.contains(frameIndex) ? project.frames[frameIndex] : nil }
  var compact: Bool {
    #if os(macOS)
    false
    #else
    sizeClass == .compact
    #endif
  }
  var body: some View {
    Group {
      if project.frames.isEmpty { emptyState }
      else {
        GeometryReader { geometry in
          if !compact && geometry.size.width > 780 {
            HStack(spacing: 0) {
              VStack { header; canvas; transport; frameStrip }.padding()
              Divider()
              ScrollView { controls.padding() }.frame(width: 300)
            }
          } else {
            ScrollView {
              VStack(spacing: 14) {
                header
                canvas.frame(height: max(210, min(360, geometry.size.height * 0.4)))
                transport
                frameStrip
                controls
              }.padding()
            }
          }
        }
      }
    }
    .disabled(model.gifExporting)
    .safeAreaInset(edge: .bottom) {
      if model.gifExporting {
        HStack {
          ProgressView(value: Double(model.gifExportCompleted), total: Double(max(1, model.gifExportTotal)))
          Text("\(model.gifExportCompleted) / \(model.gifExportTotal)")
          Button("Cancel Export") { model.gifExportTask?.cancel() }
        }.padding().background(.bar)
      }
    }
    .task(id: GIFPreviewInput(project: project, sources: model.assets, allowed: previewAllowed)) { await preparePreview() }
    .task(id: frameIndex) { await loadCurrentFrame() }
    .task(id: "\(playing)-\(playbackGeneration)") { if playing { await playback() } }
    .onChange(of: phase) { _, value in if value == .background { playing = false; previewAllowed = false } else if value == .active { previewAllowed = true } }
    .onDisappear { playing = false; preview?.remove(); preview = nil }
    .confirmationDialog("Start a new GIF?", isPresented: $showNew) {
      Button("Save Workspace Copy & Start New") {
        Task { do { _ = try await model.saveProjectCopy(); model.archiveCurrentGIF(); model.gifProject = nil; model.selectGIFPhotos() } catch { model.issues.append(error.localizedDescription) } }
      }
    } message: { Text("Your current animation will remain in the saved workspace copy.") }
  }
  var emptyState: some View {
    ContentUnavailableView {
      Label("Create an animated GIF", systemImage: "photo.stack")
    } description: {
      Text("Turn your photos into a looping animation. Add captions, adjust timing and make it your own.")
    } actions: {
      Button("Select Photos") { model.selectGIFPhotos() }.buttonStyle(.borderedProminent).controlSize(.large)
      if model.assets.isEmpty { Button("Add Photos", action: importAction) }
    }
  }
  var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      if typeSize.isAccessibilitySize {
        Text("Create GIF").font(.title2.weight(.semibold))
        HStack { historyButtons; Spacer(); moreMenu }
      } else {
        HStack { Text("Create GIF").font(.title2.weight(.semibold)); historyButtons; Spacer(); moreMenu }
      }
    }
  }
  var historyButtons: some View {
    HStack {
      Button("Undo", systemImage: "arrow.uturn.backward") { model.undoActiveWorkspace() }.labelStyle(.iconOnly).disabled(!model.canUndoActiveWorkspace)
      Button("Redo", systemImage: "arrow.uturn.forward") { model.redoActiveWorkspace() }.labelStyle(.iconOnly).disabled(!model.canRedoActiveWorkspace)
    }
  }
  var moreMenu: some View {
    Menu("More") {
      if !model.archivedGIFs.isEmpty { Menu("Saved GIFs") { ForEach(model.archivedGIFs.filter { $0.id != model.gifProject?.id }) { saved in Button(saved.name) { model.openGIF(saved) } } } }
      Button("Add Photos") { model.selectGIFPhotos(adding: true) }
      Button("New GIF…") { showNew = true }
      Button("Save Workspace Copy") { Task { do { _ = try await model.saveProjectCopy(); model.status = "Workspace and GIF saved." } catch { model.issues.append(error.localizedDescription) } } }
    }
  }
  var canvas: some View {
    GeometryReader { geometry in
      let aspect = Double(max(16, min(2000, project.width))) / Double(max(16, min(2000, project.height)))
      let width = min(geometry.size.width, geometry.size.height * aspect)
      let height = width / aspect
      ZStack {
        Color.black.opacity(0.04)
        if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
        else if let previewError {
          VStack { Text(previewError).font(.callout); Button("Replace This Frame’s Photo") { if let frame = activeFrame { model.selectGIFPhotos(replacing: frame.id) } }; Button("Locate Missing Photo…") { if let frame = activeFrame { model.library = .all; model.query = ""; model.workspaceFilter = WorkspaceFilter(); model.activePhotoID = frame.sourceID }; model.projectsView = true } }.padding()
        }
        if preparing { ProgressView("Preparing preview…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
        if !playing, let id = annotationID, let item = project.annotations.first(where: { $0.id == id }), let frame = activeFrame,
          item.frameIDs?.contains(frame.id) ?? true {
          GIFAnnotationHandles(annotation: item.annotation, canvas: CGSize(width: width, height: height), interaction: model.gifInteraction) { value in
            change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) { p.annotations[i].annotation = value } }
          }
        }
      }.frame(width: width, height: height).clipped()
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }.frame(minHeight: 200).accessibilityLabel("GIF preview, frame \(frameIndex + 1) of \(project.frames.count)")
  }
  var transport: some View {
    VStack(alignment: .leading, spacing: 8) {
      if typeSize.isAccessibilitySize {
        HStack { playbackButtons.labelStyle(.iconOnly); Spacer() }
        playbackSummary
      } else {
        HStack { playbackButtons; Spacer(); playbackSummary }
      }
    }.buttonStyle(.bordered)
  }
  var playbackButtons: some View {
    Group {
      Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") { playing.toggle() }.disabled(preparing || preview == nil)
      Button("Restart", systemImage: "backward.end.fill") { frameIndex = 0; playing = true; playbackGeneration += 1 }.disabled(preparing || preview == nil)
    }
  }
  var playbackSummary: some View {
    Text("\(project.frames.count) frames · \(project.duration, specifier: "%.2f") s").font(.caption).monospacedDigit()
  }
  var frameStrip: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Frames · \(selectedFrames.count) selected").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Menu("Order") {
          Text("Starts in selection order; range selections use workspace order.")
          Button("By Filename") { change { p in
            let lookup = Dictionary(uniqueKeysWithValues: model.assets.map { ($0.id, $0.name) })
            p.frames = p.frames.enumerated().sorted { a, b in
              let comparison = (lookup[a.element.sourceID] ?? "").localizedStandardCompare(lookup[b.element.sourceID] ?? "")
              return comparison == .orderedSame ? a.offset < b.offset : comparison == .orderedAscending
            }.map(\.element)
          } }
          Button("By Capture Date") { orderByDate() }
        }
      }
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
            VStack(spacing: 4) {
              Button { playing = false; frameIndex = index; if !selectedFrames.insert(frame.id).inserted { selectedFrames.remove(frame.id) } } label: {
                VStack {
                  if let asset = model.assets.first(where: { $0.id == frame.sourceID }) { GIFSourceThumbnail(asset: asset, processor: model.processor) }
                  else { Image(systemName: "photo.badge.exclamationmark").frame(width: 70, height: 54) }
                  Text("\(index + 1) · \(project.timing(for: frame), specifier: "%.2f")s").font(.caption2)
                }.padding(5).background(selectedFrames.contains(frame.id) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                  .overlay(RoundedRectangle(cornerRadius: 8).stroke(frameIndex == index ? Color.accentColor : .clear, lineWidth: 2))
              }.buttonStyle(.plain).accessibilityLabel("Frame \(index + 1), \(project.timing(for: frame)) seconds")
              Menu("Frame") {
                Button("Duplicate") { change { $0.duplicate(frame.id) } }
                Button("Move Earlier") { if index > 0 { change { $0.move(frame.id, before: $0.frames[index - 1].id) } } }.disabled(index == 0)
                Button("Move Later") { if index + 1 < project.frames.count { change { $0.move($0.frames[index + 1].id, before: frame.id) } } }.disabled(index + 1 == project.frames.count)
                Button("Replace Photo") { model.selectGIFPhotos(replacing: frame.id) }
                Button("Remove", role: .destructive) { change { $0.remove([frame.id]) }; selectedFrames.remove(frame.id) }
              }.font(.caption)
            }
            .draggable(frame.id.uuidString)
            .dropDestination(for: String.self) { ids, _ in
              guard let raw = ids.first, let id = UUID(uuidString: raw) else { return false }
              change { $0.move(id, before: frame.id) }; return true
            }
          }
          Button("Add Photos", systemImage: "plus") { model.selectGIFPhotos(adding: true) }.frame(minWidth: 90, minHeight: 70)
        }.padding(3)
      }
    }
  }
  var controls: some View {
    VStack(alignment: .leading, spacing: 18) {
      timingControls
      Divider()
      canvasControls
      Divider()
      annotationControls
      Divider()
      exportControls
    }
  }
  var timingControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Timing").font(.headline)
      HStack { Text("Seconds"); TextField("Duration", value: $duration, format: .number).textFieldStyle(.roundedBorder) }
      Button("Apply to This Frame") { if let frame = activeFrame { change { $0.setDuration(duration, ids: [frame.id]) } } }
      Button("Apply to \(selectedFrames.count) Selected Frames") { change { $0.setDuration(duration, ids: selectedFrames) } }.disabled(selectedFrames.isEmpty)
      Button("Apply to All Frames") { change { $0.setDuration(duration) } }
      Picker("Speed", selection: binding(\.speed)) { Text("½×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0) }
      Picker("Playback", selection: binding(\.plays)) { Text("Loop Forever").tag(0); Text("Play Once").tag(1); Text("3 Plays").tag(3); Text("5 Plays").tag(5); if ![0,1,3,5].contains(project.plays) { Text("\(project.plays) Plays").tag(project.plays) } }
      if project.plays > 0 { Stepper("Total plays: \(project.plays)", value: binding(\.plays), in: 1...65535) }
      Text("Timing is rounded to 0.01 s, with a 0.1 s minimum.").font(.caption).foregroundStyle(.secondary)
    }
  }
  var canvasControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Canvas").font(.headline)
      Menu("Canvas Size") {
        Button("Square · 800 × 800") { change { $0.width = 800; $0.height = 800 } }
        Button("Landscape · 960 × 540") { change { $0.width = 960; $0.height = 540 } }
        Button("Portrait · 540 × 960") { change { $0.width = 540; $0.height = 960 } }
        Button("Original Aspect Ratio") { originalAspect() }
      }
      HStack {
        TextField("Width", value: binding(\.width), format: .number).accessibilityLabel("Canvas width")
        Text("×")
        TextField("Height", value: binding(\.height), format: .number).accessibilityLabel("Canvas height")
      }.textFieldStyle(.roundedBorder)
      Text("16–2,000 pixels per side").font(.caption).foregroundStyle(.secondary)
      Picker("Photo fitting", selection: binding(\.fit)) { ForEach(GIFFit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
      if let frame = activeFrame {
        DisclosureGroup("Crop This Frame") {
          Text("Zoom").font(.caption)
          Slider(value: frameCropBinding(frame.id, \.zoom), in: 1...10) { Text("Frame zoom") } onEditingChanged: { model.gifInteraction($0) }
          Text("Horizontal Position").font(.caption)
          Slider(value: frameCropBinding(frame.id, \.centerX), in: 0...1) { Text("Frame horizontal position") } onEditingChanged: { model.gifInteraction($0) }
          Text("Vertical Position").font(.caption)
          Slider(value: frameCropBinding(frame.id, \.centerY), in: 0...1) { Text("Frame vertical position") } onEditingChanged: { model.gifInteraction($0) }
          Button("Reset Frame Crop") { change { p in if let i = p.frames.firstIndex(where: { $0.id == frame.id }) { p.frames[i].crop = CropConfiguration() } } }
        }
      }
      ColorPicker("Background", selection: Binding(get: { Color(cgColor: project.background.cgColor) }, set: { color in
        if let rgba = colourComponents(color) { change { $0.background = rgba } }
      }), supportsOpacity: false)
    }
  }
  var annotationControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Captions & Annotations").font(.headline)
      Menu("Add Annotation") {
        ForEach([AnnotationKind.text, .arrow, .rectangle, .ellipse, .speechBubble], id: \.self) { kind in
          Button(kind.rawValue == "speechBubble" ? "Speech Bubble" : kind.rawValue.capitalized) {
            guard let frame = activeFrame else { return }
            var value = Annotation(); value.kind = kind; value.colour = RGBAColour(0, 0, 0, 1)
            let item = GIFAnnotation(annotation: value, frameIDs: [frame.id]); annotationID = item.id
            change { $0.annotations.append(item) }
          }
        }
      }
      ForEach(project.annotations) { item in
        Button { annotationID = item.id } label: { Label(item.annotation.kind.rawValue.capitalized + (item.annotation.kind == .text ? ": " + item.annotation.text : ""), systemImage: annotationID == item.id ? "checkmark.circle.fill" : "circle") }.lineLimit(1)
      }
      if let id = annotationID, let item = project.annotations.first(where: { $0.id == id }) {
        if item.annotation.kind == .text || item.annotation.kind == .speechBubble {
          TextField("Caption", text: annotationBinding(id, \.text), axis: .vertical).textFieldStyle(.roundedBorder)
        }
        Picker("Show", selection: Binding(get: { item.frameIDs == nil ? "All Frames" : item.extendsToNewFrames || (item.frameIDs?.count ?? 0) > 1 ? "Until Removed" : "This Frame" }, set: { value in
          setVisibility(value, id: id)
        })) {
          Text("This Frame").tag("This Frame"); Text("Until Removed").tag("Until Removed"); Text("All Frames").tag("All Frames")
        }
        Button("End Before This Frame") {
          change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) {
            p.annotations[i].extendsToNewFrames = false
            let prior = Set(p.frames.prefix(frameIndex).map(\.id))
            p.annotations[i].frameIDs = (p.annotations[i].frameIDs ?? Set(p.frames.map(\.id))).intersection(prior)
          } }
        }
        ColorPicker("Colour", selection: Binding(get: { Color(cgColor: item.annotation.colour.cgColor) }, set: { color in
          if let rgba = colourComponents(color) { change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) { p.annotations[i].annotation.colour = rgba } } }
        }), supportsOpacity: false)
        Text("Drag the selected annotation to move it. Drag its corner to resize.").font(.caption).foregroundStyle(.secondary)
        Button("Remove Annotation", role: .destructive) { change { $0.annotations.removeAll { $0.id == id } }; annotationID = nil }
      }
    }
  }
  var exportControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Export GIF").font(.headline)
      TextField("Filename", text: binding(\.name)).textFieldStyle(.roundedBorder)
      Picker("Optimisation", selection: binding(\.preset)) { ForEach(GIFPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        .onChange(of: project.preset) { _, preset in
          change { p in let factor = Double(preset.maximumDimension) / Double(max(p.width, p.height, 1)); p.width = max(16, Int(Double(p.width) * factor)); p.height = max(16, Int(Double(p.height) * factor)) }
        }
      Text("Presets change dimensions. GIF uses up to 256 colours per frame; gradients may show banding. File size is measured after export.").font(.caption).foregroundStyle(.secondary)
      Button("Export GIF…", systemImage: "square.and.arrow.up") { export() }.buttonStyle(.borderedProminent)
        .disabled((try? project.validate()) == nil || preparing)
      Text("Saved automatically in this workspace.").font(.caption).foregroundStyle(.secondary)
    }
  }
  func setVisibility(_ value: String, id: UUID) {
    guard let frame = activeFrame else { return }
    change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) {
      p.annotations[i].extendsToNewFrames = value == "Until Removed"
      p.annotations[i].frameIDs = value == "All Frames" ? nil : value == "This Frame" ? [frame.id] : Set(p.frames.dropFirst(frameIndex).map(\.id))
    } }
  }
  func change(_ edit: (inout GIFProject) -> Void) {
    playing = false
    let activeID = activeFrame?.id
    var p = project; edit(&p); model.updateGIF(p)
    frameIndex = activeID.flatMap { id in p.frames.firstIndex(where: { $0.id == id }) } ?? min(frameIndex, max(0, p.frames.count - 1))
    selectedFrames.formIntersection(Set(p.frames.map(\.id))); model.persist()
  }
  func binding<T>(_ path: WritableKeyPath<GIFProject, T>) -> Binding<T> {
    Binding(get: { project[keyPath: path] }, set: { value in change { $0[keyPath: path] = value } })
  }
  func frameCropBinding(_ id: UUID, _ path: WritableKeyPath<CropConfiguration, Double>) -> Binding<Double> {
    Binding(get: { project.frames.first { $0.id == id }?.crop[keyPath: path] ?? CropConfiguration()[keyPath: path] },
      set: { value in change { p in if let i = p.frames.firstIndex(where: { $0.id == id }) { p.frames[i].crop[keyPath: path] = value } } })
  }
  func annotationBinding<T>(_ id: UUID, _ path: WritableKeyPath<Annotation, T>) -> Binding<T> {
    let fallback = Annotation()[keyPath: path]
    return Binding(get: { project.annotations.first { $0.id == id }?.annotation[keyPath: path] ?? fallback }, set: { value in change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) { p.annotations[i].annotation[keyPath: path] = value } } })
  }
  func preparePreview() async {
    playing = false; preview?.remove(); preview = nil; previewError = nil
    guard !project.frames.isEmpty, previewAllowed else { preparing = false; image = nil; return }
    preparing = true
    do {
      try await Task.sleep(for: .milliseconds(180))
      let value = try await previewBuilder.prepare(project, sources: model.assets, privateMode: model.privateEditing)
      guard !Task.isCancelled else { value.remove(); return }
      preview = value; preparing = false; await loadCurrentFrame()
    } catch is CancellationError {} catch { previewError = error.localizedDescription; preparing = false }
  }
  func loadCurrentFrame() async {
    guard let preview, preview.frames.indices.contains(frameIndex) else { return }
    let url = preview.frames[frameIndex]
    let value = await Task.detached { () -> CGImage? in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }.value
    guard !Task.isCancelled else { return }; image = value
  }
  func playback() async {
    let clock = ContinuousClock(); var deadline = clock.now; var cycles = 0
    do {
      while !Task.isCancelled, playing, let frame = activeFrame {
        deadline += .seconds(project.timing(for: frame))
        try await clock.sleep(until: deadline)
        if frameIndex + 1 >= project.frames.count {
          cycles += 1
          if project.plays > 0 && cycles >= project.plays { playing = false; return }
          frameIndex = 0
        } else { frameIndex += 1 }
      }
    } catch {}
  }
  func orderByDate() {
    let original = project
    Task {
      do {
        let info = try await WorkspaceMetadataReader().read(model.assets)
        guard project == original else { return }
        change { p in p.frames = p.frames.enumerated().sorted { a, b in
          let lhs = info[a.element.sourceID]?.date ?? .distantFuture, rhs = info[b.element.sourceID]?.date ?? .distantFuture
          return lhs == rhs ? a.offset < b.offset : lhs < rhs
        }.map(\.element) }
      } catch { model.issues.append(error.localizedDescription) }
    }
  }
  func originalAspect() {
    guard let frame = activeFrame, let asset = model.assets.first(where: { $0.id == frame.sourceID }) else { return }
    let identity = project.id
    Task { do { let size = try await model.processor.identify(asset.url); guard project.id == identity, activeFrame?.id == frame.id else { return }; change { p in let scale = 800 / max(size.width, size.height); p.width = max(16, Int(size.width * scale)); p.height = max(16, Int(size.height * scale)) } } catch { model.issues.append(error.localizedDescription) } }
  }
  func colourComponents(_ colour: Color) -> RGBAColour? {
    let c = colour.resolve(in: environment)
    return RGBAColour(Double(c.red), Double(c.green), Double(c.blue), 1)
  }
  func export() {
    #if os(macOS)
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "Export GIF"
    if panel.runModal() == .OK, let url = panel.url { model.exportGIF(to: url) }
    #else
    model.exportGIF(to: model.directory.deletingLastPathComponent().appendingPathComponent("Exports"))
    #endif
  }
}

private struct GIFSourceThumbnail: View {
  let asset: SourceAsset
  let processor: ImageProcessor
  @State private var image: CGImage?
  var body: some View {
    Group { if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() } else { Image(systemName: "photo") } }
      .frame(width: 70, height: 54)
      .task(id: asset) { image = try? await processor.thumbnail(asset.url, maximum: 140) }
  }
}
private struct GIFAnnotationHandles: View {
  let annotation: Annotation
  let canvas: CGSize
  let interaction: (Bool) -> Void
  let update: (Annotation) -> Void
  @State private var start: Annotation?
  var body: some View {
    Rectangle().fill(.clear).contentShape(Rectangle())
      .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5])))
      .frame(width: annotation.width * canvas.width, height: annotation.height * canvas.height)
      .overlay(alignment: .bottomTrailing) {
        Circle().fill(Color.accentColor).frame(width: 24, height: 24)
          .gesture(DragGesture().onChanged { value in
            if start == nil { start = annotation; interaction(true) }
            guard var a = start else { return }
            a.width = min(1 - a.x, max(0.03, a.width + value.translation.width / canvas.width))
            a.height = min(1 - a.y, max(0.03, a.height + value.translation.height / canvas.height)); update(a)
          }.onEnded { _ in start = nil; interaction(false) })
          .accessibilityLabel("Resize annotation")
      }
      .position(x: (annotation.x + annotation.width / 2) * canvas.width, y: (annotation.y + annotation.height / 2) * canvas.height)
      .gesture(DragGesture().onChanged { value in
        if start == nil { start = annotation; interaction(true) }
        guard var a = start else { return }
        a.x = min(1 - a.width, max(0, a.x + value.translation.width / canvas.width))
        a.y = min(1 - a.height, max(0, a.y + value.translation.height / canvas.height)); update(a)
      }.onEnded { _ in start = nil; interaction(false) })
      .accessibilityLabel("Selected annotation")
      .onDisappear { if start != nil { interaction(false) } }
  }
}

private struct GIFPreviewInput: Equatable { var project: GIFProject; var sources: [SourceAsset]; var allowed: Bool }
