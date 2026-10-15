import Foundation

public enum AutomationMode: String, Codable, Sendable, CaseIterable {
  case automatic = "Automatic"
  case review = "Review Before Export"
}
public struct AutomationRecipe: Codable, Sendable, Identifiable {
  public var id = UUID()
  public var name = "New Automation"
  public var enabled = false
  public var inputBookmark: Data?
  public var outputBookmark: Data?
  public var inputLabel = "Choose input folder"
  public var outputLabel = "Choose output folder"
  public var recursive = false
  public var processExisting = true
  public var mode: AutomationMode = .automatic
  public var privacyReview = false
  public var resizeEnabled = true
  public var convertEnabled = true
  public var compressionEnabled = true
  public var watermarkEnabled = true
  public var metadataEnabled = true
  public var configuration = ProcessingConfiguration()
  public var profile = ExportProfile()
  public var history: Set<String> = []
  public var pending: [AutomationJob] = []
  public var failures: [AutomationJob] = []
  public var completed = 0
  public var lastActivity: Date?
  public var error: String?
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case id, name, enabled, inputBookmark, outputBookmark, inputLabel, outputLabel, recursive,
      processExisting, mode, privacyReview, resizeEnabled, convertEnabled, compressionEnabled,
      watermarkEnabled, metadataEnabled, configuration, profile, history, pending, failures,
      completed, lastActivity, error
  }
  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    inputBookmark = try c.decodeIfPresent(Data.self, forKey: .inputBookmark)
    outputBookmark = try c.decodeIfPresent(Data.self, forKey: .outputBookmark)
    inputLabel = try c.decodeIfPresent(String.self, forKey: .inputLabel) ?? inputLabel
    outputLabel = try c.decodeIfPresent(String.self, forKey: .outputLabel) ?? outputLabel
    recursive = try c.decodeIfPresent(Bool.self, forKey: .recursive) ?? recursive
    processExisting = try c.decodeIfPresent(Bool.self, forKey: .processExisting) ?? processExisting
    mode = try c.decodeIfPresent(AutomationMode.self, forKey: .mode) ?? mode
    privacyReview = try c.decodeIfPresent(Bool.self, forKey: .privacyReview) ?? privacyReview
    resizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .resizeEnabled) ?? resizeEnabled
    convertEnabled = try c.decodeIfPresent(Bool.self, forKey: .convertEnabled) ?? convertEnabled
    compressionEnabled =
      try c.decodeIfPresent(Bool.self, forKey: .compressionEnabled) ?? compressionEnabled
    watermarkEnabled =
      try c.decodeIfPresent(Bool.self, forKey: .watermarkEnabled) ?? watermarkEnabled
    metadataEnabled = try c.decodeIfPresent(Bool.self, forKey: .metadataEnabled) ?? metadataEnabled
    configuration =
      try c.decodeIfPresent(ProcessingConfiguration.self, forKey: .configuration) ?? configuration
    profile = try c.decodeIfPresent(ExportProfile.self, forKey: .profile) ?? profile
    history = try c.decodeIfPresent(Set<String>.self, forKey: .history) ?? history
    pending = try c.decodeIfPresent([AutomationJob].self, forKey: .pending) ?? pending
    failures = try c.decodeIfPresent([AutomationJob].self, forKey: .failures) ?? failures
    completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? completed
    lastActivity = try c.decodeIfPresent(Date.self, forKey: .lastActivity)
    error = try c.decodeIfPresent(String.self, forKey: .error)
  }
}
public struct AutomationJob: Codable, Sendable, Identifiable {
  public var id = UUID()
  public var source: SourceAsset
  public var digest: String
  public var configuration: ProcessingConfiguration
  public var error: String?
  public init(source: SourceAsset, digest: String, configuration: ProcessingConfiguration) {
    self.source = source
    self.digest = digest
    self.configuration = configuration
  }
}
public enum AutomationSafety {
  /// Reject either nesting direction, including aliases, across EVERY workflow.
  public static func overlaps(_ first: URL, _ second: URL) -> Bool {
    let a = first.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let b = second.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    return a.starts(with: b) || b.starts(with: a)
  }
}
public struct FileStabilityTracker: Sendable {
  private var observed: [URL: (SourceFingerprint, Date)] = [:]
  public init() {}
  public mutating func stable(
    _ url: URL, fingerprint: SourceFingerprint, now: Date = Date(), minimumAge: TimeInterval = 2
  ) -> Bool {
    if let previous = observed[url], previous.0 == fingerprint {
      return fingerprint.bytes > 0 && now.timeIntervalSince(previous.1) >= minimumAge
    }
    observed[url] = (fingerprint, now)
    return false
  }
}

public struct AutomationLedger: Codable, Sendable {
  public var version = 1
  public var recipes: [AutomationRecipe]
  public init(recipes: [AutomationRecipe]) { self.recipes = recipes }
}

extension AutomationRecipe {
  /// Fixed action order; disabled actions are neutralized for both testing and publication.
  public func processingConfiguration(sourceFormat: OutputFormat?) throws -> ProcessingConfiguration
  {
    var c = configuration
    guard resizeEnabled || (c.crop.framing != .smart && c.crop.framing != .keepSubjects) else {
      throw ProcessingError.invalidConfiguration
    }
    if !resizeEnabled {
      c.crop.mode = .preserveAspectRatio
      c.resizeBasis = .percentage
      c.percentage = 100
    }
    if !watermarkEnabled { c.watermark.enabled = false }
    if !compressionEnabled {
      c.quality = 1
      c.targetBytes = nil
    }
    if !metadataEnabled { c.metadata = .preserve }
    if !convertEnabled {
      guard let sourceFormat, ImageProcessor.outputFormats.contains(sourceFormat) else {
        throw ProcessingError.unsupportedFormat
      }
      c.format = sourceFormat
    }
    return c
  }
}
