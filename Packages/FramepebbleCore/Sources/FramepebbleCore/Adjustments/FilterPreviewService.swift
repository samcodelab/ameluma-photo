import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

/// Two dedicated thumbnail workers keep export and canvas processing off this queue.
/// Pixel caches only; semantic edits remain in ProjectDocument.
public actor FilterPreviewService {
  public static let shared = FilterPreviewService()
  private let workers = [ImageProcessor(), ImageProcessor()]
  private var busy: Set<Int> = []
  private struct Entry { var image: CGImage; var used: UInt64; var asset: UUID }
  private var memory: [String: Entry] = [:]
  private var clock: UInt64 = 0
  private let memoryLimit = 128 * 1024 * 1024
  private var pressure: DispatchSourceMemoryPressure?
  private let diskLimit = 512 * 1024 * 1024
  private struct DiskEntry { var bytes: Int; var used: Date }
  private var diskEntries: [URL: DiskEntry]?
  private let directory: URL
  public init(directory: URL? = nil) {
    self.directory = directory ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("Framepebble/FilterPreviews-v1",isDirectory:true)
  }
  private struct Key: Encodable {
    var renderer = 1; var analysis = 1; var working = "sRGB-RGBAh"
    var source: SourceAsset; var fingerprint: SourceFingerprint
    var configuration: ProcessingConfiguration; var maximum: Int; var decodeMaximum: Int
  }
  public func preview(_ asset: SourceAsset, configuration: ProcessingConfiguration, maximum: Int, privateMode: Bool) async throws -> CGImage {
    try Task.checkCancellation()
    if pressure == nil {
      let source = DispatchSource.makeMemoryPressureSource(eventMask:[.warning,.critical],queue:.global(qos:.utility))
      source.setEventHandler { [weak self] in Task { await self?.clearMemory() } }
      source.resume(); pressure=source
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let fingerprint = try SourceFingerprint.read(asset.url)
    let data = try encoder.encode(Key(source:asset,fingerprint:fingerprint,configuration:configuration,maximum:maximum,decodeMaximum:max(384,maximum)))
    let key = asset.id.uuidString + "-" + SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    clock &+= 1
    if !privateMode, var hit = memory[key] { hit.used=clock; memory[key]=hit; return hit.image }
    let url=directory.appendingPathComponent(key).appendingPathExtension("png")
    if !privateMode, FileManager.default.fileExists(atPath:url.path), let source=CGImageSourceCreateWithURL(url as CFURL,nil), let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) {
      remember(image,key:key,asset:asset.id)
      try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:url.path)
      diskEntries?[url]?.used=Date()
      return image
    }
    while busy.count == workers.count { try await Task.sleep(for:.milliseconds(10)) }
    try Task.checkCancellation()
    let index = workers.indices.first { !busy.contains($0) } ?? 0
    busy.insert(index); defer { busy.remove(index) }
    await workers[index].setPrivateMode(privateMode)
    let image=try await workers[index].render(asset.url,configuration:configuration,previewMaximum:maximum,decodeMaximum:max(384,maximum))
    try Task.checkCancellation()
    guard try SourceFingerprint.read(asset.url) == fingerprint else { throw CancellationError() }
    if !privateMode {
      remember(image,key:key,asset:asset.id)
      try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
      let encoded=NSMutableData()
      if let dest=CGImageDestinationCreateWithData(encoded,UTType.png.identifier as CFString,1,nil) {
        CGImageDestinationAddImage(dest,image,nil)
        if CGImageDestinationFinalize(dest) {
          do { try (encoded as Data).write(to:url,options:[.atomic, .completeFileProtectionUntilFirstUserAuthentication]); recordDisk(url,bytes:encoded.length) }
          catch { /* Cache publication is optional; the validated rendered pixels remain usable. */ }
        }
      }
    }
    return image
  }
  private func remember(_ image: CGImage,key:String,asset:UUID) {
    clock &+= 1; memory[key]=Entry(image:image,used:clock,asset:asset)
    while memory.values.reduce(0,{$0+$1.image.bytesPerRow*$1.image.height}) > memoryLimit, let oldest=memory.min(by:{$0.value.used<$1.value.used})?.key { memory.removeValue(forKey:oldest) }
  }
  public func clearMemory() { memory.removeAll() }
  public func purge(_ ids: Set<UUID>) {
    memory = memory.filter { !ids.contains($0.value.asset) }
    let prefixes=ids.map(\.uuidString)
    for file in (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? [] where prefixes.contains(where:{file.lastPathComponent.hasPrefix($0)}) { try? FileManager.default.removeItem(at:file); diskEntries?.removeValue(forKey:file) }
  }
  private func recordDisk(_ url: URL, bytes: Int) {
    if diskEntries == nil {
      // Scan once per service lifetime, never for every tile in a large workspace.
      let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey])) ?? []
      var index: [URL:DiskEntry]=[:]
      for file in files {
        if let v=try? file.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]) { index[file]=DiskEntry(bytes:v.fileSize ?? 0,used:v.contentModificationDate ?? .distantPast) }
      }
      diskEntries=index
    }
    diskEntries?[url]=DiskEntry(bytes:bytes,used:Date())
    var cost=diskEntries?.values.reduce(0,{$0+$1.bytes}) ?? 0
    if cost > diskLimit {
      for (file,entry) in (diskEntries ?? [:]).sorted(by:{$0.value.used<$1.value.used}) where cost > diskLimit {
        do { try FileManager.default.removeItem(at:file); diskEntries?.removeValue(forKey:file);cost-=entry.bytes }
        catch { /* Retry eviction on the next cache publication. */ }
      }
    }
  }
}
