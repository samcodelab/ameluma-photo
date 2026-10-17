import FramepebbleCore
import SwiftUI

extension Workspace {
  func openColourReplacement(_ asset: SourceAsset, editingID: UUID? = nil) {
    guard !overlayEditor, !running, assets.contains(asset) else { return }
    let edits = configuration(for: asset).colourReplacements
    colourReplacementID = editingID ?? (edits.count >= ColourReplacement.maximumEdits ? edits.first?.id : nil); colourReplacementAsset = asset; overlayEditor = true
  }

  func commitColourReplacement(_ replacement: ColourReplacement, asset: SourceAsset, baseline: ProcessingConfiguration, sessionID: UUID, replacingID: UUID? = nil) -> Bool {
    guard sessionID == sourceSessionID, assets.contains(asset), configuration(for: asset) == baseline,
          (try? replacement.validate()) != nil else { return false }
    var value = baseline
    if let replacingID {
      guard let index = value.colourReplacements.firstIndex(where: { $0.id == replacingID }), replacement.id == replacingID else { return false }
      value.colourReplacements[index] = replacement
    } else {
      guard value.colourReplacements.count < ColourReplacement.maximumEdits else { return false }
      value.colourReplacements.append(replacement)
    }
    applyChange(ConfigurationPatch(values: value, fields: [.colourReplacements]), ids: [asset.id])
    return true
  }
}

struct PhotoDraftWorkspace: View {
  @Bindable var model: Workspace
  var embedded = true
  var body: some View {
    if let asset = model.colourReplacementAsset {
      ColourReplacementEditor(model: model, asset: asset, editingID: model.colourReplacementID, embedded: embedded).id(model.colourReplacementID)
    } else { OverlayEditor(model: model, embedded: embedded) }
  }
}

enum ColourSelectionFeedback {
  static func path(outline: [NormalizedPoint], holes: [[NormalizedPoint]], drawing: [NormalizedPoint], size: CGSize) -> Path {
    Path { path in
      let points = drawing.isEmpty ? outline : drawing
      for (index, p) in points.enumerated() {
        let q = CGPoint(x: p.x * size.width, y: p.y * size.height)
        if index == 0 { path.move(to: q) } else { path.addLine(to: q) }
      }
      if points.count >= 3 { path.closeSubpath() }
      if drawing.isEmpty {
        for hole in holes {
          for (i, p) in hole.enumerated() {
            let q = CGPoint(x: p.x * size.width, y: p.y * size.height)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
          }
          path.closeSubpath()
        }
      }
    }
  }
}

