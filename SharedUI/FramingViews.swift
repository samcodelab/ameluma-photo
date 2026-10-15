import FramepebbleCore
import SwiftUI

struct PebbleMark: View {
  var size: CGFloat = 32
  var body: some View {
    Circle().fill(
      LinearGradient(
        colors: [.indigo.opacity(0.5), .blue, .indigo], startPoint: .topLeading,
        endPoint: .bottomTrailing)
    ).overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1)).frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
struct FramingImage: View {
  let image: CGImage
  let layout: FramingLayout
  var body: some View {
    GeometryReader { geo in
      let rect = layout.sourceRectInOutput(CGRect(origin: .zero, size: layout.source))
      let sx = geo.size.width / max(1, layout.output.width)
      let sy = geo.size.height / max(1, layout.output.height)
      Image(decorative: image, scale: 1).resizable().frame(
        width: rect.width * sx, height: rect.height * sy
      )
      .position(x: rect.midX * sx, y: rect.midY * sy)

    }.clipped()
  }
}
struct FramingGuides: View {
  var body: some View {
    GeometryReader { g in
      Path { p in
        for part in [1.0 / 3, 2.0 / 3] {
          p.move(to: CGPoint(x: g.size.width * part, y: 0))
          p.addLine(to: CGPoint(x: g.size.width * part, y: g.size.height))
          p.move(to: CGPoint(x: 0, y: g.size.height * part))
          p.addLine(to: CGPoint(x: g.size.width, y: g.size.height * part))
        }
      }.stroke(.white.opacity(0.6), lineWidth: 0.75)
    }.overlay(Rectangle().stroke(.white.opacity(0.8), lineWidth: 1)).allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
/// Both grid and precision surfaces edit Workspace.edits using shared normalized geometry.
struct FramingSurface: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  var interactive = true
  var guides = false
  var original = false
  var maximum = 1200
  @State private var nominal = CGSize(width: 1, height: 1)
  @State private var source: CGImage?
  @State private var processed: CGImage?
  @State private var loadedSourceKey: String?
  @State private var processedSourceID: UUID?
  @State private var processedSourceURL: URL?
  @State private var failureSourceURL: URL?
  @State private var failure: String?
  @State private var dragStart: CropConfiguration?
  @State private var zoomStart: CropConfiguration?
  @State private var interacting = false
  @State private var renderedConfiguration: ProcessingConfiguration?
  var configuration: ProcessingConfiguration { model.configuration(for: asset) }
  var displayedImage: CGImage? {
    if original { return loadedSourceKey == sourceKey ? source : nil }
    return processedSourceID == asset.id && processedSourceURL == asset.url ? processed : nil
  }
  var layout: FramingLayout {
    let size = ImageProcessor.transformedSize(nominal, configuration: configuration)
    return FramingLayout(
      source: size, output: ImageProcessor.outputSize(source: size, configuration: configuration),
      configuration: configuration)
  }
  var ratio: Double { original ? Double(nominal.width / max(1, nominal.height)) : Double(layout.output.width / max(1, layout.output.height)) }
  var body: some View {
    GeometryReader { geo in
      let available = geo.size
      let width = min(available.width, available.height * CGFloat(ratio))
      let height = width / CGFloat(ratio)
      ZStack {
        Rectangle().fill(.secondary.opacity(0.07))
        if let image = displayedImage {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else if let failure, failureSourceURL == asset.url {
          VStack {
            Image(systemName: "exclamationmark.triangle")
            Text(failure).font(.caption).multilineTextAlignment(.center)
          }.padding()
        } else {
          ProgressView()
        }
        if !original, displayedImage != nil, renderedConfiguration != configuration {
          Text("Updating processed preview…").font(.caption2).padding(5).background(.regularMaterial)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).allowsHitTesting(false)
        }
        if guides && !original { FramingGuides() }
        if model.showSubjects, !original, let proposal = model.proposals[asset.id] {
          ForEach(Array(proposal.subjects.enumerated()), id: \.offset) { _, box in
            let rect = layout.normalizedSubjectInOutput(box)
            Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
              .frame(
                width: rect.width / layout.output.width * width,
                height: rect.height / layout.output.height * height
              )
              .position(
                x: rect.midX / layout.output.width * width,
                y: rect.midY / layout.output.height * height)
          }.allowsHitTesting(false)
        }
        SensitivePreviewCover(model: model, ids: [asset.id])
      }.frame(width: width, height: height).clipped().contentShape(Rectangle())
        .gesture(
          drag(frame: CGSize(width: width, height: height)),
          including: interactive && !original ? .all : .none
        )
        .simultaneousGesture(
          MagnifyGesture().onChanged { value in
            guard interactive, !original, !model.sensitivity.concealed(asset.id) else { return }
            if zoomStart == nil {
              zoomStart = configuration.crop
              model.beginInteraction()
              interacting = true
            }
            if let start = zoomStart {
              model.setCrop(CropGeometry.zoomed(start, factor: value.magnification), for: asset.id)
            }
          }.onEnded { _ in
            zoomStart = nil
            interacting = false
            model.endInteraction()
          }
        )
        #if os(macOS)
          .background(
            MacZoomCapture { delta in
              guard interactive, !original, !model.sensitivity.concealed(asset.id) else { return }
              model.beginInteraction()
              model.setCrop(
                CropGeometry.zoomed(configuration.crop, factor: exp(-delta * 0.015)), for: asset.id)
              model.endInteraction()
            })
        #endif
        .position(x: available.width / 2, y: available.height / 2)
    }
    .task(id: sourceKey) {
      let requestedKey = sourceKey
      let requestedConfiguration = original ? ProcessingConfiguration() : configuration
      do {
        let dimensions = try await model.processor.identify(asset.url)
        let image = try await model.processor.analysisThumbnail(
          asset.url, configuration: requestedConfiguration,
          maximum: maximum)
        try Task.checkCancellation()
        source = image
        loadedSourceKey = requestedKey
        nominal = dimensions
        failure = nil
      } catch is CancellationError {} catch {
        failure = error.localizedDescription
        failureSourceURL = asset.url
      }
    }
    .task(
      id: RenderKey(
        configuration: configuration, interacting: interacting, original: original,
        maximum: maximum, url: asset.url)
    ) {
      guard !original else { return }
      let requestedConfiguration = configuration
      do {
        try await Task.sleep(for: .milliseconds(interacting ? 16 : 60))
        let image = try await model.processor.render(
          asset.url, configuration: requestedConfiguration,
          previewMaximum: min(maximum, interacting ? 500 : 1000))
        try Task.checkCancellation()
        processed = image
        processedSourceID = asset.id
        processedSourceURL = asset.url
        renderedConfiguration = requestedConfiguration
        failure = nil
      } catch is CancellationError {} catch {
        processed = nil
        failure = error.localizedDescription
        failureSourceURL = asset.url
      }
    }
    .onDisappear {
      source = nil
      processed = nil
      loadedSourceKey = nil
      processedSourceID = nil
      processedSourceURL = nil
      if interacting { model.endInteraction() }
    }
  }
  var sourceKey: String {
    let c = configuration
    return
      "\(maximum)-\(original)-\(asset.id)-\(asset.url.path)-\(c.quarterTurns)-\(c.flipHorizontal)-\(c.flipVertical)-\(c.straighten)-\(c.crop.quarterTurns)-\(c.crop.flipHorizontal)-\(c.crop.flipVertical)-\(c.crop.straighten)"
  }
  struct RenderKey: Equatable {
    var configuration: ProcessingConfiguration
    var interacting: Bool
    var original: Bool
    var maximum: Int
    var url: URL
  }
  func drag(frame: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4).onChanged { value in
      guard interactive, !original, !model.sensitivity.concealed(asset.id), loadedSourceKey == sourceKey else {
        return
      }
      if dragStart == nil {
        dragStart = configuration.crop
        model.selected = asset.id
        model.beginInteraction()
        interacting = true
      }
      if let start = dragStart {
        model.setCrop(
          CropGeometry.dragged(
            start, source: layout.source, frame: frame, translation: value.translation,
            ratio: ratio, nativeOutput: layout.output,
            preventUpscaling: configuration.preventUpscaling), for: asset.id)
      }
    }.onEnded { _ in
      dragStart = nil
      interacting = false
      model.endInteraction()
    }
  }
}
struct PrecisionEditor: View {
  @Bindable var model: Workspace
  var showsHeader = true
  var showsPreview = true
  @State private var showOriginal = false
  private var crop: Binding<CropConfiguration> {
    Binding(
      get: { model.current.map { model.configuration(for: $0).crop } ?? model.settings.crop },
      set: { value in
        guard [value.centerX, value.centerY, value.zoom, value.straighten].allSatisfy(\.isFinite),
          let asset = model.current else { return }
        var bounded = value
        bounded.centerX = min(1, max(0, value.centerX))
        bounded.centerY = min(1, max(0, value.centerY))
        bounded.zoom = min(20, max(1, value.zoom))
        bounded.straighten = min(20, max(-20, value.straighten))
        model.setCrop(bounded, for: asset.id)
      })
  }
  var body: some View {
    VStack(spacing: 12) {
      if showsHeader {
        HStack {
          Text("Crop & Frame").font(.headline)
          Spacer()
          Button {
            model.precision = false
          } label: {
            Image(systemName: "xmark")
          }.comfortableHitTarget().help("Close precision editor").accessibilityLabel(
            "Close precision editor")
        }
      }
      if showsPreview {
      HStack {
        Button {
          model.navigate(-1)
        } label: {
          Image(systemName: "chevron.left")
        }.comfortableHitTarget().accessibilityLabel("Previous photo")
        Spacer()
        Text(model.current?.name ?? "Choose an image").font(.caption).lineLimit(1)
        Spacer()
        Button {
          model.navigate(1)
        } label: {
          Image(systemName: "chevron.right")
        }.comfortableHitTarget().accessibilityLabel("Next photo")
      }
      if let asset = model.current {
        FramingSurface(model: model, asset: asset, guides: model.showGuides, original: showOriginal)
          .frame(minHeight: 240, idealHeight: 320)
      }
      Toggle("Show original", isOn: $showOriginal).tint(.blue)
      } else {
        Text("Drag crop edges or corners in the main canvas to resize; drag inside to move. Numeric controls adjust the same crop.")
          .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Toggle("Guides", isOn: $model.showGuides).tint(.blue)
        Toggle("Subjects", isOn: $model.showSubjects).tint(.blue)
      }.font(.caption)
      HStack {
        Button("Centre") {
          var c = crop.wrappedValue
          c.mode = .fill
          c.centerX = 0.5
          c.centerY = 0.5
          c.zoom = 1
          crop.wrappedValue = c
        }
        Menu("Auto-frame") {
          Button("Smart · Replace This Photo’s Framing") {
            if let id = model.current?.id { model.autoFrame(.smart, replaceManual: true, targetIDs: [id]) }
          }
          Button("Keep Subjects · Replace This Photo’s Framing") {
            if let id = model.current?.id { model.autoFrame(.keepSubjects, replaceManual: true, targetIDs: [id]) }
          }
        }.disabled(model.analysing)
      }.buttonStyle(.bordered).font(.caption)
      Button("Reset Crop · Full Image", systemImage: "arrow.up.left.and.arrow.down.right") {
        if let id = model.current?.id { Task { await model.restoreFullImageCrop(id); showOriginal = false } }
      }.buttonStyle(.bordered)
        .help("Reveal the complete source at its original size. Keep adjustments, rotation, masks, annotations and export options. Undo is available.")
      Menu("Output aspect ratio") {
        Button("Original · Full Image") {
          if let id = model.current?.id { Task { await model.restoreFullImageCrop(id); showOriginal = false } }
        }
        Button("Square") { aspect(1) }
        Button("4:3") { aspect(4.0 / 3) }
        Button("3:2") { aspect(1.5) }
        Button("16:9") { aspect(16.0 / 9) }
      }
      LabeledContent("Image scale (%)") {
        TextField("Image scale percent", value: percent(crop.zoom), format: .number.precision(.fractionLength(0)))
          .textFieldStyle(.roundedBorder).frame(width: 80)
      }
      Slider(
        value: crop.zoom, in: 1...20,
        onEditingChanged: { editing in editing ? model.beginInteraction() : model.endInteraction() }
      ).accessibilityLabel("Crop zoom")
      HStack {
        VStack(alignment: .leading) {
          Text("Horizontal (%)").font(.caption)
          TextField("Horizontal position", value: percent(crop.centerX), format: .number.precision(.fractionLength(1))).textFieldStyle(
            .roundedBorder)
        }
        VStack(alignment: .leading) {
          Text("Vertical (%)").font(.caption)
          TextField("Vertical position", value: percent(crop.centerY), format: .number.precision(.fractionLength(1))).textFieldStyle(
            .roundedBorder)
        }
      }
      LabeledContent(
        "Straighten", value: crop.straighten.wrappedValue,
        format: .number.precision(.fractionLength(1)))
      Slider(
        value: crop.straighten, in: -20...20,
        onEditingChanged: { editing in editing ? model.beginInteraction() : model.endInteraction() }
      ).accessibilityLabel("Straighten angle")
      HStack {
        Button {
          crop.wrappedValue = CropGeometry.rotated(crop.wrappedValue, turns: -1)
        } label: {
          Image(systemName: "rotate.left")
        }.comfortableHitTarget().accessibilityLabel("Rotate counterclockwise")
        Button {
          crop.wrappedValue = CropGeometry.rotated(crop.wrappedValue, turns: 1)
        } label: {
          Image(systemName: "rotate.right")
        }.comfortableHitTarget().accessibilityLabel("Rotate clockwise")
        Button {
          crop.flipHorizontal.wrappedValue.toggle()
        } label: {
          Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
        }.comfortableHitTarget().accessibilityLabel("Flip horizontally")
        Button {
          crop.flipVertical.wrappedValue.toggle()
        } label: {
          Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
        }
      }.buttonStyle(.bordered)
      Button("Use Batch Framing") { if let id = model.selected { model.reset([id]) } }
        .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .trailing)
        .help("Remove this photo’s framing override. Keep its other edits.")
      if let asset = model.current, let proposal = model.proposals[asset.id], proposal.needsReview {
        VStack(alignment: .leading) {
          ForEach(proposal.reviewReasons, id: \.self) {
            Text($0).font(.caption).foregroundStyle(.orange)
          }
          Button("Accept framing") { model.acceptReview(asset.id) }
        }
      }
    }.padding().disabled(model.running)
  }
  func percent(_ value: Binding<Double>) -> Binding<Double> {
    Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 })
  }
  func aspect(_ ratio: Double) {
    if let asset = model.current { model.setImageAspect(ratio, for: asset.id) }
  }
}

