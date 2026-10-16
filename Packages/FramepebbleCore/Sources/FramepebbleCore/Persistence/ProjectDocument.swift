import Foundation

public struct ProcessingJob: Codable, Sendable {
    public var id: UUID
    public var sourceID: UUID; public var output: URL?; public var error: String?
    public init(id: UUID = UUID(), sourceID: UUID, output: URL? = nil, error: String? = nil) { self.id = id; self.sourceID = sourceID; self.output = output; self.error = error }
    private enum CodingKeys: String, CodingKey { case id, sourceID, output, error }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(); sourceID = try c.decode(UUID.self, forKey: .sourceID); output = try c.decodeIfPresent(URL.self, forKey: .output); error = try c.decodeIfPresent(String.self, forKey: .error) }
}
public struct ExportRequest: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var source: SourceAsset
    public var configuration: ProcessingConfiguration
    public var profile: ExportProfile
    public init(source: SourceAsset, configuration: ProcessingConfiguration, profile: ExportProfile) { self.source = source; self.configuration = configuration; self.profile = profile }
}
public struct ProjectDocument: Codable, Sendable {
    /// Sources remain owned by this project even when removed from its visible workspace.
    public var conversionInputIDs: Set<UUID>?
    public var conversionResizingEnabled: Bool?
    public var hiddenSourceIDs: Set<UUID> = []
    public var savedGIFs: [GIFProject] = []
    public var gifProject: GIFProject?
    public var workspaceSelection: [UUID] = []
    public var name = "Untitled Project"
    public var version = 4
    /// Optional UI session state; sources and edits remain independent of open tabs.
    public var batchInputIDs: Set<UUID>?
    public var editorTabIDs: [UUID] = []
    public var activeEditorPhotoID: UUID?
    public var sources: [SourceAsset] = []
    public var edits = EditingSnapshot()
    public var favourites: Set<UUID> = []
    public var classifications = ClassificationIndex()
    public var privacyCoverageReviewIDs: Set<UUID> = []
    public var proposals: [UUID: FramingProposal] = [:]
    public var profiles: [ExportProfile] = []
    public var namingTemplate = "{name}{suffix}"
    public var selectedProfiles: Set<UUID> = []
    public var privateEditing = false
    public var requirePrivacyReview = false
    public var collageOutputs: [URL] = []
    public var collage: CollageProject?
    public var collages: [SavedCollage] = []
    public var openCollageIDs: [UUID] = []
    public var activeCollageID: UUID?
    public var watermarkPresets: [WatermarkConfiguration] = []
    public var pendingExports: [ExportRequest] = []
    public var completedJobs: [ProcessingJob] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case conversionInputIDs, conversionResizingEnabled, hiddenSourceIDs, savedGIFs, gifProject, workspaceSelection, batchInputIDs, name, privacyCoverageReviewIDs, collages, openCollageIDs, activeCollageID, version, editorTabIDs, activeEditorPhotoID, sources, edits, favourites, classifications, proposals, profiles, namingTemplate, selectedProfiles, watermarkPresets, privateEditing, requirePrivacyReview, collageOutputs, collage, pendingExports, completedJobs }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        conversionInputIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .conversionInputIDs)
        conversionResizingEnabled = try c.decodeIfPresent(Bool.self, forKey: .conversionResizingEnabled)
        hiddenSourceIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .hiddenSourceIDs) ?? []
        savedGIFs = try c.decodeIfPresent([GIFProject].self, forKey: .savedGIFs) ?? []
        gifProject = try c.decodeIfPresent(GIFProject.self, forKey: .gifProject)
        workspaceSelection = try c.decodeIfPresent([UUID].self, forKey: .workspaceSelection) ?? []
        batchInputIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .batchInputIDs)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? version
        editorTabIDs = try c.decodeIfPresent([UUID].self, forKey: .editorTabIDs) ?? []
        activeEditorPhotoID = try c.decodeIfPresent(UUID.self, forKey: .activeEditorPhotoID)
        privacyCoverageReviewIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .privacyCoverageReviewIDs) ?? []
        sources = try c.decodeIfPresent([SourceAsset].self, forKey: .sources) ?? sources
        edits = try c.decodeIfPresent(EditingSnapshot.self, forKey: .edits) ?? edits
        favourites = try c.decodeIfPresent(Set<UUID>.self, forKey: .favourites) ?? favourites
        classifications = try c.decodeIfPresent(ClassificationIndex.self, forKey: .classifications) ?? classifications
        proposals = try c.decodeIfPresent([UUID: FramingProposal].self, forKey: .proposals) ?? proposals
        profiles = try c.decodeIfPresent([ExportProfile].self, forKey: .profiles) ?? profiles
        namingTemplate = try c.decodeIfPresent(String.self, forKey: .namingTemplate) ?? namingTemplate
        selectedProfiles = try c.decodeIfPresent(Set<UUID>.self, forKey: .selectedProfiles) ?? selectedProfiles
        privateEditing = try c.decodeIfPresent(Bool.self, forKey: .privateEditing) ?? false
        requirePrivacyReview = try c.decodeIfPresent(Bool.self, forKey: .requirePrivacyReview) ?? false
        collageOutputs = try c.decodeIfPresent([URL].self, forKey: .collageOutputs) ?? []
        collages = try c.decodeIfPresent([SavedCollage].self, forKey: .collages) ?? []
        openCollageIDs = try c.decodeIfPresent([UUID].self, forKey: .openCollageIDs) ?? []
        activeCollageID = try c.decodeIfPresent(UUID.self, forKey: .activeCollageID)
        collage = try c.decodeIfPresent(CollageProject.self, forKey: .collage)
        watermarkPresets = try c.decodeIfPresent([WatermarkConfiguration].self, forKey: .watermarkPresets) ?? watermarkPresets
        pendingExports = try c.decodeIfPresent([ExportRequest].self, forKey: .pendingExports) ?? pendingExports
        completedJobs = try c.decodeIfPresent([ProcessingJob].self, forKey: .completedJobs) ?? completedJobs
    }
    public static func load(_ url: URL) throws -> ProjectDocument {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let data = try Data(contentsOf: url); var value = try JSONDecoder().decode(ProjectDocument.self, from: data)
        guard (2...4).contains(value.version), Set(value.sources.map(\.id)).count == value.sources.count, Set(value.profiles.map(\.id)).count == value.profiles.count, value.sources.allSatisfy({ $0.url.isFileURL }), value.collageOutputs.allSatisfy(\.isFileURL), value.completedJobs.allSatisfy({ $0.output?.isFileURL ?? true }) else { throw CocoaError(.coderReadCorrupt) }; value.edits.migrateLegacyOverrides(); value.version = 4; return value
    }
    public func save(_ url: URL) throws { guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }; try JSONEncoder().encode(self).write(to: url, options: .atomic) }
}
public actor ProjectStore {
    public init() {}
    public func load(_ url: URL) throws -> ProjectDocument { try ProjectDocument.load(url) }
    public func save(_ document: ProjectDocument, to url: URL) throws { try Task.checkCancellation(); try document.save(url) }
}
