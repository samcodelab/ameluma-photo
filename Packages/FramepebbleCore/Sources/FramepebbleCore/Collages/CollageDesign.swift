import CoreGraphics
import CoreText
import Foundation

public enum CollageShape: String, Codable, Sendable, CaseIterable {
  case rectangle = "Rectangle", circle = "Circle", diamond = "Diamond", heart = "Heart"
  case star = "Star", hexagon = "Hexagon", text = "Text"
  /// Top-left coordinates, shared by layout, clipping, hit testing and template previews.
  public func path(in rect: CGRect, text: String = "HELLO") -> CGPath {
    let p = CGMutablePath()
    switch self {
    case .rectangle: p.addRect(rect)
    case .circle: p.addEllipse(in: rect)
    case .diamond:
      p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); p.closeSubpath()
    case .heart:
      p.move(to: CGPoint(x: 0.5, y: 0.95))
      p.addCurve(to: CGPoint(x: 0.05, y: 0.3), control1: CGPoint(x: 0.4, y: 0.8), control2: CGPoint(x: -0.1, y: 0.5))
      p.addCurve(to: CGPoint(x: 0.5, y: 0.22), control1: CGPoint(x: 0.1, y: -0.05), control2: CGPoint(x: 0.4, y: 0.02))
      p.addCurve(to: CGPoint(x: 0.95, y: 0.3), control1: CGPoint(x: 0.6, y: 0.02), control2: CGPoint(x: 0.9, y: -0.05))
      p.addCurve(to: CGPoint(x: 0.5, y: 0.95), control1: CGPoint(x: 1.1, y: 0.5), control2: CGPoint(x: 0.6, y: 0.8))
      p.closeSubpath()
      var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
      return p.copy(using: &transform) ?? p
    case .star, .hexagon:
      let count = self == .star ? 10 : 6
      for i in 0..<count {
        let angle = Double(i) * 2 * .pi / Double(count) - .pi / 2
        let radius = self == .star && i % 2 == 1 ? 0.23 : 0.5
        let point = CGPoint(x: rect.midX + cos(angle) * radius * rect.width, y: rect.midY + sin(angle) * radius * rect.height)
        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
      }
      p.closeSubpath()
    case .text:
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 64 else { return p }
      let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 100, nil)
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
      for item in CTLineGetGlyphRuns(line) as NSArray {
        let run = item as! CTRun
        let attrs = CTRunGetAttributes(run) as NSDictionary
        let runFont = (attrs[kCTFontAttributeName] as! CTFont)
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
        for i in 0..<n {
          if let outline = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
            p.addPath(outline, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
          }
        }
      }
      let b = p.boundingBoxOfPath
      guard !p.isEmpty, b.width > 0, b.height > 0 else { return p }
      let scale = min(rect.width / b.width, rect.height / b.height) * 0.94
      var t = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
        tx: rect.midX - b.midX * scale, ty: rect.midY + b.midY * scale)
      return p.copy(using: &t) ?? p
    }
    return p
  }
}

public struct SavedCollage: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var name: String
  public var project: CollageProject
  public init(name: String, project: CollageProject = CollageProject()) { self.name = name; self.project = project }
}

