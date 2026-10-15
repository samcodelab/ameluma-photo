import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Original code-native pebble mark. No third-party artwork or downloaded asset.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let folder = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func draw(_ pixels: Int, name: String, transparent: Bool) throws {
    let size = CGFloat(pixels)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: (transparent ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue) else { throw CocoaError(.coderInvalidValue) }
    if !transparent { ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
    let inset = transparent ? size * 0.08 : size * 0.16
    ctx.addEllipse(in: CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)); ctx.clip()
    let colours = [CGColor(red: 0.76, green: 0.69, blue: 1, alpha: 1), CGColor(red: 0.19, green: 0.39, blue: 0.97, alpha: 1), CGColor(red: 0.11, green: 0.06, blue: 0.63, alpha: 1)]
    guard let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: [0, 0.5, 1]) else { throw CocoaError(.coderInvalidValue) }
    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: size * 0.32, y: size * 0.8), startRadius: 0, endCenter: CGPoint(x: size * 0.57, y: size * 0.37), endRadius: size * 0.62, options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    guard let image = ctx.makeImage(), let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.coderInvalidValue) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}
var images: [[String: String]] = []
for logical in [16,32,128,256,512] { for scale in [1,2] { let name = "mac-\(logical)-\(scale)x.png"; try draw(logical * scale, name: name, transparent: true); images.append(["idiom":"mac","size":"\(logical)x\(logical)","scale":"\(scale)x","filename":name]) } }
try draw(1024, name: "ios-1024.png", transparent: false)
images.append(["idiom":"universal","platform":"ios","size":"1024x1024","filename":"ios-1024.png"])
let content: [String: Any] = ["images":images,"info":["author":"xcode","version":1]]
try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted,.sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"))
