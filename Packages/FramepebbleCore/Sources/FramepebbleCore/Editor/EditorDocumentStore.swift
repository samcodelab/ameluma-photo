import Foundation
import Darwin

/// Portable editable packages own every source. Never writes into source resources.
public actor EditorDocumentStore {
  public init() {}
  private nonisolated static func regularFile(_ url:URL, beneath root:URL) throws -> Int {
    let base=root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(base) else { throw EditorDocumentError.unsafeResource }
    let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
    guard values.isRegularFile==true, values.isSymbolicLink != true, let size=values.fileSize, size<=512*1024*1024 else { throw EditorDocumentError.unsafeResource }
    return size
  }
  public func load(_ package:URL) throws -> EditorDocument {try Self.readPackage(package)}
  public nonisolated static func readPackage(_ package:URL) throws -> EditorDocument {
    guard package.isFileURL else { throw EditorDocumentError.unsafeResource }
    let manifest=package.appendingPathComponent("manifest.json")
    guard try regularFile(manifest,beneath:package)<=8*1024*1024 else { throw EditorDocumentError.invalidDocument }
    let document=try JSONDecoder().decode(EditorDocument.self,from:Data(contentsOf:manifest))
    try document.validate()
    let root=package.appendingPathComponent("Resources",isDirectory:true)
    let rootValues=try root.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey])
    guard rootValues.isDirectory==true, rootValues.isSymbolicLink != true else { throw EditorDocumentError.unsafeResource }
    var total=0
    for resource in document.resources {
      try Task.checkCancellation()
      total += try regularFile(root.appendingPathComponent(resource.filename),beneath:package)
      guard total<=2*1024*1024*1024 else { throw EditorDocumentError.invalidDocument }
    }
    return document
  }
  public func save(_ document:EditorDocument, resources:[UUID:URL], to destination:URL) throws {try Self.writePackage(document,resources:resources,to:destination)}
  public nonisolated static func writePackage(_ document:EditorDocument, resources:[UUID:URL], to destination:URL) throws {
    try document.validate(); try Task.checkCancellation()
    guard destination.isFileURL, destination.pathExtension.lowercased()=="ameluma" else { throw EditorDocumentError.unsafeResource }
    let fm=FileManager.default
    if fm.fileExists(atPath:destination.path) {_ = try readPackage(destination)}
    let stage=destination.deletingLastPathComponent().appendingPathComponent(".ameluma-save-"+UUID().uuidString,isDirectory:true)
    let root=stage.appendingPathComponent("Resources",isDirectory:true)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:stage) }
    var total=0
    for resource in document.resources {
      try Task.checkCancellation()
      guard let source=resources[resource.id] else { throw EditorDocumentError.missingResource }
      // Acquisition supplies ordinary local immutable copies, never links into originals.
      let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
      guard source.isFileURL, values.isRegularFile==true, values.isSymbolicLink != true, let size=values.fileSize, size<=512*1024*1024 else { throw EditorDocumentError.unsafeResource }
      total += size; guard total<=2*1024*1024*1024 else { throw EditorDocumentError.invalidDocument }
      try fm.copyItem(at:source,to:root.appendingPathComponent(resource.filename))
    }
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    try encoder.encode(document).write(to:stage.appendingPathComponent("manifest.json"),options:.atomic)
    _ = try readPackage(stage)
    try Task.checkCancellation()
    if fm.fileExists(atPath:destination.path) {
      let values=try destination.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
      guard values.isDirectory==true, values.isSymbolicLink != true else { throw EditorDocumentError.unsafeResource }
      // Swap complete directories atomically; stage then contains the previous good version.
      let code=stage.withUnsafeFileSystemRepresentation { from in destination.withUnsafeFileSystemRepresentation { to in
        guard let from,let to else{return Int32(-1)};return renamex_np(from,to,UInt32(RENAME_SWAP))
      }}
      guard code==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    } else {
      let code=stage.withUnsafeFileSystemRepresentation { from in destination.withUnsafeFileSystemRepresentation { to in
        guard let from,let to else{return Int32(-1)};return renamex_np(from,to,UInt32(RENAME_EXCL))
      }}
      guard code==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    }
  }
}
