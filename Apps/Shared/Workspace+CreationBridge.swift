import Foundation
import FramepebbleCore

extension Workspace {
  /// A finished result enters the workspace as a new immutable local source.
  /// It must never inherit the batch settings that happened to be active.
  func addDocumentResult(_ session:EditorDocumentSession,sendToGIF:Bool=false) async {
    guard !switchingDemo,!Task.isCancelled,!running,!overlayEditor else {return}
    let snapshot=session.document,resources=session.resources,epoch=sourceSessionID
    running=true;session.busy=true;sourceAcquisitions += 1
    session.status="Rendering finished image…"
    defer {running=false;session.busy=false;sourceAcquisitions -= 1}
    do {
      try snapshot.validateForExport()
      let image=try await session.renderer.render(snapshot,resources:resources)
      try Task.checkCancellation()
      let folder=directory.deletingLastPathComponent().appendingPathComponent("Exports")
      try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
      var config=ProcessingConfiguration();config.format = .png;config.width=image.width;config.height=image.height
      var profile=ExportProfile();profile.namingTemplate="{name}";profile.suffix=""
      let output=try await processor.publish(image,asset:SourceAsset(url:session.directory.appendingPathComponent("Original"),name:snapshot.name),configuration:config,to:folder,profile:profile)
      guard let url=output.output else {throw ProcessingError.validation}
      let asset=try await processor.importSnapshot(url,to:directory)
      guard epoch==sourceSessionID,!clearingWorkspace,!Task.isCancelled else {try? FileManager.default.removeItem(at:asset.url);return}
      assets.append(asset);duplicatesNeedRebuild=true
      var neutral=ProcessingConfiguration();neutral.nativeOutputSizing=true;neutral.crop.mode = .preserveAspectRatio
      neutral.width=image.width;neutral.height=image.height;neutral.format = .png
      endInteraction()
      history.registerSource(asset.id,configuration:neutral);edits=history.current
      activeEditorDocumentID=nil
      if sendToGIF {startGIF(ids:[asset.id])}
      else {showAllWorkspacePhotos();showLibrary()}
      session.status="Finished image added to Workspace";status=session.status;persist()
    }catch is CancellationError {session.status="Creation transfer cancelled."}
    catch {session.error=error.localizedDescription}
  }
}
