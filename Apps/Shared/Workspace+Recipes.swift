import Foundation
import FramepebbleCore
import CoreGraphics

actor RecipeLibrary {
  let root: URL
  private let processor = ImageProcessor()
  init(root: URL) { self.root = root }
  private var file: URL { root.appendingPathComponent("Recipes.json") }
  func list() throws -> [ProcessingRecipe] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8*1024*1024 else { throw ProcessingError.invalidConfiguration }
    var recipes = try JSONDecoder().decode([ProcessingRecipe].self, from: Data(contentsOf: file))
    // App containers may be relocated by backup/restore. Rebind only validated,
    // UUID-named resources already owned by this recipe library.
    for index in recipes.indices {
      if let old=recipes[index].watermark.imageURL,
        old.deletingLastPathComponent().lastPathComponent == "RecipeAssets",
        UUID(uuidString:old.deletingPathExtension().lastPathComponent) != nil {
        let owned=root.appendingPathComponent("RecipeAssets").appendingPathComponent(old.lastPathComponent)
        if FileManager.default.fileExists(atPath:owned.path) {recipes[index].watermark.imageURL=owned}
      }
    }
    guard recipes.count<=200, Set(recipes.map(\.id)).count==recipes.count, recipes.allSatisfy({$0.version==1}) else { throw ProcessingError.invalidConfiguration }
    return recipes.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
  }
  func save(_ recipe: ProcessingRecipe) async throws -> ProcessingRecipe {
    try recipe.validate()
    var saved = recipe
    // The library owns imported marks. Neither project cleanup nor deleting the
    // original logo can invalidate a reusable recipe. Applied marks remain immutable.
    if recipe.watermark.kind == .image, let url=recipe.watermark.imageURL {
      let assets=root.appendingPathComponent("RecipeAssets")
      try FileManager.default.createDirectory(at:assets,withIntermediateDirectories:true)
      if url.deletingLastPathComponent().standardizedFileURL.path != assets.standardizedFileURL.path {
        let copy=try await processor.importSnapshot(url,to:assets);saved.watermark.imageURL=copy.url
      } else if !FileManager.default.fileExists(atPath:url.path) {throw ProcessingError.invalidImage}
    }
    // Load after acquisition: actor reentrancy cannot lose another saved recipe.
    var recipes=try list();recipes.removeAll {$0.id==saved.id};recipes.append(saved)
    guard recipes.count<=200 else {throw ProcessingError.invalidConfiguration}
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    try Task.checkCancellation()
    try JSONEncoder().encode(recipes).write(to:file,options:.atomic)
    return saved
  }
  func remove(_ id: UUID) throws {
    var recipes=try list();recipes.removeAll {$0.id==id}
    try JSONEncoder().encode(recipes).write(to:file,options:.atomic)
    // Assets may still be owned by current/saved photos or their undo histories.
  }
}
struct RecipeRequest: Identifiable {
  let id=UUID()
  let sessionID: UUID
  let assets: [SourceAsset]
  let configurations: [UUID: ProcessingConfiguration]
  var ids: [UUID] {assets.map(\.id)}
  var label: String {assets.count == 1 ? "this photo" : "\(assets.count) photos"}
}
struct RecipeOutcome {
  var changedIDs=Set<UUID>()
  var changed=0; var skipped=0; var failed=0; var notRun=0; var cancelled=false
  var reasons: [String]=[]
  var summary: String {"\(changed) changed · \(skipped) skipped · \(failed) failed" + (notRun>0 ? " · \(notRun) not run":"") + (cancelled ? " · cancelled":"")}
}
extension Workspace {
  func makeRecipeRequest(ids: [UUID]) -> RecipeRequest {
    let ids=workspaceActionIDs(ids)
    let sources=ids.compactMap {id in workspaceAssets.first {$0.id==id}}
    return RecipeRequest(sessionID:sourceSessionID,assets:sources,configurations:Dictionary(uniqueKeysWithValues:sources.map {($0.id,configuration(for:$0))}))
  }
  func continuingRecipeRequest(_ request:RecipeRequest, changedIDs:Set<UUID>) -> RecipeRequest {
    var configurations=request.configurations
    if sourceSessionID==request.sessionID {
      for asset in request.assets where changedIDs.contains(asset.id) && workspaceAssets.contains(asset) {
        configurations[asset.id]=configuration(for:asset)
      }
    }
    return RecipeRequest(sessionID:request.sessionID,assets:request.assets,configurations:configurations)
  }
  func presentRecipes(ids: [UUID]? = nil) {
    guard !overlayEditor, colourReplacementAsset == nil, activeEditorDocument == nil, !recipeApplying else {return}
    recipeRequest=makeRecipeRequest(ids:ids ?? actionContext.photoIDs)
  }
  func applyRecipe(_ recipe: ProcessingRecipe, request: RecipeRequest) async -> RecipeOutcome {
    var outcome=RecipeOutcome()
    guard !switchingDemo, !overlayEditor, !running, !quickFixRunning, !recipeApplying, request.sessionID==sourceSessionID else {outcome.skipped=request.assets.count;outcome.reasons=["The workspace changed or another operation is active. Reopen Recipes."];return outcome}
    do {try recipe.validate()}catch{outcome.failed=request.assets.count;outcome.reasons=[error.localizedDescription];return outcome}
    recipeApplying=true;recipeProgress=0;running=true;total=request.assets.count;completed=0
    status="Applying recipe · "+recipe.name
    defer {recipeApplying=false;if sourceSessionID==request.sessionID {running=false}}
    let reader=WorkspaceMetadataReader()
    var completed:[UUID:ProcessingConfiguration]=[:]
    for (index,asset) in request.assets.enumerated() {
      if Task.isCancelled {outcome.cancelled=true;break}
      guard request.sessionID==sourceSessionID else {outcome.skipped += request.assets.count-index;outcome.reasons.append("Workspace changed; remaining photos were not modified.");break}
      do {
        let metadata=try await reader.read([asset])
        guard let info=metadata[asset.id],let before=request.configurations[asset.id] else {throw ProcessingError.invalidImage}
        if recipe.enabled.contains(.filter),recipe.presetID != nil {try await processor.validateCreativeSource(asset.url)}
        let configuration=try recipe.configuration(for:before,sourceSize:CGSize(width:info.width,height:info.height),grainSeed:Self.filterSeed(asset.id))
        completed[asset.id]=configuration
      } catch is CancellationError {outcome.cancelled=true;break}
      catch {outcome.failed += 1;outcome.reasons.append(asset.name+": "+error.localizedDescription)}
      self.completed=index+1
      recipeProgress=Double(index+1)/Double(max(1,request.assets.count))
      await Task.yield()
    }
    var next=edits
    for asset in request.assets where completed[asset.id] != nil {
      guard sourceSessionID==request.sessionID, workspaceAssets.contains(asset), configuration(for:asset)==request.configurations[asset.id], let after=completed[asset.id],let before=request.configurations[asset.id] else {outcome.skipped += 1;outcome.reasons.append(asset.name+": changed or removed during this operation.");continue}
      if after != before {next.apply(ConfigurationPatch(from:before,to:after),to:asset.id);outcome.changed += 1;outcome.changedIDs.insert(asset.id)}
      else {outcome.skipped += 1}
    }
    if outcome.cancelled {outcome.notRun=max(0,request.assets.count-completed.count-outcome.failed)}
    if outcome.changed>0 {
      commit(next,title:"Recipe: "+recipe.name+" · \(outcome.changed) photos")
    }
    if request.sessionID==sourceSessionID {status=outcome.summary}
    return outcome
  }
}
