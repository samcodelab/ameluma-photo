import SwiftUI
import FramepebbleCore
import ImageIO
#if os(macOS)
import AppKit
#endif

/// Transient editor focus, never persisted as project settings or operation inputs.
struct GIFEditorFocus {
  var projectID: UUID?
  var frameIndex = 0
  var selectedFrames: Set<UUID> = []
  var annotationID: UUID?
  var selectingFrames = false
  mutating func reconcile(projectID: UUID, frames: [UUID]) {
    if self.projectID != projectID {
      self.projectID = projectID
      frameIndex = 0; selectedFrames = []; annotationID = nil; selectingFrames = false
    }
    frameIndex = min(max(0, frameIndex), max(0, frames.count - 1))
    selectedFrames.formIntersection(Set(frames))
  }
}

enum GIFControlSummary {
  static func duration(frames: [GIFFrame], ids: Set<UUID>) -> Double? {
    let values = frames.filter { ids.contains($0.id) }.map(\.duration)
    guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.0001 }) else { return nil }
    return first
  }
  static func visibleIndices(_ item: GIFAnnotation, frames: [GIFFrame]) -> [Int] {
    frames.indices.filter { item.frameIDs?.contains(frames[$0].id) ?? true }
  }
  static func coverage(_ item: GIFAnnotation, frames: [GIFFrame]) -> String {
    if item.frameIDs == nil { return "All Frames" }
    let numbers = visibleIndices(item, frames: frames).map { String($0 + 1) }
    return numbers.isEmpty ? "Not visible" : "Frames " + numbers.joined(separator: ", ")
  }
}

enum CreationOutputSummary {
  static func gif(_ project: GIFProject) -> String {
    let photos = Set(project.frames.map(\.sourceID)).count
    return "\(project.frames.count) \(project.frames.count == 1 ? "frame" : "frames") · \(photos) source \(photos == 1 ? "photo" : "photos") · GIF · \(project.width) × \(project.height) px"
  }
  static func collage(_ project: CollageProject) -> String {
    let photos = Set(project.cells.map(\.sourceID)).count
    return "\(project.cells.count) photo \(project.cells.count == 1 ? "cell" : "cells") · \(photos) source \(photos == 1 ? "photo" : "photos") · \(project.outputFormat.rawValue.uppercased()) · \(project.width) × \(project.height) px"
  }
}

