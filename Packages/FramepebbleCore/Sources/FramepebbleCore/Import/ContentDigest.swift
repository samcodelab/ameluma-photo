import CryptoKit
import Foundation

public enum ContentDigest {
  /// Streaming SHA-256, bounded to 1 MiB chunks, independent of filenames.
  public static func read(_ url: URL) throws -> String {
    guard url.isFileURL else { throw ProcessingError.invalidImage }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      try Task.checkCancellation()
      hash.update(data: chunk)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
  public static func read(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
public actor DuplicateIndex {
  private var digests: Set<String> = []
  private var sources: [String: [UUID]] = [:]
  public init() {}
  public func sourceID(for digest: String) -> UUID? { sources[digest]?.first }
  public func register(_ id: UUID, digest: String) {
    if !(sources[digest]?.contains(id) ?? false) { sources[digest, default: []].append(id) }; digests.insert(digest)
  }
  public func rebuild(_ assets: [SourceAsset]) {
    sources = [:]; digests = []
    for asset in assets { if let hash = try? ContentDigest.read(asset.url) { register(asset.id, digest: hash) } }
  }
  public func insertDigest(_ digest: String) -> Bool { digests.insert(digest).inserted }
  public func contains(_ url: URL) throws -> Bool { digests.contains(try ContentDigest.read(url)) }
  public func insert(_ url: URL) throws -> Bool {
    let hash = try ContentDigest.read(url)
    return digests.insert(hash).inserted
  }
  public func insert(_ data: Data) -> Bool { digests.insert(ContentDigest.read(data)).inserted }
}
