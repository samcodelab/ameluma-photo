import CoreGraphics
import FramepebbleCore
import SensitiveContentAnalysis

/// No entitlements are invented: the system policy is the authoritative runtime capability gate.
actor AppleSensitiveAnalyzer: SensitiveImageAnalyzing {
  private let analyzer = SCSensitivityAnalyzer()
  func availability() -> SensitiveAnalysisAvailability {
    switch analyzer.analysisPolicy {
    case .disabled:
      return .unavailable(
        "Automatic checking is unavailable. It requires a signed Sensitive Content Analysis capability and enabled system Sensitive Content Warning or Communication Safety settings. Manual review is available."
      )
    case .simpleInterventions: return .available(descriptiveInterventions: false)
    case .descriptiveInterventions: return .available(descriptiveInterventions: true)
    @unknown default:
      return .unavailable(
        "The system does not currently allow automatic checking. Use manual review.")
    }
  }
  func analyze(_ image: CGImage) async throws -> Bool {
    guard availability().canAnalyze else { throw SensitiveAnalysisError.unavailable }
    try Task.checkCancellation()
    let result = try await analyzer.analyzeImage(image)
    try Task.checkCancellation()
    guard availability().canAnalyze else { throw SensitiveAnalysisError.unavailable }
    return result.isSensitive
  }
}
enum SensitiveAnalysisError: Error { case unavailable }