struct GIFEditor: View {
  @Bindable var model: Workspace
  var importAction: () -> Void
  enum Inspector: String, CaseIterable { case timing = "Timing", canvas = "Canvas", text = "Text" }
  @State private var stickerPicker = false
  @State private var stickerFrameID: UUID?
  @State private var inspector = Inspector.timing
  @State private var exportingOptions = false
  @State private var expandedControls = false
  @State private var layoutViewport = EditorPanelViewport()
  @State private var focus = GIFEditorFocus()
  var selectingFrames: Bool { get { focus.selectingFrames } nonmutating set { focus.selectingFrames = newValue } }
  @State private var frameSelectionPresented = false
  var selectedFrames: Set<UUID> { get { focus.selectedFrames } nonmutating set { focus.selectedFrames = newValue } }
  var frameIndex: Int { get { focus.frameIndex } nonmutating set { focus.frameIndex = newValue } }
  @State private var playing = false
  @State private var playbackGeneration = 0
  @State private var previewSession = GIFPreviewSession()
  var preview: GIFPreview? { previewSession.input == previewInput ? previewSession.preview : nil }
  var image: CGImage? { previewSession.image(for: previewInput, frameID: activeFrame?.id) }
  var previewError: String? { previewSession.input == previewInput ? previewSession.error : nil }
  var preparing: Bool { previewSession.input != previewInput || previewSession.preparing }
  var previewInput: GIFPreviewInput { GIFPreviewInput(project: project, sources: model.assets, allowed: previewAllowed) }
  @State private var previewAllowed = true
  @State private var duration = 0.5
  enum EditingField: Hashable { case duration, width, height, caption, filename }
  @FocusState private var focusedField: EditingField?
  @State private var writingField = false
  @State private var fieldEditingProjectID: UUID?
  var annotationID: UUID? { get { focus.annotationID } nonmutating set { focus.annotationID = newValue } }
  @State private var draggedFrame: String?
  @State private var showNew = false
  @Environment(\.scenePhase) private var phase
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.self) private var environment
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var previewBuilder = GIFPreviewBuilder()
  @State private var emptyProject = GIFProject()
  var project: GIFProject { model.gifProject ?? emptyProject }
  var activeFrame: GIFFrame? { project.frames.indices.contains(frameIndex) ? project.frames[frameIndex] : nil }
  var recoveryFrame: GIFFrame? { project.frames.first { $0.id == previewSession.failedFrameID } ?? activeFrame }
  var recoveryFrameNumber: Int { project.frames.firstIndex(where: { $0.id == recoveryFrame?.id }).map { $0 + 1 } ?? 1 }
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
          let viewportHeight = layoutViewport.height(fallback: geometry.size.height)
          if !compact && EditorPanelLayout.supportsInspector(geometry.size.width) {
            HStack(spacing: 0) {
              VStack { header; canvas; transport; frameStrip }.padding(12)
              Divider()
              VStack(spacing: 0) {
                inspectorPicker.padding(12)
                ScrollView { controls.padding(12) }
              }.frame(width: EditorPanelLayout.inspectorWidth).editorInspectorSurface()
            }
          } else {
            VStack(spacing: 8) {
              header
              canvas.frame(maxHeight: .infinity)
              if viewportHeight >= 480 || typeSize.isAccessibilitySize { transport }
              if EditorPanelLayout.expandedControls(height: viewportHeight, accessibility: typeSize.isAccessibilitySize) {
                HStack {
                  if viewportHeight < 480 && !typeSize.isAccessibilitySize { playbackButtons.labelStyle(.iconOnly) }
                  frameChooser
                  Spacer()
                  Menu("Tools", systemImage: "slider.horizontal.3") {
                    ForEach(Inspector.allCases, id: \.self) { tool in Button(tool.rawValue) { inspector = tool; expandedControls = true } }
                  }
                }
              } else {
                frameStrip
                compactProperties
              }
            }.padding(12)
              .onAppear { layoutViewport.observe(geometry.size) }
              .onChange(of: geometry.size.width) { _, _ in layoutViewport.observe(geometry.size) }
          }
        }
      }
    }
    .sheet(isPresented: $exportingOptions) {
      NavigationStack { ScrollView { exportControls.padding() }.navigationTitle("Output Settings")
        .toolbar { Button("Done") { exportingOptions = false } } }
        .frame(minWidth: 300)
    #if os(macOS)
    .frame(minHeight: 360)
    #endif
    }
    .sheet(isPresented: $frameSelectionPresented) {
      NavigationStack {
        List {
          ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
            Toggle("Frame \(index + 1)", isOn: Binding(get: { selectedFrames.contains(frame.id) }, set: { included in
              if included { selectedFrames.insert(frame.id) } else { selectedFrames.remove(frame.id) }
            }))
          }
        }.navigationTitle("Select Frames").toolbar { Button("Done") { frameSelectionPresented = false } }
      }
    }
    .sheet(isPresented: $expandedControls) {
      NavigationStack { ScrollView { controls.padding() }.navigationTitle(inspector.rawValue)
        .toolbar { Button("Done") { expandedControls = false } } }
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
    .onChange(of:model.creationActionRequest?.id) {_,_ in
      guard let request=model.creationActionRequest, model.contextIsCurrent(request.context) else {return}
      model.creationActionRequest=nil
      if request.intent == .export {export()}
    }
    .onChange(of: project.id, initial: true) { _, _ in
      finishFieldEditing(); focusedField = nil
      focus.reconcile(projectID: project.id, frames: project.frames.map(\.id)); playing = false
    }
    .onChange(of: project.frames.map(\.id)) { _, frames in
      focus.reconcile(projectID: project.id, frames: frames)
    }
    .task(id: previewInput) { await preparePreview() }
    .task(id: frameIndex) { await loadCurrentFrame() }
    .task(id: "\(playing)-\(playbackGeneration)") { if playing { await playback() } }
    .onChange(of: phase) { _, value in if value == .background { playing = false; previewAllowed = false } else if value == .active { previewAllowed = true } }
    .onChange(of: frameIndex) { _, _ in finishFieldEditing(); focusedField = nil }
    .onChange(of: selectedFrames) { _, _ in finishFieldEditing(); focusedField = nil }
    .onChange(of: annotationID) { _, _ in finishFieldEditing(); focusedField = nil }
    .onChange(of: focusedField) { _, _ in finishFieldEditing() }
    .onDisappear { finishFieldEditing(); playing = false; previewSession.invalidate() }
    .confirmationDialog("Start a new GIF?", isPresented: $showNew) {
      Button("Save Project Instructions & Start New") {
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
      if model.workspaceAssets.isEmpty { Button("Add Photos", action: importAction) }
      savedGIFMenu
    }
  }
  var availableSavedGIFs: [GIFProject] { model.archivedGIFs.filter { $0.id != model.gifProject?.id || project.frames.isEmpty } }
  var savedGIFMenu: some View {
    Menu("Saved GIFs") {
      ForEach(availableSavedGIFs) { saved in Button(saved.name) { finishFieldEditing(); focusedField = nil; model.openGIF(saved) } }
    }.disabled(availableSavedGIFs.isEmpty)
  }
  var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !(project.reviewFrameIDs ?? []).isEmpty {
        Label("Source replaced · review framing in \((project.reviewFrameIDs ?? []).count) frames", systemImage: "exclamationmark.triangle").font(.caption)
        if !(project.privacyReviewFrameIDs ?? []).isEmpty { Text("Review captured mask coverage in \((project.privacyReviewFrameIDs ?? []).count) frames.").font(.caption) }
        Button("I’ve Reviewed These Frames") { change { $0.reviewFrameIDs = nil; $0.privacyReviewFrameIDs = nil } }.disabled(preparing || preview == nil || previewError != nil)
      }
      HStack(spacing: 6) {
        Button("Add Photos", systemImage: "photo.badge.plus") { finishFieldEditing(); focusedField = nil; model.selectGIFPhotos(adding: true) }.font(.callout).fixedSize(horizontal: true, vertical: false).foregroundStyle(.primary)
        moreMenu.foregroundStyle(.primary)
        Spacer(minLength: 4)
        historyButtons.foregroundStyle(.primary)
        gifExportButton
      }.buttonStyle(.borderless)
    }
  }
  var hasPendingFieldEdit: Bool {
    fieldEditingProjectID == project.id && model.gifInteractionStart.map { $0 != project } == true
  }
  var historyButtons: some View {
    HStack {
      Button("Undo", systemImage: "arrow.uturn.backward") { finishFieldEditing(); focusedField = nil; model.undoActiveWorkspace() }.labelStyle(.iconOnly).disabled(!model.canUndoActiveWorkspace && !hasPendingFieldEdit)
      Button("Redo", systemImage: "arrow.uturn.forward") { finishFieldEditing(); focusedField = nil; model.redoActiveWorkspace() }.labelStyle(.iconOnly).disabled(!model.canRedoActiveWorkspace || hasPendingFieldEdit)
    }
  }
  var moreMenu: some View {
    Menu {
      if !availableSavedGIFs.isEmpty { Menu("Saved GIFs") { ForEach(availableSavedGIFs) { saved in Button(saved.name) { finishFieldEditing(); focusedField = nil; model.openGIF(saved) } } } }
      Button("Output Settings…", systemImage: "slider.horizontal.3") { finishFieldEditing(); focusedField = nil; exportingOptions = true }
      Button("New GIF…") { finishFieldEditing(); focusedField = nil; showNew = true }
      Button("Save Project Instructions") { finishFieldEditing(); focusedField = nil; Task { do { _ = try await model.saveProjectCopy(); model.status = "Workspace and GIF saved." } catch { model.issues.append(error.localizedDescription) } } }
    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("GIF actions")
  }
  var gifExportButton: some View {
    Button("Export…") { finishFieldEditing(); focusedField = nil; exportingOptions = true }.buttonStyle(.borderedProminent).disabled(project.frames.isEmpty || previewError != nil || preparing)
  }
  var compactProperties: some View {
    VStack(spacing: 4) {
      HStack {
        if let frame = activeFrame {
          Text("Duration").font(.caption)
          durationEditor.frame(maxWidth: 80).comfortableHitTarget()
          Text("s").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Menu("Options", systemImage: "slider.horizontal.3") {
          ForEach(Inspector.allCases, id: \.self) { tool in
            Button(tool.rawValue) { inspector = tool; expandedControls = true }
          }
        }
      }
    }.padding(.vertical, 4)
  }
  var inspectorPicker: some View {
    Picker("GIF tool", selection: $inspector) {
      ForEach(Inspector.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }.pickerStyle(.segmented).accessibilityIdentifier("gif.toolPicker")
  }
  var canvas: some View {
    GeometryReader { geometry in
      if let previewError {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            Text(previewError).font(.callout)
            Button("Replace Frame \(recoveryFrameNumber)’s Photo") { if let frame = recoveryFrame { model.selectGIFPhotos(replacing: frame.id) } }.comfortableHitTarget()
            Button("Locate Frame \(recoveryFrameNumber)’s Photo…") { if let frame = recoveryFrame { model.relinkSourceID = frame.sourceID } }.comfortableHitTarget()
          }.padding()
        }
      } else {
      let aspect = Double(max(16, min(2000, project.width))) / Double(max(16, min(2000, project.height)))
      let width = min(geometry.size.width, geometry.size.height * aspect)
      let height = width / aspect
      ZStack {
        Color.black.opacity(0.04)
        if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
        if preparing { ProgressView("Preparing preview…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
        if !playing, let id = annotationID, let item = project.annotations.first(where: { $0.id == id }), let frame = activeFrame,
          item.frameIDs?.contains(frame.id) ?? true {
          GIFAnnotationHandles(annotation: item.annotation, canvas: CGSize(width: width, height: height), interaction: model.gifInteraction) { value in
            change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) { p.annotations[i].annotation = value } }
          }
        }
      }.frame(width: width, height: height).clipped()
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
      }
    }.frame(minHeight: 100).background { EditorCanvasBackground() }.accessibilityElement(children: .contain).accessibilityLabel("GIF preview, frame \(frameIndex + 1) of \(project.frames.count)")
  }
  var transport: some View {
    VStack(alignment: .leading, spacing: 8) {
      if typeSize.isAccessibilitySize {
        HStack { playbackButtons.labelStyle(.iconOnly); Spacer() }
        playbackSummary
      } else {
        HStack { playbackButtons.labelStyle(.iconOnly); Spacer(); playbackSummary }
      }
    }.buttonStyle(.borderless).foregroundStyle(.primary)
  }
  var playbackButtons: some View {
    Group {
      Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") { playing.toggle() }.disabled(preparing || preview == nil)
      Button("Restart", systemImage: "backward.end.fill") { frameIndex = 0; playing = true; playbackGeneration += 1 }.disabled(preparing || preview == nil)
    }
  }
  var playbackSummary: some View {
    Text("\(project.frames.count) \(project.frames.count == 1 ? "frame" : "frames") · \(project.duration, specifier: "%.2f") s").font(.caption).monospacedDigit()
  }
  var frameStrip: some View {
    VStack(alignment: .leading) {
      HStack {
        Text(selectingFrames ? "\(selectedFrames.count) frames selected" : "Frame \(frameIndex + 1) of \(project.frames.count)").font(.caption).foregroundStyle(.secondary)
        Button(selectingFrames ? "Done" : "Select") { selectingFrames.toggle(); if !selectingFrames { selectedFrames = [] } }.font(.caption)
        Spacer()
        Menu("Frame \(frameIndex + 1)", systemImage: "ellipsis.circle") {
          if let frame = activeFrame {
            Text("Frame \(frameIndex + 1)")
            frameActions(frame, index: frameIndex)
          }
          if selectingFrames && !selectedFrames.isEmpty {
            Divider()
            Button("Remove \(selectedFrames.count) Selected Frames", role: .destructive) {
              let ids = selectedFrames
              change { $0.remove(ids) }; selectedFrames = []
            }
          }
        }.foregroundStyle(.primary).accessibilityLabel("Actions for Frame \(frameIndex + 1)").accessibilityIdentifier("gif.frameActions")
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
        }.foregroundStyle(.primary)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
            VStack(spacing: 4) {
              Button { playing = false; frameIndex = index; if selectingFrames { if !selectedFrames.insert(frame.id).inserted { selectedFrames.remove(frame.id) } } } label: {
                VStack {
                  if let asset = model.assets.first(where: { $0.id == frame.sourceID }) { GIFSourceThumbnail(asset: asset, processor: model.processor) }
                  else { Image(systemName: "photo.badge.exclamationmark").frame(width: 70, height: 54) }
                  Text("\(index + 1) · \(project.timing(for: frame), specifier: "%.2f")s").font(.caption2)
                }.padding(5).editorSelectionSurface(selected: selectedFrames.contains(frame.id), idleOpacity: 0.04)
                  .overlay(RoundedRectangle(cornerRadius: 8).stroke(frameIndex == index ? Color.accentColor : .clear, lineWidth: 2))
              }.overlay(alignment: .topTrailing) {
                if previewSession.failedFrameID == frame.id { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Preview failed for this frame") }
                else if selectingFrames && selectedFrames.contains(frame.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
              }.buttonStyle(.plain).accessibilityLabel("Frame \(index + 1), \(project.timing(for: frame)) seconds")
              // Frame actions are visible in the strip header; long-press/right-click is a shortcut.

            }
            .contextMenu { frameActions(frame, index: index) }
            .draggable(frame.id.uuidString)
            .dropDestination(for: String.self) { ids, _ in
              guard let raw = ids.first, let id = UUID(uuidString: raw) else { return false }
              change { $0.move(id, before: frame.id) }; return true
            }
          }
        }.padding(3)
      }
    }
  }
  @ViewBuilder func frameActions(_ frame: GIFFrame, index: Int) -> some View {
                Button("Duplicate") { change { $0.duplicate(frame.id) } }
                Button("Move Earlier") { if index > 0 { change { $0.move(frame.id, before: $0.frames[index - 1].id) } } }.disabled(index == 0)
                Button("Move Later") { if index + 1 < project.frames.count { change { $0.move($0.frames[index + 1].id, before: frame.id) } } }.disabled(index + 1 == project.frames.count)
                Button("Replace Photo") { finishFieldEditing(); focusedField = nil; model.selectGIFPhotos(replacing: frame.id) }
                Button("Remove", role: .destructive) { change { $0.remove([frame.id]) }; selectedFrames.remove(frame.id) }
  }
  var frameChooser: some View {
    Menu(selectingFrames ? "\(selectedFrames.count) Selected" : "Frame \(frameIndex + 1) of \(project.frames.count)") {
      ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
        Button("Frame \(index + 1)") { playing = false; frameIndex = index }
      }
      Divider()
      if let frame = activeFrame { frameActions(frame, index: frameIndex) }
      Button("Add Photos") { finishFieldEditing(); focusedField = nil; model.selectGIFPhotos(adding: true) }
      Button("Select Frames…") { selectingFrames = true; frameSelectionPresented = true }
      if selectingFrames {
        if !selectedFrames.isEmpty {
          Button("Remove \(selectedFrames.count) Selected Frames", role: .destructive) {
            let ids = selectedFrames
            change { $0.remove(ids) }; selectedFrames = []
          }
        }
        Button("Finish Frame Selection") { selectingFrames = false; selectedFrames = [] }
      }
    }
  }
  var controls: some View {
    VStack(alignment: .leading, spacing: 18) {
      switch inspector {
      case .timing: timingControls
      case .canvas: canvasControls
      case .text: annotationControls
      }
    }
  }
  var durationTargetIDs: Set<UUID> { selectingFrames ? selectedFrames : Set(activeFrame.map { [$0.id] } ?? []) }
  var commonDuration: Double? { GIFControlSummary.duration(frames: project.frames, ids: durationTargetIDs) }
  var durationEditor: some View {
    TextField(commonDuration == nil ? "Mixed" : "Duration", value: Binding<Double?>(get: { commonDuration }, set: { value in
      guard let value, value.isFinite, !durationTargetIDs.isEmpty else { return }
      editField { change { $0.setDuration(value, ids: durationTargetIDs) } }
    }), format: .number.precision(.fractionLength(2)))
      .textFieldStyle(.roundedBorder).focused($focusedField, equals: .duration).disabled(durationTargetIDs.isEmpty)
      .accessibilityLabel(selectingFrames ? "Duration for \(selectedFrames.count) selected frames in seconds" : "Frame duration in seconds")
      .accessibilityValue(commonDuration.map { String(format: "%.2f seconds", $0) } ?? (durationTargetIDs.isEmpty ? "No frames selected" : "Mixed durations"))
  }
  var timingControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      InspectorHeading(title: selectingFrames ? "Selected frames" : "Frame \(frameIndex + 1)")
      InspectorMenuRow(title: "Duration (s)") {
        durationEditor.frame(maxWidth: 100)

      }
      Text(selectingFrames ? "Changes \(selectedFrames.count) selected frames" : "Changes this frame only").font(.caption).foregroundStyle(.secondary)
      Button("Apply This Duration to All Frames") {
        if let value = commonDuration { change { $0.setDuration(value) } }
      }.disabled(commonDuration == nil)
      InspectorMenuRow(title: "Speed") {
        Picker("Speed", selection: binding(\.speed)) { Text("½×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0) }.labelsHidden()
      }
      InspectorMenuRow(title: "Playback") { Picker("Playback", selection: binding(\.plays)) { Text("Loop Forever").tag(0); Text("Play Once").tag(1); Text("3 Plays").tag(3); Text("5 Plays").tag(5); if ![0,1,3,5].contains(project.plays) { Text("\(project.plays) Plays").tag(project.plays) } }.labelsHidden() }
      if project.plays > 0 { Stepper("Total plays: \(project.plays)", value: binding(\.plays), in: 1...65535) }
      Text("Timing is rounded to 0.01 s, with a 0.1 s minimum.").font(.caption).foregroundStyle(.secondary)
    }
  }
  var canvasControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      InspectorHeading(title: "GIF Canvas", subtitle: "Applies to the whole animation")
      Menu("Canvas Size") {
        Button("Square · 800 × 800") { change { $0.width = 800; $0.height = 800 } }
        Button("Landscape · 960 × 540") { change { $0.width = 960; $0.height = 540 } }
        Button("Portrait · 540 × 960") { change { $0.width = 540; $0.height = 960 } }
        Button("Match Source Aspect") { originalAspect() }
      }
      InspectorMenuRow(title: "Width (px)") { TextField("Width", value: fieldBinding(\.width), format: .number).focused($focusedField, equals: .width).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
      InspectorMenuRow(title: "Height (px)") { TextField("Height", value: fieldBinding(\.height), format: .number).focused($focusedField, equals: .height).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
      Text("16–2,000 pixels per side").font(.caption).foregroundStyle(.secondary)
      Picker("Photo fitting", selection: binding(\.fit)) { ForEach(GIFFit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
      if let frame = activeFrame {
        DisclosureGroup("Crop This Frame") {
          InspectorSlider(title: "Zoom", value: frameCropBinding(frame.id, \.zoom), range: 1...10, interaction: model.gifInteraction)
          InspectorSlider(title: "Horizontal", value: frameCropBinding(frame.id, \.centerX), range: 0...1, percentage: true, interaction: model.gifInteraction)
          InspectorSlider(title: "Vertical", value: frameCropBinding(frame.id, \.centerY), range: 0...1, percentage: true, interaction: model.gifInteraction)
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
      Button("Add Sticker", systemImage: "face.smiling") { stickerFrameID = activeFrame?.id; stickerPicker = true }
        .disabled(activeFrame == nil)
        .sheet(isPresented: $stickerPicker) {
          StickerPicker { sticker in
            guard let frameID = stickerFrameID, project.frames.contains(where: { $0.id == frameID }) else { return }
            var annotation = Annotation(); annotation.kind = .sticker; annotation.stickerID = sticker.id
            annotation.width = 0.4; annotation.height = min(0.7, 0.4 * Double(project.width) / Double(max(1, project.height)) / sticker.aspectRatio)
            annotation.x = (1-annotation.width)/2; annotation.y = (1-annotation.height)/2
            let item = GIFAnnotation(annotation: annotation, frameIDs: [frameID]); annotationID = item.id
            change { $0.annotations.append(item) }
          }
        }

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
        Button { annotationID = item.id } label: {
          VStack(alignment: .leading) {
            Label((item.annotation.kind == .sticker ? (StickerCatalog.sticker(item.annotation.stickerID ?? "")?.name ?? "Unavailable Sticker") : item.annotation.kind.title) + (item.annotation.kind == .text ? ": " + item.annotation.text : ""), systemImage: annotationID == item.id ? "checkmark.circle.fill" : "circle").lineLimit(1)
            Text(GIFControlSummary.coverage(item, frames: project.frames)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        }
      }
      if let id = annotationID, let item = project.annotations.first(where: { $0.id == id }) {
        let visibleIndices = GIFControlSummary.visibleIndices(item, frames: project.frames)
        if !visibleIndices.contains(frameIndex) {
          Text("This annotation is not visible on Frame \(frameIndex + 1).").font(.caption).foregroundStyle(.secondary)
          if let first = visibleIndices.first {
            Button("Go to Frame \(first + 1)") { playing = false; frameIndex = first }
          }
        }
        if item.annotation.kind == .text || item.annotation.kind == .speechBubble {
          TextField("Caption", text: Binding(get: { item.annotation.text }, set: { value in editField { annotationBinding(id, \.text).wrappedValue = value } }), axis: .vertical).textFieldStyle(.roundedBorder).focused($focusedField, equals: .caption)
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
        .disabled(!visibleIndices.contains(where: { $0 < frameIndex }) || !visibleIndices.contains(where: { $0 >= frameIndex }))
        if item.annotation.kind != .sticker {
        ColorPicker("Colour", selection: Binding(get: { Color(cgColor: item.annotation.colour.cgColor) }, set: { color in
          if let rgba = colourComponents(color) { change { p in if let i = p.annotations.firstIndex(where: { $0.id == id }) { p.annotations[i].annotation.colour = rgba } } }
        }), supportsOpacity: false)
        }
        Text("Drag the selected annotation to move it. Drag its corner to resize.").font(.caption).foregroundStyle(.secondary)
        Button("Remove Annotation", role: .destructive) { change { $0.annotations.removeAll { $0.id == id } }; annotationID = nil }
      }
    }
  }
  var exportControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(CreationOutputSummary.gif(project)).font(.callout).monospacedDigit()
      #if os(macOS)
      Text("Destination: choose a folder after Export GIF.").font(.caption).foregroundStyle(.secondary)
      #else
      Text("Destination: local Exports folder, then Review & Share.").font(.caption).foregroundStyle(.secondary)
      #endif
      TextField("Filename", text: fieldBinding(\.name)).textFieldStyle(.roundedBorder).focused($focusedField, equals: .filename)
      InspectorMenuRow(title: "Size Preset") {
        Picker("Size Preset", selection: binding(\.preset)) { ForEach(GIFPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
      }.onChange(of: project.preset) { _, preset in
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
  func finishFieldEditing() {
    guard let editingID = fieldEditingProjectID else { return }
    fieldEditingProjectID = nil
    if model.gifInteractionStart?.id == editingID {
      if model.gifProject?.id == editingID { model.gifInteraction(false) }
      else { model.gifInteractionStart = nil }
    }
  }
  func editField(_ edit: () -> Void) {
    if fieldEditingProjectID == nil { model.gifInteraction(true); fieldEditingProjectID = project.id }
    writingField = true; edit(); writingField = false
  }
  func fieldBinding<T>(_ path: WritableKeyPath<GIFProject, T>) -> Binding<T> {
    Binding(get: { project[keyPath: path] }, set: { value in editField { change { $0[keyPath: path] = value } } })
  }
  func change(_ edit: (inout GIFProject) -> Void) {
    if !writingField { finishFieldEditing(); focusedField = nil }
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
    playing = false
    let captured = project, sources = model.assets, allowed = previewAllowed
    await previewSession.prepare(project: captured, sources: sources, allowed: allowed) {
      try await Task.sleep(for: .milliseconds(180))
      return try await previewBuilder.prepare(captured, sources: sources, privateMode: model.privateEditing)
    }
    guard !Task.isCancelled, project == captured else { return }
    await loadCurrentFrame()
  }
  func loadCurrentFrame() async { await previewSession.load(index: frameIndex, project: project) }
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
    finishFieldEditing(); focusedField = nil
    // Keep progress and cancellation visible in the editor during encoding.
    exportingOptions = false
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
