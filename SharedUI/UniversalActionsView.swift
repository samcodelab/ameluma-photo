import SwiftUI
import FramepebbleCore
import UniformTypeIdentifiers

struct UniversalActionsView: View {
  @Bindable var model:Workspace
  let request:UniversalActionRequest
  @State private var query=""
  @State private var selectedID:String?
  @FocusState private var searchFocused:Bool
  init(model:Workspace, request:UniversalActionRequest, initialQuery:String = "") {
    self.model=model;self.request=request;_query=State(initialValue:initialQuery)
  }
  var actions:[UniversalAction] {model.universalActions(context:request.context,query:query)}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {Text("Actions").font(.title2.bold());Spacer();Button("Done") {model.universalActionRequest=nil}}
      Label(request.context.label,systemImage:"scope").font(.callout).foregroundStyle(.secondary)
      TextField("Search actions · resize to 1920, convert to PNG…",text:$query).textFieldStyle(.roundedBorder).focused($searchFocused)
        .onSubmit {activate()}
      List(selection:$selectedID) {
        ForEach(actions) {action in
          Button {model.queueUniversalAction(action,context:request.context)} label:{
            VStack(alignment:.leading,spacing:3) {
              Text(action.title).font(.headline)
              if let reason=action.disabledReason {Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
              else if action.detail != request.context.label {Text(action.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true).padding(.vertical,4)
          }.buttonStyle(.plain).disabled(action.disabledReason != nil).tag(action.id)
            .accessibilityLabel(action.title+", "+action.detail).accessibilityHint(action.disabledReason ?? "Run this action")
        }
      }.listStyle(.plain)
      if actions.isEmpty {Text("No matching action. Try “resize to 1920”, “convert to PNG” or a tool name.").font(.callout).foregroundStyle(.secondary)}
      Text("Runs locally. Applies to the scope shown above.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).frame(minWidth:320,idealWidth:560,minHeight:280,idealHeight:CGFloat(min(600,max(280,200+actions.count*60)))).background(.background)
      .onAppear {searchFocused=true;selectedID=actions.first(where:{$0.disabledReason==nil})?.id}
      .onChange(of:query) {_,_ in selectedID=actions.first(where:{$0.disabledReason==nil})?.id}
      .onKeyPress(.downArrow) {move(1);return .handled}
      .onKeyPress(.upArrow) {move(-1);return .handled}
      .onKeyPress(.escape) {model.universalActionRequest=nil;return .handled}
  }
  func activate() {if let action=actions.first(where:{$0.id==selectedID}) ?? actions.first(where:{$0.disabledReason==nil}),action.disabledReason==nil {model.queueUniversalAction(action,context:request.context)}}
  func move(_ direction:Int) {
    let available=actions.filter {$0.disabledReason==nil}
    guard !available.isEmpty else {return}
    let index=available.firstIndex(where:{$0.id==selectedID}) ?? (direction>0 ? -1 : available.count)
    selectedID=available[min(available.count-1,max(0,index+direction))].id
  }
}
struct CapturedExportView:View {
  @Bindable var model:Workspace
  let request:CapturedPhotoExport
  @State private var chooseFolder=false
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Export Photos").font(.title2.bold())
      Text(request.summary).font(.headline)
      Text("Photo edits were captured when this export was requested. Later selection or editing changes cannot change these files.").foregroundStyle(.secondary)
      ForEach(Array(request.requests.prefix(5))) {job in Text(job.source.name+" · "+job.configuration.format.rawValue.uppercased()).font(.caption)}
      if request.requests.count>5 {Text("and \(request.requests.count-5) more files").font(.caption)}
      HStack {Button("Cancel") {model.capturedPhotoExport=nil};Spacer();Button("Choose Folder…") {chooseFolder=true}}
      Button("Export & Share") {
        let folder=model.directory.deletingLastPathComponent().appendingPathComponent("Exports")
        do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);start(folder,share:true)}catch{model.issues.append(error.localizedDescription)}
      }.buttonStyle(.borderedProminent)
    }.padding(24).frame(minWidth:300,idealWidth:470).background(.background)
    .fileImporter(isPresented:$chooseFolder,allowedContentTypes:[.folder]) {result in
      switch result {case .success(let url):start(url,share:false);case .failure(let error):if !error.isUserCancellation {model.issues.append(error.localizedDescription)}}
    }
  }
  func start(_ url:URL,share:Bool) {
    guard request.sessionID==model.sourceSessionID else {model.issues.append("Workspace changed. Request this export again.");model.capturedPhotoExport=nil;return}
    model.capturedPhotoExport=nil
    if share {
      model.export(to:url,frozenRequests:request.requests) { outputs in model.beginSharing(outputs) }
    } else { model.export(to:url,frozenRequests:request.requests) }
  }
}
private struct WorkspaceActionSurfaces:ViewModifier {
  @Bindable var model:Workspace
  func body(content:Content)->some View {
    content
      .sheet(item:$model.universalActionRequest,onDismiss:model.finishUniversalAction) {UniversalActionsView(model:model,request:$0).privacyCurtain(model:model)}
      .sheet(item:$model.recipeRequest,onDismiss:{if let export=model.pendingCapturedExport {model.pendingCapturedExport=nil;model.capturedPhotoExport=export}}) {RecipeBuilder(model:model,request:$0).privacyCurtain(model:model)}
      .sheet(item:$model.capturedPhotoExport) {CapturedExportView(model:model,request:$0).privacyCurtain(model:model)}
      #if os(iOS)
      .background {Button("Actions…") {model.presentActions()}.keyboardShortcut("k",modifiers:.command).hidden().accessibilityHidden(true)}
      #endif
  }
}
extension View {func workspaceActionSurfaces(_ model:Workspace)->some View {modifier(WorkspaceActionSurfaces(model:model))}}
