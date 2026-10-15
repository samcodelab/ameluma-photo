import FramepebbleCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif
struct CollageEditor: View {
  @Bindable var model: Workspace
  var embedded = false
  @State private var choosingSources = false
  @State private var sourceSelection: Set<UUID> = []
  @State private var image: CGImage?
  @State private var selected: UUID?
  @State private var sizes: [UUID: CGSize] = [:]
  @State private var start: CropConfiguration?
  @State private var exporting = false
  @State private var output: URL?
  @State private var reviewSession: ShareOutputSession?
  @Environment(\.dismiss) private var dismiss
  var project: Binding<CollageProject> {
    Binding(get: { model.collage }, set: { model.changeCollage($0) })
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          Text("Composition · \(model.collage.cells.count) photo \(model.collage.cells.count == 1 ? "cell" : "cells") → 1 PNG file").font(.headline)
          Button("Choose Source Photos…") { sourceSelection = Set(model.collage.cells.map(\.sourceID)); choosingSources = true }
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
          .pickerStyle(.segmented)
          if embedded {
            HStack(alignment: .top, spacing: 20) {
              compositionCanvas.frame(maxWidth: .infinity).frame(height: 520)
              ScrollView { compositionControls }.frame(width: 320, height: 520)
            }
          } else {
            compositionCanvas
            compositionControls
          }
        }.padding()
      }.navigationTitle("Make a Collage").compactNavigationTitle().toolbar {
        if !embedded { Button("Done") { dismiss() } }
        else { Button("Export & Share This Collage") { export() }.disabled(exporting || model.collage.cells.isEmpty) }
      }
      .sheet(isPresented: $choosingSources) {
        NavigationStack {
          List(model.assets) { asset in
            Toggle(asset.name, isOn: Binding(get: { sourceSelection.contains(asset.id) }, set: { if $0 { sourceSelection.insert(asset.id) } else { sourceSelection.remove(asset.id) } }))
          }.navigationTitle("Collage Sources").toolbar {
            Button("Select All") { sourceSelection = Set(model.assets.map(\.id)) }
            Button("Cancel") { choosingSources = false }
            Button("Use Selected Photos") {
              var value = model.collage
              value.arrange(model.assets.filter { sourceSelection.contains($0.id) }.map(\.id), layout: value.layout)
              model.changeCollage(value); choosingSources = false
            }.disabled(sourceSelection.isEmpty)
          }
        }.frame(minWidth: 320, minHeight: 440)
          .onAppear { sourceSelection = Set(model.collage.cells.map(\.sourceID)) }
      }
      .task {
        for asset in model.assets {
          if let raw = try? await model.processor.identify(asset.url) {
            sizes[asset.id] = ImageProcessor.transformedSize(
              raw, configuration: model.configuration(for: asset))
          }
        }
      }
      .task(id: model.collage) {
        do {
          try await Task.sleep(for: .milliseconds(80))
          image = try await model.processor.renderCollage(
            model.collage, sources: model.assets, edits: model.edits, previewMaximum: 900)
        } catch is CancellationError {} catch { model.issues.append(error.localizedDescription) }
      }
      .sheet(item: $reviewSession) { session in
        ShareReview(urls: session.outputs, summary: session.summary).privacyCurtain(model: model)
      }
      .onDisappear { model.collageTask?.cancel() }
      .onAppear {
        if model.collage.cells.isEmpty {
          var p = model.collage
          p.arrange(model.filtered.filter { model.selection.contains($0.id) }.map(\.id), layout: .magazine)
          model.changeCollage(p)
        }
      }
    }.frame(minWidth: 320, minHeight: 500).overlay {
      SensitivePreviewCover(model: model, ids: Set(model.collage.cells.map(\.sourceID)))
    }
  }
  @ViewBuilder var compositionCanvas: some View {
          if let image {
            GeometryReader { proxy in
              ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable()
                ForEach(model.collage.cells) { cell in
                  let rect = model.collage.rect(for: cell, output: proxy.size)
                  Rectangle().fill(.clear).overlay(
                    Rectangle().stroke(selected == cell.id ? Color.blue : Color.clear, lineWidth: 2)
                  ).frame(width: rect.width, height: rect.height).position(
                    x: rect.midX, y: rect.midY
                  )
                  .contentShape(Rectangle()).onTapGesture { selected = cell.id }
                  .gesture(
                    DragGesture(minimumDistance: 4).onChanged { gesture in
                      selected = cell.id
                      if start == nil { start = cell.crop }
                      guard let size = sizes[cell.sourceID] else { return }
                      var p = model.collage
                      if let i = p.cells.firstIndex(where: { $0.id == cell.id }) {
                        p.cells[i].crop = CropGeometry.dragged(
                          start ?? cell.crop, source: size, frame: rect.size,
                          translation: gesture.translation, ratio: Double(rect.width / rect.height))
                        model.collage = p
                      }
                    }.onEnded { _ in
                      if let begin = start,
                        let i = model.collage.cells.firstIndex(where: { $0.id == cell.id })
                      {
                        let final = model.collage
                        model.collage.cells[i].crop = begin
                        model.changeCollage(final)
                      }
                      start = nil
                    }
                  )
                  .accessibilityLabel(
                    "Collage photo \(model.collage.cells.firstIndex(where:{$0.id==cell.id}).map{$0+1} ?? 1)"
                  )
                }
              }
            }.aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit).frame(maxWidth: 760)
          } else {
            ProgressView().frame(height: 200)
          }
  }
  var compositionControls: some View {
    VStack(alignment: .leading, spacing: 12) {
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
          if exporting { Button("Cancel collage render") { model.collageTask?.cancel() } }
          if let output { Button("Review & Share This Collage") { reviewSession = ShareOutputSession(outputs: [output], summary: "Composition · 1 PNG file") } }
    }.padding(8)
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
    exporting = true
    model.exportingPlanSummary = nil
    model.exportingRequests = []
    model.running = true
    model.total = 1
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
          model.collage, sources: model.assets, edits: model.edits)
        var c = ProcessingConfiguration()
        c.format = .png
        c.width = cg.width
        c.height = cg.height
        let result = try await model.processor.publish(
          cg, asset: SourceAsset(url: model.projectURL, name: "Collage.png"), configuration: c,
          to: folder)
        output = result.output
        if let url = result.output {
          model.collageOutputs.append(url)
          model.completed = 1
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
