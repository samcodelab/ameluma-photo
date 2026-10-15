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
    case width, height, spacing, background, layout, cells, title, captions, titleColour, canvas,
      shadow
  }
  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
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
    cells = []
    guard !sources.isEmpty else { return }
    let ids = Array(sources.prefix(24))
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
    var used: Set<UUID> = []
    for i in cells.indices {
      if let existing = previous.first(where: {
        $0.sourceID == cells[i].sourceID && !used.contains($0.id)
      }) {
        cells[i].id = existing.id
        cells[i].crop = existing.crop
        used.insert(existing.id)
      }
    }
  }
  public func rect(for cell: CollageCell, output: CGSize) -> CGRect {
    let titleBand = title.isEmpty ? 0.0 : 0.12
    let rect = CGRect(
      x: cell.x * output.width, y: (titleBand + cell.y * (1 - titleBand)) * output.height,
      width: cell.width * output.width, height: cell.height * (1 - titleBand) * output.height)
    return rect.insetBy(
      dx: spacing * min(output.width, output.height) / 2,
      dy: spacing * min(output.width, output.height) / 2)
  }
}
extension ImageProcessor {
  public func renderCollage(
    _ project: CollageProject, sources: [SourceAsset], edits: EditingSnapshot,
    previewMaximum: Int? = nil
  ) throws -> CGImage {
    guard project.width > 0, project.height > 0, project.width <= 20000, project.height <= 20000,
      Double(project.width) * Double(project.height) <= 100_000_000, project.spacing.isFinite,
      (0...0.1).contains(project.spacing), project.cells.count <= 24,
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
    for cell in project.cells {
      try Task.checkCancellation()
      try PrivacyRenderer.validate(
        x: cell.x, y: cell.y, width: cell.width, height: cell.height, rotation: cell.rotation)
      guard let source = sources.first(where: { $0.id == cell.sourceID }) else {
        throw ProcessingError.invalidImage
      }
      let rect = project.rect(for: cell, output: size)
      guard rect.width >= 1, rect.height >= 1 else { throw ProcessingError.invalidConfiguration }
      var c = edits.configuration(for: source.id)
      c.width = max(1, Int(rect.width))
      c.height = max(1, Int(rect.height))
      c.crop = c.crop.adoptingGeometry(cell.crop)
      c.format = .png
      c.canvasStyle = project.canvas
      let cg = try render(source.url, configuration: c, previewMaximum: previewMaximum)
      ctx.saveGState()
      ctx.translateBy(x: rect.midX, y: rect.midY)
      ctx.rotate(by: cell.rotation * .pi / 180)
      ctx.translateBy(x: -rect.midX, y: -rect.midY)
      if project.shadow {
        ctx.setShadow(
          offset: CGSize(width: 0, height: 3 * scale), blur: 8 * scale,
          color: CGColor(gray: 0, alpha: 0.3))
      }
      ctx.translateBy(x: rect.minX, y: rect.maxY)
      ctx.scaleBy(x: 1, y: -1)
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
      ctx.restoreGState()
    }
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
