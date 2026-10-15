import CoreGraphics
import CoreImage
import Foundation

public enum CollageLayout: String, Codable, Sendable, CaseIterable {
  case grid = "Classic Grid"
  case magazine = "Magazine"
  case freeform = "Freeform"
}
public struct CollageCell: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var sourceID: UUID
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public var rotation = 0.0
  public var crop = CropConfiguration()
  public var shape: CollageShape?
  public init(sourceID: UUID, x: Double, y: Double, width: Double, height: Double) {
    self.sourceID = sourceID
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    crop.mode = .fill
  }
}
public struct CollageProject: Codable, Sendable, Equatable {
  public static let maximumCells = 10_000
  public var outputFormat: OutputFormat = .png
  public var outputQuality = 0.9
  public var requiresPrivacyReview = false
  public var templateID: String?
  public var silhouette: CollageShape?
  public var silhouetteText = "HELLO"
  public var silhouetteFontName = "HelveticaNeue-Bold"
  public var silhouetteTextLayout = 2
  public var mosaicReferenceID: UUID?
  public var width = 2048
  public var height = 2048
  public var spacing = 0.012
  public var background = RGBAColour(1, 1, 1, 1)
  public var layout: CollageLayout = .magazine
  public var cells: [CollageCell] = []
  public var title = ""
  public var captions: [UUID: String] = [:]
  public var titleColour = RGBAColour(0, 0, 0, 1)
  public var canvas = CanvasStyle()
  public var shadow = false
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case silhouetteFontName, silhouetteTextLayout, outputFormat, outputQuality, requiresPrivacyReview, templateID, silhouette, silhouetteText, mosaicReferenceID, width, height, spacing, background, layout, cells, title, captions, titleColour, canvas,
      shadow
  }
  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    outputFormat = try c.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .png
    outputQuality = try c.decodeIfPresent(Double.self, forKey: .outputQuality) ?? 0.9
    requiresPrivacyReview = try c.decodeIfPresent(Bool.self, forKey: .requiresPrivacyReview) ?? false
    templateID = try c.decodeIfPresent(String.self, forKey: .templateID)
    silhouette = try c.decodeIfPresent(CollageShape.self, forKey: .silhouette)
    silhouetteFontName = try c.decodeIfPresent(String.self, forKey: .silhouetteFontName) ?? "HelveticaNeue-Bold"
    silhouetteTextLayout = try c.decodeIfPresent(Int.self, forKey: .silhouetteTextLayout) ?? 1
    silhouetteText = try c.decodeIfPresent(String.self, forKey: .silhouetteText) ?? silhouetteText
    mosaicReferenceID = try c.decodeIfPresent(UUID.self, forKey: .mosaicReferenceID)
    width = try c.decodeIfPresent(Int.self, forKey: .width) ?? width
    height = try c.decodeIfPresent(Int.self, forKey: .height) ?? height
    spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? spacing
    background = try c.decodeIfPresent(RGBAColour.self, forKey: .background) ?? background
    layout = try c.decodeIfPresent(CollageLayout.self, forKey: .layout) ?? layout
    cells = try c.decodeIfPresent([CollageCell].self, forKey: .cells) ?? cells
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
    captions = try c.decodeIfPresent([UUID: String].self, forKey: .captions) ?? captions
    titleColour = try c.decodeIfPresent(RGBAColour.self, forKey: .titleColour) ?? titleColour
    canvas = try c.decodeIfPresent(CanvasStyle.self, forKey: .canvas) ?? canvas
    shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? shadow
  }
  public mutating func arrange(_ sources: [UUID], layout: CollageLayout) {
    let previous = cells
    self.layout = layout
    templateID = nil; silhouette = nil; mosaicReferenceID = nil
    cells = []
    guard !sources.isEmpty else { return }
    let ids = sources
    let n = ids.count
    if layout == .magazine && n > 1 {
      cells.append(CollageCell(sourceID: ids[0], x: 0, y: 0, width: 0.62, height: 1))
      let columns = n > 5 ? 2 : 1
      let rows = Int(ceil(Double(n - 1) / Double(columns)))
      for i in 1..<n {
        cells.append(
          CollageCell(
            sourceID: ids[i], x: 0.62 + Double((i - 1) % columns) * 0.38 / Double(columns),
            y: Double((i - 1) / columns) / Double(rows), width: 0.38 / Double(columns),
            height: 1 / Double(rows)))
      }
    } else {
      let columns = Int(ceil(sqrt(Double(n))))
      let rows = Int(ceil(Double(n) / Double(columns)))
      for i in 0..<n {
        var cell = CollageCell(
          sourceID: ids[i], x: Double(i % columns) / Double(columns),
          y: Double(i / columns) / Double(rows), width: 1 / Double(columns),
          height: 1 / Double(rows))
        if layout == .freeform {
          cell.x += 0.025
          cell.y += 0.025
          cell.width *= 0.9
          cell.height *= 0.9
          cell.rotation = i % 2 == 0 ? -4 : 4
        }
        cells.append(cell)
      }
    }
    retainCellEdits(from: previous)
  }
  mutating func retainCellEdits(from previous: [CollageCell]) {
    let groups = Dictionary(grouping: previous, by: \.sourceID)
    var positions: [UUID:Int] = [:]
    for i in cells.indices {
      let source = cells[i].sourceID, offset = positions[source, default:0]
      if let group = groups[source], offset < group.count {
        cells[i].id = group[offset].id; cells[i].crop = group[offset].crop; cells[i].shape = group[offset].shape
        positions[source] = offset+1
      }
    }
  }
  public func rect(for cell: CollageCell, output: CGSize) -> CGRect {
    let titleBand = title.isEmpty ? 0.0 : 0.12
    let rect = CGRect(
      x: cell.x * output.width, y: (titleBand + cell.y * (1 - titleBand)) * output.height,
      width: cell.width * output.width, height: cell.height * (1 - titleBand) * output.height)
    return rect.insetBy(
      dx: min(spacing * min(output.width, output.height) / 2, rect.width * 0.3),
      dy: min(spacing * min(output.width, output.height) / 2, rect.height * 0.3))
  }
}
extension ImageProcessor {
  public func renderCollage(
    _ project: CollageProject, sources: [SourceAsset], edits: EditingSnapshot,
    previewMaximum: Int? = nil,
    progress: @Sendable (Int,Int) async -> Void = {_,_ in}
  ) async throws -> CGImage {
    guard project.width > 0, project.height > 0, project.width <= 20000, project.height <= 20000,
      Double(project.width) * Double(project.height) <= 100_000_000, project.spacing.isFinite,
      (0...0.1).contains(project.spacing), project.cells.count <= CollageProject.maximumCells,
      [
        project.background.red, project.background.green, project.background.blue,
        project.background.alpha,
      ].allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else { throw ProcessingError.invalidConfiguration }
    let scale =
      previewMaximum.map { min(1, Double($0) / Double(max(project.width, project.height))) } ?? 1
    guard scale > 0 else { throw ProcessingError.invalidConfiguration }
    let w = max(1, Int(Double(project.width) * scale))
    let h = max(1, Int(Double(project.height) * scale))
    let size = CGSize(width: w, height: h)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ProcessingError.encoding }
    ctx.setFillColor(project.background.cgColor)
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    let sourceLookup = Dictionary(uniqueKeysWithValues: sources.map { ($0.id,$0) })
    var cache: [CollageTileKey:CGImage] = [:], cachedBytes = 0
    var sourceSizes: [UUID:CGSize] = [:]
    if let shape = project.silhouette {
      let path = shape.path(in: CGRect(x:0,y:project.title.isEmpty ? 0 : size.height*0.12,width:size.width,height:project.title.isEmpty ? size.height : size.height*0.88), text:project.silhouetteText, fontName: project.silhouetteFontName, multiline: project.silhouetteTextLayout >= 2)
      guard !path.isEmpty else { throw ProcessingError.invalidConfiguration }
      ctx.saveGState(); ctx.addPath(path); ctx.clip(using: .evenOdd)
    }
    for (cellIndex,cell) in project.cells.enumerated() {
      try Task.checkCancellation()
      try PrivacyRenderer.validate(
        x: cell.x, y: cell.y, width: cell.width, height: cell.height, rotation: cell.rotation)
      guard let source = sourceLookup[cell.sourceID] else {
        throw ProcessingError.invalidImage
      }
      let rect = project.rect(for: cell, output: size)
      guard rect.width > 0, rect.height > 0 else { continue }
      // Sub-pixel preview cells remain visible; final dimensions are validated above.
      var c = edits.configuration(for: source.id)
      c.width = max(1, Int(rect.width))
      c.height = max(1, Int(rect.height))
      c.crop = c.crop.adoptingGeometry(cell.crop)
      c.format = .png
      c.canvasStyle = project.canvas
      if cell.shape != nil && cell.shape != .rectangle { c.canvasStyle.border=0 }
      let key = CollageTileKey(sourceID:source.id, crop:cell.crop, width:c.width, height:c.height, shaped:cell.shape != nil && cell.shape != .rectangle)
      let cg: CGImage
      if let existing = cache[key] { cg = existing }
      else {
        let nominal: CGSize
        if let known=sourceSizes[source.id] {nominal=known} else {nominal=try identify(source.url);sourceSizes[source.id]=nominal}
        let transformed=Self.transformedSize(nominal,configuration:c)
        let geometry=FramingLayout(source:transformed,output:CGSize(width:c.width,height:c.height),configuration:c)
        // Decode enough original pixels for this tile's actual crop/zoom, rather
        // than decoding every full-resolution source or undersampling tight crops.
        let needed=max(nominal.width,nominal.height)*min(1,max(geometry.scaleX,geometry.scaleY))
        let decode=max(32,min(20000,Int(ceil(needed))))
        cg = try autoreleasepool { try render(source.url, configuration:c, previewMaximum:max(c.width,c.height),decodeMaximum:decode) }
        let bytes = cg.bytesPerRow*cg.height
        if cachedBytes+bytes > 16*1024*1024 { cache.removeAll(keepingCapacity:true); cachedBytes=0 }
        if bytes <= 16*1024*1024 { cache[key]=cg; cachedBytes+=bytes }
      }
      ctx.saveGState()
      ctx.translateBy(x: rect.midX, y: rect.midY)
      ctx.rotate(by: cell.rotation * .pi / 180)
      ctx.translateBy(x: -rect.midX, y: -rect.midY)
      if project.shadow {
        ctx.setShadow(
          offset: CGSize(width: 0, height: 3 * scale), blur: 8 * scale,
          color: CGColor(gray: 0, alpha: 0.3))
      }
      if let shape = cell.shape, shape != .rectangle {
        ctx.addPath(shape.path(in:rect,text:project.silhouetteText, fontName: project.silhouetteFontName, multiline: project.silhouetteTextLayout >= 2)); ctx.clip(using:.evenOdd)
      }
      ctx.translateBy(x: rect.minX, y: rect.maxY)
      ctx.scaleBy(x: 1, y: -1)
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
      ctx.restoreGState()
      if let shape=cell.shape, shape != .rectangle, project.canvas.border > 0 {
        ctx.saveGState()
        ctx.translateBy(x:rect.midX,y:rect.midY);ctx.rotate(by:cell.rotation * .pi/180);ctx.translateBy(x:-rect.midX,y:-rect.midY)
        ctx.addPath(shape.path(in:rect,text:project.silhouetteText, fontName: project.silhouetteFontName, multiline: project.silhouetteTextLayout >= 2))
        ctx.setStrokeColor(project.canvas.borderColour.cgColor)
        ctx.setLineWidth(project.canvas.border*min(rect.width,rect.height))
        ctx.strokePath();ctx.restoreGState()
      }
      if cellIndex % 25 == 0 || cellIndex+1 == project.cells.count { await progress(cellIndex+1,project.cells.count) }
    }
    if project.silhouette != nil { ctx.restoreGState() }
    guard let base = ctx.makeImage() else { throw ProcessingError.encoding }
    var annotations: [Annotation] = []
    if !project.title.isEmpty {
      var a = Annotation()
      a.text = project.title
      a.x = 0.06
      a.y = 0.025
      a.width = 0.88
      a.height = 0.065
      a.colour = project.titleColour
      annotations.append(a)
    }
    for cell in project.cells {
      if let caption = project.captions[cell.id], !caption.isEmpty {
        let r = project.rect(for: cell, output: size)
        var a = Annotation()
        a.text = caption
        a.x = r.minX / size.width + 0.01
        a.y = max(0, r.maxY / size.height - 0.045)
        a.width = max(0.01, r.width / size.width - 0.02)
        a.height = 0.035
        a.colour = RGBAColour(1, 1, 1, 1)
        annotations.append(a)
      }
    }
    if annotations.isEmpty { return base }
    let image = try AnnotationRenderer.apply(
      to: CIImage(cgImage: base), annotations: annotations, canvas: CanvasStyle())
    guard
      let output = CIContext(options: [.cacheIntermediates: false]).createCGImage(
        image, from: image.extent)
    else { throw ProcessingError.encoding }
    return output
  }
}


