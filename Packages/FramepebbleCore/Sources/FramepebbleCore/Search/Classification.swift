import Foundation

public struct ClassificationLabel: Codable, Sendable, Equatable {
    public var identifier: String; public var confidence: Float
    public init(_ identifier: String, confidence: Float) { self.identifier = identifier; self.confidence = confidence }
}
public struct SourceFingerprint: Codable, Sendable, Equatable {
    public var bytes: Int; public var modified: Date
    public init(bytes: Int, modified: Date) { self.bytes = bytes; self.modified = modified }
    public static func read(_ url: URL) throws -> Self { guard url.isFileURL else { throw ProcessingError.invalidImage }; var fresh = url; fresh.removeAllCachedResourceValues(); let v = try fresh.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]); return Self(bytes: v.fileSize ?? 0, modified: v.contentModificationDate ?? .distantPast) }
}
public struct ClassificationRecord: Codable, Sendable, Equatable {
    public var assetID: UUID; public var labels: [ClassificationLabel]; public var revision: Int; public var fingerprint: SourceFingerprint
    public init(assetID: UUID, labels: [ClassificationLabel], revision: Int, fingerprint: SourceFingerprint) { self.assetID = assetID; self.labels = labels; self.revision = revision; self.fingerprint = fingerprint }
}
public struct ClassificationIndex: Codable, Sendable {
    public var version = 1
    public private(set) var records: [UUID: ClassificationRecord] = [:]
    public init() {}
    public mutating func insert(_ record: ClassificationRecord) { records[record.assetID] = record }
    public mutating func invalidate(_ id: UUID) { records.removeValue(forKey: id) }
    public func matches(query: String, candidates: [UUID], threshold: Float = 0.15) -> [UUID] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return candidates }
        func score(_ id: UUID) -> Float {
            guard let labels = records[id]?.labels else { return 0 }
            return tokens.map { token in labels.filter { $0.confidence >= threshold && $0.identifier.lowercased().replacingOccurrences(of: "_", with: " ").contains(token) }.map(\.confidence).max() ?? 0 }.min() ?? 0
        }
        return candidates.enumerated().compactMap { offset, id -> (UUID, Float, Int)? in let rank = score(id); return rank > 0 ? (id, rank, offset) : nil }.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }.map { $0.0 }
    }
    public var suggestedCategories: [(String, Int)] {
        var counts: [String: Int] = [:]
        for record in records.values { for label in record.labels where label.confidence >= 0.3 { counts[label.identifier, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(12).map { ($0.key, $0.value) }
    }
}
