import CoreGraphics
import CoreText
import Foundation

public struct Sticker: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let collection: String
  public let design: String
  public let variant: Int
  public var aspectRatio: Double { design == "greeting" ? 2.4 : ["glasses", "hearts", "moustache", "bow"].contains(design) ? 2 : 1 }
}
/// Original vector recipes, versioned IDs. No emoji, external packs or network assets.
public enum StickerCatalog {
  public static let collections = ["Dress Up", "Celebrate", "Decorate"]
  public static let stickers: [Sticker] = {
    let accessories = [("partyHat","Party Hat"),("topHat","Top Hat"),("crown","Crown"),("beanie","Beanie"),("sunHat","Sun Hat"),("cap","Cap"),("glasses","Round Glasses"),("glasses","Cool Shades"),("hearts","Heart Glasses"),("moustache","Curly Moustache"),("moustache","Dapper Moustache"),("bow","Bow Tie")]
    var result = accessories.enumerated().map { Sticker(id: "v1.dress.\($0.offset)", name: $0.element.1, collection: collections[0], design: $0.element.0, variant: $0.offset % 4) }
    let greetings = ["Happy Birthday!", "Congratulations!", "Party Time!", "You Did It!", "Make a Wish", "Let’s Celebrate", "Best Day Ever", "Cheers!", "Thank You!", "Hello Sunshine", "Good Vibes", "Love This!", "Hip Hip Hooray", "Birthday Star", "So Proud of You", "Happy Together", "Just Married", "Big Smiles", "Well Done!", "You’re Amazing", "Let’s Dance", "Adventure Time", "Celebrate You", "Made with Love"]
    result += greetings.enumerated().map { Sticker(id: "v1.celebrate.\($0.offset)", name: $0.element, collection: collections[1], design: "greeting", variant: $0.offset % 4) }
    for (index, design) in ["heart", "star", "balloon", "confetti", "ribbon", "sparkles"].enumerated() {
      for variant in 0..<4 { result.append(Sticker(id: "v1.decorate.\(index).\(variant)", name: ["Coral", "Blue", "Violet", "Gold"][variant] + " " + design.capitalized, collection: collections[2], design: design, variant: variant)) }
    }
    return result
  }()
  public static func sticker(_ id: String) -> Sticker? { stickers.first { $0.id == id } }
}
public enum StickerError: Error, LocalizedError {
  case unavailable
  public var errorDescription: String? { "A sticker is unavailable. Remove it or choose a supported sticker before exporting." }
}
public enum StickerRenderer {
  public static func draw(_ sticker: Sticker, in rect: CGRect, context c: CGContext) {
    c.saveGState(); defer { c.restoreGState() }
    let size = CGSize(width: 100, height: 100 / sticker.aspectRatio)
    c.translateBy(x: rect.minX, y: rect.minY); c.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
    let palette: [CGColor] = [CGColor(red: 0.96, green: 0.28, blue: 0.35, alpha: 1), CGColor(red: 0.12, green: 0.48, blue: 0.95, alpha: 1), CGColor(red: 0.58, green: 0.30, blue: 0.85, alpha: 1), CGColor(red: 1, green: 0.72, blue: 0.15, alpha: 1)]
    let ink = CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1), colour = palette[sticker.variant % 4]
    c.setFillColor(colour); c.setStrokeColor(ink); c.setLineWidth(3); c.setLineJoin(.round); c.setLineCap(.round)
    func polygon(_ points: [CGPoint], fill: Bool = true) {
      guard let first = points.first else { return }; c.beginPath(); c.move(to: first)
      for p in points.dropFirst() { c.addLine(to: p) }; c.closePath(); c.drawPath(using: fill ? .fillStroke : .stroke)
    }
    func heart(_ r: CGRect) {
      let p = CGMutablePath(); p.move(to: CGPoint(x: r.midX, y: r.maxY))
      p.addCurve(to: CGPoint(x:r.minX,y:r.minY+r.height*0.3), control1: CGPoint(x:r.minX,y:r.midY+r.height*0.1), control2:CGPoint(x:r.minX-r.width*0.1,y:r.midY))
      p.addCurve(to:CGPoint(x:r.midX,y:r.minY+r.height*0.18),control1:CGPoint(x:r.minX,y:r.minY-r.height*0.1),control2:CGPoint(x:r.midX,y:r.minY-r.height*0.1))
      p.addCurve(to:CGPoint(x:r.maxX,y:r.minY+r.height*0.3),control1:CGPoint(x:r.midX,y:r.minY-r.height*0.1),control2:CGPoint(x:r.maxX,y:r.minY-r.height*0.1))
      p.addCurve(to:CGPoint(x:r.midX,y:r.maxY),control1:CGPoint(x:r.maxX+r.width*0.1,y:r.midY),control2:CGPoint(x:r.maxX,y:r.midY+r.height*0.1));p.closeSubpath();c.addPath(p);c.drawPath(using:.fillStroke)
    }
    switch sticker.design {
    case "greeting":
      let r = CGRect(x: 2, y: 2, width: 96, height: size.height-4)
      c.addPath(CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil)); c.drawPath(using: .fillStroke)
      let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 18, nil)
      let text = NSAttributedString(string: sticker.name, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink])
      let line = CTLineCreateWithAttributedString(text); let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
      let scale = min(1, 84 / max(1,bounds.width), (size.height-14) / max(1,bounds.height))
      c.translateBy(x: 50-bounds.width*scale/2, y: size.height/2+bounds.height*scale/2); c.scaleBy(x:scale,y:-scale);c.textPosition=CGPoint(x:-bounds.minX,y:-bounds.minY);CTLineDraw(line,c)
    case "glasses", "hearts":
      if sticker.design == "hearts" { heart(CGRect(x:5,y:6,width:38,height:36));heart(CGRect(x:57,y:6,width:38,height:36)) }
      else {
        for x in [CGFloat(6),57] { c.addPath(CGPath(roundedRect: CGRect(x:x,y:6,width:37,height:34),cornerWidth:14,cornerHeight:14,transform:nil)); c.drawPath(using: sticker.variant == 3 ? .fillStroke : .stroke) }
      }
      c.move(to:CGPoint(x:43,y:20));c.addQuadCurve(to:CGPoint(x:57,y:20),control:CGPoint(x:50,y:12));c.strokePath()
      c.move(to:CGPoint(x:0,y:12));c.addLine(to:CGPoint(x:6,y:17));c.move(to:CGPoint(x:94,y:17));c.addLine(to:CGPoint(x:100,y:12));c.strokePath()
    case "moustache":
      c.setFillColor(ink)
      if sticker.variant == 2 {
        polygon([CGPoint(x:4,y:30),CGPoint(x:39,y:13),CGPoint(x:50,y:22),CGPoint(x:61,y:13),CGPoint(x:96,y:30),CGPoint(x:62,y:36),CGPoint(x:50,y:29),CGPoint(x:38,y:36)]);break
      }
      let p=CGMutablePath();p.move(to:CGPoint(x:50,y:20))
      p.addCurve(to:CGPoint(x:4,y:16),control1:CGPoint(x:23,y:-6),control2:CGPoint(x:20,y:47));p.addCurve(to:CGPoint(x:50,y:32),control1:CGPoint(x:4,y:48),control2:CGPoint(x:32,y:46))
      p.addCurve(to:CGPoint(x:96,y:16),control1:CGPoint(x:68,y:46),control2:CGPoint(x:96,y:48));p.addCurve(to:CGPoint(x:50,y:20),control1:CGPoint(x:80,y:47),control2:CGPoint(x:77,y:-6));p.closeSubpath();c.addPath(p);c.fillPath()
    case "bow": polygon([CGPoint(x:5,y:4),CGPoint(x:48,y:20),CGPoint(x:95,y:4),CGPoint(x:95,y:46),CGPoint(x:52,y:30),CGPoint(x:5,y:46)]);c.fillEllipse(in:CGRect(x:42,y:15,width:16,height:20))
    case "partyHat":
      polygon([CGPoint(x:50,y:5),CGPoint(x:12,y:88),CGPoint(x:88,y:88)])
      c.setFillColor(palette[(sticker.variant+2)%4]);for (x,y) in [(35,55),(55,70),(47,34)] { c.fillEllipse(in:CGRect(x:x,y:y,width:11,height:11)) };c.fillEllipse(in:CGRect(x:43,y:0,width:14,height:14))
    case "crown": polygon([CGPoint(x:12,y:25),CGPoint(x:32,y:47),CGPoint(x:50,y:10),CGPoint(x:68,y:47),CGPoint(x:88,y:25),CGPoint(x:80,y:85),CGPoint(x:20,y:85)]);c.setFillColor(palette[(sticker.variant+1)%4]);c.fillEllipse(in:CGRect(x:43,y:56,width:14,height:14))
    case "topHat", "sunHat":
      c.addPath(CGPath(roundedRect:CGRect(x:22,y:sticker.design == "sunHat" ? 28 : 8,width:56,height:sticker.design == "sunHat" ? 44 : 65),cornerWidth:10,cornerHeight:10,transform:nil));c.drawPath(using:.fillStroke)
      c.fillEllipse(in:CGRect(x:3,y:65,width:94,height:22));c.setStrokeColor(palette[(sticker.variant+1)%4]);c.setLineWidth(10);c.move(to:CGPoint(x:23,y:58));c.addLine(to:CGPoint(x:77,y:58));c.strokePath()
    case "beanie", "cap":
      c.fillEllipse(in:CGRect(x:17,y:15,width:66,height:65));c.addPath(CGPath(roundedRect:CGRect(x:14,y:59,width:sticker.design == "cap" ? 82 : 72,height:20),cornerWidth:6,cornerHeight:6,transform:nil));c.drawPath(using:.fillStroke)
      if sticker.design == "beanie" { c.fillEllipse(in:CGRect(x:40,y:4,width:20,height:20)) }
    case "heart": heart(CGRect(x:10,y:12,width:80,height:76))
    case "star", "sparkles":
      let n = sticker.design == "star" ? 5 : 4
      polygon((0..<(n*2)).map { i in let angle=CGFloat(i)*CGFloat.pi/CGFloat(n)-CGFloat.pi/2;let r:CGFloat=i%2==0 ? 44 : 18;return CGPoint(x:50+cos(angle)*r,y:50+sin(angle)*r) })
    case "balloon":
      c.fillEllipse(in:CGRect(x:22,y:4,width:56,height:64));polygon([CGPoint(x:50,y:64),CGPoint(x:44,y:74),CGPoint(x:56,y:74)])
      c.move(to:CGPoint(x:50,y:74));c.addCurve(to:CGPoint(x:45,y:98),control1:CGPoint(x:65,y:83),control2:CGPoint(x:34,y:87));c.strokePath()
    case "ribbon": polygon([CGPoint(x:14,y:18),CGPoint(x:86,y:18),CGPoint(x:86,y:80),CGPoint(x:50,y:64),CGPoint(x:14,y:80)])
    default:
      for i in 0..<15 { c.setFillColor(palette[(i+sticker.variant)%4]);c.saveGState();c.translateBy(x:CGFloat((i*37)%84+8),y:CGFloat((i*23)%84+8));c.rotate(by:CGFloat(i)*0.8);c.fill(CGRect(x:-3,y:-6,width:6,height:12));c.restoreGState() }
    }
  }
}
