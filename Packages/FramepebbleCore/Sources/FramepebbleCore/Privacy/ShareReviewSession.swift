import Foundation

/// Ephemeral manual review. No sensitivity verdict or approval is persisted in projects.
/// Outputs are validated files supplied by the export pipeline; edits require a new session.
public struct ShareReviewSession: Sendable {
  public let outputs: [URL]
  public private(set) var included: Set<URL>
  public var revealed: Set<URL> = []
  private var approval: Set<URL>?
  public init(outputs: [URL]) {
    self.outputs = outputs
    included = Set(outputs)
  }
  public mutating func include(_ url: URL, _ value: Bool) {
    guard outputs.contains(url) else { return }
    if value { included.insert(url) } else { included.remove(url) }
    approval = nil
  }
  public mutating func revokeApproval() { approval = nil }
  public mutating func approve() { approval = included.isEmpty ? nil : included }
  public var approvedOutputs: [URL] {
    guard approval == included else { return [] }
    return outputs.filter { included.contains($0) }
  }
}

/// Immutable output identity for one operation, independent of export history.
public struct ShareOutputSession: Identifiable, Sendable {
    public let id: UUID
    public let outputs: [URL]
    public let summary: String
    public init(outputs: [URL], summary: String = "") {
        id = UUID(); var seen: Set<URL> = []
        self.outputs = outputs.filter { seen.insert($0).inserted }; self.summary = summary
    }
}
