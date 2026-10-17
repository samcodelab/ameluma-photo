import CoreImage
import Foundation

public enum ColourToolError: Error, LocalizedError {
  case kernel, hdr
  public var errorDescription: String? {
    switch self {
    case .kernel: "The local colour processor is unavailable. Retry or remove the colour edit."
    case .hdr: "Colour Mix and Replace Colour currently require an SDR photo. HDR development is not available yet."
    }
  }
}

/// Version-one local SDR colour operations shared by preview and export.
public enum ColourRenderer {
  private static let kernels: Result<[CIKernel], Error> = Result {
    guard let url = Bundle.module.url(forResource: "ColourTools.metal", withExtension: "txt") else { throw ColourToolError.kernel }
    return try CIKernel.kernels(withMetalString: String(contentsOf: url, encoding: .utf8))
  }
  static func kernel(_ name: String) throws -> CIColorKernel {
    guard let kernel = try kernels.get().first(where: { $0.name == name }) as? CIColorKernel else { throw ColourToolError.kernel }
    return kernel
  }
  public static func mix(_ image: CIImage, bands: [CIVector]) throws -> CIImage {
    guard bands.count == 8, let space = CGColorSpace(name: CGColorSpace.sRGB),
      let input = image.matchedFromWorkingSpace(to: space),
      let output = try kernel("colourMix").apply(extent: image.extent, arguments: [input] + bands),
      let matched = output.matchedToWorkingSpace(from: space) else { throw ColourToolError.kernel }
    return matched
  }
}
