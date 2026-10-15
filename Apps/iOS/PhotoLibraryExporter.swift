import Foundation
import Photos

/// Photos executes change blocks on its own queue. They must never inherit a view's MainActor.
enum PhotoLibraryExporter {
    nonisolated static func save(_ url: URL) async throws {
        let changes: @Sendable () -> Void = {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
        try await PHPhotoLibrary.shared().performChanges(changes)
    }
}
