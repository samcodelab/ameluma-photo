import Foundation
import FramepebbleCore

struct SavedWatermarkDesign: Identifiable, Sendable {
  var document: EditorDocument
  var url: URL
  var id: UUID { document.id }
}
actor WatermarkDesignLibrary {
  let root: URL
  init(root: URL) { self.root = root }
  func list() async throws -> [SavedWatermarkDesign] {
    guard FileManager.default.fileExists(atPath: root.path) else { return [] }
    var result: [SavedWatermarkDesign] = []
    for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      where url.pathExtension == "ameluma" {
      let document = try EditorDocumentStore.readPackage(url)
      result.append(SavedWatermarkDesign(document: document, url: url))
    }
    return result.sorted { $0.document.name.localizedStandardCompare($1.document.name) == .orderedAscending }
  }
  func importDesign(_ url: URL) throws -> URL {
    var document = try EditorDocumentStore.readPackage(url)
    document.id = UUID() // Import is a new saved design, never an implicit replacement.
    let resources = Dictionary(uniqueKeysWithValues: document.resources.map { ($0.id, url.appendingPathComponent("Resources").appendingPathComponent($0.filename)) })
    return try save(document, resources: resources)
  }
  func remove(_ design: SavedWatermarkDesign) throws {
    let expected = root.appendingPathComponent(design.id.uuidString + ".ameluma")
    guard design.url.standardizedFileURL.path == expected.standardizedFileURL.path else { throw EditorDocumentError.unsafeResource }
    _ = try EditorDocumentStore.readPackage(expected)
    try FileManager.default.removeItem(at: expected)
  }
  func freeze(_ design: SavedWatermarkDesign, to destination: URL) throws -> EditorDocument {
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: design.url, to: destination)
    return try EditorDocumentStore.readPackage(destination)
  }
  func save(_ document: EditorDocument, resources: [UUID: URL]) throws -> URL {
    try document.validateForExport()
    guard document.watermarkDesign == true, document.background == nil,
      !document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      document.layers.contains(where: { $0.visible && $0.opacity > 0 }) else { throw EditorDocumentError.invalidDocument }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent(document.id.uuidString + ".ameluma")
    try EditorDocumentStore.writePackage(document, resources: resources, to: url)
    return url
  }
}

extension Workspace {
  func newWatermarkDesign(_ template: WatermarkTemplate) {
    guard !overlayEditor, !running else { return }
    var document = template.document; document.id = UUID()
    let session = EditorDocumentSession(document: document,
      directory: directory.deletingLastPathComponent().appendingPathComponent("EditorDocuments").appendingPathComponent(UUID().uuidString))
    editorDocuments.append(session); activeEditorDocumentID = session.id; session.scheduleRecovery()
  }
  func editWatermarkDesign(_ design: SavedWatermarkDesign) async {
    guard !overlayEditor, !running else { return }
    let session = EditorDocumentSession(directory: directory.deletingLastPathComponent().appendingPathComponent("EditorDocuments").appendingPathComponent(UUID().uuidString))
    do {
      try await session.open(design.url)
      editorDocuments.append(session); activeEditorDocumentID = session.id
    } catch { issues.append("Could not open watermark design: " + error.localizedDescription) }
  }
  /// Freeze the target, content and prior edits before any decoding or rendering.
  /// A changed photo is skipped rather than having a newer edit overwritten.
  @discardableResult
  func applyWatermarkDesign(_ design: SavedWatermarkDesign, ids: [UUID]) async -> Bool {
    let capturedIDs = workspaceActionIDs(ids)
    guard !overlayEditor, !running, !capturedIDs.isEmpty else { return false }
    let sourceSession = sourceSessionID
    let sources = Dictionary(uniqueKeysWithValues: workspaceAssets.filter { capturedIDs.contains($0.id) }.map { ($0.id, $0) })
    let before = Dictionary(uniqueKeysWithValues: workspaceAssets.filter { capturedIDs.contains($0.id) }.map { ($0.id, edits.configuration(for: $0.id)) })
    let job = directory.deletingLastPathComponent().appendingPathComponent("WatermarkRenderJobs").appendingPathComponent(UUID().uuidString)
    sourceAcquisitions += 1
    var acquiredStamp: URL?
    var committed = false
    defer {
      sourceAcquisitions -= 1; try? FileManager.default.removeItem(at: job)
      if !committed, let acquiredStamp { try? FileManager.default.removeItem(at: acquiredStamp) }
    }
    do {
      let frozen = job.appendingPathComponent("Design.ameluma")
      let document = try await watermarkDesignLibrary.freeze(design, to: frozen)
      let resources = Dictionary(uniqueKeysWithValues: document.resources.map { ($0.id, frozen.appendingPathComponent("Resources").appendingPathComponent($0.filename)) })
      try document.validateForExport()
      guard document.watermarkDesign == true, document.background == nil else { throw EditorDocumentError.invalidDocument }
      let metadata = try await WorkspaceMetadataReader().read(Array(sources.values))
      let requiredWidth = capturedIDs.reduce(Double(document.width)) { result, id in
        guard let configuration = before[id] else { return result }
        let sourceEdge = metadata[id].map { max($0.width, $0.height) } ?? 0
        let edge = max(sourceEdge, max(configuration.width, configuration.height))
        return max(result, Double(edge) * configuration.watermark.relativeWidth)
      }
      let aspect = Double(document.width) / Double(document.height)
      // One bounded high-resolution stamp per application; text and shapes rasterize
      // at the required output size rather than enlarging a thumbnail-sized bitmap.
      let budgetWidth = min(20000.0, 20000.0 * aspect, sqrt(16_000_000 * aspect))
      let width = max(1, Int(min(requiredWidth, budgetWidth).rounded(.down)))
      let longEdge = max(width, Int((Double(width) / aspect).rounded(.down)))
      let image = try await EditorDocumentRenderer().render(document, resources: resources, outputLongEdge: longEdge)
      try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
      var config = ProcessingConfiguration(); config.format = .png
      var profile = ExportProfile(); profile.suffix = ""; profile.namingTemplate = "{name}"
      let output = try await processor.publish(image, asset: SourceAsset(url: job.appendingPathComponent("Design"), name: document.name), configuration: config, to: job, profile: profile, flattenTransparency: false)
      guard let url = output.output else { throw ProcessingError.validation }
      let stamp = try await processor.importSnapshot(url, to: directory)
      acquiredStamp = stamp.url
      try Task.checkCancellation()
      guard sourceSession == sourceSessionID, !clearingWorkspace else { return false }
      let valid = Set(workspaceActionIDs(capturedIDs).filter { id in before[id] == edits.configuration(for: id) && sources[id] == workspaceAssets.first(where: { $0.id == id }) })
      guard !valid.isEmpty else { status = "No watermark applied. Target photos changed; select them again."; return false }
      var value = ProcessingConfiguration(); value.watermark.kind = .image
      value.watermark.enabled = true; value.watermark.imageURL = stamp.url
      let patch = ConfigurationPatch(values: value, fields: [.watermark_kind, .watermark_enabled, .watermark_imageURL])
      var next = edits
      for id in valid { next.apply(patch, to: id) }
      commit(next, title: "Apply " + document.name + " · \(valid.count) photos")
      committed = true
      status = "Applied \(document.name) to \(valid.count) \(valid.count == 1 ? "photo" : "photos")" + (valid.count < capturedIDs.count ? "; skipped \(capturedIDs.count-valid.count) changed photos." : ".")
      return true
    } catch is CancellationError { status = "Watermark application cancelled."; return false }
    catch { issues.append("Watermark application failed: " + error.localizedDescription); return false }
  }
}