private struct CollageTileKey: Hashable {
  var sourceID: UUID; var crop: CropConfiguration; var width: Int; var height: Int; var shaped: Bool
}

/// Identifies exactly the inputs that can affect one rendered composition.
/// Unrelated library edits do not invalidate an otherwise current output.
public struct CollageRenderIdentity: Equatable, Sendable {
  public var project: CollageProject
  public var sources: [SourceAsset]
  public var configurations: [UUID: ProcessingConfiguration]
  public init(project: CollageProject, sources: [SourceAsset], edits: EditingSnapshot) {
    self.project = project
    let used = Set(project.cells.map(\.sourceID)).union(project.mosaicReferenceID.map { [$0] } ?? [])
    self.sources = sources.filter { used.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
    configurations = Dictionary(uniqueKeysWithValues: self.sources.map { ($0.id, edits.configuration(for: $0.id)) })
  }
}

public enum CollageGeometry {
  public static func moved(_ cell: CollageCell, translation: CGSize, viewport: CGSize, titleBand: Double = 0, snap: Bool = true) -> CollageCell {
    guard viewport.width > 0, viewport.height > 0 else { return cell }
    var value = cell
    value.x = min(max(0, 1 - cell.width), max(0, cell.x + translation.width / viewport.width))
    value.y = min(max(0, 1 - cell.height), max(0, cell.y + translation.height / (viewport.height * max(0.01, 1 - titleBand))))
    if snap {
      for target in [0.0, (1 - cell.width) / 2, 1 - cell.width] where abs(value.x - target) < 0.012 { value.x = target; break }
      for target in [0.0, (1 - cell.height) / 2, 1 - cell.height] where abs(value.y - target) < 0.012 { value.y = target; break }
    }
    return value
  }
  public static func resized(_ cell: CollageCell, handle: OverlayResizeHandle, translation: CGSize, viewport: CGSize) -> CollageCell {
    let changed = OverlayGeometry.resized(OverlayBounds(x: cell.x, y: cell.y, width: cell.width, height: cell.height, rotation: cell.rotation), handle: handle, translation: translation, viewport: viewport)
    var value = cell; value.x = changed.x; value.y = changed.y; value.width = changed.width; value.height = changed.height
    return value
  }
  public static func rotated(_ cell: CollageCell, from: CGPoint, to: CGPoint, viewport: CGSize) -> CollageCell {
    let changed = OverlayGeometry.rotated(OverlayBounds(x: cell.x, y: cell.y, width: cell.width, height: cell.height, rotation: cell.rotation), from: from, to: to, viewport: viewport)
    var value = cell; value.rotation = changed.rotation; return value
  }
}
