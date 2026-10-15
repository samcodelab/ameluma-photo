import CoreServices
import Foundation

/// Events are hints only. Reconciliation and stability checks remain the authoritative queue.
private final class FolderEventRelay: @unchecked Sendable {
  let action: @MainActor @Sendable () async -> Void
  init(action: @escaping @MainActor @Sendable () async -> Void) { self.action = action }
}
final class FolderEvents {
  private var stream: FSEventStreamRef?
  private var access: [URL] = []
  private let relay: FolderEventRelay
  init(folders: [URL], onChange: @escaping @MainActor @Sendable () async -> Void) {
    relay = FolderEventRelay(action: onChange)
    for folder in folders where folder.startAccessingSecurityScopedResource() {
      access.append(folder)
    }
    guard !folders.isEmpty else { return }
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(relay).toOpaque(),
      retain: { pointer in
        guard let pointer else { return nil }
        return UnsafeRawPointer(Unmanaged<FolderEventRelay>.fromOpaque(pointer).retain().toOpaque())
      },
      release: { pointer in
        if let pointer { Unmanaged<FolderEventRelay>.fromOpaque(pointer).release() }
      }, copyDescription: nil)
    stream = FSEventStreamCreate(
      nil,
      { _, info, _, _, _, _ in
        guard let info else { return }
        let relay = Unmanaged<FolderEventRelay>.fromOpaque(info).takeUnretainedValue()
        let action = relay.action
        Task { @MainActor in await action() }
      }, &context, folders.map(\.path) as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
      FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
    if let stream {
      FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
      if !FSEventStreamStart(stream) {
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
      }
    }
  }
  deinit {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    for folder in access { folder.stopAccessingSecurityScopedResource() }
  }
}
