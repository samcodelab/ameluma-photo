import FramepebbleCore
import SwiftUI

struct CollageGallery: View {
  @Bindable var model: Workspace
  @Environment(\.dismiss) private var dismiss
  @State private var category = "All"
  @State private var query = ""
  @State private var createNew = false
  @State private var orientation = "Any"
  @State private var recommendedOnly = true
  var templates: [CollageTemplate] {
    let result = CollageTemplate.catalog.filter {
      (category == "All" || $0.category == category) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) &&
      (orientation == "Any" || orientation == "Square" && abs($0.aspect - 1) < 0.01 || orientation == "Landscape" && $0.aspect > 1.01 || orientation == "Portrait" && $0.aspect < 0.99)
    }
    guard recommendedOnly && category == "All" && query.isEmpty else { return result }
    var counts: [String: Int] = [:]
    return result.filter { item in
      let key = item.category
      let count = counts[key, default: 0]; counts[key] = count + 1
      return count < 3
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:20) {
          if !model.savedCollages.isEmpty {
            Text("Your Collages").font(.title2.bold())
            LazyVGrid(columns:[GridItem(.adaptive(minimum:160))],spacing:14) {
              ForEach(model.savedCollages) { item in
                Button {
                  model.activateCollage(item.id); dismiss()
                } label: {
                  VStack(alignment:.leading) {
                    CollageCardPreview(model: model, project: item.project).aspectRatio(CGFloat(item.project.width)/CGFloat(max(1,item.project.height)),contentMode:.fit).frame(height:110)
                    Text(item.name).font(.headline).lineLimit(2)
                    Text("\(item.project.cells.count) photo tiles").font(.caption).foregroundStyle(.secondary)
                  }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
                }.buttonStyle(.plain)
              }
            }
          }
          Text("Layout Gallery · \(CollageTemplate.catalog.count) layouts").font(.title2.bold())
          Text("Preview an arrangement, then apply it to the current composition or create a separate collage. Layout changes can be undone.").font(.callout).foregroundStyle(.secondary)
          if model.activeCollageID != nil {
            Picker("Layout action", selection: $createNew) {
              Text("Apply to Current Collage").tag(false)
              Text("Create New Collage").tag(true)
            }.pickerStyle(.segmented)
          }
          Toggle("Recommended layouts", isOn: $recommendedOnly)
          Picker("Orientation", selection: $orientation) {
            ForEach(["Any", "Square", "Landscape", "Portrait"], id: \.self) { Text($0) }
          }
          Text("Layout previews use up to 24 of your chosen photos. Saved compositions show their actual content unless Private Editing Mode is enabled.").font(.caption).foregroundStyle(.secondary)
          Picker("Layout category",selection:$category) {
            ForEach(["All","Grids","Editorial","Strips","Mosaics","Freeform"],id:\.self) { Text($0) }
          }.pickerStyle(.menu)
          LazyVGrid(columns:[GridItem(.adaptive(minimum:160))],spacing:14) {
            ForEach(templates) { template in
              Button {
                if createNew || model.activeCollageID == nil { model.newCollage(template: template) }
                else { model.applyCollageTemplate(template) }
                dismiss()
              } label: {
                VStack(alignment:.leading,spacing:8) {
                  CollageCardPreview(model: model, template: template).aspectRatio(template.aspect,contentMode:.fit).frame(height:120)
                  Text(template.name).font(.headline).lineLimit(2)
                  Text(template.category + " · Flexible photo count").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
              }.buttonStyle(.plain).contextMenu {
                Button("New Collage with This Layout") { model.newCollage(template:template); dismiss() }
                Button("Apply to Current Collage") {
                  model.applyCollageTemplate(template); dismiss()
                }.disabled(model.activeCollageID == nil || model.running || model.collageGenerating)
              }
            }
          }
        }.padding()
      }.searchable(text:$query,prompt:"Find a layout").navigationTitle("Collages").compactNavigationTitle()
        .toolbar { Button("Done") { dismiss() } }
    }.background(.background)
    #if os(macOS)
      .frame(minWidth:640,idealWidth:860,minHeight:500,idealHeight:700)
    #endif
  }
}
struct CollageLayoutDiagram: View {
  var project: CollageProject
  init(project:CollageProject) { self.project=project }
  init(template:CollageTemplate) {
    var p=CollageProject()
    template.apply(to:&p,sources:(0..<8).map { _ in UUID() })
    project=p
  }
  var body: some View {
    Canvas { context,size in
      let bounds=CGRect(origin:.zero,size:size)
      context.fill(Path(bounds),with:.color(Color(red:project.background.red,green:project.background.green,blue:project.background.blue,opacity:project.background.alpha)))
      if let shape=project.silhouette {
        context.clip(to:Path(shape.path(in:bounds,text:project.silhouetteText, fontName: project.silhouetteFontName, multiline: project.silhouetteTextLayout >= 2)),style:FillStyle(eoFill:true))
      }
      for (i,cell) in project.cells.enumerated() {
        let rect=project.rect(for:cell,output:size)
        var layer=context
        layer.translateBy(x:rect.midX,y:rect.midY); layer.rotate(by:.degrees(cell.rotation)); layer.translateBy(x:-rect.midX,y:-rect.midY)
        let path=cell.shape.map { Path($0.path(in:rect,text:project.silhouetteText, fontName: project.silhouetteFontName, multiline: project.silhouetteTextLayout >= 2)) } ?? Path(roundedRect:rect,cornerRadius:2)
        layer.fill(path,with:.color(Color(hue:0.56+Double(i%5)*0.025,saturation:0.35,brightness:0.62+Double(i%3)*0.12)))
      }
    }.clipShape(RoundedRectangle(cornerRadius:8)).accessibilityLabel("Collage layout diagram")
  }
}

struct CollageCardPreview: View {
  @Bindable var model: Workspace
  var project: CollageProject
  @State private var image: CGImage?
  @State private var failed = false
  init(model: Workspace, project: CollageProject) { self.model = model; self.project = project }
  init(model: Workspace, template: CollageTemplate) {
    self.model = model
    var value = CollageProject()
    let selected = model.assets.filter { model.selection.contains($0.id) }.map(\.id)
    let candidates = selected.isEmpty ? model.collage.cells.map(\.sourceID) : selected
    template.apply(to: &value, sources: Array((candidates.isEmpty ? model.assets.map(\.id) : candidates).prefix(24)))
    project = value
  }
  struct CardKey: Equatable { var identity: CollageRenderIdentity; var privateMode: Bool }
  var key: CollageRenderIdentity { CollageRenderIdentity(project: project, sources: model.assets, edits: model.edits) }
  var body: some View {
    ZStack {
      if let image, !model.privateEditing { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else {
        CollageLayoutDiagram(project: project)
        if !model.privateEditing && !project.cells.isEmpty && !failed { ProgressView().controlSize(.small) }
      }
      SensitivePreviewCover(model: model, ids: Set(project.cells.map(\.sourceID)))
    }.task(id: CardKey(identity: key, privateMode: model.privateEditing)) {
      image = nil; failed = false
      guard !model.privateEditing, !project.cells.isEmpty else { return }
      do {
        let rendered = try await model.processor.renderCollage(project, sources: model.assets, edits: model.edits, previewMaximum: 280)
        try Task.checkCancellation(); image = rendered
      } catch is CancellationError {} catch { failed = true }
    }.onChange(of: model.privateEditing) { _, enabled in if enabled { image = nil } }
      .onDisappear { image = nil }
  }
}
