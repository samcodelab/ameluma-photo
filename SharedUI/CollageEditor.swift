import FramepebbleCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif
struct CollageEditor: View {
  @Bindable var model: Workspace
  var embedded = false
  enum Inspector: String, CaseIterable { case composition = "Canvas", photo = "Photo", output = "Output Settings" }
  @State private var inspector = Inspector.composition
  @State private var titleExpanded = false
  @State private var canvasScale = 1.0
  @State private var expandedControls = false
  @State private var exportingOptions = false
  @State private var layoutViewport = EditorPanelViewport()
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var gallery = false
  @State private var artMode = "Shape"
  @State private var artShape: CollageShape = .heart
  @State private var artText = "HELLO"
  @State private var artFont = "HelveticaNeue-Bold"
  @State private var tileCount = 100
  @State private var referenceID: UUID?
  @State private var reuse = true
  @State private var useAllSources = false
  @State private var rename = false
  @State private var collageName = ""
  @State private var renderedID: UUID?
  @State private var renderedIdentity: CollageRenderIdentity?
  @State private var previewFailure: String?
  @State private var previewRetry = 0
  @State private var unavailableSourceIDs: Set<UUID> = []
  @State private var renderingPreview = false
  @State private var interactionStart: CollageProject?
  @State private var choosingSources = false
  @State private var choosingReference = false
  @State private var referenceSelection: Set<UUID> = []
  @State private var artPresented = false
  @State private var selectedTileNumber = 1
  @State private var moveFrames = true
  @State private var snapFrames = true
  @State private var replacingCell = false
  @State private var replacementSelection: Set<UUID> = []
  @State private var transformStart: CollageCell?
  @State private var inspectingComposition = false
  @State private var detailImage: CGImage?
  @State private var proofComposition = false
  @State private var compositionByteCount: Int?
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var sourceSelection: Set<UUID> = []
  @State private var image: CGImage?
  @State private var selected: UUID?
  @State private var sizes: [UUID: CGSize] = [:]
  @State private var start: CropConfiguration?
  @State private var exporting = false
  struct ExportedComposition { var url: URL; var identity: CollageRenderIdentity; var date: Date }
  @State private var outputs: [UUID: ExportedComposition] = [:]
  @State private var reviewSession: ShareOutputSession?
  @Environment(\.dismiss) private var dismiss
  var project: Binding<CollageProject> {
    Binding(get: { model.collage }, set: { if interactionStart != nil { model.collage = $0 } else { model.changeCollage($0) } })
  }
  struct PreviewRequest: Equatable { var identity: CollageRenderIdentity; var retry: Int }
  struct SourceRequest: Equatable { var sources: [SourceAsset]; var retry: Int }
  var renderIdentity: CollageRenderIdentity { CollageRenderIdentity(project: model.collage, sources: model.assets, edits: model.edits) }
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let viewportHeight = layoutViewport.height(fallback: geometry.size.height)
        VStack(spacing: 0) {
          workspaceHeader(width: geometry.size.width)
          if model.activeCollageID != nil {
            reviewNotices
            if EditorPanelLayout.supportsInspector(geometry.size.width) {
              HStack(spacing: 0) {
                canvasWorkspace
                Divider()
                VStack(spacing: 0) {
                  inspectorPicker.padding(12)
                  Divider()
                  ScrollView { compositionControls }
                }.frame(width: EditorPanelLayout.inspectorWidth).editorInspectorSurface()
              }
            } else {
              compositionCanvas.frame(maxWidth: .infinity, maxHeight: .infinity)
              if sizeClass == .compact || EditorPanelLayout.expandedControls(height: viewportHeight, accessibility: typeSize.isAccessibilitySize) {
                ViewThatFits(in: .horizontal) {
                  HStack {
                    ForEach(Inspector.allCases, id: \.self) { tool in
                      Button(tool == .output ? "Output" : tool.rawValue) { inspector = tool; expandedControls = true }
                        .accessibilityLabel(tool.rawValue).comfortableHitTarget().frame(maxWidth: .infinity)
                        .editorSelectionSurface(selected: inspector == tool)
                    }
                  }
                  Menu("Collage Tools", systemImage: "slider.horizontal.3") {
                    ForEach(Inspector.allCases, id: \.self) { tool in Button(tool.rawValue) { inspector = tool; expandedControls = true } }
                  }
                }
              } else {
                inspectorPicker
                ScrollView { compositionControls }.frame(height: min(220, viewportHeight * 0.3))
              }
            }
          } else {
            ContentUnavailableView("Your Collages", systemImage: "rectangle.split.2x2", description: Text("Create a collage or reopen a saved composition."))
            Button("Saved Collages & Layouts…") { gallery = true }.buttonStyle(.borderedProminent)
            creationChoices
          }
        }.padding(workspacePadding)
          .onAppear { layoutViewport.observe(geometry.size) }
          .onChange(of: geometry.size.width) { _, _ in layoutViewport.observe(geometry.size) }
      }.safeAreaInset(edge: .top, spacing: 0) { activityBar }
      .navigationTitle(model.activeCollageName).compactNavigationTitle()
      .sheet(isPresented: $expandedControls) {
        NavigationStack { ScrollView { compositionControls }.navigationTitle(inspector.rawValue)
          .toolbar { Button("Done") { expandedControls = false } } }
      }
      .sheet(isPresented: $exportingOptions) {
        NavigationStack {
          ScrollView { outputControls.padding() }
            .navigationTitle("Output Settings").compactNavigationTitle()
            .toolbar { Button("Done") { exportingOptions = false } }
        }
      }
      .sheet(isPresented: $artPresented) {
        NavigationStack {
          ScrollView { artControls.padding() }
            .navigationTitle(artMode == "Photomosaic" ? "Photo Mosaic" : artMode + " Collage")
            .toolbar { Button("Done") { artPresented = false } }
        }.frame(minWidth: 320)
        #if os(macOS)
        .frame(minHeight: 440)
        #endif
      }
      .sheet(isPresented: $replacingCell) {
        CollagePhotoPicker(model: model, selection: $replacementSelection, single: true, title: "Replace Collage Photo") {
          if let selected, let source = replacementSelection.first { model.replaceCollagePhoto(cellID: selected, sourceID: source) }
          replacingCell = false
        }
      }
      .sheet(isPresented: $inspectingComposition) {
        NavigationStack {
          Group {
            if let detailImage {
              VStack {
                PixelZoomViewer(image: detailImage)
                if let compositionByteCount { Text("Encoded output · \(compositionByteCount) bytes").font(.caption) }
              }
            }
            else { ProgressView("Rendering composition detail…") }
          }.padding().navigationTitle("Composition Detail")
            .toolbar { Button("Done") { inspectingComposition = false; detailImage = nil } }
            .task {
              do {
                let detail = try await model.processor.renderCollage(model.collage, sources: model.assets, edits: model.edits)
                try Task.checkCancellation()
                if proofComposition {
                  var config = ProcessingConfiguration(); config.format = model.collage.outputFormat; config.quality = model.collage.outputQuality
                  config.width = detail.width; config.height = detail.height
                  let proof = try await model.processor.encodedPreview(detail, configuration: config)
                  try Task.checkCancellation(); detailImage = proof.image; compositionByteCount = proof.byteCount
                } else { detailImage = detail; compositionByteCount = nil }
              } catch is CancellationError {} catch { model.issues.append(error.localizedDescription); inspectingComposition = false }
            }
        }.frame(minWidth: 320)
        #if os(macOS)
        .frame(minHeight: 500)
        #endif
      }
      .sheet(isPresented:$gallery) { CollageGallery(model:model) }
      .alert("Name this collage",isPresented:$rename) {
        TextField("Name",text:$collageName)
        Button("Save") { model.renameCollage(collageName) }
        Button("Cancel",role:.cancel) {}
      }
      .sheet(isPresented: $choosingSources) {
        CollagePhotoPicker(model:model,selection:$sourceSelection) {
          var value=model.collage
          let ids=model.workspaceAssets.filter {sourceSelection.contains($0.id)}.map(\.id)
          if let template=CollageTemplate.catalog.first(where:{$0.id==value.templateID}) {template.apply(to:&value,sources:ids)}
          else {value.arrange(ids,layout:value.layout)}
          model.changeCollage(value);choosingSources=false
        }
      }
      .task(id: SourceRequest(sources: renderIdentity.sources, retry: previewRetry)) {
        sizes = [:]; unavailableSourceIDs = []
        let ids=Set(model.collage.cells.map(\.sourceID)).union(model.collage.mosaicReferenceID.map { [$0] } ?? [])
        for asset in model.assets where ids.contains(asset.id) {
          do {
            let raw=try await model.processor.identify(asset.url)
            try Task.checkCancellation()
            sizes[asset.id]=raw
          } catch is CancellationError { return } catch {
            guard !Task.isCancelled else { return }
            unavailableSourceIDs.insert(asset.id)
          }
        }
      }
      .task(id: PreviewRequest(identity: renderIdentity, retry: previewRetry)) {
        let identity = renderIdentity
        renderingPreview = true; previewFailure = nil
        let project=model.collage, edits=model.edits, id=model.activeCollageID, sources=model.assets
        do {
          try await Task.sleep(for:.milliseconds(100))
          let preview=try await model.processor.renderCollage(project,sources:sources,edits:edits,previewMaximum:900)
          try Task.checkCancellation()
          guard id == model.activeCollageID else { return }
          image=preview; renderedID=id; renderedIdentity=identity; renderingPreview=false
        } catch is CancellationError { } catch {
          guard !Task.isCancelled, identity == renderIdentity else { return }
          renderingPreview=false; previewFailure=error.localizedDescription
        }
      }
      .sheet(item: $reviewSession) { session in
        ShareReview(urls: session.outputs, summary: session.summary).privacyCurtain(model: model)
      }
      .safeAreaInset(edge: .bottom) {
        if previewFailure != nil || missingReferenceID != nil { previewRecovery.padding(12).background(.bar) }
      }
      .onDisappear { model.collageTask?.cancel() }
    .onChange(of:model.creationActionRequest?.id) {_,_ in
      guard let request=model.creationActionRequest, model.contextIsCurrent(request.context) else {return}
      model.creationActionRequest=nil
      if request.intent == .export {export()}
    }
      .onChange(of: renderIdentity) { _, _ in reviewSession = nil; detailImage = nil; compositionByteCount = nil }
      .onAppear { model.ensureCollageDocument(); titleExpanded = !model.collage.title.isEmpty }
      .onChange(of: selected) { _, value in if value != nil { inspector = .photo } }
      .onChange(of: model.collage.title) { _, value in if !value.isEmpty { titleExpanded = true } }
      .onChange(of:model.activeCollageID) { _,_ in selected=nil; start=nil; interactionStart=nil; titleExpanded = !model.collage.title.isEmpty; canvasScale = 1 }

    }.background(.background).frame(minWidth: 320)
    #if os(macOS)
    .frame(minHeight: 500)
    #endif
    .overlay {
      SensitivePreviewCover(model: model, ids: Set(model.collage.cells.map(\.sourceID)).union(model.collage.mosaicReferenceID.map { [$0] } ?? []))
    }
  }
  @ViewBuilder var reviewNotices: some View {
          if model.collage.requiresFramingReview {
            Label("Source replaced · review this composition’s framing", systemImage: "exclamationmark.triangle")
            Button("I’ve Reviewed This Composition’s Framing") { var value = model.collage; value.requiresFramingReview = false; model.changeCollage(value) }.disabled(renderedIdentity != renderIdentity)
          }
          if model.collage.requiresPrivacyReview {
            VStack(alignment: .leading, spacing: 6) {
              Label("Review masks after changing this composition", systemImage: "exclamationmark.shield").font(.headline)
              Text("Cell framing, layout or shape changes can expose a previously covered detail. Inspect the final composition.").font(.caption)
              Button("I’ve Checked This Composition’s Mask Coverage") {
                var value = model.collage; value.requiresPrivacyReview = false; model.changeCollage(value)
              }.disabled(renderedIdentity != renderIdentity)
            }.padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
          }
  }
  var workspacePadding: CGFloat {
    #if os(macOS)
    0
    #else
    12
    #endif
  }
  @ViewBuilder func workspaceHeader(width: CGFloat) -> some View {
    #if os(macOS)
    HStack(spacing: 10) {
      collageTabs.frame(minWidth: 120, maxWidth: .infinity).frame(height: 34)
      Divider().frame(height: 18)
      headerActions(showsHistory: true)
    }.controlSize(.small).padding(.horizontal, 12).padding(.vertical, 8)
    Divider()
    #else
    if model.activeCollageID != nil { headerActions(showsHistory: true).padding(.bottom, 4) }
    #endif
  }
  func headerActions(showsHistory: Bool) -> some View {
    HStack(spacing: 6) {
      Button { model.selectPhotos(for: .collageAdd) } label: {
        Label("Add Photos", systemImage: "photo.badge.plus").font(.callout).fixedSize(horizontal: true, vertical: false)
      }.foregroundStyle(.primary).comfortableHitTarget().accessibilityLabel("Add photos to collage").help("Add Photos")
      Menu { collageActions } label: { Image(systemName: "ellipsis.circle") }
        .foregroundStyle(.primary).comfortableHitTarget().accessibilityLabel("Collage actions and saved compositions").help("Collage actions and saved compositions")
      #if os(iOS)
      Spacer(minLength: 8)
      #endif
      if showsHistory {
        #if os(macOS)
        Divider().frame(height: 18)
        #endif
        Button { model.undoCollage() } label: { Image(systemName: "arrow.uturn.backward") }
          .foregroundStyle(.primary).comfortableHitTarget().disabled(model.collageUndo.isEmpty).accessibilityLabel("Undo collage edit").help("Undo")
        Button { model.redoCollage() } label: { Image(systemName: "arrow.uturn.forward") }
          .foregroundStyle(.primary).comfortableHitTarget().disabled(model.collageRedo.isEmpty).accessibilityLabel("Redo collage edit").help("Redo")
      }
      Group {
        Button("Export…") { exportingOptions = true }.buttonStyle(.borderedProminent)
          .fixedSize(horizontal: true, vertical: false).comfortableHitTarget()
          .disabled(exporting || model.collageGenerating || model.collage.cells.isEmpty)
      }
    }.buttonStyle(.borderless)
  }
  @ViewBuilder var canvasWorkspace: some View {
    #if os(macOS)
    VStack(spacing: 0) {
      GeometryReader { geometry in
        let ratio = Double(max(1, model.collage.width)) / Double(max(1, model.collage.height))
        let width = min(max(1, geometry.size.width - 32), max(1, geometry.size.height - 32) * ratio)
        ScrollView([.horizontal, .vertical]) {
          compositionCanvas.frame(width: width * canvasScale, height: width / ratio * canvasScale)
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .padding(16)
            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
        }.defaultScrollAnchor(.center)
      }.background { EditorCanvasBackground() }
      Divider()
      HStack(spacing: 10) {
        Text("\(model.collage.width) × \(model.collage.height) px")
        Text("·").foregroundStyle(.tertiary)
        Text("\(model.collage.cells.count) \(model.collage.cells.count == 1 ? "photo" : "photos")")
        Spacer()
        Button { canvasScale = max(0.5, canvasScale - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
          .disabled(canvasScale <= 0.5).accessibilityLabel("Zoom out canvas")
        Button(canvasScale == 1 ? "Fit" : canvasScale.formatted(.number.precision(.fractionLength(2))) + "× Fit") { canvasScale = 1 }
          .frame(minWidth: 48).help("Fit canvas to window; viewing zoom does not change output dimensions")
        Button { canvasScale = min(3, canvasScale + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
          .disabled(canvasScale >= 3).accessibilityLabel("Zoom in canvas")
      }.font(.caption).monospacedDigit().foregroundStyle(.secondary).buttonStyle(.borderless)
        .padding(.horizontal, 12).frame(height: 30)
    }
    #else
    compositionCanvas.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
    #endif
  }
  func propertyRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 6) { Text(title).foregroundStyle(.secondary); control() }
      } else {
        HStack(spacing: 10) {
          Text(title).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false).frame(minWidth: 88, alignment: .leading).layoutPriority(1)
          control().comfortableHitTarget().frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func propertySlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, percentage: Bool = false) -> some View {
    propertyRow(title) {
      HStack(spacing: 8) {
        Slider(value: value, in: range, onEditingChanged: sliderInteraction).accessibilityLabel(title)
        Text(percentage ? value.wrappedValue.formatted(.percent.precision(.fractionLength(0))) : (value.wrappedValue * 100).formatted(.number.precision(.fractionLength(0))) + "%")
          .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
      }
    }
  }
  var canvasControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Canvas").font(.subheadline.weight(.semibold))
      propertyRow("Layout") {
        Picker("Layout", selection: Binding(get: { model.collage.layout }, set: { layout in
          var value = model.collage; value.arrange(value.cells.map(\.sourceID), layout: layout); model.changeCollage(value)
        })) { ForEach(CollageLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
      }
      propertyRow("Size") {
        HStack(spacing: 5) {
          TextField("Width", value: project.width, format: .number).accessibilityLabel("Canvas width in pixels")
          Text("×").foregroundStyle(.tertiary).accessibilityHidden(true)
          TextField("Height", value: project.height, format: .number).accessibilityLabel("Canvas height in pixels")
          Text("px").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).monospacedDigit()
      }
      propertyRow("Background") {
        Picker("Background", selection: project.background) {
          Text("White").tag(RGBAColour(1, 1, 1, 1)); Text("Black").tag(RGBAColour(0, 0, 0, 1)); Text("Transparent").tag(RGBAColour(0, 0, 0, 0))
        }.labelsHidden()
      }
      if model.collage.layout == .freeform {
        propertyRow("Interaction") { Picker("Canvas interaction", selection: $moveFrames) { Text("Move Frames").tag(true); Text("Reframe Photos").tag(false) }.labelsHidden() }
        Toggle("Snap frames to canvas", isOn: $snapFrames)
      }
      Divider().padding(.vertical, 2)
      Text("Appearance").font(.subheadline.weight(.semibold))
      propertySlider("Spacing", value: project.spacing, range: 0...0.08, percentage: true)
      propertySlider("Border", value: project.canvas.border, range: 0...0.05, percentage: true)
      propertySlider("Corners", value: project.canvas.cornerRadius, range: 0...0.3, percentage: true)
      propertyRow("Shadow") { Toggle("Shadow", isOn: project.shadow).labelsHidden().toggleStyle(.switch) }
      Divider().padding(.vertical, 2)
      DisclosureGroup("Title", isExpanded: $titleExpanded) {
        VStack(alignment: .leading, spacing: 12) {
          TextField("Add a title", text: project.title).textFieldStyle(.roundedBorder).accessibilityLabel("Collage title")
          propertyRow("Colour") {
            Picker("Title colour", selection: project.titleColour) {
              Text("Dark").tag(RGBAColour(0, 0, 0, 1)); Text("Light").tag(RGBAColour(1, 1, 1, 1)); Text("Blue").tag(RGBAColour(0, 0.3, 1, 1))
            }.labelsHidden()
          }
        }.padding(.top, 8)
      }
    }
    #if os(macOS)
    .controlSize(.small)
    #endif
  }
  var inspectorPicker: some View {
    Picker("Collage tool", selection: $inspector) {
      ForEach(Inspector.allCases, id: \.self) { Text($0 == .output ? "Output" : $0.rawValue).accessibilityLabel($0.rawValue).tag($0) }
    }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("collage.toolPicker")
  }
  @ViewBuilder var creationChoices: some View {
    if sizeClass == .compact {
      HStack(spacing: 8) { creationButtons }
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 8) { creationButtons }
    }
  }
  @ViewBuilder var creationButtons: some View {
    creationChoice("Photo Layout", "square.grid.2x2", "Arrange your photos", mode: nil)
    creationChoice("Shape Collage", "heart", "Fill a shape with photos", mode: "Shape")
    creationChoice("Text Collage", "textformat", "Make words from photos", mode: "Text")
    creationChoice("Photo Mosaic", "photo.on.rectangle", "Recreate a reference image", mode: "Photomosaic")
  }
  func creationChoice(_ title: String, _ symbol: String, _ detail: String, mode: String?) -> some View {
    Button {
      activateCreation(mode)
    } label: {
      Group {
        if sizeClass == .compact {
          VStack(spacing: 4) {
            Image(systemName: symbol)
            Text(mode == nil ? "Layout" : mode == "Photomosaic" ? "Mosaic" : mode ?? title).font(.caption)
          }.frame(maxWidth: .infinity, minHeight: 44)
        } else {
          VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).accessibilityLabel(title + ". " + detail)
      .disabled(model.running || model.collageGenerating)
  }
  func activateCreation(_ mode: String?) {
      if model.activeCollageID == nil { model.newCollage() }
      if let mode {
        artMode = mode; artPresented = true
        if model.collage.cells.isEmpty { useAllSources = true }
        referenceID = model.collage.mosaicReferenceID
        artFont = model.collage.silhouetteFontName
        if mode == "Text", model.collage.silhouette == .text {
          artText = model.collage.silhouetteText; tileCount = model.collage.cells.count
        } else if mode == "Shape", let shape = model.collage.silhouette, shape != .text {
          artShape = shape; tileCount = model.collage.cells.count
        } else if mode == "Photomosaic", model.collage.mosaicReferenceID != nil { tileCount = model.collage.cells.count }
      }
      else { gallery = true }
  }
  @ViewBuilder var activityBar: some View {
    if model.collageGenerating || exporting {
      VStack(alignment:.leading,spacing:6) {
        Text(model.collageGenerating ? model.collageArtProgress.phase : model.status).font(.callout)
        HStack {
          ProgressView(value:Double(model.collageGenerating ? model.collageArtProgress.completed : model.completed),total:Double(max(1,model.collageGenerating ? model.collageArtProgress.total : model.total)))
          Button("Cancel") {
            if model.collageGenerating {model.collageGenerationTask?.cancel()} else {model.collageTask?.cancel()}
          }.comfortableHitTarget()
        }
      }.padding().background(.bar)
    }
  }
  struct PreviewKey: Equatable { var project:CollageProject; var edits:EditingSnapshot; var id:UUID? }
  @ViewBuilder var collageActions: some View {
    #if os(iOS)
      Menu("Open Collages") {
        ForEach(model.openCollageIDs, id: \.self) { id in
          Button(model.collageDocuments.first { $0.id == id }?.name ?? "Collage") { model.activateCollage(id) }
        }
        if let id = model.activeCollageID { Button("Close This Collage; Keep Composition") { model.closeCollageTab(id) } }
      }
    #endif
    Divider()
    Button("Output Settings…", systemImage: "slider.horizontal.3") { exportingOptions = true }
    Button("Layouts & Saved Collages…",systemImage:"square.grid.3x3") {gallery=true}
    Button("New Collage",systemImage:"plus") {model.newCollage()}
    Button("Rename…") {collageName=model.activeCollageName;rename=true}
    Menu("Create") {
      Button("Shape Collage") { activateCreation("Shape") }
      Button("Text Collage") { activateCreation("Text") }
      Button("Photo Mosaic") { activateCreation("Photomosaic") }
    }
    Button("Inspect Pixels") { proofComposition = false; inspectingComposition = true }
      .disabled(renderedIdentity != renderIdentity)
    Button("Preview Encoded Output") { proofComposition = true; inspectingComposition = true }
      .disabled(renderedIdentity != renderIdentity)
  }
  @ViewBuilder var collageTabs: some View {
    if sizeClass == .compact {
      HStack {
        Menu("Open Collages (\(model.openCollageIDs.count))") {
          ForEach(model.savedCollages.filter { model.openCollageIDs.contains($0.id) }) {item in Button(item.name) {model.activateCollage(item.id)}}
          Button("Saved Collages & Layouts…") { gallery = true }
          Button("New Collage") {model.newCollage()}
        }
        Spacer()
        if let id=model.activeCollageID {
          Button {model.closeCollageTab(id)} label:{Image(systemName:"xmark")}
            .comfortableHitTarget().accessibilityLabel("Close collage tab; keep composition")
        }
      }.disabled(model.running || model.collageGenerating)
    } else {
      ScrollView(.horizontal) {
        HStack {
          ForEach(model.openCollageIDs,id:\.self) { id in
            HStack {
              Button(model.collageDocuments.first { $0.id == id }?.name ?? "Collage") { model.activateCollage(id) }
                .comfortableHitTarget()
              Button { model.closeCollageTab(id) } label: { Image(systemName:"xmark") }
                .comfortableHitTarget().accessibilityLabel("Close collage tab; keep composition")
            }.buttonStyle(.plain).padding(10)
              .editorSelectionSurface(selected: model.activeCollageID == id, idleOpacity: 0.04)
              .draggable("ameluma-collage:" + id.uuidString)
              .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, value.hasPrefix("ameluma-collage:"), let source = UUID(uuidString: String(value.dropFirst(16))) else { return false }
                model.moveCollageTab(source, before: id); return true
              }
              .contextMenu {
                Button("Close Collage") { model.closeCollageTab(id) }
                Button("Close Other Collages") { model.closeOtherCollageTabs(keeping: id) }
              }

          }
          Button { model.newCollage() } label: { Image(systemName:"plus") }.comfortableHitTarget().accessibilityLabel("New collage")
        }
      }.disabled(model.running || model.collageGenerating)
    }
  }
  @ViewBuilder var compositionCanvas: some View {
    if model.collage.cells.isEmpty {
      ScrollView {
        VStack(spacing: 12) {
          Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
          Text("Add photos to your collage").font(.headline)
          Text("Choose photos from your workspace to start arranging.").foregroundStyle(.secondary)
          Button("Select Photos") { model.selectPhotos(for: .collageAdd) }.buttonStyle(.borderedProminent)
            .disabled(model.collageGenerating || model.running)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding()
      }
    } else if let image, renderedID == model.activeCollageID {
      GeometryReader { proxy in
        ZStack(alignment:.topLeading) {
          Image(decorative:image,scale:1).resizable()
          if renderedIdentity != renderIdentity {
            Text(previewFailure == nil ? "Updating composition preview…" : "Preview out of date: " + (previewFailure ?? ""))
              .font(.caption).padding(8).background(.regularMaterial)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).allowsHitTesting(false)
          }
          if let cell=model.collage.cells.first(where: { $0.id == selected }) {
            let r=model.collage.rect(for:cell,output:proxy.size)
            Rectangle().stroke(.blue,lineWidth:2).frame(width:r.width,height:r.height)
              .rotationEffect(.degrees(cell.rotation)).position(x:r.midX,y:r.midY).allowsHitTesting(false)
            if model.collage.layout == .freeform && moveFrames {
              transformHandles(cell, rect: r, viewport: proxy.size)
            }
          }
        }.coordinateSpace(name: "CollageCanvas").contentShape(Rectangle())
          .onTapGesture { point in selected=hit(point,in:proxy.size)?.id }
          .gesture(DragGesture(minimumDistance:4).onChanged { gesture in
            guard !model.collageGenerating, !model.running else { return }
            if interactionStart == nil {
              guard let cell=hit(gesture.startLocation,in:proxy.size) else { return }
              selected=cell.id; start=cell.crop; interactionStart=model.collage
            }
            if moveFrames && model.collage.layout == .freeform,
               let original = interactionStart?.cells.first(where: { $0.id == selected }),
               let index = model.collage.cells.firstIndex(where: { $0.id == selected }) {
              model.collage.cells[index] = CollageGeometry.moved(original, translation: gesture.translation,
                viewport: proxy.size, titleBand: model.collage.title.isEmpty ? 0 : 0.12, snap: snapFrames)
              return
            }
            guard let cell=model.collage.cells.first(where: { $0.id == selected }), let raw=sizes[cell.sourceID], let start else { return }
            let size=ImageProcessor.transformedSize(raw,configuration:model.configuration(forID:cell.sourceID))
            var value=model.collage
            if let index=value.cells.firstIndex(where: { $0.id == cell.id }) {
              let rect=value.rect(for:cell,output:proxy.size)
              value.cells[index].crop=CropGeometry.dragged(start,source:size,frame:rect.size,translation:gesture.translation,ratio:Double(rect.width/rect.height))
              model.collage=value
            }
          }.onEnded { _ in finishInteraction() })
          .simultaneousGesture(MagnifyGesture().onChanged { value in
            guard !model.collageGenerating, !model.running, let cell=model.collage.cells.first(where:{$0.id==selected}) else {return}
            if interactionStart == nil { interactionStart=model.collage; start=cell.crop }
            if moveFrames && model.collage.layout == .freeform,
               let original = interactionStart?.cells.first(where: { $0.id == cell.id }),
               let index = model.collage.cells.firstIndex(where: { $0.id == cell.id }) {
              let factor = min(1 / max(original.width, original.height), max(0.05 / min(original.width, original.height), value.magnification))
              var resized = original
              resized.width *= factor; resized.height *= factor
              resized.x = min(1 - resized.width, max(0, original.x + (original.width - resized.width) / 2))
              resized.y = min(1 - resized.height, max(0, original.y + (original.height - resized.height) / 2))
              model.collage.cells[index] = resized
              return
            }
            guard let start else {return}
            var p=model.collage
            if let i=p.cells.firstIndex(where:{$0.id==cell.id}) {p.cells[i].crop=CropGeometry.zoomed(start,factor:value.magnification);model.collage=p}
          }.onEnded {_ in finishInteraction()})
          .dropDestination(for: String.self) { values, point in
            guard let value = values.first, let target = hit(point, in: proxy.size) else { return false }
            if value.hasPrefix("ameluma-cell:"), let source = UUID(uuidString: String(value.dropFirst(13))) {
              model.swapCollagePhotos(source, target.id); return true
            }
            if let source = UUID(uuidString: value), model.assets.contains(where: { $0.id == source }) {
              model.replaceCollagePhoto(cellID: target.id, sourceID: source); return true
            }
            return false
          }
          .accessibilityLabel("Collage canvas, \(model.collage.cells.count) photo tiles. Select a tile to reframe, or use Selected photo controls.")
      }.aspectRatio(CGFloat(image.width)/CGFloat(image.height),contentMode:.fit)
        .overlay(alignment: .bottomLeading) {
          if selected != nil {
            VStack(alignment: .leading, spacing: 4) {
              Text(model.collage.layout == .freeform && moveFrames ? "Move Frames · pinch resizes frame" : "Reframe Photo · pinch changes crop").font(.caption)
              Button("View Zoom…", systemImage: "plus.magnifyingglass") { proofComposition = false; inspectingComposition = true }
                .disabled(renderedIdentity != renderIdentity)
                .accessibilityHint("Inspect the composition without changing its crop or dimensions")
            }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(8)
          }
        }
    } else if let previewFailure {
      ContentUnavailableView("Composition preview failed", systemImage: "exclamationmark.triangle", description: Text(previewFailure))
    } else { ProgressView("Rendering composition…").frame(height:240) }
  }
  var missingSourceCells: [CollageCell] {
    model.collage.cells.filter { cell in
      !model.assets.contains(where: { $0.id == cell.sourceID }) || unavailableSourceIDs.contains(cell.sourceID)
    }
  }
  var missingReferenceID: UUID? {
    guard let id = model.collage.mosaicReferenceID,
      !model.assets.contains(where: { $0.id == id }) || unavailableSourceIDs.contains(id) else { return nil }
    return id
  }
  var recoverySourceIDs: [UUID] {
    var seen: Set<UUID> = []
    return missingSourceCells.map(\.sourceID).filter { seen.insert($0).inserted }
  }
  var previewRecovery: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !recoverySourceIDs.isEmpty || missingReferenceID != nil {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(recoverySourceIDs, id: \.self) { id in
            let cells = model.collage.cells.enumerated().filter { $0.element.sourceID == id }
            let numbers = cells.map { String($0.offset + 1) }.joined(separator: ", ")
            let name = model.assets.first(where: { $0.id == id })?.name ?? "Unavailable photo"
            VStack(alignment: .leading, spacing: 4) {
              Text(name).font(.caption.bold())
              Text("Photo Cells " + numbers).font(.caption).lineLimit(2)
              HStack {
                if model.assets.contains(where: { $0.id == id }) {
                  Button("Locate Photo…") { model.relinkSourceID = id }
                }
                Menu("Replace in Cell…") {
                  ForEach(cells.map(\.element)) { cell in
                    let number = model.collage.cells.firstIndex(where: { $0.id == cell.id }).map { $0 + 1 } ?? 1
                    Button("Photo Cell \(number)…") { selected = cell.id; replacementSelection = []; replacingCell = true }
                  }
                }
              }
            }
          }
          if let id = missingReferenceID {
            VStack(alignment: .leading, spacing: 4) {
              Text("Mosaic Reference · " + (model.assets.first(where: { $0.id == id })?.name ?? "Unavailable photo")).font(.caption.bold())
              if model.assets.contains(where: { $0.id == id }) {
                Button("Locate Reference Photo…") { model.relinkSourceID = id }
              }
              Button("Choose Reference & Regenerate…") { activateCreation("Photomosaic") }
              Text("Existing tiles stay unchanged until you generate the mosaic again.").font(.caption).foregroundStyle(.secondary)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: sizeClass == .compact ? 160 : 220)
      }
      if previewFailure != nil {
        Button("Retry Composition Preview", systemImage: "arrow.clockwise") { previewRetry += 1 }
          .disabled(renderingPreview)
      }
    }
  }
  @ViewBuilder func transformHandles(_ cell: CollageCell, rect: CGRect, viewport: CGSize) -> some View {
    ForEach(OverlayResizeHandle.allCases, id: \.rawValue) { handle in
      let point = handle.anchor
      let dx = (point.x - 0.5) * rect.width, dy = (point.y - 0.5) * rect.height
      let angle = cell.rotation * .pi / 180
      Circle().fill(.white).overlay(Circle().stroke(.blue)).frame(width: 9, height: 9)
        .frame(width: 44, height: 44).contentShape(Rectangle())
        .position(x: rect.midX + dx * cos(angle) - dy * sin(angle), y: rect.midY + dx * sin(angle) + dy * cos(angle))
        .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("CollageCanvas")).onChanged { value in
          beginTransform(cell)
          guard let original = transformStart, let index = model.collage.cells.firstIndex(where: { $0.id == cell.id }) else { return }
          let band = model.collage.title.isEmpty ? 0.0 : 0.12
          model.collage.cells[index] = CollageGeometry.resized(original, handle: handle, translation: value.translation,
            viewport: CGSize(width: viewport.width, height: viewport.height * (1 - band)))
        }.onEnded { _ in finishInteraction(); transformStart = nil })
        .accessibilityLabel("Resize photo frame " + handle.rawValue)
    }
    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
      .position(x: rect.midX, y: max(22, rect.minY - 24))
      .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("CollageCanvas")).onChanged { value in
        beginTransform(cell)
        guard let original = transformStart, let index = model.collage.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        let band = model.collage.title.isEmpty ? 0.0 : 0.12
        let offset = viewport.height * band
        model.collage.cells[index] = CollageGeometry.rotated(original,
          from: CGPoint(x: value.startLocation.x, y: value.startLocation.y - offset),
          to: CGPoint(x: value.location.x, y: value.location.y - offset),
          viewport: CGSize(width: viewport.width, height: viewport.height * (1 - band)))
      }.onEnded { _ in finishInteraction(); transformStart = nil })
      .accessibilityLabel("Rotate photo frame")
  }
  func beginTransform(_ cell: CollageCell) {
    if interactionStart == nil { interactionStart = model.collage; transformStart = cell }
  }
  func hit(_ point:CGPoint,in size:CGSize) -> CollageCell? {
    if let shape=model.collage.silhouette {
      let band=model.collage.title.isEmpty ? 0.0 : 0.12
      let bounds=CGRect(x:0,y:size.height*band,width:size.width,height:size.height*(1-band))
      guard shape.path(in:bounds,text:model.collage.silhouetteText, fontName: model.collage.silhouetteFontName, multiline: model.collage.silhouetteTextLayout >= 2).contains(point,using:.evenOdd) else {return nil}
    }
    return model.collage.cells.reversed().first { cell in
      let rect=model.collage.rect(for:cell,output:size), angle = -cell.rotation * .pi/180
      let dx=point.x-rect.midX, dy=point.y-rect.midY
      let local=CGPoint(x:rect.midX+dx*cos(angle)-dy*sin(angle),y:rect.midY+dx*sin(angle)+dy*cos(angle))
      return (cell.shape ?? .rectangle).path(in:rect,text:model.collage.silhouetteText, fontName: model.collage.silhouetteFontName, multiline: model.collage.silhouetteTextLayout >= 2).contains(local,using:.evenOdd)
    }
  }
  func finishInteraction() {
    if let before=interactionStart { let final=model.collage; model.collage=before; model.changeCollage(final) }
    interactionStart=nil; start=nil
  }
  var artControls: some View {
    VStack(alignment:.leading,spacing:10) {
      Text(artMode == "Photomosaic" ? "Photo Mosaic" : artMode + " Collage").font(.headline)
      Picker("Create",selection:$artMode) {
        Text("Shape").tag("Shape"); Text("Text").tag("Text"); Text("Photomosaic").tag("Photomosaic")
      }.pickerStyle(.menu)
      if artMode == "Shape" {
        Picker("Composition shape",selection:$artShape) {
          ForEach(CollageShape.allCases.filter { $0 != .text },id:\.self) { Text($0.rawValue).tag($0) }
        }
      } else if artMode == "Text" {
        TextField("Text silhouette, e.g. HELLO", text: $artText, axis: .vertical).lineLimit(1...4)
        Picker("Outline font", selection: $artFont) {
          Text("Helvetica Neue Bold").tag("HelveticaNeue-Bold")
          Text("Avenir Next Heavy").tag("AvenirNext-Heavy")
          Text("Georgia Bold").tag("Georgia-Bold")
          Text("Menlo Bold").tag("Menlo-Bold")
        }
        Text("1–64 outline characters across one or more lines. Photos fill the letters; spaces and letter holes stay open.").font(.caption).foregroundStyle(.secondary)
      } else {
        Text("1. Choose the picture to recreate").font(.headline)
        Button("Choose Reference Image…",systemImage:"photo") {referenceSelection=referenceID.map {[$0]} ?? [];choosingReference=true}
          .sheet(isPresented: $choosingReference) {
            CollagePhotoPicker(model: model, selection: $referenceSelection, single: true, title: "Mosaic Reference") {
              referenceID = referenceSelection.first; choosingReference = false
            }
          }
        if let reference=model.assets.first(where:{$0.id==referenceID}) {
          FramingSurface(model:model,asset:reference,interactive:false,maximum:200).frame(height:100)
          Text(reference.name).font(.caption).lineLimit(2)
        }
        Toggle("Allow photo reuse",isOn:$reuse)
        Text("Matches photo colours and local tones to the reference, which fills the canvas. Repetition improves matching with smaller libraries. No reference pixels are pasted into the tiles, and photos are not tinted. Results depend on your photo palette.").font(.caption).foregroundStyle(.secondary)
      }
      Text(artMode == "Photomosaic" ? "2. Choose tile photos" : "Choose photos to fill the composition").font(.headline)
      Toggle("Use entire workspace",isOn:$useAllSources)
      Text(useAllSources ? "All library photos are candidates. The reference is excluded." : "The current composition’s photos are candidates. Use Choose Source Photos to change them.").font(.caption).foregroundStyle(.secondary)
      Text("3. Choose detail and generate").font(.headline)
      TextField("Number of photo tiles (1–10,000)",value:$tileCount,format:.number)
      Text("Candidates: \(useAllSources ? model.workspaceAssets.count : Set(model.collage.cells.map(\.sourceID)).count) photos · Requested: \(tileCount) tiles").font(.caption)
      Button("Generate \(artMode)") {
        let ids=useAllSources ? Set(model.workspaceAssets.map(\.id)) : Set(model.collage.cells.map(\.sourceID))
        artPresented = false
        model.generateCollageArt(shape:artMode == "Photomosaic" ? nil : artMode == "Text" ? .text : artShape,text:artText,sourceIDs:ids,count:tileCount,referenceID:artMode == "Photomosaic" ? referenceID : nil,reuse:reuse,fontName:artFont)
      }.disabled(model.collageGenerating || model.running || tileCount < 1 || tileCount > CollageProject.maximumCells || (useAllSources ? model.workspaceAssets.isEmpty : model.collage.cells.isEmpty) || (artMode == "Photomosaic" && referenceID == nil))
      Text("Generation replaces this composition’s arrangement. Undo restores the previous layout.").font(.caption).foregroundStyle(.secondary)
      Divider()
      Picker("Photo frame shape · all tiles",selection:Binding(get:{ model.collage.cells.first?.shape ?? .rectangle },set:{ shape in
        var p=model.collage; for i in p.cells.indices { p.cells[i].shape=shape }; model.changeCollage(p)
      })) {
        ForEach(CollageShape.allCases.filter { $0 != .text },id:\.self) { Text($0.rawValue).tag($0) }
      }
      if model.collage.cells.count > 200 {
        HStack {
          TextField("Tile number",value:$selectedTileNumber,format:.number)
          Button("Select Tile") {
            if model.collage.cells.indices.contains(selectedTileNumber-1) {selected=model.collage.cells[selectedTileNumber-1].id}
          }
        }
      } else {
        Picker("Selected photo",selection:$selected) {
          Text("Tap a photo on the canvas").tag(UUID?.none)
          ForEach(Array(model.collage.cells.enumerated()),id:\.element.id) {index,cell in Text("Tile \(index+1)").tag(Optional(cell.id))}
        }
      }
    }
  }
  var compositionControls: some View {
    VStack(alignment: .leading, spacing: 12) {
          if inspector == .composition { canvasControls }
          if inspector == .photo { InspectorHeading(title: selectedCellTitle) }
          if inspector == .output { InspectorHeading(title: "Output Settings") }
          if inspector == .photo {
          if let id = selected, let cell = model.collage.cells.first(where: { $0.id == id }) {
            let b = cellBinding(id)
            Text(model.collage.layout == .freeform && moveFrames ? "Move Frames · drag to move; pinch to resize the frame." : "Reframe Photo · drag to position; pinch to crop closer.")
              .font(.caption).foregroundStyle(.secondary)
            if model.collage.layout == .freeform {
              Picker("Canvas interaction", selection: $moveFrames) { Text("Move Frames").tag(true); Text("Reframe Photos").tag(false) }.pickerStyle(.segmented)
            }
            propertyRow("Shape") { Picker("Photo frame shape",selection:Binding(get:{ cell.shape ?? .rectangle },set:{ value in var p=model.collage; if let i=p.cells.firstIndex(where:{$0.id==id}) {p.cells[i].shape=value};model.changeCollage(p) })) {
              ForEach(CollageShape.allCases.filter { $0 != .text },id:\.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden() }
            TextField(
              "Caption",
              text: Binding(
                get: { model.collage.captions[id] ?? "" },
                set: {
                  var p = model.collage
                  p.captions[id] = $0
                  model.changeCollage(p)
                }))
            Button("Replace Photograph…", systemImage: "photo.on.rectangle") {
              replacementSelection = [cell.sourceID]; replacingCell = true
            }
            Label("Drag to swap with another tile", systemImage: "arrow.left.arrow.right")
              .draggable("ameluma-cell:" + cell.id.uuidString)
              .font(.caption).help("Drag this label onto a photo tile to swap photos and their framing.")
            HStack {
              Button("Bring to Front") {
                var p = model.collage; p.cells.removeAll { $0.id == id }; p.cells.append(cell); model.changeCollage(p)
              }
              Button("Send to Back") {
                var p = model.collage; p.cells.removeAll { $0.id == id }; p.cells.insert(cell, at: 0); model.changeCollage(p)
              }
            }
            propertySlider("Zoom", value: b.crop.zoom, range: 1...8)
            propertySlider("Horizontal", value: b.crop.centerX, range: 0...1, percentage: true)
            propertySlider("Vertical", value: b.crop.centerY, range: 0...1, percentage: true)
            if model.collage.layout == .freeform {
              propertySlider("Position X", value: b.x, range: 0...0.9, percentage: true)
              propertySlider("Position Y", value: b.y, range: 0...0.9, percentage: true)
              propertySlider("Width", value: b.width, range: 0.1...1, percentage: true)
              propertySlider("Height", value: b.height, range: 0.1...1, percentage: true)
              InspectorSlider(title: "Rotation", value: b.rotation, range: -180...180, interaction: sliderInteraction)
            }
            Button("Swap Photos with Next · Keep Frame Crops") {
              var p = model.collage
              if let i = p.cells.firstIndex(where: { $0.id == cell.id }), p.cells.count > 1 {
                let j = (i + 1) % p.cells.count
                let old = p.cells[i].sourceID
                p.cells[i].sourceID = p.cells[j].sourceID
                p.cells[j].sourceID = old
                model.changeCollage(p)
              }
            }
            Button("Remove photograph", role: .destructive) {
              var p = model.collage
              p.cells.removeAll { $0.id == id }
              model.changeCollage(p)
            }
          }
          if selected == nil { Text("Select a photo on the canvas to crop, replace or remove it.").font(.callout).foregroundStyle(.secondary) }
          }
          if inspector == .output { outputControls }
    }.padding(14).disabled(model.collageGenerating || model.running)
  }
  var outputControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(CreationOutputSummary.collage(model.collage)).font(.callout).monospacedDigit()
      Text("Destination: local Exports folder, then Review & Share.").font(.caption).foregroundStyle(.secondary)
          propertyRow("Format") { Picker("Output format", selection: project.outputFormat) {
            ForEach(ImageProcessor.outputFormats, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
          }.labelsHidden() }
          if model.collage.outputFormat.supportsQuality {
            LabeledContent("Quality", value: model.collage.outputQuality, format: .percent)
            Slider(value: project.outputQuality, in: 0.1...1, onEditingChanged: sliderInteraction)
          }
          if !model.collage.outputFormat.preservesAlpha {
            Text("This format flattens transparent pixels onto white.").font(.caption).foregroundStyle(.secondary)
          }
          Button("Export & Share") { export() }.buttonStyle(.borderedProminent).disabled(exporting || model.collage.cells.isEmpty)
          if let id=model.activeCollageID, let output=outputs[id] {
            if output.identity == renderIdentity {
              Button("Review & Share Current Export") { exportingOptions = false; reviewSession = ShareOutputSession(outputs: [output.url], summary: "Current composition · 1 " + model.collage.outputFormat.rawValue.uppercased() + " file") }
            } else {
              Label("Previous export is out of date", systemImage: "clock.badge.exclamationmark").font(.caption)
              Text("Export again to include your latest edits. The previous file is retained in export history.").font(.caption).foregroundStyle(.secondary)
            }
          }
    }.disabled(model.collageGenerating || model.running)
  }
  var selectedCellTitle: String {
    guard let selected, let index = model.collage.cells.firstIndex(where: { $0.id == selected }) else { return "Photo Cell" }
    return "Photo Cell \(index + 1)"
  }
  func cellBinding(_ id: UUID) -> Binding<CollageCell> {
    Binding(
      get: {
        model.collage.cells.first { $0.id == id }
          ?? CollageCell(sourceID: UUID(), x: 0, y: 0, width: 1, height: 1)
      },
      set: { value in
        var p = model.collage
        if let i = p.cells.firstIndex(where: { $0.id == id }) { p.cells[i] = value }
        if interactionStart != nil { model.collage = p } else { model.changeCollage(p) }
      })
  }
  func sliderInteraction(_ began: Bool) {
    if began { interactionStart = model.collage }
    else { finishInteraction() }
  }
  func export() {
    exportingOptions = false
    guard let collageID=model.activeCollageID else { return }
    let project=model.collage, sources=model.assets, edits=model.edits
    let identity = renderIdentity
    let filename=model.activeCollageName + "." + project.outputFormat.fileExtension
    exporting = true
    model.exportingPlanSummary = nil
    model.exportingRequests = []
    model.running = true
    model.total = project.cells.count+1
    model.completed = 0
    model.status = "Rendering collage…"
    model.collageTask = Task {
      defer {
        exporting = false
        model.running = false
      }
      do {
        let folder = model.directory.deletingLastPathComponent().appendingPathComponent(
          "Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cg = try await model.processor.renderCollage(
          project, sources:sources, edits:edits, progress: {done,total in
            await MainActor.run {
              model.completed=done;model.total=total+1
              model.status="Rendering collage tiles · \(done) / \(total)"
            }
          })
        var c = ProcessingConfiguration()
        c.format = project.outputFormat; c.quality = project.outputQuality
        c.width = cg.width
        c.height = cg.height
        let result = try await model.processor.publish(
          cg, asset: SourceAsset(url: model.projectURL, name: filename), configuration: c,
          to: folder, flattenTransparency: true)
        if let url=result.output { outputs[collageID]=ExportedComposition(url: url, identity: identity, date: Date()) }
        if let url = result.output {
          model.collageOutputs.append(url)
          model.completed = model.total
          model.status = "Collage exported and validated."
          model.persist()
          reviewSession = ShareOutputSession(outputs: [url], summary: "Composition · 1 " + project.outputFormat.rawValue.uppercased() + " file")
        }
      } catch is CancellationError {
        model.status = "Collage render cancelled; completed outputs remain available."
      } catch { model.issues.append(error.localizedDescription) }
    }
  }
}
