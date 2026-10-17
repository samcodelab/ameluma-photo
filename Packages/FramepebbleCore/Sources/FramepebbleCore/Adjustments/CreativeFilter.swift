import CoreImage
import Foundation

public struct FilterEdit: Codable, Equatable, Sendable {
  public var presetID: String?
  public var recipeVersion: Int = 1
  public var intensity: Double = 0.7
  public var grainSeed: UInt32
  public init(presetID: String? = nil, intensity: Double = 0.7, grainSeed: UInt32 = 0) {
    self.presetID = presetID; self.intensity = intensity; self.grainSeed = grainSeed
  }
}
public enum FilterCollection: String, Codable, CaseIterable, Sendable {
  case essentials = "Essentials", film = "Film", cinema = "Cinema", monochrome = "Monochrome"
}
public struct CreativePreset: Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let description: String
  public let collection: FilterCollection
  public var exposure: Double = 0
  public var saturation: Double = 1
  public var contrast: Double = 1
  public var tint: [Double] = [0,0,0]
  public var curve: String? = nil
  public var vignette: Double = 0
  public var grain: Double = 0
  public var bloom: Double = 0
  public var monochrome: [Double]? = nil
  public var split: String? = nil
}
/// Frozen recipe version 1. Never edit these recipes to revise already-saved work.
public enum FilterCatalog {
  public static let version = 1
  public static let presets: [CreativePreset] = [
    .init(id:"essentials.clean",name:"Clean",description:"Subtle everyday polish",collection:.essentials,saturation:1.03,contrast:1.03),
    .init(id:"essentials.vivid",name:"Vivid",description:"Richer color and separation",collection:.essentials,saturation:1.18,contrast:1.08,curve:"Gentle"),
    .init(id:"essentials.soft",name:"Soft",description:"Gentle contrast and glow",collection:.essentials,saturation:0.94,contrast:0.96,curve:"Lift",bloom:0.08),
    .init(id:"essentials.warm",name:"Warm",description:"Warm daylight",collection:.essentials,saturation:1.02,tint:[0.022,0.007,-0.018]),
    .init(id:"essentials.cool",name:"Cool",description:"Clean, cool light",collection:.essentials,saturation:0.98,tint:[-0.016,0.003,0.022]),
    .init(id:"essentials.crisp",name:"Crisp",description:"Stronger tonal definition",collection:.essentials,saturation:1.04,contrast:1.14,curve:"Gentle"),
    .init(id:"film.faded",name:"Faded",description:"Lifted blacks and subdued color",collection:.film,saturation:0.86,contrast:0.97,curve:"Fade",grain:0.012),
    .init(id:"film.amber",name:"Amber",description:"Warm nostalgic color",collection:.film,saturation:0.94,tint:[0.035,0.012,-0.025],curve:"Gentle",grain:0.010),
    .init(id:"film.daylight",name:"Daylight",description:"Bright everyday film character",collection:.film,saturation:1.08,tint:[0.010,0.004,-0.008],curve:"Gentle",grain:0.008),
    .init(id:"film.dusty",name:"Dusty",description:"Muted earth tones",collection:.film,saturation:0.78,tint:[0.018,0.008,-0.012],curve:"Fade",grain:0.016),
    .init(id:"film.cool_print",name:"Cool Print",description:"Cool shadows and soft contrast",collection:.film,saturation:0.90,tint:[-0.012,0.004,0.020],curve:"Lift",grain:0.012),
    .init(id:"film.evening",name:"Evening",description:"Warm, quieter evenings",collection:.film,exposure:-0.10,saturation:0.92,tint:[0.025,0.002,-0.016],curve:"Gentle",vignette:0.18,grain:0.010),
    .init(id:"cinema.warm_frame",name:"Warm Frame",description:"Warm highlights, cool shadows",collection:.cinema,saturation:0.94,curve:"Cinema",vignette:0.12,split:"Warm"),
    .init(id:"cinema.cool_frame",name:"Cool Frame",description:"Cool atmosphere",collection:.cinema,saturation:0.88,curve:"Cinema",vignette:0.12,split:"Cool"),
    .init(id:"cinema.teal_amber",name:"Teal & Amber",description:"Stylized color separation",collection:.cinema,saturation:0.94,curve:"Cinema",split:"TealAmber"),
    .init(id:"cinema.moody",name:"Moody",description:"Darker, subdued color",collection:.cinema,exposure:-0.15,saturation:0.78,contrast:1.06,curve:"Cinema",vignette:0.22,split:"Cool"),
    .init(id:"cinema.nightfall",name:"Nightfall",description:"Cool evening mood",collection:.cinema,exposure:-0.20,saturation:0.82,tint:[-0.012,-0.002,0.020],curve:"Gentle",vignette:0.20),
    .init(id:"cinema.dramatic",name:"Dramatic",description:"Strong contrast and edge falloff",collection:.cinema,saturation:0.90,contrast:1.16,curve:"Cinema",vignette:0.24),
    .init(id:"mono.classic",name:"Classic",description:"Balanced neutral monochrome",collection:.monochrome,curve:"Gentle",monochrome:[0.2126,0.7152,0.0722]),
    .init(id:"mono.bold",name:"Bold",description:"Bold monochrome separation",collection:.monochrome,contrast:1.18,curve:"Cinema",monochrome:[0.25,0.65,0.10]),
    .init(id:"mono.soft",name:"Soft Mono",description:"Soft, lifted monochrome",collection:.monochrome,contrast:0.95,curve:"Lift",monochrome:[0.25,0.65,0.10]),
    .init(id:"mono.silver",name:"Silver",description:"Neutral silver tones and fine grain",collection:.monochrome,curve:"Gentle",grain:0.012,monochrome:[0.30,0.60,0.10]),
    .init(id:"mono.noir",name:"Noir",description:"Deep monochrome with edge falloff",collection:.monochrome,exposure:-0.10,contrast:1.20,curve:"Cinema",vignette:0.25,grain:0.010,monochrome:[0.20,0.65,0.15]),
    .init(id:"mono.warm_paper",name:"Warm Paper",description:"Warm tinted paper and lifted blacks",collection:.monochrome,tint:[0.018,0.009,-0.012],curve:"Fade",grain:0.010,monochrome:[0.30,0.59,0.11])
  ]
  public static func preset(_ id: String, version: Int) -> CreativePreset? { version == 1 ? presets.first { $0.id == id } : nil }
}
public enum CreativeFilterError: Error, LocalizedError {
  case unavailable, kernel, hdr
  public var errorDescription: String? {
    switch self {
    case .unavailable: "Filter unavailable. Select Original or a supported filter before exporting."
    case .kernel: "The local filter kernel could not be loaded. Retry or choose Original."
    case .hdr: "Creative filters require an SDR source. HDR development is not available yet."
    }
  }
}
public enum CreativeFilterRenderer {
  private static let kernels: Result<[CIKernel], Error> = Result {
    guard let url = Bundle.module.url(forResource: "CreativeFilters.metal", withExtension: "txt") else { throw CreativeFilterError.kernel }
    return try CIKernel.kernels(withMetalString: String(contentsOf: url, encoding: .utf8))
  }
  private static func kernel(_ name: String) throws -> CIColorKernel {
    guard let result = try kernels.get().first(where: { $0.name == name }) as? CIColorKernel else { throw CreativeFilterError.kernel }
    return result
  }
  public static func apply(_ edit: FilterEdit?, to source: CIImage, fullSize: CGSize) throws -> CIImage {
    guard let edit else { return source }
    let origin = source.extent.origin
    let input = source.transformed(by:CGAffineTransform(translationX:-origin.x,y:-origin.y))
    guard edit.intensity.isFinite, (0...1).contains(edit.intensity) else { throw ProcessingError.invalidConfiguration }
    guard let id = edit.presetID else { return source }
    guard let p = FilterCatalog.preset(id, version: edit.recipeVersion) else { throw CreativeFilterError.unavailable }
    guard edit.intensity > 0 else { return source }
    try Task.checkCancellation()
    var image = input
    func node(_ name: String, _ values: [String: Any]) throws {
      var values = values; values[kCIInputImageKey] = image
      guard let result = CIFilter(name: name, parameters: values)?.outputImage else { throw ProcessingError.invalidConfiguration }
      image = result.cropped(to: input.extent)
    }
    if p.exposure != 0 { try node("CIExposureAdjust", [kCIInputEVKey:p.exposure]) }
    if let m = p.monochrome { let v = CIVector(x:m[0],y:m[1],z:m[2],w:0); try node("CIColorMatrix", ["inputRVector":v,"inputGVector":v,"inputBVector":v]) }
    try node("CIColorControls", [kCIInputSaturationKey:p.saturation,kCIInputContrastKey:p.contrast,kCIInputBrightnessKey:0])
    if let curve = p.curve {
      let curves: [String:[Double]] = ["Gentle":[0,0.23,0.51,0.79,1],"Lift":[0.025,0.27,0.52,0.77,0.985],"Fade":[0.055,0.28,0.51,0.75,0.965],"Cinema":[0.008,0.20,0.49,0.79,0.985]]
      guard let ys = curves[curve] else { throw CreativeFilterError.unavailable }
      try node("CIToneCurve", Dictionary(uniqueKeysWithValues: ys.enumerated().map { ("inputPoint\($0.offset)", CIVector(x:Double($0.offset)/4,y:$0.element)) }))
    }
    let splits: [String:([Double],[Double])] = ["Warm":([-0.012,0.003,0.018],[0.024,0.010,-0.014]),"Cool":([-0.018,0.004,0.025],[0.006,0.003,0.010]),"TealAmber":([-0.025,0.018,0.022],[0.030,0.010,-0.022])]
    let split = p.split.flatMap { splits[$0] } ?? ([0,0,0],[0,0,0])
    func vector(_ v: [Double]) -> CIVector { CIVector(x:v[0],y:v[1],z:v[2]) }
    guard let biased = try kernel("creativeBias").apply(extent: input.extent, arguments:[image,vector(p.tint),vector(split.0),vector(split.1)]) else { throw CreativeFilterError.kernel }
    image = biased
    let scale = input.extent.width / max(1,fullSize.width)
    let side = min(fullSize.width,fullSize.height)*scale
    if p.bloom > 0 {
      image = image.clampedToExtent()
      try node("CIBloom", [kCIInputRadiusKey:side*0.006,kCIInputIntensityKey:p.bloom])
    }
    if p.vignette > 0 { try node("CIVignette", [kCIInputRadiusKey:side*0.75,kCIInputIntensityKey:p.vignette]) }
    guard let result = try kernel("creativeFinish").apply(extent: input.extent, arguments:[input,image,p.grain,Double(edit.grainSeed >> 16),Double(edit.grainSeed & 65535),1/max(scale,0.000001),edit.intensity]) else { throw CreativeFilterError.kernel }
    return result.transformed(by:CGAffineTransform(translationX:origin.x,y:origin.y))
  }
}
