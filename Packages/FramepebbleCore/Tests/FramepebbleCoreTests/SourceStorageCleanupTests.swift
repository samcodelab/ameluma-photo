import XCTest
@testable import FramepebbleCore

final class SourceStorageCleanupTests: XCTestCase {
    func testOnlyUnusedPrivateSnapshotsAreRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let original = root.appendingPathComponent(UUID().uuidString + ".png")
        let unused = storage.appendingPathComponent(UUID().uuidString + ".png")
        let retained = storage.appendingPathComponent(UUID().uuidString + ".png")
        let unknown = storage.appendingPathComponent("user-original.png")
        let link = storage.appendingPathComponent(UUID().uuidString + ".png")
        let bytes = Data("original photo bytes".utf8)
        for url in [original, unused, retained, unknown] { try bytes.write(to: url) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let removed = try await SourceStorageCleanup().removeUnreferenced(in: storage, retaining: [retained.lastPathComponent])
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unused.path))
        for url in [original, retained, unknown, link] { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        do { _ = try await SourceStorageCleanup().removeUnreferenced(in: root, retaining: []); XCTFail("Must reject external locations") } catch {}
    }
}
