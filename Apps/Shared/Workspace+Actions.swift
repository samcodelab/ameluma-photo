import Foundation
import FramepebbleCore

enum ActionContextKind: String { case workspace, photo, batch, document, gif, collage, draft }
struct WorkspaceActionContext {
  var sessionID: UUID
  var kind: ActionContextKind
  var photoIDs: [UUID] = []
  var creationID: UUID?
  var label: String
}
enum UniversalIntent: Equatable {
  case resizeOptions, convertOptions, autoEnhance, removeAutoEnhance, recalculateAutoEnhance, removeWatermark
  case workspace, choosePhoto, adjust, filters, crop, retouch, annotate, privacy, watermark, recipes, gif, collage, compose, export, save, undo, redo
  case addText, addShape, duplicateLayer, deleteLayer, addToWorkspace, sendToGIF
  case resize(Int), convert(OutputFormat), filter(String)
}
struct UniversalAction: Identifiable {
  let id: String
  var title: String
  var detail: String
  var intent: UniversalIntent
  var disabledReason: String?
}
struct UniversalActionRequest: Identifiable {let id=UUID();var context: WorkspaceActionContext}
struct CreationActionRequest: Identifiable {let id=UUID();var context: WorkspaceActionContext;var intent: UniversalIntent}
struct CapturedPhotoExport: Identifiable {
  let id=UUID();var sessionID:UUID;var requests:[ExportRequest]
  var summary:String {Workspace.planSummary(photos:Set(requests.map {$0.source.id}).count,files:requests.count,profiles:Set(requests.map {$0.profile.id}).count)}
}
extension Workspace {
  var actionContext: WorkspaceActionContext {
    if let document=activeEditorDocument {return .init(sessionID:sourceSessionID,kind:.document,creationID:document.id,label:"Document · "+document.document.name)}
    if overlayEditor || colourReplacementAsset != nil {return .init(sessionID:sourceSessionID,kind:.draft,photoIDs:current.map{[$0.id]} ?? [],label:"Unapplied draft · "+(current?.name ?? "Photo"))}
    if browsingLibrary {
      let ids=workspaceActionIDs(orderedSelection + workspaceAssets.filter {selection.contains($0.id)}.map(\.id))
      return .init(sessionID:sourceSessionID,kind:.workspace,photoIDs:ids,label:ids.isEmpty ? "Workspace · choose photos" : "\(ids.count) selected \(ids.count==1 ? "photo":"photos")")
    }
    switch workflow {
    case .photo: return .init(sessionID:sourceSessionID,kind:.photo,photoIDs:current.map{[$0.id]} ?? [],label:"Current photo · "+(current?.name ?? "None"))
    case .batch: return .init(sessionID:sourceSessionID,kind:.batch,photoIDs:targets.map(\.id),label:"\(targets.count) captured batch inputs")
    case .gif: return .init(sessionID:sourceSessionID,kind:.gif,creationID:gifProject?.id,label:"GIF · \(gifProject?.frames.count ?? 0) frames")
    case .collages: return .init(sessionID:sourceSessionID,kind:.collage,creationID:activeCollageID,label:"Collage · "+activeCollageName)
    case .automations: return .init(sessionID:sourceSessionID,kind:.workspace,label:"Automations · no photo target")
    }
  }
  func contextIsCurrent(_ context: WorkspaceActionContext) -> Bool {
    guard context.sessionID==sourceSessionID else {return false}
    let current=actionContext
    if [.document,.gif,.collage].contains(context.kind) {return current.kind==context.kind && current.creationID==context.creationID}
    if context.kind == .draft {return current.kind == .draft && context.photoIDs==current.photoIDs}
    return activeEditorDocument==nil && !overlayEditor && colourReplacementAsset==nil && workspaceActionIDs(context.photoIDs)==context.photoIDs
  }
  func presentActions() {universalActionRequest=UniversalActionRequest(context:actionContext)}
  func universalActions(context: WorkspaceActionContext, query: String) -> [UniversalAction] {
    var result:[UniversalAction]=[]
    func add(_ id:String,_ title:String,_ intent:UniversalIntent,_ reason:String?=nil,_ detail:String?=nil) {
      result.append(.init(id:id,title:title,detail:detail ?? context.label,intent:intent,disabledReason:reason))
    }
    let busy=running || gifExporting || recipeApplying || quickFixRunning || activeEditorDocument?.busy == true
    if context.kind == .document,let session=activeEditorDocument {
      add("text","Add Text Layer",.addText);add("shape","Add Shape Layer",.addShape)
      let layer=session.selectedLayer
      add("duplicate","Duplicate Layer",.duplicateLayer,layer==nil ? "Select a layer first":nil,context.label+" · "+(layer?.name ?? "No layer"))
      add("delete","Delete Layer",.deleteLayer,layer==nil || layer?.locked == true ? "Select an unlocked layer":nil,context.label+" · "+(layer?.name ?? "No layer"))
      add("save",session.document.watermarkDesign == true ? "Save Watermark Design":"Save Editable Document",.save)
      let review=session.document.pendingPrivacyReviewIDs.isEmpty ? nil : "Review visible photo layers before exporting"
      add("export","Export Finished Image…",.export,review)
      add("workspace-result","Add Finished Image to Workspace",.addToWorkspace,review)
      add("gif-result","Create GIF from Finished Image",.sendToGIF,review)
      add("undo","Undo",.undo,!session.canUndo ? "Nothing to undo":nil)
      add("redo","Redo",.redo,!session.canRedo ? "Nothing to redo":nil)
    } else if context.kind == .draft {
      add("undo","Undo Draft Edit",.undo,colourReplacementAsset != nil || !canUndoActiveWorkspace ? "Use the current tool’s history controls":nil)
      add("redo","Redo Draft Edit",.redo,colourReplacementAsset != nil || !canRedoActiveWorkspace ? "Use the current tool’s history controls":nil)
      add("back","Return to Canvas",.workspace,nil,"Finish Apply or Cancel in the tool before changing workflows")
    } else if context.kind == .gif || context.kind == .collage {
      add("export",context.kind == .gif ? "Export GIF…":"Export Collage…",.export,context.kind == .gif ? (gifProject?.frames.isEmpty != false ? "Add frames first":nil) : (collage.cells.isEmpty || activeCollageID == nil ? "Add photos to the collage first":nil))
      add("undo","Undo Creation Edit",.undo,!canUndoActiveWorkspace ? "Nothing to undo":nil)
      add("redo","Redo Creation Edit",.redo,!canRedoActiveWorkspace ? "Nothing to redo":nil)
      add("workspace","Back to Workspace",.workspace)
    } else {
      let count=context.photoIDs.count
      if count==1 {
        add("adjust","Adjust Photo",.adjust);add("filters","Photo Filters",.filters)
        add("crop","Crop Photo",.crop);add("retouch","Retouch Photo",.retouch)
        add("annotate","Annotate Photo",.annotate);add("privacy","Pixelate or Cover an Area",.privacy)
        add("watermark","Watermark Photo",.watermark)
      }
      add("resize-options",count==1 ? "Resize This Photo…":"Resize Photos…",.resizeOptions,count==0 ? "Choose photos first":nil)
      add("convert-options",count==1 ? "Convert This Photo…":"Convert Photos…",.convertOptions,count==0 ? "Choose photos first":nil)
      if count>1 {add("filters","Apply Filter to Photos…",.filters);add("watermark","Watermark Photos…",.watermark)}
      let enhanced=context.photoIDs.contains {edits.configuration(for:$0).autoEnhance?.enabled == true}
      add("enhance",count==1 ? "Auto Enhance This Photo":"Auto Enhance Photos",.autoEnhance,count==0 ? "Choose photos first":nil)
      if enhanced {add("enhance-off","Remove Auto Enhance",.removeAutoEnhance);add("enhance-recalculate","Recalculate Auto Enhance",.recalculateAutoEnhance)}
      if context.photoIDs.contains(where:{edits.configuration(for:$0).watermark.enabled}) {add("watermark-remove","Remove Watermark",.removeWatermark)}
      add("recipe","Build or Apply a Recipe…",.recipes,nil,count==0 ? "Save reusable parameters · choose photos before applying":context.label)
      add("gif","Create GIF",.gif,count==0 ? "Choose photos first":nil)
      add("collage","Create Collage",.collage,count==0 ? "Choose photos first":nil)
      #if os(macOS)
      add("compose","Open Photos as Layers",.compose,count==0 ? "Choose photos first":nil)
      #endif
      add("export",count==1 ? "Export This Photo…":"Export Photos…",.export,count==0 ? "Choose photos first":nil)
      add("choose","Choose a Photo to Edit…",.choosePhoto)
      if !browsingLibrary {add("workspace","Back to Workspace",.workspace)}
      if context.kind == .photo || context.kind == .batch {
        add("undo","Undo Photo Edit",.undo,!canUndo ? "Nothing to undo":nil)
        add("redo","Redo Photo Edit",.redo,!canRedo ? "Nothing to redo":nil)
      }
      let text=query.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
      if let range=text.range(of:#"^resize(?: to)? ([0-9]+)(?: ?(?:px|pixels))?$"#,options:.regularExpression), range.lowerBound==text.startIndex,
         let number=text.split(whereSeparator:{!$0.isNumber}).compactMap({Int($0)}).first {
        add("resize","Resize longest edge to \(number) px",.resize(number),count==0 ? "Choose photos first":!(1...20000).contains(number) ? "Use 1–20,000 pixels":nil,context.label+" · no enlargement")
      }
      for format in OutputFormat.allCases where text=="convert to \(format.rawValue)" || text=="convert \(format.rawValue)" || (format == .jpeg && text=="convert to jpg") {
        add("convert","Convert to "+format.rawValue.uppercased(),.convert(format),count==0 ? "Choose photos first":!ImageProcessor.outputFormats.contains(format) ? "Unavailable on this system":nil)
      }
      for preset in FilterCatalog.presets where text=="filter "+preset.name.lowercased() || text=="apply "+preset.name.lowercased() {
        add("filter-"+preset.id,"Apply "+preset.name+" · 70%",.filter(preset.id),count==0 ? "Choose photos first":nil)
      }
    }
    let query=query.trimmingCharacters(in:.whitespacesAndNewlines)
    let aliases=["share":"export","blemish":"retouch","censor":"pixelate","make":"create","brightness":"adjust","remove":"delete"]
    let stop:Set<String>=["add","a","an","the","to","this","current","selected","photos","photo","images","image"]
    let words=query.lowercased().split(whereSeparator:{!$0.isLetter && !$0.isNumber}).map(String.init)
    let tokens=words.filter {!stop.contains($0)}
    if !query.isEmpty {
      result=result.filter {action in
        if action.id=="resize" || action.id=="convert" || action.id.hasPrefix("filter-") {return true}
        let title=action.title.lowercased()
        return !tokens.isEmpty && tokens.allSatisfy {word in
          title.contains(word) || title.contains(aliases[word] ?? word) || (word=="delete" && title.contains("remove"))
        }
      }
    }
    if words.contains("add") {result.removeAll {$0.title.hasPrefix("Remove") || $0.title.hasPrefix("Delete")}}
    if words.contains("selected") && [.photo,.batch].contains(context.kind) {
      for index in result.indices {result[index].disabledReason="This context targets \(context.label). Return to Workspace to act on its selection."}
    }
    if busy {for index in result.indices {result[index].disabledReason="Wait for the current operation to finish"}}
    if !contextIsCurrent(context) {for index in result.indices {result[index].disabledReason="Context changed. Close and reopen Actions."}}
    return result
  }
  func queueUniversalAction(_ action: UniversalAction, context: WorkspaceActionContext) {
    guard action.disabledReason==nil else {return}
    pendingUniversalAction=(action.intent,context);universalActionRequest=nil
  }
  func finishUniversalAction() {
    guard let (intent,context)=pendingUniversalAction else {return}
    pendingUniversalAction=nil
    guard !switchingDemo, contextIsCurrent(context), !running, !gifExporting, !recipeApplying else {issues.append("The action target changed. Open Actions again.");return}
    switch intent {
    case .workspace: if context.kind != .draft {activeEditorDocumentID=nil;showLibrary()}
    case .choosePhoto: selectPhotos(for:.edit)
    case .resizeOptions:
      if context.photoIDs.count==1, let asset=workspaceAssets.first(where:{$0.id==context.photoIDs[0]}) {openPhoto(asset);activatePhotoTool(.resize)}
      else {beginBatch(ids:context.photoIDs,tool:.resize)}
    case .convertOptions:
      if context.photoIDs.count==1,let asset=workspaceAssets.first(where:{$0.id==context.photoIDs[0]}) {
        openPhoto(asset);var value=configuration(for:asset);value.nativeOutputSizing=true
        applyChange(ConfigurationPatch(values:value,fields:[.nativeOutputSizing]),ids:[asset.id]);activatePhotoTool(.output)
      } else {beginConversion(ids:context.photoIDs)}
    case .autoEnhance: setAutoEnhance(true,targetIDs:Set(context.photoIDs))
    case .removeAutoEnhance: setAutoEnhance(false,targetIDs:Set(context.photoIDs))
    case .recalculateAutoEnhance: setAutoEnhance(true,recalculate:true,targetIDs:Set(context.photoIDs))
    case .removeWatermark:
      var value=ProcessingConfiguration();value.watermark.enabled=false
      applyChange(ConfigurationPatch(values:value,fields:[.watermark_enabled]),ids:Set(context.photoIDs))
    case .filters where context.photoIDs.count>1: presentFilterBatch(context.photoIDs)
    case .watermark where context.photoIDs.count>1: beginBatch(ids:context.photoIDs,tool:.watermark)
    case .recipes: presentRecipes(ids:context.photoIDs)
    case .gif: startGIF(ids:context.photoIDs)
    case .collage: performTask(.collage,ids:context.photoIDs)
    case .compose: Task {await openPhotosAsDocument(context.photoIDs)}
    case .export:
      if [.document,.gif,.collage].contains(context.kind) {creationActionRequest=CreationActionRequest(context:context,intent:intent)}
      else {presentCapturedExport(ids:context.photoIDs)}
    case .save: creationActionRequest=CreationActionRequest(context:context,intent:intent)
    case .undo: if let session=activeEditorDocument {session.undo()}else{undoActiveWorkspace()}
    case .redo: if let session=activeEditorDocument {session.redo()}else{redoActiveWorkspace()}
    case .addText: activeEditorDocument?.addText()
    case .addShape: activeEditorDocument?.addShape(.rectangle)
    case .duplicateLayer: activeEditorDocument?.duplicate()
    case .deleteLayer: activeEditorDocument?.remove()
    case .addToWorkspace,.sendToGIF:
      if let session=activeEditorDocument {task=Task {await addDocumentResult(session,sendToGIF:intent == .sendToGIF)}}
    case .convert(let format):
      var next=edits
      for id in context.photoIDs {
        var value=edits.configuration(for:id);value.format=format;value.nativeOutputSizing=true
        next.apply(ConfigurationPatch(values:value,fields:[.format,.nativeOutputSizing]),to:id)
      }
      commit(next,title:"Convert to "+format.rawValue.uppercased())
    case .resize,.filter:
      var recipe=ProcessingRecipe()
      switch intent {
      case .resize(let edge): recipe.name="Resize \(edge) px";recipe.enabled=[.resize];recipe.longestEdge=edge
      case .convert(let format): recipe.name="Convert to "+format.rawValue.uppercased();recipe.enabled=[.output];recipe.format=format
      case .filter(let id):recipe.name="Apply Filter";recipe.enabled=[.filter];recipe.presetID=id
      default:break
      }
      let request=makeRecipeRequest(ids:context.photoIDs)
      task=Task {_ = await applyRecipe(recipe,request:request)}
    default:
      guard context.photoIDs.count==1,let asset=workspaceAssets.first(where:{$0.id==context.photoIDs[0]}) else {return}
      let tool:PhotoTool
      switch intent {case .adjust:tool = .adjust;case .filters:tool = .filters;case .crop:tool = .crop;case .retouch:tool = .retouch;case .annotate:tool = .annotate;case .privacy:tool = .privacy;case .watermark:tool = .watermark;default:return}
      openPhoto(asset);activatePhotoTool(tool)
    }
  }
  func presentCapturedExport(ids:[UUID]) {
    let ids=workspaceActionIDs(ids)
    guard !ids.isEmpty else {return}
    capturedPhotoExport=CapturedPhotoExport(sessionID:sourceSessionID,requests:plannedRequests(targetIDs:Set(ids)))
  }
}
