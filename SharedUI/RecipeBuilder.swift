import SwiftUI
import FramepebbleCore
import CoreGraphics

struct RecipeBuilder: View {
  @Bindable var model: Workspace
  let request: RecipeRequest
  @State private var refreshedInputs: RecipeRequest?
  var inputs: RecipeRequest {refreshedInputs ?? request}
  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var phase
  private struct PreviewIdentity: Equatable {var recipe:ProcessingRecipe;var active:Bool;var requestID:UUID}
  @State private var recipe=ProcessingRecipe()
  @State private var saved:[ProcessingRecipe]=[]
  @State private var error:String?
  @State private var result:RecipeOutcome?
  @State private var saving=false
  @State private var deleting=false
  @State private var applying=false
  @State private var operation:Task<Void,Never>?
  @State private var preview:CGImage?
  @State private var renderedRecipe:ProcessingRecipe?
  @State private var previewError:String?
  @State private var previewExpanded=true
  private let previewProcessor=ImageProcessor()
  var valid:Bool {(try? recipe.validate()) != nil}
  var body: some View {
    VStack(spacing:0) {
      HStack(alignment:.firstTextBaseline) {
        Text("Recipes").font(.title2.bold());Spacer()
        if applying {Button("Stop") {operation?.cancel()}}else{Button("Done") {dismiss()}}
      }.padding()
      Divider()
      GeometryReader { geometry in
        if geometry.size.width >= 740 && !typeSize.isAccessibilitySize {
          HStack(alignment:.top,spacing:0) {
            ScrollView { builderContent }
            Divider()
            ScrollView { previewPanel.padding() }.frame(width:280)
          }
        } else {
          ScrollView {
            VStack(alignment:.leading,spacing:8) {previewPanel.padding(.horizontal);builderContent}
          }
        }
      }.disabled(applying || saving)
      Divider()
      VStack(alignment:.leading,spacing:8) {
        if applying {ProgressView(value:model.recipeProgress);Text("Completed changes are kept if stopped. One Undo restores this application.").font(.caption)}
        let vertical=sizeClass == .compact || typeSize.isAccessibilitySize
        let buttons=vertical ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout())
        buttons {
          if vertical, let result, result.changed>0 {
            Menu("Save / Export") {
              Button("Save Recipe") {save()}.disabled(!valid || saving || applying)
              exportResultButton(result)
            }
          } else {
            Button("Save Recipe") {save()}.disabled(!valid || saving || applying)
            if !vertical {Spacer()}
            if let result,result.changed>0 {exportResultButton(result)}
          }
          Button("Apply to \(inputs.label)") {
            applying=true;error=nil
            let submitted=inputs
            operation=Task {
              let outcome=await model.applyRecipe(recipe,request:submitted)
              refreshedInputs=model.continuingRecipeRequest(submitted,changedIDs:outcome.changedIDs)
              result=outcome;applying=false
            }
            model.task=operation
          }.buttonStyle(.borderedProminent).disabled(!valid || applying || saving || model.running || model.quickFixRunning || inputs.assets.isEmpty || inputs.sessionID != model.sourceSessionID)
        }
      }.padding()
    }.frame(minWidth:320,idealWidth:820,minHeight:280,idealHeight:730).background(.background).tint(.accentColor)
    .confirmationDialog("Delete saved recipe “\(recipe.name)” ?",isPresented:$deleting,titleVisibility:.visible) {
      Button("Delete Recipe",role:.destructive) {
        Task {
          do {try await model.recipeLibrary.remove(recipe.id);saved=try await model.recipeLibrary.list();recipe.id=UUID();error=nil}
          catch {self.error=error.localizedDescription}
        }
      }
    } message:{Text("Applied photo edits and exported files stay unchanged. Your current draft remains available.")}
    .onAppear {if typeSize.isAccessibilitySize {previewExpanded=false}}
    .task {do {saved=try await model.recipeLibrary.list()}catch{self.error=error.localizedDescription}}
    .task(id:PreviewIdentity(recipe:recipe,active:phase != .background,requestID:inputs.id)) {
      renderedRecipe=nil;previewError=nil
      guard phase != .background,let asset=inputs.assets.first,let before=inputs.configurations[asset.id] else {return}
      do {
        try await Task.sleep(for:.milliseconds(160))
        let metadata=try await WorkspaceMetadataReader().read([asset])
        guard let info=metadata[asset.id] else {throw ProcessingError.invalidImage}
        let c=try recipe.configuration(for:before,sourceSize:CGSize(width:info.width,height:info.height),grainSeed:Workspace.filterSeed(asset.id))
        let captured=recipe
        let image=try await previewProcessor.render(asset.url,configuration:c,previewMaximum:800,decodeMaximum:1000)
        try Task.checkCancellation();guard recipe==captured else {return}
        preview=image;renderedRecipe=captured
      }catch is CancellationError {}catch{previewError=error.localizedDescription}
    }
    .onChange(of:phase) {_,value in if value == .background {operation?.cancel();preview=nil;Task {await previewProcessor.clearInteractiveCaches()}}}
    .onChange(of:recipe) {_,_ in result=nil}
    .onDisappear {operation?.cancel();Task {await previewProcessor.clearInteractiveCaches()}}
  }
  func exportResultButton(_ result:RecipeOutcome) -> some View {
    Button("Export \(result.changed) Changed \(result.changed == 1 ? "Photo" : "Photos")…") {
      model.pendingCapturedExport=CapturedPhotoExport(sessionID:model.sourceSessionID,requests:model.plannedRequests(targetIDs:result.changedIDs));dismiss()
    }
  }
  var builderContent:some View {
    VStack(alignment:.leading,spacing:16) {
          Text(inputs.assets.isEmpty ? "Build a reusable workflow. Choose photos before applying." : "Applies only to \(inputs.label). Other photos stay unchanged.").font(.callout).foregroundStyle(.secondary)
          let libraryLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)):AnyLayout(HStackLayout())
          libraryLayout {
            Menu("Open Saved Recipe") {
              ForEach(saved) {item in Button(item.name) {recipe=item;result=nil}}
              if saved.isEmpty {Text("No saved recipes yet")}
            }
            if !typeSize.isAccessibilitySize {Spacer()}
            if saved.contains(where:{$0.id==recipe.id}) {
              Button {deleting=true} label:{Image(systemName:"trash")}.accessibilityLabel("Delete saved recipe")
            }
            Button("New") {recipe=ProcessingRecipe();result=nil}
          }
          TextField("Recipe name",text:$recipe.name).textFieldStyle(.roundedBorder)
          Text("Enable the steps you need, in processing order.").font(.caption).foregroundStyle(.secondary)
          ForEach(Array(RecipeStage.allCases.enumerated()),id:\.element) {index,stage in
            VStack(alignment:.leading,spacing:10) {
              Toggle(isOn:Binding(get:{recipe.enabled.contains(stage)},set:{on in if on {recipe.enabled.insert(stage);if stage == .watermark {recipe.watermark.enabled=true}}else{recipe.enabled.remove(stage)}})) {
                Label("\(index+1). "+stage.rawValue,systemImage:symbol(stage)).font(.headline)
              }
              if recipe.enabled.contains(stage) {controls(stage)}
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
          }
          if let error {Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.orange)}
          if let result {
            Text(result.summary).font(.headline)
            ForEach(Array(result.reasons.prefix(8).enumerated()),id:\.offset) {_,reason in Text(reason).font(.caption)}
            if result.failed>0 || result.notRun>0 || (result.skipped>0 && !result.reasons.isEmpty) {
              Button("Retry Remaining Photos") {
                let remaining=inputs.ids.filter {!result.changedIDs.contains($0)}
                refreshedInputs=model.makeRecipeRequest(ids:remaining);self.result=nil
              }
            }
          }
      DisclosureGroup("What stays unchanged") {
        Text("Other photos, crop positions, retouch, annotations and each photo’s Auto Enhance stay unchanged. Recipe parameters start independently; they are never captured from an image implicitly.").font(.caption).foregroundStyle(.secondary)
      }
    }.padding()
  }
  @ViewBuilder var previewPanel:some View {
          if !inputs.assets.isEmpty {
            DisclosureGroup("Preview · "+(inputs.assets.first?.name ?? "First photo"),isExpanded:$previewExpanded) {
              ZStack {
                Color.secondary.opacity(0.08)
                if renderedRecipe==recipe,let preview {Image(decorative:preview,scale:1).resizable().scaledToFit()}
                else if let previewError {Text(previewError).font(.caption).padding()}
                else {ProgressView("Updating preview…")}
              }.frame(height:typeSize.isAccessibilitySize ? 120:180)
              Text("Captured photo edits + enabled steps. Newer edits are skipped; other photos use their own edits.").font(.caption).foregroundStyle(.secondary)
            }
          }
  }
  func symbol(_ stage:RecipeStage)->String {
    switch stage {case .resize:"arrow.up.left.and.arrow.down.right";case .corrections:"slider.horizontal.3";case .filter:"camera.filters";case .watermark:"signature";case .output:"square.and.arrow.up"}
  }
  @ViewBuilder func controls(_ stage:RecipeStage)->some View {
    switch stage {
    case .resize:
      HStack {Text("Longest edge (px)");Spacer();TextField("Pixels",value:$recipe.longestEdge,format:.number).frame(maxWidth:100).textFieldStyle(.roundedBorder)}
      Text("1–20,000 pixels").font(.caption).foregroundStyle(.secondary)
      Toggle("Allow enlargement",isOn:$recipe.allowUpscaling)
      Text("Resize the finished photo while preserving its framing and aspect ratio.").font(.caption).foregroundStyle(.secondary)
    case .corrections:
      InspectorSlider(title:"Exposure (EV)",value:$recipe.exposure,range:-2...2)
      InspectorSlider(title:"Contrast",value:$recipe.contrast,range:0.5...1.5)
      InspectorSlider(title:"Saturation",value:$recipe.saturation,range:0...2)
      InspectorSlider(title:"Warmth",value:$recipe.warmth,range:-1...1)
    case .filter:
      Picker("Look",selection:$recipe.presetID) {
        Text("Original · clear creative filter").tag(String?.none)
        ForEach(FilterCollection.allCases,id:\.self) {collection in
          Section(collection.rawValue) {ForEach(FilterCatalog.presets.filter {$0.collection==collection}) {Text($0.name).tag(Optional($0.id))}}
        }
      }
      InspectorSlider(title:"Intensity",value:$recipe.intensity,range:0...1,percentage:true)
    case .watermark:
      if recipe.watermark.kind == .text {TextField("Watermark text",text:$recipe.watermark.text).textFieldStyle(.roundedBorder)}
      else {Label("Saved image/design snapshot",systemImage:"photo");Button("Use Text Instead") {recipe.watermark.kind = .text;recipe.watermark.imageURL=nil}}
      Button("Use Watermark from This Photo") {
        if let first=inputs.assets.first,let mark=inputs.configurations[first.id]?.watermark {recipe.watermark=mark}
      }.disabled(inputs.assets.first.flatMap {inputs.configurations[$0.id]?.watermark.enabled} != true)
      InspectorSlider(title:"Relative width",value:$recipe.watermark.relativeWidth,range:0.02...0.8,percentage:true)
      InspectorSlider(title:"Opacity",value:$recipe.watermark.opacity,range:0...1,percentage:true)
      AnchorPicker(anchor:$recipe.watermark.anchor)
      Toggle("Repeat watermark",isOn:$recipe.watermark.tiled)
      Text("Only watermark content and placement are copied explicitly. No other photo settings enter this recipe.").font(.caption).foregroundStyle(.secondary)
    case .output:
      Picker("Format",selection:$recipe.format) {ForEach(ImageProcessor.outputFormats,id:\.self) {Text($0.rawValue.uppercased()).tag($0)}}
      if recipe.format.supportsQuality {InspectorSlider(title:"Quality",value:$recipe.quality,range:0.1...1,percentage:true)}
      Picker("Metadata",selection:$recipe.metadata) {ForEach(MetadataPolicy.allCases,id:\.self) {Text($0 == .remove ? "Remove Metadata" : $0 == .preserve ? "Keep Metadata" : "Remove Location").tag($0)}}
      Text("Conversion alone preserves dimensions. Export destination and file naming are chosen at export.").font(.caption).foregroundStyle(.secondary)
    }
  }
  func save() {
    saving=true;let captured=recipe
    Task {
      defer {saving=false}
      do {let value=try await model.recipeLibrary.save(captured);recipe=value;saved=try await model.recipeLibrary.list();error=nil}
      catch {self.error=error.localizedDescription}
    }
  }
}