public enum CollagePattern: String, Codable, Sendable { case grid, rows, columns, featureLeft, featureRight, featureTop, featureBottom, brick, freeform }
public struct CollageTemplate: Identifiable, Sendable {
  public var id: String
  public var name: String
  public var category: String
  public var pattern: CollagePattern
  public var divisions: Int
  public var fraction: Double
  public var aspect: Double
  public static let catalog: [CollageTemplate] = {
    let aspects = [("Square", 1.0), ("Landscape", 1.5), ("Portrait", 2.0 / 3)]
    var result: [CollageTemplate] = []
    for (label, aspect) in aspects {
      for columns in 1...8 {
        result.append(Self(id: "grid-\(label)-\(columns)", name: "\(columns)-Column \(label)", category: "Grids", pattern: .grid, divisions: columns, fraction: 0.5, aspect: aspect))
      }
      for (pattern, label2) in [(CollagePattern.featureLeft,"Left"),(.featureRight,"Right"),(.featureTop,"Top"),(.featureBottom,"Bottom")] {
        for fraction in [0.45, 0.6, 0.72] {
          result.append(Self(id: "hero-\(label)-\(label2)-\(fraction)", name: "\(label) · \(label2) \(Int(fraction*100))", category: "Editorial", pattern: pattern, divisions: 2, fraction: fraction, aspect: aspect))
        }
      }
      result.append(Self(id: "brick-\(label)", name: "\(label) Brickwork", category: "Mosaics", pattern: .brick, divisions: 3, fraction: 0.5, aspect: aspect))
      result.append(Self(id: "free-\(label)", name: "\(label) Pinboard", category: "Freeform", pattern: .freeform, divisions: 3, fraction: 0.5, aspect: aspect))
    }
    for divisions in 1...4 {
      for pattern in [CollagePattern.rows, .columns] {
        result.append(Self(id: "strip-\(pattern.rawValue)-\(divisions)", name: "\(divisions) \(pattern == .rows ? "Rows" : "Strips")", category: "Strips", pattern: pattern, divisions: divisions, fraction: 0.5, aspect: 1.5))
      }
    }
    return result
  }()
  public func apply(to project: inout CollageProject, sources: [UUID]) {
    project.templateID = id
    project.silhouette = nil
    project.mosaicReferenceID = nil
    project.layout = pattern == .freeform ? .freeform : pattern == .grid ? .grid : .magazine
    project.width = 2400; project.height = Int((2400 / aspect).rounded())
    let old = project.cells
    let n = sources.count
    guard n > 0, n <= CollageProject.maximumCells else { project.cells = []; return }
    var cells: [CollageCell] = []
    func grid(_ ids: ArraySlice<UUID>, in box: CGRect, columns: Int, brick: Bool = false) {
      guard !ids.isEmpty else { return }
      let columns = max(1, min(columns, ids.count)), rows = Int(ceil(Double(ids.count) / Double(columns)))
      let list = Array(ids)
      for row in 0..<rows {
        let count = min(columns, list.count - row * columns)
        for col in 0..<count {
          let offset = brick && row % 2 == 1 ? 0.06 : 0.0
          cells.append(CollageCell(sourceID: list[row * columns + col], x: box.minX + (Double(col) + offset) * box.width / Double(count), y: box.minY + Double(row) * box.height / Double(rows), width: box.width / Double(count) * (1 - offset), height: box.height / Double(rows)))
        }
      }
    }
    let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    if [.featureLeft, .featureRight, .featureTop, .featureBottom].contains(pattern), n > 1 {
      let horizontal = pattern == .featureLeft || pattern == .featureRight
      let reverse = pattern == .featureRight || pattern == .featureBottom
      let hero = horizontal ? CGRect(x: reverse ? 1-fraction : 0, y: 0, width: fraction, height: 1) : CGRect(x: 0, y: reverse ? 1-fraction : 0, width: 1, height: fraction)
      let rest = horizontal ? CGRect(x: reverse ? 0 : fraction, y: 0, width: 1-fraction, height: 1) : CGRect(x: 0, y: reverse ? 0 : fraction, width: 1, height: 1-fraction)
      cells.append(CollageCell(sourceID: sources[0], x: hero.minX, y: hero.minY, width: hero.width, height: hero.height))
      grid(sources.dropFirst(), in: rest, columns: horizontal ? (n > 8 ? 2 : 1) : min(n-1, 3))
    } else {
      let cols = pattern == .rows ? Int(ceil(Double(n)/Double(divisions))) : divisions
      grid(sources[...], in: whole, columns: cols, brick: pattern == .brick)
      if pattern == .freeform {
        for i in cells.indices { cells[i].x += 0.01; cells[i].y += 0.01; cells[i].width *= 0.94; cells[i].height *= 0.94; cells[i].rotation = i % 2 == 0 ? -3 : 3 }
      }
    }
    project.cells = cells
    project.retainCellEdits(from: old)
  }
}
