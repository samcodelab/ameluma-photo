import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

public enum SourceImportEvent: Sendable {
  case discovered
  case copying(name: String, bytes: Int64, total: Int64)
  case ready(SourceAsset, digest: String)
  case failed(name: String, message: String)
}

/// Separate from the render actor: slow file servers never hold the preview/transform queue.
/// One source copy at a time, 1 MiB buffers, backpressure at progress/asset callbacks.
public actor SourceImporter {
  private let validator = ImageProcessor()
  public init() {}
  public func removeOwnedSnapshot(_ url: URL, from directory: URL) throws {
    guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    else { throw CocoaError(.fileWriteNoPermission) }
    try FileManager.default.removeItem(at: url)
  }
  public func run(
    _ urls: [URL], destination: URL, onEvent: @Sendable (SourceImportEvent) async -> Void
  ) async throws {
    for url in urls {
      try Task.checkCancellation()
      guard url.isFileURL else {
        await onEvent(.failed(name: "Source", message: "Only local files can be imported."))
        continue
      }
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      do {
        let rootProperties = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let directory = rootProperties.isDirectory == true
        let privateRoot = destination.resolvingSymlinksInPath().standardizedFileURL
        if directory && url.resolvingSymlinksInPath().standardizedFileURL == privateRoot {
          throw SourceImportError.ownedFolder
        }
        if directory {
          let failures = EnumerationFailures()
          guard
            let walker = FileManager.default.enumerator(
              at: url.resolvingSymlinksInPath(),
              includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
              options: [.skipsHiddenFiles, .skipsPackageDescendants],
              errorHandler: { _, error in
                failures.append(error.localizedDescription)
                return true
              })
          else { throw CocoaError(.fileReadNoPermission) }
          while let file = walker.nextObject() as? URL {
            try Task.checkCancellation()
            if file.standardizedFileURL == privateRoot {
              walker.skipDescendants()
              continue
            }
            let properties = try file.resourceValues(forKeys: [
              .isRegularFileKey, .isSymbolicLinkKey,
            ])
            if properties.isSymbolicLink == true {
              walker.skipDescendants()
              continue
            }
            guard properties.isRegularFile == true,
              let type = UTType(filenameExtension: file.pathExtension),
              ImageProcessor.importTypes.contains(where: { type.conforms(to: $0) })
            else { continue }
            await process(file, destination: destination, onEvent: onEvent)
          }
          for message in failures.messages {
            await onEvent(.failed(name: url.lastPathComponent, message: message))
          }
        } else {
          await process(
            url, destination: destination, resolveSymlink: rootProperties.isSymbolicLink == true,
            onEvent: onEvent)
        }
      } catch is CancellationError { throw CancellationError() } catch {
        await onEvent(.failed(name: url.lastPathComponent, message: error.localizedDescription))
      }
    }
    try Task.checkCancellation()
  }
  private func process(
    _ url: URL, destination: URL, resolveSymlink: Bool = false,
    onEvent: @Sendable (SourceImportEvent) async -> Void
  ) async {
    await onEvent(.discovered)
    do {
      let (asset, digest) = try await copy(
        url, destination: destination, resolveSymlink: resolveSymlink, onEvent: onEvent)
      await onEvent(.ready(asset, digest: digest))
    } catch is CancellationError
    { /* The outer loop observes cancellation; owned partial copies are removed. */  } catch {
      await onEvent(.failed(name: url.lastPathComponent, message: error.localizedDescription))
    }
  }
  private func copy(
    _ source: URL, destination: URL, resolveSymlink: Bool,
    onEvent: @Sendable (SourceImportEvent) async -> Void
  ) async throws -> (SourceAsset, String) {
    try Task.checkCancellation()
    let original = resolveSymlink ? source.resolvingSymlinksInPath() : source
    let before = try SourceFingerprint.read(original)
    guard before.bytes <= 512 * 1024 * 1024 else { throw SourceImportError.tooLarge }
    let local = destination.appendingPathComponent(UUID().uuidString).appendingPathExtension(
      source.pathExtension)
    let fd = Darwin.open(local.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
    let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var keep = false
    defer {
      try? output.close()
      if !keep { try? FileManager.default.removeItem(at: local) }
    }
    let input = try FileHandle(forReadingFrom: original)
    defer { try? input.close() }
    var hash = SHA256()
    var copied: Int64 = 0
    var lastUpdate = Date.distantPast
    await onEvent(.copying(name: source.lastPathComponent, bytes: 0, total: Int64(before.bytes)))
    while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      try Task.checkCancellation()
      copied += Int64(chunk.count)
      guard copied <= 512 * 1024 * 1024 else { throw SourceImportError.tooLarge }
      try output.write(contentsOf: chunk)
      hash.update(data: chunk)
      if Date().timeIntervalSince(lastUpdate) >= 0.1 || copied == Int64(before.bytes) {
        lastUpdate = Date()
        await onEvent(
          .copying(name: source.lastPathComponent, bytes: copied, total: Int64(before.bytes)))
      }
    }
    try output.close()
    try Task.checkCancellation()
    guard copied == Int64(before.bytes), try SourceFingerprint.read(original) == before else {
      throw SourceImportError.changed
    }
    // All decode/validation now happens from the local snapshot, not across the network.
    _ = try await validator.identify(local)
    try Task.checkCancellation()
    keep = true
    return (
      SourceAsset(url: local, name: source.lastPathComponent),
      hash.finalize().map { String(format: "%02x", $0) }.joined()
    )
  }
}

private enum SourceImportError: LocalizedError {
  case tooLarge, changed, ownedFolder
  var errorDescription: String? {
    switch self {
    case .ownedFolder: "Choose an import folder outside Framepebble’s private source storage."
    case .tooLarge: "The image file exceeds the 512 MB import limit."
    case .changed:
      "The source changed while copying. Wait for the transfer to finish, then import it again."
    }
  }
}
private final class EnumerationFailures: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []
  func append(_ value: String) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }
  var messages: [String] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}
