import FramepebbleCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif
struct CollageEditor: View {
  @Bindable var model: Workspace
  var embedded = false
  @State private var gallery = false
  @State private var artMode = "Shape"
  @State private var artShape: CollageShape = .heart
  @State private var artText = "HELLO"
  @State private var tileCount = 100
  @State private var referenceID: UUID?
  @State private var reuse = true
  @State private var useAllSources = false
  @State private var rename = false
  @State private var collageName = ""
  @State private var renderedID: UUID?
  @State private var interactionStart: CollageProject?
  @State private var choosingSources = false
  @State private var choosingReference = false
  @State private var referenceSelection: Set<UUID> = []
  @State private var artExpanded = false
  @State private var artPresented = false
  @State private var selectedTileNumber = 1
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var sourceSelection: Set<UUID> = []
  @State private var image: CGImage?
  @State private var selected: UUID?
  @State private var sizes: [UUID: CGSize] = [:]
  @State private var start: CropConfiguration?
  @State private var exporting = false
  @State private var outputs: [UUID:URL] = [:]
  @State private var reviewSession: ShareOutputSession?
  @Environment(\.dismiss) private var dismiss
  var project: Binding<CollageProject> {
    Binding(get: { model.collage }, set: { model.changeCollage($0) })
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          collageTabs
          if model.activeCollageID != nil {
          creationChoices
          Text("Composition · \(model.collage.cells.count) photo \(model.collage.cells.count == 1 ? "cell" : "cells") → 1 PNG file").font(.headline)
          Button("Choose Source Photos…") { sourceSelection = Set(model.collage.cells.map(\.sourceID)); choosingSources = true }.disabled(model.running || model.collageGenerating)
          Picker(
            "Layout",
            selection: Binding(
              get: { model.collage.layout },
              set: { layout in
                var p = model.collage
                p.arrange(p.cells.map(\.sourceID), layout: layout)
                model.changeCollage(p)
              })
          ) { ForEach(CollageLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          .pickerStyle(.segmented).disabled(model.running || model.collageGenerating)
          ViewThatFits(in:.horizontal) {
            HStack {collageActions}.fixedSize(horizontal:true,vertical:false)
            Menu("Collage Actions") {collageActions}
          }.disabled(model.running || model.collageGenerating)
          if let template=CollageTemplate.catalog.first(where:{$0.id==model.collage.templateID}) {
            Text("Layout: " + template.name).font(.caption).foregroundStyle(.secondary)
          }
          if embedded {
            ViewThatFits(in:.horizontal) {
              HStack(alignment:.top,spacing:20) {
                compositionCanvas.frame(maxWidth:.infinity).frame(height:520)
                ScrollView {compositionControls}.frame(width:320,height:520)
              }.frame(minWidth:760)
              VStack {compositionCanvas;compositionControls}
            }
          } else {
            compositionCanvas
            compositionControls
          }
          } else {
            ContentUnavailableView("Your Collages",systemImage:"rectangle.split.2x2",description:Text("Create a collage or reopen a saved composition. Closing a tab keeps its editable project."))
            Button("Open Layout Gallery…") { gallery=true }.buttonStyle(.borderedProminent)
            creationChoices
          }
        }.padding()
      }.safeAreaInset(edge:.top,spacing:0) {activityBar}
      .navigationTitle(model.activeCollageName).compactNavigationTitle().toolbar {
        if !embedded { Button("Done") { dismiss() } }
        else { Button("Export & Share This Collage") { export() }.disabled(exporting || model.collageGenerating || model.activeCollageID == nil || model.collage.cells.isEmpty) }
      }
      .sheet(isPresented: $artPresented) {
        NavigationStack {
          ScrollView { artControls.padding() }
            .navigationTitle(artMode == "Photomosaic" ? "Photo Mosaic" : artMode + " Collage")
            .toolbar { Button("Done") { artPresented = false } }
        }.frame(minWidth: 320, minHeight: 440)
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
          let ids=model.assets.filter {sourceSelection.contains($0.id)}.map(\.id)
          if let template=CollageTemplate.catalog.first(where:{$0.id==value.templateID}) {template.apply(to:&value,sources:ids)}
          else {value.arrange(ids,layout:value.layout)}
          model.changeCollage(value);choosingSources=false
        }
      }
      .task(id:Set(model.collage.cells.map(\.sourceID))) {
        let ids=Set(model.collage.cells.map(\.sourceID))
        for asset in model.assets where ids.contains(asset.id) {
          do {
            let raw=try await model.processor.identify(asset.url)
            try Task.checkCancellation()
            sizes[asset.id]=raw
          } catch is CancellationError { return } catch { model.issues.append("A collage photo could not be read for framing: " + error.localizedDescription) }
        }
      }
      .task(id:PreviewKey(project:model.collage,edits:model.edits,id:model.activeCollageID)) {
        let project=model.collage, edits=model.edits, id=model.activeCollageID, sources=model.assets
        do {
          try await Task.sleep(for:.milliseconds(100))
          let preview=try await model.processor.renderCollage(project,sources:sources,edits:edits,previewMaximum:900)
          try Task.checkCancellation()
          guard id == model.activeCollageID else { return }
          image=preview; renderedID=id
        } catch is CancellationError { } catch { model.issues.append(error.localizedDescription) }
      }
      .sheet(item: $reviewSession) { session in
        ShareReview(urls: session.outputs, summary: session.summary).privacyCurtain(model: model)
      }
      .onDisappear { model.collageTask?.cancel() }
      .onAppear { model.ensureCollageDocument() }
      .onChange(of:model.activeCollageID) { _,_ in selected=nil; start=nil; interactionStart=nil }

    }.background(.background).frame(minWidth: 320, minHeight: 500).overlay {
      SensitivePreviewCover(model: model, ids: Set(model.collage.cells.map(\.sourceID)).union(model.collage.mosaicReferenceID.map { [$0] } ?? []))
    }
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
      if model.activeCollageID == nil { model.newCollage() }
      if let mode { artMode = mode; artExpanded = true; artPresented = true }
      else { gallery = true }
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
    Button("Layout Gallery…",systemImage:"square.grid.3x3") {gallery=true}
    Button("New Collage",systemImage:"plus") {model.newCollage()}
    Button("Rename…") {collageName=model.activeCollageName;rename=true}
  }
  @ViewBuilder var collageTabs: some View {
    if sizeClass == .compact {
      HStack {
        Menu("Open Collages (\(model.openCollageIDs.count))") {
          ForEach(model.savedCollages) {item in Button(item.name) {model.activateCollage(item.id)}}
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
              .background(model.activeCollageID == id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
          }
          Button { model.newCollage() } label: { Image(systemName:"plus") }.comfortableHitTarget().accessibilityLabel("New collage")
        }
      }.disabled(model.running || model.collageGenerating)
    }
  }
  @ViewBuilder var compositionCanvas: some View {
    if let image, renderedID == model.activeCollageID {
      GeometryReader { proxy in
        ZStack(alignment:.topLeading) {
          Image(decorative:image,scale:1).resizable()
          if let cell=model.collage.cells.first(where: { $0.id == selected }) {
            let r=model.collage.rect(for:cell,output:proxy.size)
            Rectangle().stroke(.blue,lineWidth:2).frame(width:r.width,height:r.height)
              .rotationEffect(.degrees(cell.rotation)).position(x:r.midX,y:r.midY).allowsHitTesting(false)
          }
        }.contentShape(Rectangle())
          .onTapGesture { point in selected=hit(point,in:proxy.size)?.id }
          .gesture(DragGesture(minimumDistance:4).onChanged { gesture in
            guard !model.collageGenerating, !model.running else { return }
            if interactionStart == nil {
              guard let cell=hit(gesture.startLocation,in:proxy.size) else { return }
              selected=cell.id; start=cell.crop; interactionStart=model.collage
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
            guard let start else {return}
            var p=model.collage
            if let i=p.cells.firstIndex(where:{$0.id==cell.id}) {p.cells[i].crop=CropGeometry.zoomed(start,factor:value.magnification);model.collage=p}
          }.onEnded {_ in finishInteraction()})
          .accessibilityLabel("Collage canvas, \(model.collage.cells.count) photo tiles. Select a tile to reframe, or use Selected photo controls.")
      }.aspectRatio(CGFloat(image.width)/CGFloat(image.height),contentMode:.fit).frame(maxWidth:1000)
    } else { ProgressView("Rendering composition…").frame(height:240) }
  }
  func hit(_ point:CGPoint,in size:CGSize) -> CollageCell? {
    if let shape=model.collage.silhouette {
      let band=model.collage.title.isEmpty ? 0.0 : 0.12
      let bounds=CGRect(x:0,y:size.height*band,width:size.width,height:size.height*(1-band))
      guard shape.path(in:bounds,text:model.collage.silhouetteText).contains(point,using:.evenOdd) else {return nil}
    }
    return model.collage.cells.reversed().first { cell in
      let rect=model.collage.rect(for:cell,output:size), angle = -cell.rotation * .pi/180
      let dx=point.x-rect.midX, dy=point.y-rect.midY
      let local=CGPoint(x:rect.midX+dx*cos(angle)-dy*sin(angle),y:rect.midY+dx*sin(angle)+dy*cos(angle))
      return (cell.shape ?? .rectangle).path(in:rect,text:model.collage.silhouetteText).contains(local,using:.evenOdd)
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
        TextField("Text silhouette, e.g. HELLO",text:$artText)
        Text("1–64 outline letters. Photos fill the letters; spaces and letter holes stay open.").font(.caption).foregroundStyle(.secondary)
      } else {
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
      Toggle("Use entire photo library",isOn:$useAllSources)
      Text(useAllSources ? "All library photos are candidates. The reference is excluded." : "The current composition’s photos are candidates. Use Choose Source Photos to change them.").font(.caption).foregroundStyle(.secondary)
      TextField("Number of photo tiles (1–10,000)",value:$tileCount,format:.number)
      Text("Requested: \(tileCount) tiles · Composition: \(model.collage.cells.count) tiles").font(.caption)
      Button("Generate \(artMode)") {
        let ids=useAllSources ? Set(model.assets.map(\.id)) : Set(model.collage.cells.map(\.sourceID))
        artPresented = false
        model.generateCollageArt(shape:artMode == "Photomosaic" ? nil : artMode == "Text" ? .text : artShape,text:artText,sourceIDs:ids,count:tileCount,referenceID:artMode == "Photomosaic" ? referenceID : nil,reuse:reuse)
      }.disabled(model.collageGenerating || model.running || tileCount < 1 || tileCount > CollageProject.maximumCells)
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
          DisclosureGroup("Shape, Text & Photo Mosaic",isExpanded:$artExpanded) {artControls}
          Divider()
          TextField("Collage title", text: project.title)
          Picker("Title colour", selection: project.titleColour) {
            Text("Dark").tag(RGBAColour(0, 0, 0, 1))
            Text("Light").tag(RGBAColour(1, 1, 1, 1))
            Text("Blue").tag(RGBAColour(0, 0.3, 1, 1))
          }
          HStack {
            TextField("Width", value: project.width, format: .number)
            Text("×")
            TextField("Height", value: project.height, format: .number)
          }
          Text("Spacing")
          Slider(value: project.spacing, in: 0...0.08)
          Picker("Background", selection: project.background) {
            Text("White").tag(RGBAColour(1, 1, 1, 1))
            Text("Black").tag(RGBAColour(0, 0, 0, 1))
            Text("Transparent").tag(RGBAColour(0, 0, 0, 0))
          }
          Toggle("Shadows", isOn: project.shadow)
          Text("Borders")
          Slider(value: project.canvas.border, in: 0...0.05)
          Text("Corners")
          Slider(value: project.canvas.cornerRadius, in: 0...0.3)
          if let id = selected, let cell = model.collage.cells.first(where: { $0.id == id }) {
            let b = cellBinding(id)
            Picker("Photo frame shape",selection:Binding(get:{ cell.shape ?? .rectangle },set:{ value in var p=model.collage; if let i=p.cells.firstIndex(where:{$0.id==id}) {p.cells[i].shape=value};model.changeCollage(p) })) {
              ForEach(CollageShape.allCases.filter { $0 != .text },id:\.self) { Text($0.rawValue).tag($0) }
            }
            TextField(
              "Caption",
              text: Binding(
                get: { model.collage.captions[id] ?? "" },
                set: {
                  var p = model.collage
                  p.captions[id] = $0
                  model.changeCollage(p)
                }))
            Picker("Photograph", selection: b.sourceID) {
              ForEach(model.assets) { Text($0.name).tag($0.id) }
            }
            Text("Zoom")
            Slider(value: b.crop.zoom, in: 1...8)
            Text("Horizontal framing")
            Slider(value: b.crop.centerX, in: 0...1)
            Text("Vertical framing")
            Slider(value: b.crop.centerY, in: 0...1)
            if model.collage.layout == .freeform {
              Text("Position X")
              Slider(value: b.x, in: 0...0.9)
              Text("Position Y")
              Slider(value: b.y, in: 0...0.9)
              Text("Width")
              Slider(value: b.width, in: 0.1...1)
              Text("Height")
              Slider(value: b.height, in: 0.1...1)
              Text("Rotation")
              Slider(value: b.rotation, in: -45...45)
            }
            Button("Swap with next") {
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
          Menu("Add photograph") {
            ForEach(model.assets) { asset in
              Button(asset.name) {
                var p = model.collage
                let ids = p.cells.map(\.sourceID) + [asset.id]
                p.arrange(ids, layout: p.layout)
                model.changeCollage(p)
              }
            }
          }
          HStack {
            Button("Undo") { model.undoCollage() }.disabled(model.collageUndo.isEmpty)
            Button("Redo") { model.redoCollage() }.disabled(model.collageRedo.isEmpty)
          }
          Button("Render & Share Collage") { export() }.buttonStyle(.borderedProminent).disabled(
            exporting || model.collage.cells.isEmpty)

          if let id=model.activeCollageID, let output=outputs[id] { Button("Review & Share This Collage") { reviewSession = ShareOutputSession(outputs: [output], summary: "Composition · 1 PNG file") } }
    }.padding(8).disabled(model.collageGenerating || model.running)
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
        model.changeCollage(p)
      })
  }
  func export() {
    guard let collageID=model.activeCollageID else { return }
    let project=model.collage, sources=model.assets, edits=model.edits
    let filename=model.activeCollageName + ".png"
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
        c.format = .png
        c.width = cg.width
        c.height = cg.height
        let result = try await model.processor.publish(
          cg, asset: SourceAsset(url: model.projectURL, name: filename), configuration: c,
          to: folder)
        if let url=result.output { outputs[collageID]=url }
        if let url = result.output {
          model.collageOutputs.append(url)
          model.completed = model.total
          model.status = "Collage exported and validated."
          model.persist()
          reviewSession = ShareOutputSession(outputs: [url], summary: "Composition · 1 PNG file")
        }
      } catch is CancellationError {
        model.status = "Collage render cancelled; completed outputs remain available."
      } catch { model.issues.append(error.localizedDescription) }
    }
  }
}
