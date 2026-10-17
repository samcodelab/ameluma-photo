import XCTest
import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FramepebbleCore
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

@MainActor final class EditorUsabilityTests: XCTestCase {
  #if os(macOS)
  func testNativeSelectionReceivesDragBeforeMouseUp() throws {
    let view = MacRetouchInput.InputView(frame:CGRect(x:0,y:0,width:400,height:300))
    let window = NSWindow(contentRect:view.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView = view; view.active = true
    var moved:[CGPoint] = []; var ended = false
    view.moved = { moved.append($0) }; view.ended = { _ in ended = true }
    func event(_ type:NSEvent.EventType,_ point:CGPoint) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
    }
    view.mouseDown(with:try event(.leftMouseDown,CGPoint(x:30,y:30)))
    view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:60,y:50)))
    view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:90,y:70)))
    XCTAssertEqual(moved.count,2)
    XCTAssertFalse(ended,"Live feedback must receive points before release")
    view.mouseUp(with:try event(.leftMouseUp,CGPoint(x:100,y:80)))
    XCTAssertTrue(ended)
  }
  #endif
  func testLiveSelectionFeedbackUsesCurrentDragAndPreservesHoles() {
    let saved = [NormalizedPoint(0,0),NormalizedPoint(1,0),NormalizedPoint(1,1),NormalizedPoint(0,1)]
    let hole = [NormalizedPoint(0.4,0.4),NormalizedPoint(0.6,0.4),NormalizedPoint(0.6,0.6),NormalizedPoint(0.4,0.6)]
    let live = [NormalizedPoint(0.1,0.1),NormalizedPoint(0.3,0.1),NormalizedPoint(0.3,0.3),NormalizedPoint(0.1,0.3)]
    let size = CGSize(width:1000,height:500)
    let dragging = ColourSelectionFeedback.path(outline:saved,holes:[hole],drawing:live,size:size)
    XCTAssertTrue(dragging.contains(CGPoint(x:200,y:100),eoFill:true))
    XCTAssertFalse(dragging.contains(CGPoint(x:800,y:400),eoFill:true))
    let committed = ColourSelectionFeedback.path(outline:saved,holes:[hole],drawing:[],size:size)
    XCTAssertTrue(committed.contains(CGPoint(x:200,y:100),eoFill:true))
    XCTAssertFalse(committed.contains(CGPoint(x:500,y:250),eoFill:true))
  }
  func testEditorTimingRejectsSupersededAndChangedInputs() {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model=Workspace(directory:root)
    defer { model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root) }
    let a=SourceAsset(url:root.appendingPathComponent("a.png")),b=SourceAsset(url:root.appendingPathComponent("b.png"))
    model.assets=[a,b];model.openPhoto(a)
    let config=model.configuration(for:a)
    let old=model.beginEditorFeedback(.toolSwitch,for:a,configuration:config)
    let new=model.beginEditorFeedback(.strokePreview,for:a,configuration:nil)
    model.finishEditorFeedback(old,for:a,configuration:config)
    XCTAssertTrue(model.editorFeedbackMeasurements.isEmpty)
    model.updateEditorFeedback(new,configuration:config)
    model.finishEditorFeedback(new,for:b,configuration:config)
    XCTAssertTrue(model.editorFeedbackMeasurements.isEmpty)
    model.finishEditorFeedback(new,for:a,configuration:config)
    XCTAssertEqual(model.editorFeedbackMeasurements.count,1)
    XCTAssertEqual(model.editorFeedbackMeasurements.first?.kind,.strokePreview)
    let changed=model.beginEditorFeedback(.toolSwitch,for:a,configuration:config)
    model.sourceSessionID=UUID()
    model.finishEditorFeedback(changed,for:a,configuration:config)
    XCTAssertEqual(model.editorFeedbackMeasurements.count,1)
    model.cancelEditorFeedback(changed)
    XCTAssertNil(model.editorFeedbackToken)
  }

  func testToolMagnificationSurvivesSwitchesWithoutChangingOutputOrBatchScope() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let a = SourceAsset(url: root.appendingPathComponent("a.png")), b = SourceAsset(url: root.appendingPathComponent("b.png"))
    model.assets = [a,b]; model.openPhoto(a); model.selection = [b.id]; model.batchInputIDs = [b.id]
    let configuration = model.configuration(for: a)
    model.setPhotoMagnification(2.5, for: a.id)
    model.setPhotoViewportCenter(CGPoint(x:0.7,y:0.3),for:a.id)
    XCTAssertTrue(model.activatePhotoTool(.crop))
    XCTAssertTrue(model.precision)
    XCTAssertTrue(model.activatePhotoTool(.filters))
    XCTAssertFalse(model.precision, "Crop must not remain active beneath another tool")
    XCTAssertTrue(model.activatePhotoTool(.retouch))
    XCTAssertEqual(model.photoMagnification(for: a.id), 2.5)
    XCTAssertTrue(model.activatePhotoTool(.adjust))
    XCTAssertEqual(model.photoMagnification(for: a.id), 2.5)
    XCTAssertEqual(model.photoMagnification(for: b.id), 1)
    XCTAssertEqual(model.photoViewportCenter(for:a.id),CGPoint(x:0.7,y:0.3))
    XCTAssertEqual(model.photoViewportCenter(for:b.id),CGPoint(x:0.5,y:0.5))
    XCTAssertEqual(model.configuration(for: a), configuration)
    XCTAssertEqual(model.selection, [b.id]); XCTAssertEqual(model.batchInputIDs, [b.id])
    model.setPhotoMagnification(.nan, for: a.id)
    XCTAssertEqual(model.photoMagnification(for: a.id), 2.5)
    model.setPhotoMagnification(100, for: a.id)
    XCTAssertEqual(model.photoMagnification(for: a.id), 4)
    model.sourceSessionID = UUID()
    XCTAssertEqual(model.photoMagnification(for: a.id), 1, "A different workspace cannot inherit an old photo viewport")
    XCTAssertEqual(model.photoViewportCenter(for:a.id),CGPoint(x:0.5,y:0.5))
  }

  func testEditorPreviewIsReusedOnlyForMatchingPhotoEditsAndSession() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let a = SourceAsset(url: root.appendingPathComponent("a.png")), b = SourceAsset(url: root.appendingPathComponent("b.png"))
    model.assets = [a,b]; model.openPhoto(a)
    let c = model.configuration(for: a)
    let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try XCTUnwrap(context.makeImage())
    model.rememberEditorPreview(image, source: a, configuration: c, maximum: 1600)
    XCTAssertTrue(try XCTUnwrap(model.editorPreview(for: a, configuration: c, minimum: 1600)) === image)
    XCTAssertNil(model.editorPreview(for: a, configuration: c, minimum: 3200))
    XCTAssertNil(model.editorPreview(for: b, configuration: c))
    var changed = c; changed.adjustments.exposure = 1
    XCTAssertNil(model.editorPreview(for: a, configuration: changed))
    model.rememberEditorPreview(image, source: a, configuration: changed)
    XCTAssertTrue(try XCTUnwrap(model.editorPreview(for: a, configuration: c)) === image, "An uncommitted draft cannot replace the committed preview")
    XCTAssertTrue(model.activatePhotoTool(.filters))
    XCTAssertTrue(model.activatePhotoTool(.replaceColour))
    XCTAssertEqual(model.colourReplacementAsset, a)
    XCTAssertTrue(try XCTUnwrap(model.editorPreview(for: a, configuration: c)) === image)
    model.sourceSessionID = UUID()
    XCTAssertNil(model.editorPreview(for: a, configuration: c))
    model.rememberEditorPreview(image,source:a,configuration:c)
    XCTAssertNotNil(model.editorPreviewSnapshot)
    model.privateEditing=true
    XCTAssertNil(model.editorPreviewSnapshot)
    model.rememberEditorPreview(image,source:a,configuration:c)
    XCTAssertNil(model.editorPreview(for:a,configuration:c))
  }

  func testLiveColourSelectionFillFollowsTraceAndKeepsSavedCutouts() {
    let outline = [NormalizedPoint(0.1,0.1), NormalizedPoint(0.8,0.1), NormalizedPoint(0.8,0.8), NormalizedPoint(0.1,0.8)]
    let hole = [NormalizedPoint(0.4,0.4), NormalizedPoint(0.6,0.4), NormalizedPoint(0.6,0.6), NormalizedPoint(0.4,0.6)]
    let live = ColourSelectionFeedback.path(outline: [], holes: [], drawing: outline, size: CGSize(width: 100, height: 200))
    XCTAssertTrue(live.contains(CGPoint(x: 50, y: 100)))
    XCTAssertFalse(live.contains(CGPoint(x: 95, y: 100)))
    XCTAssertEqual(live.boundingRect, CGRect(x: 10, y: 20, width: 70, height: 140))
    let saved = ColourSelectionFeedback.path(outline: outline, holes: [hole], drawing: [], size: CGSize(width: 100, height: 200))
    XCTAssertFalse(saved.contains(CGPoint(x: 50, y: 100), eoFill: true))
    XCTAssertTrue(saved.contains(CGPoint(x: 20, y: 40), eoFill: true))
  }

  func testColourReplacementOpensInEditorAndProtectsActiveDraft() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: root) }
    let a = SourceAsset(url: root.appendingPathComponent("a.png")), b = SourceAsset(url: root.appendingPathComponent("b.png"))
    model.assets = [a,b]; model.openPhoto(a); model.selection = [b.id]; model.batchInputIDs = [b.id]
    let edits = model.edits
    model.openColourReplacement(a)
    XCTAssertTrue(model.overlayEditor)
    XCTAssertEqual(model.colourReplacementAsset, a)
    XCTAssertFalse(model.browsingLibrary)
    XCTAssertEqual(model.selection, [b.id]); XCTAssertEqual(model.batchInputIDs, [b.id]); XCTAssertEqual(model.edits, edits)
    model.openColourReplacement(b)
    XCTAssertEqual(model.colourReplacementAsset, a, "Another tool entry cannot replace an unfinished colour draft")
    model.presentWorkspaceSwitcher()
    XCTAssertFalse(model.projectsView)
  }

  func testColourReplacementTargetsOnePhotoSupportsUndoAndRejectsStaleDraft() {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model=Workspace(directory:root)
    defer { model.persistenceTask?.cancel();try? FileManager.default.removeItem(at:root) }
    let a=SourceAsset(url:root.appendingPathComponent("a.png")),b=SourceAsset(url:root.appendingPathComponent("b.png"))
    model.assets=[a,b];model.selection=[a.id,b.id];model.batchInputIDs=[a.id,b.id]
    let baseline=model.configuration(for:a),session=model.sourceSessionID
    var edit=ColourReplacement();edit.points=[NormalizedPoint(0,0),NormalizedPoint(1,0),NormalizedPoint(1,1),NormalizedPoint(0,1)]
    XCTAssertTrue(model.commitColourReplacement(edit,asset:a,baseline:baseline,sessionID:session))
    XCTAssertEqual(model.configuration(for:a).colourReplacements,[edit]);XCTAssertTrue(model.configuration(for:b).colourReplacements.isEmpty)
    XCTAssertEqual(model.batchInputIDs,[a.id,b.id]);XCTAssertEqual(model.selection,[a.id,b.id])
    XCTAssertFalse(model.commitColourReplacement(edit,asset:a,baseline:baseline,sessionID:session),"A stale draft must not overwrite a newer edit")
    model.undo();XCTAssertEqual(model.configuration(for:a),baseline)
    model.redo();XCTAssertEqual(model.configuration(for:a).colourReplacements,[edit])
    var revised = edit; revised.intensity = 0.3
    XCTAssertTrue(model.commitColourReplacement(revised,asset:a,baseline:model.configuration(for:a),sessionID:session,replacingID:edit.id))
    XCTAssertEqual(model.configuration(for:a).colourReplacements,[revised],"Editing a saved area replaces it instead of stacking another copy")
    let current=model.configuration(for:a);model.sourceSessionID=UUID()
    XCTAssertFalse(model.commitColourReplacement(edit,asset:a,baseline:current,sessionID:session))
  }

  func testCompletedNumericSessionUndoesMultipleLiveValuesTogether() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: directory)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: directory) }
    let source = SourceAsset(url: directory.appendingPathComponent("photo.png"))
    model.assets = [source]; model.openPhoto(source)
    model.selectCreativeFilter("essentials.clean")
    let baseline = model.configuration(for: source)
    XCTAssertFalse(model.interactionInProgress)
    model.beginInteraction()
    XCTAssertTrue(model.interactionInProgress)
    model.setFilterIntensity(0.2)
    model.setFilterIntensity(0.25)
    model.setFilterIntensity(0.3)
    model.endInteraction()
    XCTAssertFalse(model.interactionInProgress)
    XCTAssertEqual(model.configuration(for: source).filterEdit?.intensity, 0.3)
    model.undo()
    XCTAssertEqual(model.configuration(for: source), baseline)
    model.redo()
    XCTAssertEqual(model.configuration(for: source).filterEdit?.intensity, 0.3)
  }

  func testRetouchComparisonKeepsCurrentProtectiveOverlaysAndOtherEdits() {
    var original = ProcessingConfiguration()
    original.retouchStrokes = [RetouchStroke()]
    var current = original
    current.retouchStrokes.append(RetouchStroke())
    current.masks = [PrivacyMask()]
    current.annotations = [Annotation()]
    current.watermark.enabled = true
    current.adjustments.exposure = 0.4
    let compared = OverlayPreviewRequest.beforeRetouch(current: current, original: original)
    XCTAssertEqual(compared.retouchStrokes, original.retouchStrokes)
    var expected = current; expected.retouchStrokes = original.retouchStrokes
    XCTAssertEqual(compared, expected)
    XCTAssertEqual(current.retouchStrokes.count, 2, "Comparing never modifies committed or draft instructions")
  }

  func testNormalPreviewHonorsDetailBudgetWithoutChangingCropPreviewLimits() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: directory)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: directory) }
    let asset = SourceAsset(url: directory.appendingPathComponent("photo.png"))
    var preview = FramingSurface(model: model, asset: asset, interactive: false, maximum: 3200)
    XCTAssertEqual(preview.renderMaximum, 3200)
    preview.maximum = 100_000
    XCTAssertEqual(preview.renderMaximum, 3200, "Viewing detail remains bounded")
    preview.interactive = true
    XCTAssertEqual(preview.renderMaximum, 1000, "Interactive crop preview retains its established budget")
    preview.maximum = 240
    XCTAssertEqual(preview.renderMaximum, 240, "Thumbnail callers retain their requested smaller budget")
  }

  func testFilterChromeDistinguishesOriginalLegacyAndUnavailablePreset() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: directory)
    defer { model.persistenceTask?.cancel(); try? FileManager.default.removeItem(at: directory) }
    let source = SourceAsset(url: directory.appendingPathComponent("photo.png"))
    model.assets = [source]; model.openPhoto(source)
    let picker = PhotoLooksPicker(model: model)
    XCTAssertFalse(picker.hasCreativeFilter)
    var configuration = model.configuration(for: source)
    configuration.look = .vivid
    model.setImageConfiguration(configuration, for: source.id)
    XCTAssertTrue(picker.hasCreativeFilter, "Legacy looks must remain removable")
    configuration.look = nil; configuration.filterEdit = FilterEdit(presetID: "future.unavailable")
    model.setImageConfiguration(configuration, for: source.id)
    XCTAssertTrue(picker.hasCreativeFilter, "Unavailable saved recipes must remain removable")
    model.selectCreativeFilter(nil)
    XCTAssertFalse(picker.hasCreativeFilter)
  }

  func testAdjustmentDisplayScalesRoundTripExistingEdits() {
    for parameter in AdjustmentParameter.allCases {
      let scale = AdjustmentDisplayScale.forTitle(parameter.rawValue)
      for value in [parameter.range.lowerBound, parameter.neutral, parameter.range.upperBound] {
        XCTAssertEqual(scale.stored(scale.display(value)), value, accuracy: 0.0000001)
      }
    }
    XCTAssertEqual(AdjustmentDisplayScale.forTitle("Exposure").unit, "EV")
    XCTAssertEqual(AdjustmentDisplayScale.forTitle("Saturation").display(1), 0)
    XCTAssertEqual(AdjustmentDisplayScale.forTitle("Contrast").display(1), 0)
    XCTAssertEqual(AdjustmentDisplayScale.forTitle("Brightness").display(-0.5), -100)
    XCTAssertEqual(AdjustmentDisplayScale.forTitle("Highlights").display(1), 0)
    XCTAssertEqual(AdjustmentDisplayScale.forTitle("Hue (°)").display(30), 30)
  }

  func testRetouchGesturePreservesClickDabAndRejectsStationaryEvents() {
    let point = NormalizedPoint(0.5, 0.5)
    let size = CGSize(width: 1000, height: 800)
    let dab = RetouchGesturePath.appending(point, to: [], size: size)
    XCTAssertEqual(dab, [point])
    XCTAssertEqual(RetouchGesturePath.appending(point, to: dab, size: size), dab)
    XCTAssertEqual(RetouchGesturePath.appending(NormalizedPoint(0.5001, 0.5), to: dab, size: size), dab)
    XCTAssertEqual(RetouchGesturePath.appending(NormalizedPoint(0.501, 0.5), to: dab, size: size).count, 2)
    XCTAssertEqual(RetouchGesturePath.appending(point, to: Array(repeating: point, count: 2000), size: size).count, 2000)
  }

  func testRetouchDetailBudgetDoesNotGrowWithRepeatedZoom() {
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: 1, retouch: true), 1000)
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: 1.5, retouch: true), 2000)
    for zoom in [2.0, 4, 8, 100] {
      XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: zoom, retouch: true), 3200)
    }
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: .nan, retouch: true), 1000)
    XCTAssertEqual(OverlayPreviewRequest.maximum(zoom: 4, retouch: false), 1000)
  }

  func testPreviewIdentitySeparatesDisplayDetailFromCommittedGeometry() {
    var configuration = ProcessingConfiguration()
    let fit = OverlayPreviewRequest(source: nil, configuration: configuration, maximum: 1000, retry: 0)
    var detail = fit; detail.maximum = 3200
    XCTAssertNotEqual(fit, detail)
    XCTAssertEqual(fit.configuration, detail.configuration)
    configuration.adjustments.exposure = 0.5
    detail.configuration = configuration
    XCTAssertNotEqual(fit.configuration, detail.configuration)
    var retry = fit; retry.retry += 1
    XCTAssertNotEqual(fit, retry)
    let source = SourceAsset(url: URL(fileURLWithPath: "/tmp/original.png"))
    var originalRequest = fit; originalRequest.source = source
    var relinkedSource = source; relinkedSource.url = URL(fileURLWithPath: "/tmp/relinked.png")
    var relinkedRequest = originalRequest; relinkedRequest.source = relinkedSource
    XCTAssertEqual(originalRequest.source?.id, relinkedRequest.source?.id)
    XCTAssertNotEqual(originalRequest, relinkedRequest, "Same source UUID must not accept a preview from its previous pixels")
  }

  func testHigherDetailRenderPreservesOutputGeometryAndOriginalBytes() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: url) }
    let context = try XCTUnwrap(CGContext(data: nil, width: 3600, height: 2400, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.6, green: 0.2, blue: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3600, height: 2400))
    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let original = try Data(contentsOf: url)
    var configuration = ProcessingConfiguration()
    configuration.crop.mode = .preserveAspectRatio
    configuration.resizeBasis = .percentage; configuration.percentage = 100
    let processor = ImageProcessor()
    let fit = try await processor.render(url, configuration: configuration, previewMaximum: 1000)
    let detail = try await processor.render(url, configuration: configuration, previewMaximum: 3200, decodeMaximum: 3200)
    XCTAssertEqual(fit.width, 1000)
    XCTAssertEqual(detail.width, 3200)
    XCTAssertEqual(Double(fit.width) / Double(fit.height), Double(detail.width) / Double(detail.height), accuracy: 0.002)
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(configuration.percentage, 100)
  }
}