/// Single-photo crop boundaries edit the shared crop definition, never source pixels.
/// Output width is retained; freeform boundary changes derive output height.
struct PhotoCropCanvas: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var showFinal = false
  @State private var image: CGImage?
  @State private var sourceSize = CGSize(width: 1, height: 1)
  @State private var startRect: CGRect?
  @State private var draftRect: CGRect?
  @State private var error: String?
  var config: ProcessingConfiguration { model.configuration(for: asset) }
  var cropRect: CGRect {
    if let draftRect { return draftRect }
    let output = ImageProcessor.outputSize(source: sourceSize, configuration: config)
    return FramingLayout(source: sourceSize, output: output, configuration: config).cropRect
  }
  var locked: Bool { model.cropKeepsOutputSize[asset.id] == true || (model.cropAspectLocks[asset.id] ?? (config.crop.aspectRatio != nil)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if sizeClass == .compact || typeSize.isAccessibilitySize {
        HStack {
          Button("Done") { model.precision = false }
          Menu("Crop Options") { cropOptions }
          Spacer(minLength: 0)
        }
      } else {
        ViewThatFits(in: .horizontal) {
          HStack { cropOptions }
          VStack(alignment: .leading) { cropOptions }
        }
      }
      GeometryReader { geometry in
      let scale = min(geometry.size.width / sourceSize.width, geometry.size.height / sourceSize.height)
      let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
      if showFinal {
        FramingSurface(model: model, asset: asset, interactive: false)
          .overlay(alignment: .bottomLeading) { Text("Edited output · masks and watermark included").font(.caption).padding(6).background(.regularMaterial) }
      } else {
      ZStack {
        if let image {
          Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
          let rect = CGRect(x: cropRect.minX * scale, y: cropRect.minY * scale,
                            width: cropRect.width * scale, height: cropRect.height * scale)
          Path { path in
            path.addRect(CGRect(origin: .zero, size: size)); path.addRect(rect)
          }.fill(.black.opacity(0.5), style: FillStyle(eoFill: true)).allowsHitTesting(false)
          Rectangle().fill(.clear).contentShape(Rectangle())
            .overlay {
              if model.showGuides { FramingGuides() }
              else { Rectangle().stroke(.white, lineWidth: 1).allowsHitTesting(false) }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(cropGesture(scale: scale, handle: nil))
            .accessibilityLabel("Crop selection. Drag to move; use precision controls for numeric positioning.")
          if model.showSubjects, let proposal = model.proposals[asset.id] {
            ForEach(Array(proposal.subjects.enumerated()), id: \.offset) { _, box in
              Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: box.width * size.width, height: box.height * size.height)
                .position(x: box.midX * size.width, y: box.midY * size.height)
            }.allowsHitTesting(false)
          }
          ForEach(0..<8, id: \.self) { index in
            let x = [0.0, 0.5, 1.0, 1.0, 1.0, 0.5, 0.0, 0.0][index]
            let y = [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0, 0.5][index]
            Circle().fill(.white).frame(width: 9, height: 9)
              .frame(width: 44, height: 44).contentShape(Rectangle())
              .position(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
              .gesture(cropGesture(scale: scale, handle: CGPoint(x: x, y: y)))
              .accessibilityLabel("Resize crop boundary \(index + 1)")
          }
        } else if let error { Text(error).font(.caption) }
        else { ProgressView("Loading crop view…") }
        VStack {
          Spacer()
          Text("Crop view · overlays hidden")
            .font(.caption).padding(6).background(.regularMaterial)
        }.allowsHitTesting(false)
        SensitivePreviewCover(model: model, ids: [asset.id])
      }.frame(width: size.width, height: size.height)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
      }
      }
    }.task(id: PreviewKey(id: asset.id, configuration: uncropped)) {
      do {
        let dimensions = try await model.processor.identify(asset.url)
        let size = ImageProcessor.transformedSize(dimensions, configuration: config)
        let preview = try await model.processor.render(asset.url, configuration: uncropped, previewMaximum: 1200)
        try Task.checkCancellation()
        sourceSize = size; image = preview; error = nil
      } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
  }
  @ViewBuilder var cropOptions: some View {
    Button("Done Cropping") { model.precision = false }
    Toggle("Preview Edited Output", isOn: $showFinal)
    Toggle("Lock aspect ratio", isOn: Binding(get: { locked }, set: { model.cropAspectLocks[asset.id] = $0 }))
      .disabled(model.cropKeepsOutputSize[asset.id] == true)
    Toggle("Keep export dimensions", isOn: Binding(get: { model.cropKeepsOutputSize[asset.id] == true }, set: { value in
      model.cropKeepsOutputSize[asset.id] = value
      if value {
        model.cropAspectLocks[asset.id] = true
        var next = config; next.crop.mode = .manualCrop; next.crop.aspectRatio = Double(next.width) / Double(max(1, next.height))
        model.applyChange(ConfigurationPatch(values: next, fields: [.crop_mode, .crop_aspectRatio]), ids: [asset.id])
      }
    }))
    Text("Output: \(config.width) × \(model.cropKeepsOutputSize[asset.id] == true ? config.height : max(1, Int(Double(config.width) * cropRect.height / max(1, cropRect.width)))) px")
      .font(.caption.monospacedDigit())
  }
  struct PreviewKey: Equatable { var id: UUID; var configuration: ProcessingConfiguration }
  var uncropped: ProcessingConfiguration {
    var value = config
    value.crop.mode = .preserveAspectRatio; value.resizeBasis = .percentage; value.percentage = 100
    value.crop.zoom = 1; value.crop.aspectRatio = nil
    value.crop.centerX = 0.5; value.crop.centerY = 0.5
    value.masks = []; value.annotations = []; value.watermark.enabled = false
    value.canvasStyle = CanvasStyle()
    return value
  }
  func cropGesture(scale: CGFloat, handle: CGPoint?) -> some Gesture {
    DragGesture(minimumDistance: 2).onChanged { gesture in
      guard !model.sensitivity.concealed(asset.id), scale > 0 else { return }
      if startRect == nil { startRect = cropRect }
      guard let start = startRect else { return }
      let dx = gesture.translation.width / scale, dy = gesture.translation.height / scale
      var rect = start
      if let handle {
        let handles: [OverlayResizeHandle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
        let index = handles.firstIndex { $0.anchor == handle } ?? 0
        rect = CropGeometry.resized(start, source: sourceSize, handle: handles[index],
          translation: CGSize(width: dx, height: dy), preserveAspect: locked)
      } else {
        rect.origin.x = min(sourceSize.width - rect.width, max(0, start.minX + dx))
        rect.origin.y = min(sourceSize.height - rect.height, max(0, start.minY + dy))
      }
      draftRect = rect
    }.onEnded { _ in
      defer { startRect = nil; draftRect = nil }
      guard let rect = draftRect, rect != startRect else { return }
      model.applyPhotoCrop(rect, sourceSize: sourceSize, id: asset.id, keepOutputSize: model.cropKeepsOutputSize[asset.id] == true)
    }
  }
}

/// A real pixel viewer: at 100%, one image pixel maps to one display pixel.
/// The caller supplies full-resolution pixels, never an enlarged thumbnail.
struct PixelZoomViewer: View {
  let image: CGImage
  @State private var zoom: Double?
  @State private var pinchStart: Double?
  @Environment(\.displayScale) private var displayScale
  var body: some View {
    GeometryReader { geometry in
      let native = CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale)
      let fit = min(geometry.size.width / max(1, native.width), max(1, geometry.size.height - 48) / max(1, native.height))
      let factor = zoom ?? fit
      VStack(spacing: 8) {
        ScrollView([.horizontal, .vertical]) {
          Image(decorative: image, scale: 1).resizable()
            .frame(width: native.width * factor, height: native.height * factor)
            .frame(minWidth: geometry.size.width, minHeight: max(1, geometry.size.height - 48))
        }.simultaneousGesture(MagnifyGesture().onChanged { value in
          if pinchStart == nil { pinchStart = factor }
          zoom = min(8, max(0.01, (pinchStart ?? factor) * value.magnification))
        }.onEnded { _ in pinchStart = nil })
        HStack {
          Button("Fit") { zoom = nil }
          Button("100%") { zoom = 1 }
          Button { zoom = max(0.01, factor / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
          Text("\(Int(factor * 100))%").font(.caption.monospacedDigit()).frame(minWidth: 42)
          Button { zoom = min(8, factor * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
          Spacer(minLength: 0)
          Text("\(image.width) × \(image.height) px").font(.caption)
        }.buttonStyle(.bordered).padding(.horizontal, 4)
      }
    }.accessibilityLabel("Full-resolution image. Scroll to pan, pinch or use zoom controls.")
  }
}

struct InspectablePhoto: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  var original = false
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var detail = false
  @State private var image: CGImage?
  @State private var failure: String?
  var configuration: ProcessingConfiguration {
    if !original { return model.configuration(for: asset) }
    var value = ProcessingConfiguration()
    value.crop.mode = .preserveAspectRatio; value.resizeBasis = .percentage; value.percentage = 100
    return value
  }
  struct Key: Equatable { var asset: SourceAsset; var configuration: ProcessingConfiguration; var detail: Bool }
  var body: some View {
    VStack(spacing: 6) {
      if detail {
        ZStack {
          if let image { PixelZoomViewer(image: image) }
          else if let failure { ContentUnavailableView("Detail preview failed", systemImage: "exclamationmark.triangle", description: Text(failure)) }
          else { ProgressView("Rendering full-resolution detail…") }
          SensitivePreviewCover(model: model, ids: [asset.id])
        }
      } else { FramingSurface(model: model, asset: asset, interactive: false, original: original) }
      HStack {
        if typeSize.isAccessibilitySize {
          Menu("View", systemImage: "magnifyingglass") { Toggle("Inspect Full-resolution Pixels", isOn: $detail) }
        } else {
          Toggle("Inspect Pixels", isOn: $detail).toggleStyle(.button)
            .help("Loads full-resolution pixels for 100% inspection and panning.")
        }
        if detail { Text("Full-resolution detail").font(.caption).foregroundStyle(.secondary) }
        Spacer()
      }
    }.task(id: Key(asset: asset, configuration: configuration, detail: detail)) {
      image = nil; failure = nil
      guard detail else { return }
      let requested = configuration
      do {
        let rendered = try await model.processor.render(asset.url, configuration: requested)
        try Task.checkCancellation()
        image = rendered
      } catch is CancellationError {} catch { failure = error.localizedDescription }
    }.onDisappear { image = nil }
  }
}

struct WatermarkCanvas: View {
  @Bindable var model: Workspace
  let asset: SourceAsset
  @State private var bounds: CGRect?
  @State private var output = CGSize(width: 1, height: 1)
  @State private var start: WatermarkConfiguration?
  @State private var startBounds: CGRect?
  var config: ProcessingConfiguration { model.configuration(for: asset) }
  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / output.width, geometry.size.height / output.height)
      let size = CGSize(width: output.width * scale, height: output.height * scale)
      ZStack(alignment: .topLeading) {
        FramingSurface(model: model, asset: asset, interactive: false)
        if config.watermark.enabled, !config.watermark.tiled, let bounds {
          Rectangle().stroke(.blue, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .background(.white.opacity(0.001)).contentShape(Rectangle())
            .frame(width: bounds.width * scale, height: bounds.height * scale)
            .position(x: bounds.midX * scale, y: bounds.midY * scale)
            .gesture(DragGesture().onChanged { value in
              begin()
              guard let start else { return }
              var mark = start
              mark.offsetX = min(1, max(-1, start.offsetX + value.translation.width / size.width))
              mark.offsetY = min(1, max(-1, start.offsetY + value.translation.height / size.height))
              update(mark, fields: [.watermark_offsetX, .watermark_offsetY])
            }.onEnded { _ in finish() })
          Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill").foregroundStyle(.blue)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: bounds.maxX * scale, y: bounds.maxY * scale)
            .highPriorityGesture(DragGesture().onChanged { value in
              begin(); guard let start else { return }
              var mark = start
              let box = startBounds ?? bounds
              let dx = value.translation.width / scale, dy = value.translation.height / scale
              let factor = max(0.02 / start.relativeWidth, min(1 / start.relativeWidth,
                1 + (dx * box.width + dy * box.height) / max(1, box.width * box.width + box.height * box.height)))
              mark.relativeWidth = start.relativeWidth * factor
              let placement = WatermarkRenderer.placement(size: CGSize(width: box.width * factor, height: box.height * factor), output: output, configuration: mark)
              mark.offsetX = min(1, max(-1, mark.offsetX + (box.minX - placement.minX) / output.width))
              mark.offsetY = min(1, max(-1, mark.offsetY + (box.minY - placement.minY) / output.height))
              update(mark, fields: [.watermark_relativeWidth, .watermark_offsetX, .watermark_offsetY])
            }.onEnded { _ in finish() }).accessibilityLabel("Resize watermark")
          Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.blue)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: bounds.midX * scale, y: max(22, bounds.minY * scale - 24))
            .highPriorityGesture(DragGesture(coordinateSpace: .named("WatermarkCanvas")).onChanged { value in
              begin(); guard let start, let box = startBounds else { return }
              let centre = CGPoint(x: box.midX * scale, y: box.midY * scale)
              let first = atan2(value.startLocation.y - centre.y, value.startLocation.x - centre.x)
              let last = atan2(value.location.y - centre.y, value.location.x - centre.x)
              var mark = start
              mark.rotation = (start.rotation + (last - first) * 180 / .pi).truncatingRemainder(dividingBy: 360)
              if mark.rotation > 180 { mark.rotation -= 360 }; if mark.rotation < -180 { mark.rotation += 360 }
              update(mark, fields: [.watermark_rotation])
            }.onEnded { _ in finish() }).accessibilityLabel("Rotate watermark")
        }
        SensitivePreviewCover(model: model, ids: [asset.id])
      }.coordinateSpace(name: "WatermarkCanvas").frame(width: size.width, height: size.height).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }.task(id: WatermarkKey(asset: asset, configuration: config)) {
      do {
        let size = try await model.processor.identify(asset.url)
        let transformed = ImageProcessor.transformedSize(size, configuration: config)
        output = ImageProcessor.outputSize(source: transformed, configuration: config)
        try Task.checkCancellation()
        bounds = config.watermark.enabled ? try await model.processor.watermarkBounds(config.watermark, output: output) : nil
      } catch { bounds = nil; model.issues.append("Watermark controls could not load: " + error.localizedDescription) }
    }.onDisappear { finish() }
  }
  struct WatermarkKey: Equatable { var asset: SourceAsset; var configuration: ProcessingConfiguration }
  func begin() { if start == nil { start = config.watermark; startBounds = bounds; model.beginInteraction() } }
  func finish() { if start != nil { start = nil; startBounds = nil; model.endInteraction() } }
  func update(_ mark: WatermarkConfiguration, fields: Set<ConfigurationField>) {
    guard !model.sensitivity.concealed(asset.id) else { return }
    var value = config; value.watermark = mark
    model.applyChange(ConfigurationPatch(values: value, fields: fields), ids: [asset.id])
  }
}
