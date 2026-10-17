import Foundation

public enum EditorDocumentError: Error, LocalizedError {
  case invalidDocument, unsupportedVersion, missingResource, unsafeResource, hdr, reviewRequired
  public var errorDescription: String? {
    switch self {
    case .reviewRequired: "Review the visible photo layers before exporting this document."
    case .hdr: "Layered documents currently support SDR images. HDR development is not available yet."
    case .invalidDocument: "The editable document contains invalid or excessive content."
    case .unsupportedVersion: "This document needs a newer version of Ameluma. The saved file has not been changed."
    case .missingResource: "An image required by this document is missing."
    case .unsafeResource: "The document contains an unsafe resource reference."
    }
  }
}
public enum EditorBlendMode: String, Codable, CaseIterable, Sendable {
  case normal, multiply, screen, overlay, darken, lighten, softLight, hardLight
}
public enum EditorShapeKind: String, Codable, CaseIterable, Sendable {
  case rectangle, roundedRectangle, ellipse, line, arrow
}
public struct EditorTextShadow: Codable, Equatable, Sendable {
  public var colour = RGBAColour(0,0,0,0.6)
  public var radius = 3.0
  public var offsetX = 2.0
  public var offsetY = -2.0
  public init() {}
}
public struct EditorText: Codable, Equatable, Sendable {
  public var text = "Your text"
  public var fontName = "HelveticaNeue"
  public var fontSize = 48.0
  public var colour = RGBAColour(0,0,0,1)
  public var alignment: AnnotationTextAlignment = .leading
  public var bold = false
  public var italic = false
  public var underline = false
  public var outlineColour: RGBAColour?
  public var outlineWidth: Double?
  public var shadow: EditorTextShadow?
  public init() {}
}
public struct EditorShape: Codable, Equatable, Sendable {
  public var kind: EditorShapeKind = .rectangle
  public var fill: RGBAColour? = RGBAColour(0.15,0.45,0.95,1)
  public var stroke = RGBAColour(0,0,0,1)
  public var strokeWidth = 2.0
  public var cornerRadius = 20.0
  public init() {}
}
public enum EditorLayerContent: Codable, Equatable, Sendable {
  case image(resourceID: UUID, configuration: ProcessingConfiguration)
  case text(EditorText)
  case shape(EditorShape)
}
/// Document pixels, top-left origin. Content stays local; transforms do not rewrite resources.
public struct EditorLayer: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var name: String
  public var content: EditorLayerContent
  public var x = 0.0
  public var y = 0.0
  public var width = 640.0
  public var height = 480.0
  public var watermarkResourceID: UUID?
  public var rotation = 0.0
  public var flipHorizontal = false
  public var flipVertical = false
  public var visible = true
  public var locked = false
  public var opacity = 1.0
  public var blendMode: EditorBlendMode = .normal
  public init(name: String, content: EditorLayerContent) { self.name=name; self.content=content }
}
public struct EditorResource: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var fileExtension: String
  public var filename: String { id.uuidString + "." + fileExtension }
  public init(id: UUID = UUID(), name: String, fileExtension: String) {
    self.id=id; self.name=name; self.fileExtension=fileExtension.lowercased()
  }
}
public struct EditorDocument: Codable, Equatable, Identifiable, Sendable {
  public var version = 1
  public var id = UUID()
  public var name = "Untitled Image"
  public var width = 1600
  public var height = 1200
  /// nil means transparent. The viewport checkerboard is never exported.
  public var background: RGBAColour?
  public var layers: [EditorLayer] = [] // back to front
  public var resources: [EditorResource] = []
  /// Optional for compatibility with existing version-1 image documents.
  public var watermarkDesign: Bool?
  public var privacyReviewLayerIDs:Set<UUID>?
  public var pendingPrivacyReviewIDs:Set<UUID> {
    (privacyReviewLayerIDs ?? []).intersection(Set(layers.filter{$0.visible && $0.opacity>0}.map(\.id)))
  }
  /// Version 2 prevents older editors silently discarding designer metadata or text treatments.
  public var requiredVersion: Int {
    if watermarkDesign == true { return 2 }
    return layers.contains { layer in
      if case .text(let text) = layer.content { return text.outlineColour != nil || text.outlineWidth != nil || text.shadow != nil }
      return false
    } ? 2 : 1
  }
  public func validateForExport() throws {try validate();if !pendingPrivacyReviewIDs.isEmpty {throw EditorDocumentError.reviewRequired}}
  public init() {}
  public func validate() throws {
    guard (1...2).contains(version) else { throw EditorDocumentError.unsupportedVersion }
    guard version >= requiredVersion else { throw EditorDocumentError.unsupportedVersion }
    guard (1...20000).contains(width), (1...20000).contains(height), width*height<=50_000_000,
      name.count<=512, layers.count<=200, resources.count<=200,
      Set(layers.map(\.id)).count==layers.count, Set(resources.map(\.id)).count==resources.count else { throw EditorDocumentError.invalidDocument }
    func colour(_ c: RGBAColour) -> Bool { [c.red,c.green,c.blue,c.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    guard background.map(colour) ?? true else { throw EditorDocumentError.invalidDocument }
    for resource in resources {
      guard !resource.fileExtension.isEmpty, resource.fileExtension.count<=10,
        resource.fileExtension.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }),
        resource.name.count<=1024 else { throw EditorDocumentError.unsafeResource }
    }
    for layer in layers {
      guard layer.name.count<=512,
        [layer.x,layer.y,layer.width,layer.height,layer.rotation,layer.opacity].allSatisfy(\.isFinite),
        abs(layer.x)<=100000, abs(layer.y)<=100000, (0.1...20000).contains(layer.width), (0.1...20000).contains(layer.height),
        layer.width*layer.height<=50_000_000, abs(layer.rotation)<=360, (0...1).contains(layer.opacity) else { throw EditorDocumentError.invalidDocument }
      switch layer.content {
      case .image(let id, let configuration):
        guard resources.contains(where: { $0.id==id }), configuration.width>0, configuration.height>0, configuration.width<=20000, configuration.height<=20000, Double(configuration.width)*Double(configuration.height)<=100_000_000 else { throw EditorDocumentError.missingResource }
        // External watermark resources must be embedded and rewritten by acquisition before saving.
        if configuration.watermark.enabled && configuration.watermark.kind == .image && layer.watermarkResourceID == nil {throw EditorDocumentError.missingResource}
        if configuration.watermark.imageURL != nil { throw EditorDocumentError.unsafeResource }
        if let watermark=layer.watermarkResourceID, !resources.contains(where: { $0.id==watermark }) {throw EditorDocumentError.missingResource}
      case .text(let text):
        guard text.text.count<=10000, text.fontName.count<=256, text.fontSize.isFinite, (1...2000).contains(text.fontSize), colour(text.colour) else { throw EditorDocumentError.invalidDocument }
        if let width = text.outlineWidth, !width.isFinite || !(0...100).contains(width) { throw EditorDocumentError.invalidDocument }
        if let outline = text.outlineColour, !colour(outline) { throw EditorDocumentError.invalidDocument }
        if let shadow = text.shadow {
          guard colour(shadow.colour), [shadow.radius, shadow.offsetX, shadow.offsetY].allSatisfy(\.isFinite),
            (0...100).contains(shadow.radius), abs(shadow.offsetX)<=100, abs(shadow.offsetY)<=100 else { throw EditorDocumentError.invalidDocument }
        }
      case .shape(let shape):
        guard shape.strokeWidth.isFinite, (0...1000).contains(shape.strokeWidth), shape.cornerRadius.isFinite,
          (0...10000).contains(shape.cornerRadius), colour(shape.stroke), shape.fill.map(colour) ?? true else { throw EditorDocumentError.invalidDocument }
      }
    }
  }
}
/// Semantic snapshots use copy-on-write values and immutable resource references, never decoded bitmaps.
public struct EditorDocumentHistory: Sendable {
  public struct Step: Identifiable, Sendable { public var id=UUID(); public var title:String; public var document:EditorDocument }
  public private(set) var current: EditorDocument
  public private(set) var undoSteps: [Step] = []
  public private(set) var redoSteps: [Step] = []
  public init(_ document:EditorDocument) { current=document }
  public mutating func apply(_ next:EditorDocument, title:String) throws {
    try next.validate(); guard next != current else { return }
    undoSteps.append(Step(title:title,document:current)); if undoSteps.count>80 { undoSteps.removeFirst() }
    current=next; redoSteps=[]
  }
  public mutating func undo() {
    guard let previous=undoSteps.popLast() else{return}
    redoSteps.append(Step(title:previous.title,document:current)); current=previous.document
  }
  public mutating func redo() {
    guard let next=redoSteps.popLast() else{return}
    undoSteps.append(Step(title:next.title,document:current)); current=next.document
  }
}
