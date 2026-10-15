import Foundation
import Darwin

/// Own a staging file only after exclusive creation succeeds. Existing files are never cleaned up.
enum StagingWriter {
    static func write(_ data: Data, to url: URL) throws {
        guard url.isFileURL else { throw ProcessingError.destination }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do { try handle.write(contentsOf: data); try handle.close() }
        catch { try? handle.close(); try? FileManager.default.removeItem(at: url); throw error }
    }
}
