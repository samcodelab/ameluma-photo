import Foundation

/// Deletes only direct, UUID-named regular snapshots in private Sources storage.
/// No recursion, source-reference deletion, symlink following, or exported-file deletion.
public actor SourceStorageCleanup {
    public init() {}
    public func retainedSnapshotNames(projects: URL, reusableConfiguration: Data) throws -> Set<String> {
        var retained: Set<String> = []
        func collect(_ value: Any) {
            if let text = value as? String, let url = URL(string: text), url.isFileURL,
               url.deletingLastPathComponent().lastPathComponent == "Sources" {
                retained.insert(url.lastPathComponent)
            } else if let array = value as? [Any] { array.forEach(collect) }
            else if let dictionary = value as? [String: Any] { dictionary.values.forEach(collect) }
        }
        if FileManager.default.fileExists(atPath: projects.path) {
            for url in try FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                try Task.checkCancellation()
                collect(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
            }
        }
        collect(try JSONSerialization.jsonObject(with: reusableConfiguration))
        return retained
    }
    public func removeUnreferenced(in directory: URL, retaining names: Set<String>) throws -> Int {
        guard directory.isFileURL, directory.lastPathComponent == "Sources",
              directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL
        else { throw CocoaError(.fileWriteNoPermission) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        var removed = 0
        for file in files {
            try Task.checkCancellation()
            guard !names.contains(file.lastPathComponent), UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try FileManager.default.removeItem(at: file)
            removed += 1
        }
        return removed
    }
}
