import Foundation
import ImageIO

public struct WorkspacePhotoInfo: Codable, Sendable, Equatable {
  public var date: Date?
  public var width: Int
  public var height: Int
  public var format: String
  public init(date: Date?, width: Int, height: Int, format: String) {
    self.date = date; self.width = width; self.height = height; self.format = format
  }
  /// Reads image headers only. EXIF dates without a timezone use the local timezone.
  public static func read(_ url: URL) throws -> Self {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int
    else { throw ProcessingError.invalidImage }
    let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    let capture = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap { formatter.date(from: $0) }
    let fallback = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
    let orientation = p[kCGImagePropertyOrientation] as? Int ?? 1
    return Self(date: capture ?? fallback?.creationDate ?? fallback?.contentModificationDate,
      width: orientation >= 5 ? h : w, height: orientation >= 5 ? w : h,
      format: (CGImageSourceGetType(source) as String?) ?? "unknown")
  }
}
public struct WorkspaceFilter: Sendable, Equatable {
  public enum Period: String, CaseIterable, Sendable { case any = "Any date", hour = "Last hour", today = "Today", yesterday = "Yesterday", week = "Last 7 days", month = "Last 30 days", custom = "Custom date range" }
  public enum Orientation: String, CaseIterable, Sendable { case any = "Any orientation", landscape = "Landscape", portrait = "Portrait", square = "Square" }
  public enum Sort: String, CaseIterable, Sendable { case imported = "Import order", filename = "Filename", date = "Capture date" }
  public var period: Period = .any
  public var orientation: Orientation = .any
  public var format = ""
  public var sort: Sort = .imported
  public var start = Calendar.current.startOfDay(for: Date())
  public var end = Date()
  public init() {}
  public var isActive: Bool { period != .any || orientation != .any || !format.isEmpty || sort != .imported }
  public func apply(to assets: [SourceAsset], information: [UUID: WorkspacePhotoInfo], now: Date = Date(), calendar: Calendar = .current) -> [SourceAsset] {
    let today = calendar.startOfDay(for: now)
    let lower: Date
    let upper: Date
    switch period {
    case .any: lower = .distantPast; upper = .distantFuture
    case .hour: lower = now.addingTimeInterval(-3600); upper = now
    case .today: lower = today; upper = calendar.date(byAdding: .day, value: 1, to: today) ?? now
    case .yesterday: lower = calendar.date(byAdding: .day, value: -1, to: today) ?? today; upper = today
    case .week: lower = calendar.date(byAdding: .day, value: -7, to: now) ?? now; upper = now
    case .month: lower = calendar.date(byAdding: .day, value: -30, to: now) ?? now; upper = now
    case .custom: lower = start; upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
    }
    let result = assets.filter { asset in
      let info = information[asset.id]
      if period != .any { guard let date = info?.date, date >= lower, date < upper else { return false } }
      if !format.isEmpty && info?.format != format { return false }
      switch orientation {
      case .any: return true
      case .landscape: return (info?.width ?? 0) > (info?.height ?? 0)
      case .portrait: return (info?.height ?? 0) > (info?.width ?? 0)
      case .square: return info != nil && info?.width == info?.height
      }
    }
    guard sort != .imported else { return result }
    return result.enumerated().sorted { a, b in
      if sort == .filename {
        let comparison = a.element.name.localizedStandardCompare(b.element.name)
        return comparison == .orderedSame ? a.offset < b.offset : comparison == .orderedAscending
      }
      let lhs = information[a.element.id]?.date ?? .distantFuture, rhs = information[b.element.id]?.date ?? .distantFuture
      return lhs == rhs ? a.offset < b.offset : lhs < rhs
    }.map(\.element)
  }
}
public actor WorkspaceMetadataReader {
  public init() {}
  public func read(_ assets: [SourceAsset]) throws -> [UUID: WorkspacePhotoInfo] {
    var result: [UUID: WorkspacePhotoInfo] = [:]
    for asset in assets { try Task.checkCancellation(); if let info = try? WorkspacePhotoInfo.read(asset.url) { result[asset.id] = info } }
    return result
  }
}
