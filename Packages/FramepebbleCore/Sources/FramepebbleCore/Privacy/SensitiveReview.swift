import CoreGraphics
import Foundation

public enum SensitiveAnalysisAvailability: Sendable, Equatable {
  case available(descriptiveInterventions: Bool)
  case unavailable(String)
  public var canAnalyze: Bool {
    if case .available = self { return true }
    return false
  }
}
public protocol SensitiveImageAnalyzing: Sendable {
  func availability() async -> SensitiveAnalysisAvailability
  func analyze(_ image: CGImage) async throws -> Bool
}
/// Deliberately not Codable: sensitivity findings and reveal choices never enter project storage.
public struct SensitiveReviewState: Sendable {
  public struct Finding: Sendable {
    public var sensitive: Bool
    public var fingerprint: SourceFingerprint
  }
  public private(set) var findings: [UUID: Finding] = [:]
  public private(set) var manual: Set<UUID> = []
  public var revealed: Set<UUID> = []
  public init() {}
  public var flagged: Set<UUID> { manual.union(findings.filter { $0.value.sensitive }.keys) }
  public func concealed(_ id: UUID) -> Bool { flagged.contains(id) && !revealed.contains(id) }
  public mutating func record(_ sensitive: Bool, id: UUID, fingerprint: SourceFingerprint) {
    findings[id] = Finding(sensitive: sensitive, fingerprint: fingerprint)
    if sensitive { revealed.remove(id) }
  }
  public mutating func mark(_ id: UUID, forReview: Bool) {
    if forReview {
      manual.insert(id)
      revealed.remove(id)
    } else {
      manual.remove(id)
    }
  }
  public mutating func invalidateFinding(_ id: UUID) { findings.removeValue(forKey: id) }
  public mutating func invalidate(_ id: UUID) {
    findings.removeValue(forKey: id)
    manual.remove(id)
    revealed.remove(id)
  }
}