/// One bounded local task. The draft never changes the photo until Apply.
struct ColourReplacementEditor: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  let editingID: UUID?
  var embedded = false
  @State private var baseline: ProcessingConfiguration
  @State private var sessionID: UUID
  @State private var draft = ColourReplacement()
  @State private var drawing: [NormalizedPoint] = []
  @State private var gestureStart: CGPoint?
  @State private var objectPoint: NormalizedPoint?
  @State private var image: CGImage?
  @State private var samplingImage: CGImage?
  @State private var sampling = false
  @State private var selectingObject = true
  @State private var findingObject = false
  @State private var objectGeneration = UUID()
  @State private var objectTask: Task<Void, Never>?
  private var processor: ImageProcessor { model.editorProcessor }
  @State private var sampled = false
  @State private var before = false
  @State private var ready: ColourReplacement?
  @State private var error: String?
  @State private var retry = 0
  @State private var suspended = false
  private var zoom: CGFloat {
    get { CGFloat(model.photoMagnification(for: asset.id)) }
    nonmutating set { model.setPhotoMagnification(Double(newValue), for: asset.id) }
  }
  @State private var pendingTool: PhotoTool?
  @State private var showInspector = false
  @State private var pinchStart: CGFloat?
  @State private var canvasPosition = ScrollPosition()
  @State private var panning = false
  @State private var samplingMaximum = 0
  var previewMaximum: Int { OverlayPreviewRequest.maximum(zoom: Double(zoom), retouch: true) }
  @Environment(\.dismiss) private var dismiss
  @Environment(\.self) private var environment
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var typeSize
  init(model: Workspace, asset: SourceAsset, editingID: UUID? = nil, embedded: Bool = false) {
    self.model = model; self.asset = asset; self.editingID = editingID; self.embedded = embedded
    if let edit = model.configuration(for: asset).colourReplacements.first(where: { $0.id == editingID }) {
      _draft = State(initialValue: edit); _sampled = State(initialValue: true); _selectingObject = State(initialValue: false)
    }
    _image = State(initialValue: model.editorPreview(for: asset, configuration: model.configuration(for: asset)))
    _baseline = State(initialValue: model.configuration(for: asset)); _sessionID = State(initialValue: model.sourceSessionID)
  }
  private struct Request: Equatable { var edit: ColourReplacement; var before: Bool; var suspended: Bool; var sampled: Bool; var sampling: Bool; var selectingObject: Bool; var retry: Int; var maximum: Int }
  var body: some View {
    Group {
      if embedded { editorContent }
      else { NavigationStack { editorContent } }
    }
      .interactiveDismissDisabled()
      .confirmationDialog("Finish Replace Colour before changing tools", isPresented: Binding(get: { pendingTool != nil }, set: { if !$0 { pendingTool = nil } }), titleVisibility: .visible) {
        Button("Apply and Switch") { finishSwitch(applying: true) }.disabled(!canApply)
        Button("Discard and Switch", role: .destructive) { finishSwitch(applying: false) }
        Button("Keep Editing", role: .cancel) { pendingTool = nil }
      }
      .task(id: Request(edit: draft, before: before, suspended: suspended, sampled: sampled, sampling: sampling, selectingObject: selectingObject, retry: retry, maximum: previewMaximum)) { await prepare() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background { Task { await processor.clearInteractiveCaches() }; objectTask?.cancel(); objectGeneration = UUID(); findingObject = false; drawing = []; gestureStart = nil; suspended = true; image = nil; samplingImage = nil; ready = nil }
        if phase == .active { suspended = false }
      }
      .onDisappear { Task { await processor.clearInteractiveCaches() }; objectTask?.cancel(); objectGeneration = UUID(); drawing = []; gestureStart = nil; image = nil; samplingImage = nil; ready = nil }
  }
  var hasUnsavedSelection: Bool {
    if let editingID, let original = baseline.colourReplacements.first(where: { $0.id == editingID }) { return draft != original || !drawing.isEmpty }
    return !draft.points.isEmpty || !drawing.isEmpty
  }
  var canApply: Bool { sampled && ready == draft && !before && !sampling && !selectingObject && !findingObject && error == nil && !suspended }
  func close() {
    objectTask?.cancel()
    if embedded { model.colourReplacementAsset = nil; model.colourReplacementID = nil; model.overlayEditor = false }
    else { dismiss() }
  }
  func removeArea(_ id: UUID) {
    guard model.sourceSessionID == sessionID, model.configuration(for: asset) == baseline else { error = "The photo changed. Cancel and reopen this tool."; return }
    var updated = baseline; updated.colourReplacements.removeAll { $0.id == id }
    model.applyChange(ConfigurationPatch(values: updated, fields: [.colourReplacements]), ids: [asset.id])
    close()
  }
  func apply() {
    if model.commitColourReplacement(draft, asset: asset, baseline: baseline, sessionID: sessionID, replacingID: editingID) {
      if let image { model.rememberEditorPreview(image, source: asset, configuration: model.configuration(for: asset), maximum: previewMaximum) }
      close()
    }
    else { error = "This photo changed. Cancel and reopen Replace Colour to keep the newer edits." }
  }
  func selectTool(_ tool: PhotoTool) {
    guard tool != .replaceColour else { return }
    pendingTool = tool
    if !hasUnsavedSelection { finishSwitch(applying: false) }
  }
  func finishSwitch(applying: Bool) {
    guard let tool = pendingTool else { return }
    if applying {
      guard canApply else { return }
      apply()
      guard !model.overlayEditor else { pendingTool = nil; return }
    } else { close() }
    pendingTool = nil
    _ = model.activatePhotoTool(tool)
    model.photoToolOptionsVisible = true
  }
  var editorContent: some View {
      GeometryReader { geometry in
        let wide = geometry.size.width >= 760 && !typeSize.isAccessibilitySize
        let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
          canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
              if wide && embedded && !showInspector {
                FloatingToolOptions(title:"Replace Colour",toolIndex:4,pin:{ showInspector=true }) {
                  ScrollView { controls.padding(8) }.frame(maxHeight:min(500,geometry.size.height*0.7))
                }
              }
            }
          if !wide || !embedded || showInspector {
            VStack(spacing:0) {
              if wide && embedded {
                HStack { Text("Replace Colour").font(.headline);Spacer();Button { showInspector=false } label: { Image(systemName:"sidebar.right") }.accessibilityLabel("Float tool settings") }.padding(12)
                Divider()
              }
              ScrollView { controls.padding(16) }
            }.frame(width:wide ? 300:nil,height:wide ? nil:(typeSize.isAccessibilitySize ? 260:225)).background(.bar)
          }
          if embedded {
            PhotoEditorTools(model: model, selectedTool: .replaceColour, onSelect: selectTool, vertical: wide)
              .frame(width: wide ? 48 : nil).background(.bar)
          }
        }
      }.navigationTitle(embedded ? "" : "Replace Colour").compactNavigationTitle()
        #if os(macOS)
        .safeAreaInset(edge: .top) {
          if embedded {
            HStack {
              #if os(macOS)
              PhotoDocumentTabs(model:model).disabled(true).frame(maxWidth:.infinity)
              #else
              Text(asset.name).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
              Spacer()
              #endif
              Button("Cancel") { close() }
              Button("Apply") { apply() }.buttonStyle(.borderedProminent).disabled(!canApply)
            }.padding(.horizontal,8).padding(.vertical,4).background(.bar)
          }
        }
        #endif
        .toolbar {
          #if os(iOS)
          ToolbarItem(placement:.cancellationAction) { Button(hasUnsavedSelection ? "Cancel":"Done") { close() } }
          ToolbarItem(placement:.principal) {
            VStack(spacing:1) {
              Text(asset.name).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
              Text("Replace Colour · Draft").font(.caption2).foregroundStyle(.secondary)
            }
          }
          ToolbarItem(placement:.confirmationAction) { Button("Apply") { apply() }.disabled(!canApply) }
          #else
          if !embedded {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
            ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() }.disabled(!canApply) }
          }
          #endif
        }
      #if os(macOS)
      .frame(minWidth: embedded ? nil : 800, idealWidth: embedded ? nil : 1040, minHeight: embedded ? nil : 600, idealHeight: embedded ? nil : 740)
      #endif
  }
  @ViewBuilder func selectionInput(_ size: CGSize) -> some View {
    #if os(macOS)
    MacRetouchInput(active: !panning, began: { point, _ in beginSelection(point, size) },
      moved: { updateSelection($0, size) }, ended: { endSelection($0, size) }, hovered: { _ in })
    #else
    Color.clear.contentShape(Rectangle()).allowsHitTesting(!panning)
      .gesture(DragGesture(minimumDistance: 0).onChanged { value in
        if gestureStart == nil { beginSelection(value.startLocation, size) }
        updateSelection(value.location, size)
      }.onEnded { endSelection($0.location, size) })
    #endif
  }
  func beginSelection(_ point: CGPoint, _ size: CGSize) {
    objectTask?.cancel(); objectGeneration = UUID(); findingObject = false; objectPoint = nil
    error = nil; gestureStart = point
    if !sampling { drawing = [normalized(point,size)] }
  }
  func updateSelection(_ point: CGPoint, _ size: CGSize) {
    guard !sampling, let start = gestureStart else { return }
    // Tap remains object selection; every real drag is an immediate local lasso.
    guard hypot(point.x-start.x,point.y-start.y) >= 2 else { return }
    let next = normalized(point,size)
    if drawing.count < 2000, drawing.last.map({ hypot(($0.x-next.x)*size.width,($0.y-next.y)*size.height) >= 0.5 }) ?? true {
      drawing.append(next)
    }
  }
  func endSelection(_ point: CGPoint, _ size: CGSize) {
    guard let start = gestureStart else { return }
    updateSelection(point,size); gestureStart = nil
    if sampling { drawing = []; sample(normalized(point,size)); return }
    if hypot(point.x-start.x,point.y-start.y) < 2 {
      drawing = []
      if selectingObject { selectObject(normalized(point,size)) }
      return
    }
    guard drawing.count >= 3 else { drawing = []; return }
    // Publish the manual selection immediately, without waiting for Vision or rendering.
    draft.points = drawing; draft.excludedContours = nil; drawing = []
    selectingObject = false; sampling = true; sampled = false
  }
  func selectionPath(_ size: CGSize) -> Path {
    ColourSelectionFeedback.path(outline: draft.points, holes: draft.excludedContours ?? [], drawing: drawing, size: size)
  }
  var canvas: some View {
    GeometryReader { geometry in
      if let image {
        let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width)*scale*zoom, height: CGFloat(image.height)*scale*zoom)
        ScrollView([.horizontal, .vertical]) {
        ZStack {
          Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
          selectionPath(size).fill(Color.accentColor.opacity(sampling ? 0.06 : 0.20), style: FillStyle(eoFill: true)).allowsHitTesting(false)
          selectionPath(size).stroke(.black.opacity(0.75), lineWidth: 3).allowsHitTesting(false)
          selectionPath(size).stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5,4])).allowsHitTesting(false)
          if let cursor = drawing.last {
            Circle().fill(Color.accentColor).overlay(Circle().stroke(.white, lineWidth: 2))
              .frame(width: 8, height: 8).position(x: cursor.x * size.width, y: cursor.y * size.height).allowsHitTesting(false)
          }
          selectionInput(size)
          if findingObject, let point = objectPoint {
            ProgressView().padding(10).background(.regularMaterial, in: Capsule())
              .position(x: min(size.width-24,max(24,point.x*size.width)), y: min(size.height-24,max(24,point.y*size.height)))
              .allowsHitTesting(false)
          }
        }.frame(width:size.width,height:size.height)
          .frame(minWidth:geometry.size.width,minHeight:geometry.size.height)
        }.scrollDisabled(!panning || zoom <= 1)
          .modifier(PhotoViewportContinuity(model:model,assetID:asset.id,position:$canvasPosition))
          #if os(macOS)
          .background(MacZoomCapture { delta in zoom=min(4,max(1,zoom*exp(-delta*0.015))) })
          #endif
          .highPriorityGesture(MagnifyGesture().onChanged { value in
            if pinchStart == nil { pinchStart = zoom }
            drawing = []; gestureStart = nil; zoom = min(4,max(1,(pinchStart ?? 1)*value.magnification))
          }.onEnded { _ in pinchStart = nil;drawing = [] })
          .onChange(of: zoom) { _, value in if value <= 1 { panning = false } }
          .onChange(of: sampling) { _, value in if value { panning = false } }
          .overlay(alignment:.bottomLeading) {
            Menu {
              Button("Fit Photo") { zoom = 1;panning = false }
              Button("Zoom In") { zoom = min(4,zoom*1.5) }.disabled(zoom >= 4)
              Button("Zoom Out") { zoom = max(1,zoom/1.5) }.disabled(zoom <= 1)
            } label: { Label(zoom == 1 ? "Fit" : String(format:"%.1f× Fit",Double(zoom)),systemImage:"magnifyingglass") }
              .comfortableHitTarget().padding(.horizontal,8).background(.regularMaterial,in:Capsule()).padding(8).accessibilityLabel("View Zoom")
          }
      } else if let error {
        ContentUnavailableView("Preview unavailable", systemImage:"exclamationmark.triangle",description:Text(error))
      } else { ProgressView("Preparing photo…").frame(maxWidth:.infinity,maxHeight:.infinity) }
    }.background(.primary.opacity(0.04))
      .overlay(alignment: .topLeading) { if !embedded { Text("Draft").font(.caption.weight(.medium)).padding(6).background(.regularMaterial, in: Capsule()).padding(8).allowsHitTesting(false) } }
  }
  var controls: some View {
    VStack(alignment: .leading, spacing: 12) {
      if embedded, !baseline.colourReplacements.isEmpty {
        DisclosureGroup("Saved Areas (\(baseline.colourReplacements.count))") {
          ForEach(Array(baseline.colourReplacements.enumerated()), id: \.element.id) { index, edit in
            HStack {
              Button("Edit Area \(index + 1)") { model.colourReplacementID = edit.id }.disabled(hasUnsavedSelection)
              Spacer()
              Button("Remove Area \(index + 1)", systemImage: "trash", role: .destructive) { removeArea(edit.id) }.labelStyle(.iconOnly).disabled(hasUnsavedSelection)
            }
          }
          if editingID != nil { Button("New Area") { model.colourReplacementID = nil }.disabled(hasUnsavedSelection || baseline.colourReplacements.count >= ColourReplacement.maximumEdits) }
          if hasUnsavedSelection { Text("Apply or cancel this selection before changing areas.").font(.caption).foregroundStyle(.secondary) }
        }
      }
      Text(selectingObject ? "Tap an object, or drag to draw a selection." : draft.points.isEmpty ? "Trace around the shirt, veil or other area." : sampling ? "Tap the original colour inside the outlined area." : "Choose a replacement and refine the range.").font(.callout)
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout(spacing:8))
      Toggle(draft.points.isEmpty ? "Select Object" : "Refine Edges", isOn: $selectingObject).toggleStyle(.button).disabled(findingObject)
        .onChange(of: selectingObject) { _, active in if active { sampling = false; panning = false } }
      layout {
        Button("Trace", systemImage:"pencil.tip") { selectingObject = false; draft.points = []; draft.excludedContours = nil; drawing = []; sampled = false; sampling = false; panning = false }.comfortableHitTarget()
        Toggle("Sample", isOn:$sampling).toggleStyle(.button).comfortableHitTarget().disabled(draft.points.isEmpty)
        Toggle("Pan", isOn:$panning).toggleStyle(.button).comfortableHitTarget().disabled(zoom <= 1).help("Move the zoomed view without tracing a new area")
      }.disabled(findingObject)
      if findingObject { ProgressView("Finding object edges…"); Button("Cancel Detection") { objectTask?.cancel(); objectGeneration = UUID(); findingObject = false; objectPoint = nil } }
      ColorPicker("Original colour", selection: colour(\.source), supportsOpacity:false).disabled(draft.points.isEmpty)
      ColorPicker("Replacement", selection: colour(\.replacement), supportsOpacity:false)
      slider("Colour Range", value:$draft.range, range:0.01...1)
      slider("Strength", value:$draft.intensity, range:0...1)
      slider("Edge Softness", value:$draft.feather, range:0...0.05)
      Toggle("Before", isOn:$before).toggleStyle(.button).disabled(!sampled || sampling)
      if let error {
        Text(error).font(.caption).foregroundStyle(.red)
        Button("Retry Preview") { retry += 1 }
      }
      if image != nil && ready != draft && !before { ProgressView("Updating preview…").font(.caption) }
      Text("If nearby objects are selected together, Trace loosely around one object, then use Refine Edges and tap inside it.").font(.caption).foregroundStyle(.secondary)
      Text("Lighting and texture are retained where possible. Very dark, white, patterned or translucent fabrics may need careful refinement.").font(.caption).foregroundStyle(.secondary)
    }
  }
  func slider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>) -> some View {
    VStack(spacing:4) {
      HStack { Text(title); Spacer(); Text(value.wrappedValue,format:.percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary) }
      Slider(value:value,in:range).accessibilityLabel(title)
    }
  }
  func colour(_ key:WritableKeyPath<ColourReplacement,RGBAColour>) -> Binding<Color> {
    Binding(get:{ let c=draft[keyPath:key];return Color(.sRGB,red:c.red,green:c.green,blue:c.blue) },set:{ let c=$0.resolve(in:environment);draft[keyPath:key]=RGBAColour(Double(c.red),Double(c.green),Double(c.blue),1);if key == \.source { sampled = true; sampling = false } })
  }
  func normalized(_ p:CGPoint,_ s:CGSize) -> NormalizedPoint { NormalizedPoint(min(1,max(0,p.x/max(1,s.width))),min(1,max(0,p.y/max(1,s.height)))) }
  func sample(_ point:NormalizedPoint) {
    guard let image=samplingImage, let pixel=image.cropping(to:CGRect(x:min(image.width-1,Int(point.x*Double(image.width))),y:min(image.height-1,Int(point.y*Double(image.height))),width:1,height:1)) else { return }
    var rgba=[UInt8](repeating:0,count:4)
    rgba.withUnsafeMutableBytes { bytes in
      if let context=CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) { context.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1)) }
    }
    guard rgba[3] > 0 else { error = "Choose an opaque part of the photo.";return }
    let a=Double(rgba[3]);draft.source=RGBAColour(Double(rgba[0])/a,Double(rgba[1])/a,Double(rgba[2])/a,1);sampled=true;sampling=false
  }
  func selectObject(_ point: NormalizedPoint) {
    guard !findingObject else { return }
    guard let reference = samplingImage ?? (editingID == nil ? image : nil) else {
      error = "Preparing the photo for selection. Try again in a moment."; return
    }
    let boundary = draft.points
    if !boundary.isEmpty {
      let path = CGMutablePath()
      for (i, p) in boundary.enumerated() { if i == 0 { path.move(to: CGPoint(x: p.x, y: p.y)) } else { path.addLine(to: CGPoint(x: p.x, y: p.y)) } }
      path.closeSubpath()
      guard path.contains(CGPoint(x: point.x, y: point.y)) else { error = "Tap inside the outlined area to refine its edges."; return }
    }
    findingObject = true; objectPoint = point; error = nil
    let generation = UUID(); objectGeneration = generation
    objectTask = Task {
      defer { if objectGeneration == generation { findingObject = false; objectPoint = nil } }
      do {
        let outline = try await processor.colourObjectOutline(reference, at: point, within: boundary.isEmpty ? nil : boundary)
        try Task.checkCancellation()
        guard !suspended, objectGeneration == generation else { return }
        draft.points = outline.points; draft.excludedContours = outline.holes
        draft.constrainFeatherToSelection = true
        selectingObject = false
        sample(point)
      } catch is CancellationError { }
      catch { guard !suspended, objectGeneration == generation else { return }; self.error = "Couldn’t isolate that object. Try another point, or use Trace for a manual outline." }
    }
  }
  func prepare() async {
    let feedbackToken=model.editorFeedbackToken
    guard !suspended else { return }
    let requested = draft
    ready = nil; error = nil
    do {
      try await Task.sleep(for:.milliseconds(embedded ? 16:70));try Task.checkCancellation()
      var beforeConfig = baseline
      if let editingID { beforeConfig.colourReplacements.removeAll { $0.id == editingID } }
      let maximum = previewMaximum
      if samplingImage == nil || samplingMaximum < maximum {
        let base: CGImage
        if let cached = model.editorPreview(for: asset, configuration: beforeConfig, minimum: maximum) { base = cached }
        else { base = try await processor.render(asset.url, configuration: beforeConfig, previewMaximum: maximum, decodeMaximum: max(1200, maximum)) }
        try Task.checkCancellation(); samplingImage = base; samplingMaximum = maximum
      }
      if sampling || selectingObject || before || !sampled {
        try Task.checkCancellation()
        image = samplingImage; ready = requested
        model.finishEditorFeedback(feedbackToken,for:asset,configuration:baseline)
        return
      }
      var config = beforeConfig
      if !before && sampled {
        try requested.validate()
        if let editingID, let index = baseline.colourReplacements.firstIndex(where: { $0.id == editingID }) {
          config = baseline; config.colourReplacements[index] = requested
        } else { config.colourReplacements.append(requested) }
      }
      let rendered = try await processor.render(asset.url,configuration:config,previewMaximum:maximum,decodeMaximum:maximum*2)
      try Task.checkCancellation()
      guard requested == draft, !suspended else { return }
      image = rendered;ready = requested
      model.finishEditorFeedback(feedbackToken,for:asset,configuration:baseline)
    } catch is CancellationError { }
    catch { guard !Task.isCancelled else { return };image = nil;ready = nil;self.error = error.localizedDescription }
  }
}
