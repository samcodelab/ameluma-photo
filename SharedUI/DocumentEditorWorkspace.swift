#if os(macOS)
import AppKit
import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers

struct DocumentEditorWorkspace:View {
  @Bindable var model:Workspace
  @Bindable var session:EditorDocumentSession
  @State private var preview:CGImage?
  @State private var rendered:EditorDocument?
  @State private var renderError:String?
  @State private var retry=0
  @State private var scaleOverride:Double?
  @State private var pinchStart:Double?
  @State private var dragStart:CGPoint?
  @State private var movingLayer:EditorLayer?
  @State private var rotationStart:Double?
  @State private var rotationPointerAngle:Double?
  @State private var closeRequested=false
  @State private var historyVisible=false
  @State private var aspectLock=true
  @State private var exportFormat:OutputFormat = .png
  @State private var exportQuality=0.9
  @State private var exporting=false
  @State private var exportTask:Task<Void,Never>?
  @State private var showExport=false
  @State private var watermarkBackground = "Dark"
  @Environment(\.dynamicTypeSize) private var typeSize
  @FocusState private var canvasFocused:Bool
  @FocusState private var editingField:String?
  private struct RenderRequest:Equatable {var document:EditorDocument;var retry:Int;var maximum:Int}
  var body:some View {
    VStack(spacing:0) {
      documentTabs
      HStack {
        Button(session.document.watermarkDesign == true ? "Back" : "Workspace", systemImage: "chevron.left") {
          model.activeEditorDocumentID = nil
          if session.document.watermarkDesign != true { model.showLibrary() }
        }.help(session.document.watermarkDesign == true ? "Return to the photo or batch you were editing" : "Return to Workspace")
        Divider().frame(height:18)
        if session.document.watermarkDesign == true {
          TextField("Design name", text: Binding(get: { session.document.name }, set: { value in session.update("Rename Design") { $0.name = value } }))
            .textFieldStyle(.roundedBorder).frame(width: 180).focused($editingField, equals: "design-name")
            .accessibilityLabel("Watermark design name")
        } else { Text(session.document.name).font(.headline) }
        if session.document.watermarkDesign == true {
          Picker("Preview", selection: $watermarkBackground) {
            ForEach(["Dark", "Light", "Checkerboard"], id: \.self) { Text($0).tag($0) }
          }.frame(width: 160).help("Preview background; never included in the saved watermark")
        }
        if session.dirty {Text("Edited").font(.caption).foregroundStyle(.secondary)}
        Spacer()
        Button {session.undo()} label:{Image(systemName:"arrow.uturn.backward")}.disabled(!session.canUndo).help("Undo "+(session.history.undoSteps.last?.title ?? ""))
        Button {session.redo()} label:{Image(systemName:"arrow.uturn.forward")}.disabled(!session.canRedo).help("Redo "+(session.history.redoSteps.last?.title ?? ""))
        if session.document.watermarkDesign == true {
          Button("Save Design") { saveWatermarkDesign() }.disabled(session.busy)
        } else { Button("Save…",action:save).disabled(session.busy) }
        Menu("Use Result") {
          Button("Add Finished Image to Workspace") {model.task=Task {await model.addDocumentResult(session)}}
          Button("Create GIF from Finished Image") {model.task=Task {await model.addDocumentResult(session,sendToGIF:true)}}
          Button("Actions…") {model.presentActions()}
        }.disabled(session.busy || model.running || !session.document.pendingPrivacyReviewIDs.isEmpty)
        Button("Export…") {showExport=true}.disabled(exporting || !session.document.pendingPrivacyReviewIDs.isEmpty)
        Button {closeRequested=true} label:{Image(systemName:"xmark")}.help("Close Document").disabled(session.busy)
      }.padding(10).background(.bar)
      if !session.document.pendingPrivacyReviewIDs.isEmpty {
        HStack {
          Label("Review photo coverage before exporting",systemImage:"exclamationmark.shield")
          Spacer()
          Button("I’ve Checked Visible Layers") {let checked=session.document.pendingPrivacyReviewIDs;session.update("Confirm Photo Review") {$0.privacyReviewLayerIDs=($0.privacyReviewLayerIDs ?? []).subtracting(checked)}}
        }.font(.callout).padding(10).background(.orange.opacity(0.12))
      }
      Divider()
      HStack(spacing:0) {
        VStack(spacing:12) {
          Button(action:addImages) {Image(systemName:"photo.badge.plus")}.help("Place Image Layer").accessibilityLabel("Place image layer")
          Button {session.addText()} label:{Image(systemName:"textformat")}.help("Add Editable Text").accessibilityLabel("Add editable text")
          Menu {ForEach(EditorShapeKind.allCases,id:\.self) {kind in Button(kind.rawValue) {session.addShape(kind)}}} label:{Image(systemName:"square.on.circle")}.menuStyle(.borderlessButton).help("Add Shape").accessibilityLabel("Add shape")
          Spacer()
          Button {historyVisible.toggle()} label:{Image(systemName:"clock.arrow.circlepath")}.help("Layers / History")
        }.buttonStyle(.borderless).font(.system(size:18)).padding(12).frame(width:48).background(.bar)
        Divider()
        canvas
        Divider()
        ScrollView {VStack(alignment:.leading,spacing:16) {
          if historyVisible {historyPanel} else {layersPanel;Divider();properties}
          Divider();canvasProperties
        }.padding(12)}.frame(width:typeSize.isAccessibilitySize ? 360:300).background(.bar)
      }
      Divider()
      HStack {
        Text("\(session.document.width) × \(session.document.height) px · sRGB")
        Spacer()
        if exporting {ProgressView().controlSize(.small);Button("Cancel Export") {exportTask?.cancel()}}
        else if !session.status.isEmpty {Text(session.status).lineLimit(1)}
        if session.busy {ProgressView().controlSize(.small);if model.running {Button("Cancel") {model.task?.cancel()}}}
      }.font(.caption).foregroundStyle(.secondary).padding(8)
      if let message=session.error ?? renderError {
        HStack {Label(message,systemImage:"exclamationmark.triangle");Spacer();Button("Retry Preview") {retry += 1}}.font(.caption).padding(8).background(.orange.opacity(0.12))
      }
    }
    .onChange(of:model.creationActionRequest?.id) {_,_ in
      guard let request=model.creationActionRequest, request.context.creationID==session.id, model.contextIsCurrent(request.context) else {return}
      model.creationActionRequest=nil
      if request.intent == .save {save()} else if request.intent == .export {showExport=true}
    }
    .onChange(of:editingField) {_,field in
      if field != nil {session.endInteraction("Edit Layer");session.beginInteraction()}
      else if movingLayer==nil && dragStart==nil {session.endInteraction("Edit Layer")}
    }
    .onChange(of:session.selectedLayerID) {_,_ in if editingField != nil {session.endInteraction("Edit Layer");editingField=nil}}
    .focusedSceneValue(\.editorDocumentCommands,EditorDocumentCommands(save:{save()},saveCopy:{saveCopy()},export:{showExport=true},close:{closeRequested=true},place:{addImages()},copy:{copyFlattened()},paste:{pasteImage()}))
    .task(id:RenderRequest(document:session.document,retry:retry,maximum:scaleOverride == nil ? 2000:max(session.document.width,session.document.height))) {
      let snapshot=session.document,urls=session.resources
      renderError=nil
      do {
        try await Task.sleep(for:.milliseconds(24))
        let image=try await session.renderer.render(snapshot,resources:urls,maximum:scaleOverride == nil ? 2000:max(snapshot.width,snapshot.height))
        try Task.checkCancellation();guard session.document==snapshot else{return}
        preview=image;rendered=snapshot
      }catch is CancellationError {}catch{renderError=error.localizedDescription}
    }
    .confirmationDialog(session.dirty ? "Save changes before closing?":"Close this document?",isPresented:$closeRequested,titleVisibility:.visible) {
      if session.dirty {Button("Save and Close…") {save(closeAfter:true)}}
      Button(session.dirty ? "Discard Changes":"Close",role:.destructive) {close()}
      Button("Keep Editing",role:.cancel) {}
    }
    .sheet(isPresented:$showExport) {
      Form {
        Text("Export a finished, flattened image. Your editable document remains unchanged.").font(.callout)
        Picker("Format",selection:$exportFormat) {ForEach(ImageProcessor.outputFormats,id:\.self) {Text($0.rawValue.uppercased()).tag($0)}}
        if exportFormat.supportsQuality {Slider(value:$exportQuality,in:0.1...1) {Text("Quality")};Text(exportQuality,format:.percent.precision(.fractionLength(0)))}
        if !exportFormat.preservesAlpha {Text("Transparent areas will be exported on white.").font(.caption)}
        HStack {Button("Cancel") {showExport=false};Spacer();Button("Choose Destination…") {showExport=false;export()}.buttonStyle(.borderedProminent)}
      }.padding(20).frame(width:420)
    }
    .onDisappear {exportTask?.cancel();session.endInteraction("Transform Layer");Task {await session.renderer.clearCaches();await session.thumbnailRenderer.clearCaches()}}
  }
  var documentTabs:some View {
    ScrollView(.horizontal) {HStack(spacing:4) {
      ForEach(model.editorDocuments) {item in
        Button {session.endInteraction("Edit Layer");model.activeEditorDocumentID=item.id} label:{Text(item.document.name+(item.dirty ? " •":"")).lineLimit(1).padding(.horizontal,10).padding(.vertical,7)}
          .buttonStyle(.plain).background(item.id==session.id ? Color.accentColor.opacity(0.17):Color.clear,in:RoundedRectangle(cornerRadius:5))
      }
      Button {model.newEditorDocument()} label:{Image(systemName:"plus")}.buttonStyle(.borderless).help("New Image Document")
    }.padding(6)}.background(.bar)
  }
  var canvas:some View {
    GeometryReader {proxy in
      let fit=max(0.01,min((proxy.size.width-32)/Double(session.document.width),(proxy.size.height-32)/Double(session.document.height)))
      let scale=scaleOverride ?? fit
      let size=CGSize(width:Double(session.document.width)*scale,height:Double(session.document.height)*scale)
      ScrollView([.horizontal,.vertical]) {
        ZStack(alignment:.topLeading) {
          Checkerboard().frame(width:size.width,height:size.height)
          if session.document.watermarkDesign == true, watermarkBackground != "Checkerboard" {
            (watermarkBackground == "Dark" ? Color(white: 0.16) : Color.white).frame(width:size.width,height:size.height)
          }
          if let preview {Image(decorative:preview,scale:1).resizable().frame(width:size.width,height:size.height)}
          if let layer=session.selectedLayer {
            Rectangle().stroke(Color.accentColor,lineWidth:1)
              .frame(width:layer.width*scale,height:layer.height*scale)
              .rotationEffect(.degrees(layer.rotation)).position(x:(layer.x+layer.width/2)*scale,y:(layer.y+layer.height/2)*scale).allowsHitTesting(false)
          }
          MacRetouchInput(active:true,began:{point,_ in beginMove(point,scale:scale)},moved:{point in move(point,scale:scale)},ended:{point in move(point,scale:scale);session.endInteraction("Move Layer");movingLayer=nil;dragStart=nil},hovered:{_ in})
            .frame(width:size.width,height:size.height)
          if let layer=session.selectedLayer,!layer.locked {
            Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor,lineWidth:2)).frame(width:12,height:12)
              .position(handlePoint(layer,scale:scale,bottom:true))
              .gesture(DragGesture().onChanged {v in
                if movingLayer==nil {movingLayer=layer;session.beginInteraction()}
                guard let start=movingLayer else{return}
                let angle=start.rotation * .pi/180
                let dx=(v.translation.width*cos(angle)+v.translation.height*sin(angle))/scale
                let dy=(-v.translation.width*sin(angle)+v.translation.height*cos(angle))/scale
                let width=min(20000,max(1,start.width+dx))
                let height=min(20000,max(1,aspectLock ? width*start.height/start.width:start.height+dy))
                session.changeLayer("Resize Layer") {
                  $0.width=width;$0.height=height
                  let dw=width-start.width,dh=height-start.height
                  $0.x=start.x+(dw*cos(angle)-dh*sin(angle)-dw)/2
                  $0.y=start.y+(dw*sin(angle)+dh*cos(angle)-dh)/2
                }
              }.onEnded {_ in session.endInteraction("Resize Layer");movingLayer=nil})
              .accessibilityLabel("Resize selected layer; numeric size is available in the inspector")
            Circle().fill(Color.white).overlay(Image(systemName:"rotate.right").font(.system(size:9)).foregroundStyle(.black)).frame(width:18,height:18)
              .position(handlePoint(layer,scale:scale,bottom:false))
              .gesture(DragGesture(coordinateSpace:.named("documentCanvas")).onChanged {value in
                session.beginInteraction()
                let center=CGPoint(x:(layer.x+layer.width/2)*scale,y:(layer.y+layer.height/2)*scale)
                if rotationStart==nil {rotationStart=layer.rotation;rotationPointerAngle=atan2(value.startLocation.y-center.y,value.startLocation.x-center.x)}
                let delta=(atan2(value.location.y-center.y,value.location.x-center.x)-(rotationPointerAngle ?? 0))*180 / .pi
                let angle=((rotationStart ?? layer.rotation)+delta).truncatingRemainder(dividingBy:360)
                session.changeLayer("Rotate Layer") {$0.rotation=angle>180 ? angle-360:angle < -180 ? angle+360:angle}
              }.onEnded {_ in session.endInteraction("Rotate Layer");rotationStart=nil;rotationPointerAngle=nil})
              .accessibilityLabel("Rotate selected layer; numeric rotation is available in the inspector")
          }
        }.frame(width:size.width,height:size.height).coordinateSpace(name:"documentCanvas").padding(16)
          .frame(minWidth:proxy.size.width,minHeight:proxy.size.height)
      }.background(Color(nsColor:.underPageBackgroundColor))
        .background(MacZoomCapture {delta in scaleOverride=min(16,max(0.01,scale*exp(-delta*0.015)))})
        .simultaneousGesture(MagnifyGesture().onChanged {value in
          if pinchStart==nil {pinchStart=scale};scaleOverride=min(16,max(0.01,(pinchStart ?? scale)*value.magnification))
        }.onEnded {_ in pinchStart=nil})
        .overlay(alignment:.bottomLeading) {
          Menu {
            Button("Fit to Window") {scaleOverride=nil}
            Button("Actual Pixels · 100%") {scaleOverride=1/(NSScreen.main?.backingScaleFactor ?? 2)}
            Button("Zoom In") {scaleOverride=min(16,scale*1.5)}
            Button("Zoom Out") {scaleOverride=max(0.01,scale/1.5)}
          } label:{Text(scaleOverride==nil ? "Fit":String(format:"%.0f%%",scale*(NSScreen.main?.backingScaleFactor ?? 2)*100))}.padding(8).background(.regularMaterial,in:Capsule()).padding(12)
        }
        .overlay(alignment:.topTrailing) {
          if rendered != session.document {HStack {if renderError==nil {ProgressView().controlSize(.small)};Text(renderError==nil ? "Updating preview…":"Preview unavailable")}.font(.caption).padding(8).background(.regularMaterial,in:Capsule()).padding(12)}
        }
        .focusable().focused($canvasFocused).focusEffectDisabled()
        .onKeyPress(.delete) {session.remove();return .handled}
        .onKeyPress("+") {scaleOverride=min(16,scale*1.5);return .handled}
        .onKeyPress("-") {scaleOverride=max(0.01,scale/1.5);return .handled}
        .onKeyPress("0") {scaleOverride=nil;return .handled}
        .onDrop(of:[UTType.fileURL.identifier],isTargeted:nil) {providers in
          Task {@MainActor in
            var urls:[URL]=[]
            for provider in providers {
              let url:URL?=await withCheckedContinuation {continuation in
                provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) {item,_ in
                  continuation.resume(returning:(item as? URL) ?? (item as? Data).flatMap{URL(dataRepresentation:$0,relativeTo:nil)})
                }
              }
              if let url {urls.append(url)}
            }
            let accessed=urls.filter{$0.startAccessingSecurityScopedResource()};defer{accessed.forEach{$0.stopAccessingSecurityScopedResource()}}
            await session.addImages(urls.map{($0,nativeConfiguration())})
          }
          return !providers.isEmpty
        }
    }
  }
  func handlePoint(_ layer:EditorLayer,scale:Double,bottom:Bool)->CGPoint {
    let a=layer.rotation * .pi/180
    let dx=bottom ? layer.width/2:0,dy=bottom ? layer.height/2:-layer.height/2-24/scale
    var point=CGPoint(x:(layer.x+layer.width/2+dx*cos(a)-dy*sin(a))*scale,y:(layer.y+layer.height/2+dx*sin(a)+dy*cos(a))*scale)
    if !bottom {point.x=min(Double(session.document.width)*scale-10,max(10,point.x));point.y=min(Double(session.document.height)*scale-10,max(10,point.y))}
    return point
  }
  func beginMove(_ point:CGPoint,scale:Double) {
    session.endInteraction("Edit Layer");editingField=nil;canvasFocused=true
    let p=CGPoint(x:point.x/scale,y:point.y/scale)
    session.selectedLayerID=session.document.layers.reversed().first {layer in
      guard layer.visible else{return false}
      let a = -layer.rotation * .pi/180,dx=p.x-layer.x-layer.width/2,dy=p.y-layer.y-layer.height/2
      let local=CGPoint(x:dx*cos(a)-dy*sin(a)+layer.width/2,y:dx*sin(a)+dy*cos(a)+layer.height/2)
      return CGRect(x:0,y:0,width:layer.width,height:layer.height).contains(local)
    }?.id
    guard let layer=session.selectedLayer,!layer.locked else{return}
    movingLayer=layer;dragStart=point;session.beginInteraction()
  }
  func move(_ point:CGPoint,scale:Double) {
    guard let start=movingLayer,let origin=dragStart else{return}
    session.changeLayer("Move Layer") {$0.x=min(100000,max(-100000,start.x+(point.x-origin.x)/scale));$0.y=min(100000,max(-100000,start.y+(point.y-origin.y)/scale))}
  }
  var layersPanel:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {Text("Layers").font(.headline);Spacer();Button(action:session.duplicate) {Image(systemName:"plus.square.on.square")}.disabled(session.selectedLayer==nil);Button(action:session.remove) {Image(systemName:"trash")}.disabled(session.selectedLayer==nil || session.selectedLayer?.locked==true)}
      ForEach(session.document.layers.reversed()) {layer in
        HStack {
          Button {session.update("Layer Visibility") {doc in if let i=doc.layers.firstIndex(where:{$0.id==layer.id}) {doc.layers[i].visible.toggle()}}} label:{Image(systemName:layer.visible ? "eye":"eye.slash")}.help("Show / Hide Layer").accessibilityLabel((layer.visible ? "Hide ":"Show ")+layer.name)
          Button {session.selectedLayerID=layer.id} label:{HStack {DocumentLayerThumbnail(session:session,layer:layer).frame(width:36,height:28);Text(layer.name).lineLimit(1);Spacer()}}.buttonStyle(.plain)
          Button {session.update("Layer Lock") {doc in if let i=doc.layers.firstIndex(where:{$0.id==layer.id}) {doc.layers[i].locked.toggle()}}} label:{Image(systemName:layer.locked ? "lock.fill":"lock.open")}.help("Lock / Unlock Layer").accessibilityLabel((layer.locked ? "Unlock ":"Lock ")+layer.name)
        }.padding(7).background(session.selectedLayerID==layer.id ? Color.accentColor.opacity(0.18):Color.clear,in:RoundedRectangle(cornerRadius:5))
          .draggable(layer.id.uuidString)
          .dropDestination(for:String.self) {items,_ in guard let value=items.first,let id=UUID(uuidString:value) else{return false};session.move(id,before:layer.id);return true}
      }
      if session.document.layers.isEmpty {Text("Place an image, add text or draw a shape to begin.").font(.caption).foregroundStyle(.secondary)}
    }.buttonStyle(.borderless)
  }
  func symbol(_ layer:EditorLayer)->String {switch layer.content {case .image:"photo";case .text:"textformat";case .shape:"square.on.circle"}}
  @ViewBuilder var properties:some View {
    if let layer=session.selectedLayer {
      VStack(alignment:.leading,spacing:10) {
        Text("Layer Properties").font(.headline)
        TextField("Layer name",text:Binding(get:{session.selectedLayer?.name ?? ""},set:{value in session.changeLayer("Rename Layer") {$0.name=value}})).focused($editingField,equals:"layerName")
        if layer.locked {Label("Locked",systemImage:"lock.fill").font(.caption)}
        Group {
          switch layer.content {
          case .text(let text):textProperties(text)
          case .shape(let shape):shapeProperties(shape)
          case .image: Text("Captured photo edits remain attached to this layer.").font(.caption).foregroundStyle(.secondary)
          }
          DisclosureGroup("Transform") {
            VStack(spacing:8) {
              numeric("X",\.x);numeric("Y",\.y);numeric("Width",\.width);numeric("Height",\.height);numeric("Rotation",\.rotation)
              Toggle("Keep proportions when resizing",isOn:$aspectLock).font(.caption)
              HStack {Button("Flip Horizontal") {session.changeLayer("Flip Horizontal") {$0.flipHorizontal.toggle()}};Button("Flip Vertical") {session.changeLayer("Flip Vertical") {$0.flipVertical.toggle()}}}
            }.padding(.top,6)
          }
          HStack {Text("Opacity");Spacer();Text(layer.opacity,format:.percent.precision(.fractionLength(0)))}
          Slider(value:Binding(get:{session.selectedLayer?.opacity ?? 1},set:{v in session.changeLayer("Layer Opacity") {$0.opacity=v}}),in:0...1,onEditingChanged:{active in if active {session.beginInteraction()}else{session.endInteraction("Layer Opacity")}})
          Picker("Blend",selection:Binding(get:{session.selectedLayer?.blendMode ?? .normal},set:{v in session.changeLayer("Blend Mode") {$0.blendMode=v}})) {ForEach(EditorBlendMode.allCases,id:\.self) {Text($0.rawValue.capitalized).tag($0)}}
        }.disabled(layer.locked)
      }
    }
  }
  func numeric(_ label:String,_ path:WritableKeyPath<EditorLayer,Double>)->some View {
    HStack {Text(label);Spacer();TextField(label,value:Binding(get:{session.selectedLayer?[keyPath:path] ?? 0},set:{v in session.changeLayer("Change "+label) {$0[keyPath:path]=v}}),format:.number.precision(.fractionLength(0...2))).frame(width:90).multilineTextAlignment(.trailing).focused($editingField,equals:"number-"+label)}
  }
  func updateText(_ title:String,_ action:(inout EditorText)->Void) {
    session.changeLayer(title) {layer in if case .text(var text)=layer.content {action(&text);layer.content = .text(text)}}
  }
  func textProperties(_ text:EditorText)->some View {
    VStack(alignment:.leading) {
      TextEditor(text:Binding(get:{if case .text(let value)=session.selectedLayer?.content {return value.text};return ""},set:{v in updateText("Edit Text") {$0.text=v}})).focused($editingField,equals:"text").frame(height:90).border(.secondary.opacity(0.3))
      Picker("Font",selection:Binding(get:{text.fontName},set:{v in updateText("Text Font") {$0.fontName=v}})) {ForEach(Array(Set(NSFontManager.shared.availableFontFamilies+[text.fontName])).sorted(),id:\.self) {Text($0).tag($0)}}
      HStack {Text("Size (px)");Spacer();TextField("Font size",value:Binding(get:{text.fontSize},set:{v in updateText("Text Size") {$0.fontSize=v}}),format:.number).frame(width:80).multilineTextAlignment(.trailing)}
      let traitsLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading)):AnyLayout(HStackLayout())
      traitsLayout {Toggle("Bold",isOn:Binding(get:{text.bold},set:{v in updateText("Bold") {$0.bold=v}}));Toggle("Italic",isOn:Binding(get:{text.italic},set:{v in updateText("Italic") {$0.italic=v}}));Toggle("Underline",isOn:Binding(get:{text.underline},set:{v in updateText("Underline") {$0.underline=v}}))}.toggleStyle(.button)
      Picker("Alignment",selection:Binding(get:{text.alignment},set:{v in updateText("Text Alignment") {$0.alignment=v}})) {ForEach(AnnotationTextAlignment.allCases,id:\.self) {Text($0.rawValue.capitalized).tag($0)}}
      ColorPicker("Text Colour",selection:Binding(get:{Color(cgColor:text.colour.cgColor)},set:{v in let c=rgba(v);updateText("Text Colour") {$0.colour=c}}))
      DisclosureGroup("Outline & Shadow") {
        Toggle("Outline", isOn: Binding(get: { text.outlineColour != nil }, set: { on in updateText("Text Outline") { $0.outlineColour = on ? RGBAColour(0,0,0,1) : nil; $0.outlineWidth = on ? 2 : nil } }))
        if let outline = text.outlineColour {
          ColorPicker("Outline Colour", selection: Binding(get: { Color(cgColor: outline.cgColor) }, set: { value in let c = rgba(value); updateText("Outline Colour") { $0.outlineColour = c } }))
          TextField("Outline (px)", value: Binding(get: { text.outlineWidth ?? 2 }, set: { v in updateText("Outline Width") { $0.outlineWidth = v } }), format: .number)
        }
        Toggle("Shadow", isOn: Binding(get: { text.shadow != nil }, set: { on in updateText("Text Shadow") { $0.shadow = on ? EditorTextShadow() : nil } }))
        if let shadow = text.shadow {
          ColorPicker("Shadow Colour", selection: Binding(get: { Color(cgColor: shadow.colour.cgColor) }, set: { value in let c = rgba(value); updateText("Shadow Colour") { $0.shadow?.colour = c } }))
          TextField("Blur (px)", value: Binding(get: { shadow.radius }, set: { v in updateText("Shadow Blur") { $0.shadow?.radius = v } }), format: .number)
          TextField("Offset X (px)", value: Binding(get: { shadow.offsetX }, set: { v in updateText("Shadow Offset") { $0.shadow?.offsetX = v } }), format: .number)
          TextField("Offset Y (px)", value: Binding(get: { shadow.offsetY }, set: { v in updateText("Shadow Offset") { $0.shadow?.offsetY = v } }), format: .number)
        }
      }

    }
  }
  func shapeProperties(_ shape:EditorShape)->some View {
    VStack {
      Toggle("Fill",isOn:Binding(get:{shape.fill != nil},set:{active in updateShape { $0.fill=active ? RGBAColour(0.15,0.45,0.95,1):nil}}))
      if let fill=shape.fill {ColorPicker("Fill Colour",selection:Binding(get:{Color(cgColor:fill.cgColor)},set:{v in let c=rgba(v);updateShape {$0.fill=c}}))}
      ColorPicker("Stroke",selection:Binding(get:{Color(cgColor:shape.stroke.cgColor)},set:{v in let c=rgba(v);updateShape {$0.stroke=c}}))
      HStack {Text("Stroke (px)");Spacer();TextField("Stroke width",value:Binding(get:{shape.strokeWidth},set:{v in updateShape {$0.strokeWidth=v}}),format:.number).frame(width:80)}
      if shape.kind == .roundedRectangle {TextField("Corner radius (px)",value:Binding(get:{shape.cornerRadius},set:{v in updateShape {$0.cornerRadius=v}}),format:.number)}
    }
  }
  func updateShape(_ action:(inout EditorShape)->Void) {session.changeLayer("Shape Style") {layer in if case .shape(var value)=layer.content {action(&value);layer.content = .shape(value)}}}
  func rgba(_ colour:Color)->RGBAColour {
    let c=NSColor(colour).usingColorSpace(.sRGB) ?? .black
    return RGBAColour(c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent)
  }
  var canvasProperties:some View {
    VStack(alignment:.leading,spacing:8) {
      Text("Canvas").font(.headline)
      TextField("Name",text:Binding(get:{session.document.name},set:{v in session.update("Document Name") {$0.name=v}}))
      HStack {Text("Width (px)");Spacer();TextField("Width",value:Binding(get:{session.document.width},set:{v in session.update("Canvas Width") {$0.width=v}}),format:.number).frame(width:90)}
      HStack {Text("Height (px)");Spacer();TextField("Height",value:Binding(get:{session.document.height},set:{v in session.update("Canvas Height") {$0.height=v}}),format:.number).frame(width:90)}
      Toggle("Transparent",isOn:Binding(get:{session.document.background==nil},set:{v in session.update("Canvas Background") {$0.background=v ? nil:RGBAColour(1,1,1,1)}})).disabled(session.document.watermarkDesign == true)
      if session.document.watermarkDesign == true { Text("Designs stay transparent. Preview backgrounds are never saved or applied.").font(.caption).foregroundStyle(.secondary) }
      if let colour=session.document.background {ColorPicker("Background",selection:Binding(get:{Color(cgColor:colour.cgColor)},set:{v in let c=rgba(v);session.update("Canvas Background") {$0.background=c}}))}
      Text("Canvas size changes the boundary; layer pixels and positions remain independent.").font(.caption).foregroundStyle(.secondary)
    }
  }
  var historyPanel:some View {
    VStack(alignment:.leading) {
      Text("Document History").font(.headline)
      Button("Back to Layers") {historyVisible=false}
      ForEach(Array(session.history.undoSteps.enumerated()),id:\.element.id) {index,step in
        Button(step.title) {let count=session.history.undoSteps.count-index;for _ in 0..<count {session.undo()}}
      }
      Text("Current state").font(.caption)
      ForEach(Array(session.history.redoSteps.reversed().enumerated()),id:\.element.id) {index,step in Button("Redo "+step.title) {for _ in 0...index {session.redo()}}}
      Text("History belongs only to this document. Saved content survives reopening; session Undo starts again.").font(.caption).foregroundStyle(.secondary)
    }
  }
  func nativeConfiguration()->ProcessingConfiguration {var c=ProcessingConfiguration();c.nativeOutputSizing=true;c.crop.mode = .preserveAspectRatio;c.format = .png;return c}
  func addImages() {
    let panel=NSOpenPanel();panel.allowedContentTypes=ImageProcessor.importTypes;panel.allowsMultipleSelection=true
    panel.begin {response in guard response == .OK else{return};let urls=panel.urls
      Task {@MainActor in
        let accessed=urls.filter{$0.startAccessingSecurityScopedResource()};defer{accessed.forEach{$0.stopAccessingSecurityScopedResource()}}
        await session.addImages(urls.map{($0,nativeConfiguration())})
      }
    }
  }
  func saveCopy() {save(closeAfter:false,chooseDestination:true)}
  func copyFlattened() {
    let snapshot=session.document,urls=session.resources
    Task {
      do {
        try snapshot.validateForExport()
        let image=try await session.renderer.render(snapshot,resources:urls)
        let data=try await session.processor.encode(image,format:.png,quality:1)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(data,forType:.png) else {throw ProcessingError.destination}
        session.status="Copied flattened image"
      }catch {session.error=error.localizedDescription}
    }
  }
  func pasteImage() {
    let png=NSPasteboard.general.data(forType:.png)
    let data=png ?? NSPasteboard.general.data(forType:.tiff)
    guard let data else {session.error="The clipboard does not contain an image.";return}
    Task {
      do {
        let root=session.directory.appendingPathComponent("Clipboard")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source=try await session.processor.importData(data,name:png == nil ? "Clipboard.tiff":"Clipboard.png",to:root)
        defer {try? FileManager.default.removeItem(at:source.url)}
        await session.addImages([(source.url,nativeConfiguration())])
      }catch {session.error=error.localizedDescription}
    }
  }
  func saveWatermarkDesign(closeAfter: Bool = false) {
    Task {
      session.endInteraction("Edit Design")
      let snapshot = session.document, resources = session.resources
      session.busy = true
      defer { session.busy = false }
      do {
        _ = try await model.watermarkDesignLibrary.save(snapshot, resources: resources)
        session.status = "Saved watermark design. Return to the photo’s Watermark tool to apply it."
        session.savedDocument = snapshot; session.error = nil; session.scheduleRecovery()
        if closeAfter { close() }
      } catch { session.error = error.localizedDescription }
    }
  }
  func save() {save(closeAfter:false)}
  func save(closeAfter:Bool,chooseDestination:Bool=false) {
    if session.document.watermarkDesign == true, !chooseDestination { saveWatermarkDesign(closeAfter: closeAfter); return }
    if !chooseDestination,let url=session.fileURL {Task {if await session.save(to:url),closeAfter {close()}};return}
    let panel=NSSavePanel();panel.allowedContentTypes=[UTType(exportedAs:"com.broadframestudio.ameluma.document",conformingTo:.package)];panel.nameFieldStringValue=session.document.name+".ameluma";panel.message="Save editable layers and their original image resources. Use Export for a flattened image to share."
    panel.begin {response in guard response == .OK,let url=panel.url else{return};Task {@MainActor in
      let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
      if await session.save(to:url),closeAfter {close()}
    }}
  }
  func close() {
    session.closing=true;session.recoveryTask?.cancel();let recovery=session.recoveryTask
    model.editorDocuments.removeAll{$0.id==session.id};model.activeEditorDocumentID=model.editorDocuments.last?.id
    Task {
      await recovery?.value
      do {try FileManager.default.removeItem(at:session.directory)}catch{model.issues.append("Could not clear closed document recovery: "+error.localizedDescription)}
    }
  }
  func export() {
    let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.prompt="Export here"
    panel.begin {response in guard response == .OK,let directory=panel.url else{return}
      let snapshot=session.document,urls=session.resources,format=exportFormat,quality=exportQuality
      exporting=true
      exportTask=Task {@MainActor in
        let access=directory.startAccessingSecurityScopedResource();defer{exporting=false;if access {directory.stopAccessingSecurityScopedResource()}}
        do {
          try snapshot.validateForExport()
          let image=try await session.renderer.render(snapshot,resources:urls)
          try Task.checkCancellation()
          var c=ProcessingConfiguration();c.format=format;c.quality=quality
          var profile=ExportProfile();profile.suffix="";profile.namingTemplate="{name}"
          let result=try await session.processor.publish(image,asset:SourceAsset(url:session.directory.appendingPathComponent("Original"),name:snapshot.name),configuration:c,to:directory,profile:profile,flattenTransparency:true)
          guard let output=result.output else {throw ProcessingError.validation}
          session.status="Exported "+output.lastPathComponent
        }catch is CancellationError {session.status="Export cancelled"}catch{session.error=error.localizedDescription}
      }
    }
  }
}
struct EditorDocumentCommands {
  var save:()->Void;var saveCopy:()->Void;var export:()->Void;var close:()->Void
  var place:()->Void;var copy:()->Void;var paste:()->Void
}
private struct EditorDocumentCommandKey:FocusedValueKey {typealias Value=EditorDocumentCommands}
extension FocusedValues {
  var editorDocumentCommands:EditorDocumentCommands? {
    get {self[EditorDocumentCommandKey.self]}
    set {self[EditorDocumentCommandKey.self]=newValue}
  }
}
private struct DocumentLayerThumbnail:View {
  var session:EditorDocumentSession
  var layer:EditorLayer
  @State private var image:CGImage?
  var body:some View {
    Group {if let image {Image(decorative:image,scale:1).resizable().scaledToFit()}else{Image(systemName:"square.dashed").foregroundStyle(.secondary)}}
      .task(id:layer) {
        var document=EditorDocument();document.width=max(1,Int(layer.width.rounded()));document.height=max(1,Int(layer.height.rounded()))
        var content=layer;content.x=0;content.y=0;content.rotation=0;content.visible=true;content.opacity=1
        document.layers=[content];document.resources=session.document.resources
        do {let result=try await session.thumbnailRenderer.render(document,resources:session.resources,maximum:80);try Task.checkCancellation();image=result}catch{image=nil}
      }.accessibilityHidden(true)
  }
}
private struct Checkerboard:View {
  var body:some View {Canvas {context,size in
    context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.white))
    for y in stride(from:0.0,to:size.height,by:12) {for x in stride(from:0.0,to:size.width,by:12) where (Int(x/12)+Int(y/12))%2==0 {context.fill(Path(CGRect(x:x,y:y,width:12,height:12)),with:.color(.gray.opacity(0.2)))}}
  }.accessibilityHidden(true)}
}
#endif
