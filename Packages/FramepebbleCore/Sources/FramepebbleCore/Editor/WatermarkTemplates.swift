import Foundation

/// Original, code-authored starting points using the ordinary editable layer model.
/// Application placement and opacity belong to WatermarkConfiguration, not the design.
public struct WatermarkTemplate: Identifiable, Sendable {
  public var id: String
  public var name: String
  public var category: String
  public var document: EditorDocument
}
public enum WatermarkTemplates {
  public static let all: [WatermarkTemplate] = {
    let recipes: [(String,String,String,String,String)] = [
      ("signature", "Quiet Signature", "Minimal", "Your Name", "PHOTOGRAPHY"),
      ("editorial", "Editorial", "Typography", "YOUR NAME", "PHOTOGRAPHER · EST. 2026"),
      ("studio", "Studio Line", "Studio", "YOUR STUDIO", "PHOTOGRAPHY & DESIGN"),
      ("copyright", "Copyright", "Copyright", "© Your Name", "ALL RIGHTS RESERVED"),
      ("monogram", "Initials", "Monogram", "YN", "YOUR NAME"),
      ("social", "Social Signature", "Social", "@yourname", "PHOTOGRAPHY"),
      ("frame", "Fine Frame", "Elegant", "Your Name", "FINE ART PHOTOGRAPHY"),
      ("stamp", "Studio Stamp", "Studio", "YOUR STUDIO", "ORIGINAL PHOTOGRAPH"),
      ("serif", "Serif Signature", "Elegant", "Your Name", "CAPTURED WITH CARE"),
      ("modern", "Modern Mark", "Typography", "YOUR NAME", "PHOTO / FILM"),
      ("protection", "Protection", "Protection", "© YOUR NAME", "PREVIEW · NOT FOR DISTRIBUTION"),
      ("logo", "Logo & Name", "Logo", "YOUR STUDIO", "PLACE YOUR LOGO ABOVE")
    ]
    return recipes.map { id,name,category,title,subtitle in
      var doc = EditorDocument(); doc.name = name; doc.width = 1200; doc.height = 420
      doc.watermarkDesign = true; doc.version = 2
      let white = RGBAColour(1,1,1,1)
      var text = EditorText(); text.text = title; text.colour = white; text.alignment = .centre
      text.fontSize = id == "monogram" ? 145 : 100
      text.fontName = ["signature","serif","frame"].contains(id) ? "Baskerville" : "HelveticaNeue"
      text.italic = id == "signature"; text.bold = ["studio","modern","stamp"].contains(id)
      var heading = EditorLayer(name: "Name", content: .text(text))
      heading.x = 60; heading.y = 85; heading.width = 1080; heading.height = 190
      var detail = EditorText(); detail.text = subtitle; detail.fontSize = 28
      detail.colour = white; detail.alignment = .centre
      var caption = EditorLayer(name: "Tagline", content: .text(detail))
      caption.x = 60; caption.y = 290; caption.width = 1080; caption.height = 65
      doc.layers = [heading, caption]
      if ["studio","frame","stamp","modern"].contains(id) {
        var shape = EditorShape(); shape.fill = nil; shape.stroke = white
        shape.kind = id == "frame" || id == "stamp" ? .rectangle : .line
        shape.strokeWidth = 3
        var decoration = EditorLayer(name: "Rule / Frame", content: .shape(shape))
        decoration.x = 25; decoration.y = shape.kind == .line ? 265 : 25
        decoration.width = 1150; decoration.height = shape.kind == .line ? 1 : 370
        doc.layers.insert(decoration, at: 0)
      }
      if id == "logo" {
        var shape = EditorShape(); shape.kind = .ellipse; shape.fill = nil; shape.stroke = white; shape.strokeWidth = 4
        var placeholder = EditorLayer(name: "Replace with your logo", content: .shape(shape))
        placeholder.x = 550; placeholder.y = 12; placeholder.width = 100; placeholder.height = 100
        doc.layers.insert(placeholder, at: 0)
        doc.layers[1].y = 125
      }
      // Distinct silhouettes, not merely new names on the same two-line layout.
      if id == "signature" || id == "copyright" || id == "social" {
        doc.height = 260
        doc.layers[0].y = 20; doc.layers[0].height = 150
        doc.layers[1].y = 185; doc.layers[1].height = 55
      }
      if id == "monogram" {
        doc.width = 600; doc.height = 600
        var ring = EditorShape(); ring.kind = .ellipse; ring.fill = nil; ring.stroke = white; ring.strokeWidth = 4
        var border = EditorLayer(name: "Monogram Ring", content: .shape(ring))
        border.x = 45; border.y = 30; border.width = 510; border.height = 510
        var initials = heading; initials.x = 60; initials.y = 175; initials.width = 480; initials.height = 220
        if case .text(var value) = initials.content { value.fontSize = 160; value.fontName = "Baskerville"; initials.content = .text(value) }
        var name = caption; name.x = 70; name.y = 425; name.width = 460; name.height = 60
        doc.layers = [border, initials, name]
      }
      if id == "modern" {
        doc.layers = [heading, caption]
        doc.layers[0].x = 130; doc.layers[0].width = 1010
        doc.layers[1].x = 130; doc.layers[1].width = 1010
        for index in doc.layers.indices {
          if case .text(var value) = doc.layers[index].content { value.alignment = .leading; doc.layers[index].content = .text(value) }
        }
        var bar = EditorShape(); bar.fill = white; bar.strokeWidth = 0
        var accent = EditorLayer(name: "Vertical Accent", content: .shape(bar))
        accent.x = 55; accent.y = 85; accent.width = 12; accent.height = 260
        doc.layers.insert(accent, at: 0)
      }
      if id == "stamp" {
        doc.width = 900; doc.height = 600
        doc.layers[0].width = 850; doc.layers[0].height = 550
        doc.layers[1].x = 60; doc.layers[1].y = 190; doc.layers[1].width = 780
        if case .text(var value) = doc.layers[1].content { value.fontSize = 90; doc.layers[1].content = .text(value) }
        doc.layers[2].x = 60; doc.layers[2].y = 395; doc.layers[2].width = 780
      }
      if id == "protection" {
        doc.layers[0].rotation = -12; doc.layers[0].opacity = 0.85
        doc.layers[1].rotation = -12; doc.layers[1].opacity = 0.85
      }
      return WatermarkTemplate(id: id, name: name, category: category, document: doc)
    }
  }()
}
