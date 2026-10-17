import CoreImage
import Foundation

public struct SerializedAdjustment: Codable, Equatable, Sendable {
  public var name: String
  public var numbers: [String: Double] = [:]
  public var vectors: [String: [Double]] = [:]
  public var colors: [String: [Double]] = [:]
  public init(name: String) { self.name = name }
  static let allowed: [String: Set<String>] = [
    "CIExposureAdjust":["inputEV"], "CIVibrance":["inputAmount"],
    "CIHighlightShadowAdjust":["inputHighlightAmount","inputShadowAmount","inputRadius"],
    "CIColorControls":["inputSaturation","inputBrightness","inputContrast"],
    "CIToneCurve":Set((0...4).map { "inputPoint\($0)" }),
    "CITemperatureAndTint":["inputNeutral","inputTargetNeutral"],
    "CIWhitePointAdjust":["inputColor"]
  ]
  static func capture(_ filter: CIFilter) -> SerializedAdjustment? {
    guard let keys = allowed[filter.name] else { return nil }
    var value = SerializedAdjustment(name: filter.name)
    for key in keys {
      if let n = filter.value(forKey:key) as? NSNumber, n.doubleValue.isFinite { value.numbers[key] = n.doubleValue }
      else if let v = filter.value(forKey:key) as? CIVector { value.vectors[key] = (0..<v.count).map { Double(v.value(at:$0)) } }
      else if let c = filter.value(forKey:key) as? CIColor { value.colors[key] = [c.red,c.green,c.blue,c.alpha].map(Double.init) }
    }
    return value.numbers.isEmpty && value.vectors.isEmpty && value.colors.isEmpty ? nil : value
  }
  func apply(to image: CIImage) throws -> CIImage {
    guard let allowed = Self.allowed[name], let filter = CIFilter(name:name), Set(numbers.keys).union(vectors.keys).union(colors.keys).isSubset(of:allowed) else { throw CreativeFilterError.unavailable }
    let vectorKeys: Set<String> = name == "CIToneCurve" ? Set((0...4).map { "inputPoint\($0)" }) : name == "CITemperatureAndTint" ? ["inputNeutral","inputTargetNeutral"] : []
    let colorKeys: Set<String> = name == "CIWhitePointAdjust" ? ["inputColor"] : []
    guard Set(numbers.keys).isSubset(of:allowed.subtracting(vectorKeys).subtracting(colorKeys)),
      Set(vectors.keys).isSubset(of:vectorKeys), Set(colors.keys).isSubset(of:colorKeys) else { throw ProcessingError.invalidConfiguration }
    filter.setValue(image, forKey:kCIInputImageKey)
    for (key,value) in numbers { guard value.isFinite else { throw ProcessingError.invalidConfiguration }; filter.setValue(value,forKey:key) }
    for (key,values) in vectors {
      guard values.count == 2, values.allSatisfy(\.isFinite) else { throw ProcessingError.invalidConfiguration }
      filter.setValue(CIVector(values:values.map { CGFloat($0) },count:values.count),forKey:key)
    }
    for (key,v) in colors {
      guard v.count == 4, v.allSatisfy(\.isFinite) else { throw ProcessingError.invalidConfiguration }
      filter.setValue(CIColor(red:v[0],green:v[1],blue:v[2],alpha:v[3]),forKey:key)
    }
    guard let result=filter.outputImage else { throw ProcessingError.invalidConfiguration }
    return result.cropped(to:image.extent)
  }
}
public struct AutoEnhanceEdit: Codable, Equatable, Sendable {
  public var enabled: Bool = true
  public var analysisVersion: Int = 1
  public var resolvedAdjustments: [SerializedAdjustment] = []
  public init(enabled: Bool = true, resolvedAdjustments: [SerializedAdjustment] = []) { self.enabled=enabled; self.resolvedAdjustments=resolvedAdjustments }
  public func apply(to input: CIImage) throws -> CIImage {
    guard enabled else { return input }
    guard analysisVersion == 1 else { throw CreativeFilterError.unavailable }
    return try resolvedAdjustments.reduce(input) { try $1.apply(to:$0) }
  }
}
