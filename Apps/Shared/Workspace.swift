import SwiftUI
import FramepebbleCore
import UniformTypeIdentifiers

enum WorkspaceMode: String, CaseIterable { case browse = "Browse", frame = "Frame", compare = "Compare" }
enum LibraryScope: String, CaseIterable { case exceptions = "Individual Overrides", all = "Workspace", favourites = "Favourites", edited = "Edited", review = "Needs Review", privacyReview = "Privacy Review" }
enum ApplyScope: String, CaseIterable { case all = "All images", selected = "Selected images", results = "Search results", individual = "Current image" }

@MainActor @Observable final class Workspace {
    var workflow: StudioWorkflow = .batch
    var browsingLibrary = false
    var batchGalleryMode: WorkspaceMode = .browse
    var galleryFocusToken = 0
    var selectionAnchor: UUID?
    var copiedEdits: ConfigurationPatch?
    let defaultProfileID = UUID()
    var previewProfileID: UUID?
    var projectName = "Untitled Project" { didSet { persist() } }
    var assets: [SourceAsset] = []
    var editorTabs: [UUID] = []
    var editorPhotoID: UUID?
    var editorTools: [UUID: (precision: Bool, inspector: InspectorTask)] = [:]
    var activePhotoID: UUID?
    /// Legacy UI accessor; active photo and the explicit selected-ID set are independent.
    var selected: UUID? { get { workflow == .photo && !browsingLibrary ? editorPhotoID ?? activePhotoID : activePhotoID } set { if workflow == .photo && !browsingLibrary { editorPhotoID = newValue } else { activePhotoID = newValue } } }
    var selection: Set<UUID> = [] { didSet { selectionOrder.removeAll { !selection.contains($0) }; selectionOrder.append(contentsOf: assets.map(\.id).filter { selection.contains($0) && !selectionOrder.contains($0) }) } }
    var selecting = false
    var selectionOrder: [UUID] = []
    var workspaceFilter = WorkspaceFilter() { didSet { reconcileVisibleSelection() } }
    var photoInfo: [UUID: WorkspacePhotoInfo] = [:]
    var mode: WorkspaceMode = .browse
    var library: LibraryScope = .all { didSet { reconcileVisibleSelection() } }
    var query = "" { didSet { reconcileVisibleSelection() } }
    var tileSize: Double = 190
    var batchInputIDs: Set<UUID>?
    var scope: ApplyScope = .all { didSet { if scope != .selected { batchInputIDs = nil } } }
    var inspectorTask: InspectorTask = .resize
    var cropAspectLocks: [UUID: Bool] = [:]
    var cropKeepsOutputSize: [UUID: Bool] = [:]
    var precision = false
    var thumbnailEditing = false
    var overlayEditor = false
    var overlayStartsWithMasks = true
    var overlaySession: OverlayEditingSession?
    var pendingOverlayDestination: EditorDestination?
    var collageEditor = false
    var collageOutputs: [URL] = []
    var collage = CollageProject()
    var collageDocuments: [SavedCollage] = []
    var openCollageIDs: [UUID] = []
    var activeCollageID: UUID?
    var collageHistories: [UUID: ([CollageProject],[CollageProject])] = [:]
    let collageArtBuilder = CollageArtBuilder()
    var collageGenerationTask: Task<Void,Never>?
    var collageGenerating = false
    var collageArtProgress = CollageArtProgress("Preparing collage",0,1)
    var collageUndo: [CollageProject] = []
    var collageRedo: [CollageProject] = []
    var projectsView = false
    var helpPresented = false
    var sensitiveReviewPresented = false
    var sensitivity = SensitiveReviewState()
    var sensitivityAvailability: SensitiveAnalysisAvailability = .unavailable("Checking capability…")
    var sensitivityTask: Task<Void, Never>?
    var sensitivityCompleted = 0
    var sensitivityTotal = 0
    var sensitivityStatus = ""
    var pendingPrivacyEditor: EditorDestination?
    let sensitiveAnalyzer: any SensitiveImageAnalyzing
    let sensitivityProcessor = ImageProcessor()
    var sharingSession: ShareOutputSession?
    var copySourceID: UUID?
    func beginSharing(_ outputs: [URL]) {
        sharingSession = outputs.isEmpty ? nil : ShareOutputSession(outputs: outputs, summary: status)
        if outputs.isEmpty { status = "No new output succeeded; nothing to share." }
    }
    var requirePrivacyReview = false { didSet { persist() } }
    var skipDuplicates = true
    var duplicates = DuplicateIndex()
    var clearingWorkspace = false
    var concealed = false
    var privateEditing = false { didSet { Task { await processor.setPrivateMode(privateEditing) }; persist() } }
    var showGuides = true
    var showSubjects = false
    var favourites: Set<UUID> = []
    var edits = EditingSnapshot()
    var history = EditingHistory()
    var historyPresented = false
    var index = ClassificationIndex()
    var proposals: [UUID: FramingProposal] = [:]
    var privacyCoverageReviewIDs: Set<UUID> = []
    var profiles: [ExportProfile] = []
    var watermarkPresets: [WatermarkConfiguration] = []
    var results: [ProcessingResult] = []
    var status = "Your photos. Your way."
    var issues: [String] = []
    var total = 0
    var completed = 0
    var running = false
    var exportingPlanSummary: String?
    var exportingRequests: [ExportRequest] = []
    var quickFixTask: Task<Void, Never>?
    var quickFixRunning = false
    var quickFixCompleted = 0
    var quickFixTotal = 0
    var analysing = false
    var analysisCompleted = 0
    var analysisTotal = 0
    var indexed = 0
    var collageTask: Task<Void, Never>?
    var importTask: Task<Void, Never>?
    var importing = false
    var fileImportTask: Task<Void, Never>?
    var importDiscovered = 0
    var importCompleted = 0
    var importSkipped = 0
    var importFailed = 0
    var importBytes: Int64 = 0
    var importSize: Int64 = 0
    var importMessage = "Receiving images…"
    private var importGeneration = 0
    private var pendingImportedAssets: [SourceAsset] = []
    private var importPublicationTask: Task<Void, Never>?
    private var publishedFirstImport = false
    private func publishPendingImports() {
        importPublicationTask?.cancel(); importPublicationTask = nil
        guard !pendingImportedAssets.isEmpty else { return }
        assets.append(contentsOf: pendingImportedAssets)
        selected = selected ?? pendingImportedAssets.first?.id
        pendingImportedAssets.removeAll(keepingCapacity: true)
        publishedFirstImport = true
        persist()
    }
    var isImporting: Bool { importing || fileImportTask != nil }
    let sourceImporter = SourceImporter()
    func cancelImport() { importGeneration += 1; importTask?.cancel(); fileImportTask?.cancel() }
    var task: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var indexingTask: Task<Void, Never>?
    var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = UUID()
    var lastDestination: URL?
    var pendingExports: [ExportRequest] = []
    var exportProfiles: Set<UUID> = [] { didSet { persist() } }
    var namingTemplate = "{name}{suffix}" { didSet { persist() } }
    private var interactionStart: EditingSnapshot?
    private var started = false
    @ObservationIgnored private var visibleIDs: Set<UUID> = []
    let processor = ImageProcessor()
    let analyzer = VisionAnalyzer()
    let store = ProjectStore()
    let directory: URL
    let isReviewSession: Bool
    let projectURL: URL
    init(directory: URL? = nil, sensitiveAnalyzer: any SensitiveImageAnalyzing = AppleSensitiveAnalyzer(), startInLibrary: Bool = false) {
        self.sensitiveAnalyzer = sensitiveAnalyzer
        browsingLibrary = startInLibrary
        #if DEBUG
        let arguments = CommandLine.arguments
        let reviewPosition = arguments.firstIndex(of: "-FramepebbleReviewRoot")
        let reviewRoot = reviewPosition.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1], isDirectory: true) : nil }
        #else
        let reviewRoot: URL? = nil
        #endif
        isReviewSession = directory == nil && reviewRoot != nil
        let root = directory ?? reviewRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Framepebble", isDirectory: true)
        self.directory = root.appendingPathComponent("Sources", isDirectory: true)
        projectURL = root.appendingPathComponent("Session.json")
        do { try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true) } catch { status = error.localizedDescription }
        profiles = Self.defaultProfiles()
    }
    var settings: ProcessingConfiguration {
        get { edits.settings }
        set {
            if Double(max(1, newValue.width)) / Double(max(1, newValue.height)) != Double(max(1, edits.settings.width)) / Double(max(1, edits.settings.height)) {
                for (id, override) in edits.overrides { var proposal = proposals[id] ?? FramingProposal(crop: override.crop, subjects: [], reviewReasons: []); proposal.reviewReasons.append("Output aspect changed; previous framing intent is preserved. Review this image."); proposals[id] = proposal }
            }
            var next = edits; next.settings = newValue
            let delta = newValue.quarterTurns - edits.settings.quarterTurns
            if delta != 0 || newValue.flipHorizontal != edits.settings.flipHorizontal || newValue.flipVertical != edits.settings.flipVertical || newValue.straighten != edits.settings.straighten {
                for (id, override) in edits.overrides {
                    var proposal = proposals[id] ?? FramingProposal(crop: override.crop, subjects: [], reviewReasons: [])
                    proposal.subjects = []; proposal.reviewReasons.append("Source orientation changed; review the retained framing."); proposals[id] = proposal
                }
            }
            commit(next)
        }
    }
    var current: SourceAsset? { (workflow == .photo && !browsingLibrary ? assets : filtered).first { $0.id == selected } }
    var filtered: [SourceAsset] {
        let emptyQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Common gallery path is O(1): no full-array copy, UUID dictionary or classification pass.
        if library == .all && emptyQuery && !workspaceFilter.isActive { return assets }
        let privacyIDs = library == .privacyReview ? sensitivity.flagged : []
        let base = library == .all ? assets : assets.filter { asset in
            switch library {
            case .all: true
            case .exceptions: edits.overrides[asset.id] != nil
            case .favourites: favourites.contains(asset.id)
            case .edited: isEdited(asset.id)
            case .review: proposals[asset.id]?.needsReview == true || privacyCoverageNeedsReview(asset.id)
            case .privacyReview: privacyIDs.contains(asset.id) || privacyCoverageNeedsReview(asset.id)
            }
        }
        let narrowed = workspaceFilter.apply(to: base, information: photoInfo)
        if emptyQuery { return narrowed }
        let recognised = Set(index.matches(query: query, candidates: narrowed.map(\.id)))
        let ids = narrowed.filter { recognised.contains($0.id) || $0.name.localizedCaseInsensitiveContains(query) }.map(\.id)
        let lookup = Dictionary(uniqueKeysWithValues: narrowed.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }
    var targets: [SourceAsset] {
        if browsingLibrary { return [] }
        if workflow == .photo { return current.map { [$0] } ?? [] }
        if workflow == .automations || workflow == .collages { return [] }
        if let ids = batchInputIDs { return assets.filter { ids.contains($0.id) } }
        return switch scope { case .all: assets; case .selected: assets.filter { selection.contains($0.id) }; case .results: filtered; case .individual: current.map { [$0] } ?? [] }
    }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    func configuration(for asset: SourceAsset) -> ProcessingConfiguration { edits.configuration(for: asset.id) }
    var gallerySummary: String {
        let visible = filtered.count
        let photos = "\(visible) " + (visible == 1 ? "photo" : "photos")
        return selecting || scope == .selected ? photos + " · \(selection.count) selected (\(selection.subtracting(Set(filtered.map(\.id))).count) hidden)" : photos
    }
    var targetSummary: String {
        let count = targets.count
        return workflow == .photo ? "Editor · " + (current?.name ?? "Choose a photo") : "\(count) " + (count == 1 ? "photo" : "photos") + " · " + scope.rawValue
    }
    func toggleSelectionMode() {
        selecting.toggle()
        if selecting { scope = .selected }
    }
    func selectVisiblePhotos() { selection.formUnion(filtered.map(\.id)); selecting = true; scope = .selected }
    func select(_ asset: SourceAsset) {
        galleryFocusToken += 1
        selected = asset.id
        if selecting { if selection.contains(asset.id) { selection.remove(asset.id) } else { selection.insert(asset.id) } }
        else { selection = [asset.id] }
        selectionAnchor = asset.id
    }
    func navigate(_ delta: Int) {
        let visible = workflow == .photo && !browsingLibrary ? openEditorPhotos : filtered; guard !visible.isEmpty else { return }
        let pos = visible.firstIndex { $0.id == selected } ?? 0
        let id = visible[min(visible.count - 1, max(0, pos + delta))].id
        if workflow == .photo && !browsingLibrary { activateEditorTab(id) } else { selected = id }
    }
    func commit(_ next: EditingSnapshot, title: String? = nil) {
        if next != edits && mode == .browse { mode = .frame }
        if interactionStart == nil { markPrivacyCoverageChanges(from: edits, to: next) }
        var label = title
        if label == nil && next.settings == edits.settings {
            let changed = Set(next.overrides.keys).union(edits.overrides.keys).filter { next.overrides[$0] != edits.overrides[$0] }
            if changed.count == 1, let id = changed.first, let asset = assets.first(where: { $0.id == id }) {
                let fields = ConfigurationPatch(from: edits.configuration(for: id), to: next.configuration(for: id)).fields
                let details = fields.count == 1 ? fields.first?.displayName ?? "Edit" : Set(fields.map { $0.category.rawValue }).sorted().joined(separator: ", ")
                label = asset.name + " · " + details
            }
        }
        edits = next
        if interactionStart == nil { history.apply(next, title: label); persist() }
    }
    func beginInteraction() { if interactionStart == nil { interactionStart = edits } }
    func endInteraction() { guard let start = interactionStart else { return }; markPrivacyCoverageChanges(from: start, to: edits); interactionStart = nil; history.apply(edits); persist() }
    func setCrop(_ crop: CropConfiguration, for id: UUID, manual: Bool = true) {
        var value = crop
        if manual { value.framing = .manual }
        var before = edits.configuration(for: id); let old = before
        before.crop = value
        var next = edits; next.apply(ConfigurationPatch(from: old, to: before), to: id); commit(next)
        if manual { proposals.removeValue(forKey: id) }
    }
    func changeConfiguration(_ value: ProcessingConfiguration) {
        applyChange(ConfigurationPatch(from: controlConfiguration, to: value))
    }
    func applyChange(_ change: ConfigurationPatch, ids: Set<UUID>? = nil) {
        guard !change.fields.isEmpty else { return }
        if ids == nil && scope == .all && workflow == .batch {
            settings = change.applying(to: settings)
        } else {
            var next = edits
            for id in (ids ?? Set(targets.map(\.id))).intersection(Set(assets.map(\.id))) { next.apply(change, to: id) }
            commit(next)
        }
    }
    var controlConfiguration: ProcessingConfiguration {
        get { workflow == .batch && scope == .all ? settings : targets.first.map { configuration(for: $0) } ?? settings }
        set { changeConfiguration(newValue) }
    }
    func updateField<T>(_ key: WritableKeyPath<ProcessingConfiguration, T>, value: T, fields: Set<ConfigurationField>) {
        var config = controlConfiguration; config[keyPath: key] = value
        applyChange(ConfigurationPatch(values: config, fields: fields))
    }
    var mixedFields: Set<ConfigurationField> {
        if workflow == .batch && scope == .all { return [] }
        guard let first = targets.first else { return [] }
        let initial = configuration(for: first)
        return targets.dropFirst().reduce(into: []) { $0.formUnion(ConfigurationPatch(from: initial, to: configuration(for: $1)).fields) }
    }
    func isEdited(_ id: UUID) -> Bool { edits.configuration(for: id) != ProcessingConfiguration() }
    func setImageAspect(_ ratio: Double, for id: UUID) {
        guard ratio.isFinite, ratio > 0 else { return }
        let c = edits.configuration(for: id)
        let height = Double(c.width) / ratio
        guard height.isFinite, height >= 1, height <= 20000 else { issues.append("This aspect ratio exceeds output dimension limits."); return }
        var updated = c; updated.crop.mode = .manualCrop; updated.crop.framing = .manual; updated.crop.aspectRatio = ratio
        var next = edits; next.apply(ConfigurationPatch(from: c, to: updated), to: id)
        next.overrides[id]?.dimensions = PixelDimensions(width: c.width, height: Int(height), followsBatchWidth: true)
        commit(next)
    }
    func setImageConfiguration(_ value: ProcessingConfiguration, for id: UUID) {
        var next = edits; next.apply(ConfigurationPatch(from: configuration(forID: id), to: value), to: id); commit(next)
    }
    func configuration(forID id: UUID) -> ProcessingConfiguration { edits.configuration(for: id) }
    func reset(_ ids: Set<UUID>) { resetCategories([.framing], ids: ids) }
    func resetCategories(_ categories: Set<EditCategory>, ids: Set<UUID>) {
        var next = edits
        for id in ids { next.reset(categories, for: id); if categories.contains(.framing) { proposals.removeValue(forKey: id) } }
        commit(next)
    }
    func resetAllImageEdits(_ ids:Set<UUID>) { var next=edits;for id in ids {next.overrides.removeValue(forKey:id);proposals.removeValue(forKey:id)};commit(next) }
    func undo() { let previous = edits; history.undo(); edits = history.current; flagChangedFraming(previous); persist() }
    func redo() { let previous = edits; history.redo(); edits = history.current; flagChangedFraming(previous); persist() }
    func flagChangedFraming(_ previous: EditingSnapshot) {
        markPrivacyCoverageChanges(from: previous, to: edits)
        for asset in assets where previous.configuration(for: asset.id).crop != edits.configuration(for: asset.id).crop {
            proposals[asset.id] = FramingProposal(crop: edits.configuration(for: asset.id).crop, subjects: [], reviewReasons: ["Framing history changed; verify this crop."])
        }
    }
    func toggleFavourite(_ id: UUID) { if favourites.contains(id) { favourites.remove(id) } else { favourites.insert(id) }; persist() }
    func acceptReview(_ id: UUID) { proposals[id]?.reviewReasons.removeAll { $0 != Self.privacyCoverageReason }; persist() }
    func applyPreset(_ profile: ExportProfile) { namingTemplate = profile.namingTemplate; if let config = profile.processing { applyChange(ConfigurationPatch(values: config, fields: Set(ConfigurationField.allCases.filter { $0.category != .privacy && $0.category != .annotations }))) } }
    func saveProfile(name: String) { guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }; var p = ExportProfile(); p.name = name; var saved = controlConfiguration; saved.masks = []; saved.annotations = []; saved.privacyExport = false; p.processing = saved; p.namingTemplate = namingTemplate; p.suffix = "-" + name; profiles.append(p); persist() }
    func changeCollage(_ proposed: CollageProject) {
        var value = proposed
        let geometryChanged = value.cells != collage.cells || value.width != collage.width || value.height != collage.height || value.spacing != collage.spacing || value.silhouette != collage.silhouette || value.title.isEmpty != collage.title.isEmpty
        if geometryChanged && value.cells.contains(where: { !configuration(forID: $0.sourceID).masks.isEmpty }) { value.requiresPrivacyReview = true }
        guard value != collage else { return }
        collageUndo.append(collage); if collageUndo.count > 80 { collageUndo.removeFirst() }
        collageRedo=[]; collage=value; persist()
    }
    func undoCollage() { guard let last=collageUndo.popLast() else{return};collageRedo.append(collage);collage=last;persist() }
    func redoCollage() { guard let next=collageRedo.popLast() else{return};collageUndo.append(collage);collage=next;persist() }
    func quickFix(_ fix: QuickFix) {
        guard !quickFixRunning, !running, !overlayEditor else { return }
        let jobs = targets.map { ($0, configuration(for: $0)) }
        guard !jobs.isEmpty else { return }
        quickFixRunning = true; quickFixCompleted = 0; quickFixTotal = jobs.count
        quickFixTask = Task {
            defer { quickFixRunning = false }
            var proposals: [QuickFixUpdate] = []
            do {
                for (asset, before) in jobs {
                    try Task.checkCancellation()
                    do {
                        let value = try await processor.quickFix(fix, url: asset.url, configuration: before)
                        proposals.append(QuickFixUpdate(asset: asset, before: before, after: value))
                    } catch is CancellationError { throw CancellationError() }
                    catch { issues.append("Quick Fix could not process a photo: " + error.localizedDescription) }
                    quickFixCompleted += 1
                }
                try Task.checkCancellation()
                applyQuickFixUpdates(proposals, title: fix.rawValue)
            } catch is CancellationError { status = "Quick Fix cancelled. No automatic changes were applied." }
            catch { issues.append(error.localizedDescription) }
        }
    }
    struct QuickFixUpdate {
        var asset: SourceAsset
        var before: ProcessingConfiguration
        var after: ProcessingConfiguration
    }
    /// Merge once, preserving edits made while analysis was running, even to the
    /// same field. One requested batch action creates one named Undo step.
    func applyQuickFixUpdates(_ updates: [QuickFixUpdate], title: String) {
        var next = edits
        var skipped = 0
        for update in updates where assets.contains(where: { $0.id == update.asset.id && $0.url == update.asset.url }) {
            let current = next.configuration(for: update.asset.id)
            let changedByUser = ConfigurationPatch(from: update.before, to: current).fields
            var automatic = ConfigurationPatch(from: update.before, to: update.after)
            if !automatic.fields.isDisjoint(with: changedByUser) { skipped += 1 }
            automatic.fields.subtract(changedByUser)
            if !automatic.fields.isEmpty { next.apply(automatic, to: update.asset.id) }
        }
        commit(next, title: title + " · \(updates.count) photos")
        status = skipped == 0 ? title + " completed. Undo restores the whole operation." : "Quick Fix completed; newer manual values were kept for \(skipped) photos."
    }
    func saveWatermarkPreset() { watermarkPresets.append(controlConfiguration.watermark); persist() }
    static func defaultProfiles() -> [ExportProfile] {
        [("AI Training",1024,1024,CropMode.fill),("Social Media",1080,1350,.fill),("Website",1920,1080,.fit),("Product Photos",1600,1600,.canvas),("Print",3840,2160,.fit),("Photography Proofs",1200,800,.fit)].map { name,w,h,mode in
            var profile = ExportProfile(); profile.name = name; profile.suffix = "-" + name.lowercased().replacingOccurrences(of: " ", with: "-")
            var c = ProcessingConfiguration(); c.width = w; c.height = h; c.crop.mode = mode
            if name == "Website" { c.quality = 0.75 }; if name == "Product Photos" { c.background = RGBAColour(1,1,1,1) }; if name == "Photography Proofs" { c.watermark.enabled = true }
            profile.processing = c; return profile
        }
    }
    func start() async {
        guard !started else { return }; started = true
        if FileManager.default.fileExists(atPath: projectURL.path) {
            do {
                let doc = relocate(try await store.load(projectURL)); if doc.privateEditing { concealed = true }; projectName = doc.name; batchInputIDs = doc.batchInputIDs; if batchInputIDs != nil { scope = .selected }; assets = doc.sources; for asset in assets { _ = try? await duplicates.insert(asset.url) }; edits = doc.edits; history = EditingHistory(snapshot: edits); favourites = doc.favourites; index = doc.classifications; proposals = doc.proposals; privacyCoverageReviewIDs = doc.privacyCoverageReviewIDs; profiles = doc.profiles; namingTemplate = doc.namingTemplate; exportProfiles = doc.selectedProfiles; watermarkPresets = doc.watermarkPresets; collage = doc.collage ?? CollageProject(); collageOutputs = doc.collageOutputs; privateEditing = doc.privateEditing; requirePrivacyReview = doc.requirePrivacyReview; pendingExports = doc.pendingExports
                results = doc.completedJobs.compactMap { job in guard let source = assets.first(where: { $0.id == job.sourceID }) else { return nil }; var result = ProcessingResult(source: source, output: job.output, error: job.error); result.id = job.id; return result }
                selected = assets.first?.id
                restoreEditorTabs(doc)
                restoreCollageDocuments(doc)
                let missing = assets.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
                for asset in missing { issues.append("Missing source: \(asset.name). Reimport the original to continue.") }
                status = "Restored \(assets.count) images."
            } catch { issues.append("Session could not be restored: \(error.localizedDescription)") }
        }
        startIndexing()
    }
    /// iOS updates can move the app container. Private snapshots are resolved relative to this session.
    func relocate(_ document: ProjectDocument) -> ProjectDocument {
        func local(_ url: URL?) -> URL? {
            guard let url else { return nil }
            let parent = url.deletingLastPathComponent().lastPathComponent
            guard parent == "Sources" || parent == "Exports" else { return url }
            let root = parent == "Sources" ? directory : directory.deletingLastPathComponent().appendingPathComponent("Exports")
            let candidate = root.appendingPathComponent(url.lastPathComponent)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : url
        }
        func config(_ original: ProcessingConfiguration) -> ProcessingConfiguration { var value = original; value.watermark.imageURL = local(value.watermark.imageURL); return value }
        var doc = document
        for position in doc.sources.indices { doc.sources[position].url = local(doc.sources[position].url) ?? doc.sources[position].url }
        doc.edits.settings = config(doc.edits.settings)
        for id in Array(doc.edits.overrides.keys) {
            if let c = doc.edits.overrides[id]?.processing { doc.edits.overrides[id]?.processing = config(c) }
            if let patch = doc.edits.overrides[id]?.patch { doc.edits.overrides[id]?.patch?.values = config(patch.values) }
        }
        for position in doc.profiles.indices { if let c = doc.profiles[position].processing { doc.profiles[position].processing = config(c) } }
        doc.collageOutputs = doc.collageOutputs.map { local($0) ?? $0 }
        for position in doc.watermarkPresets.indices { doc.watermarkPresets[position].imageURL = local(doc.watermarkPresets[position].imageURL) }
        for position in doc.pendingExports.indices { doc.pendingExports[position].source.url = local(doc.pendingExports[position].source.url) ?? doc.pendingExports[position].source.url; doc.pendingExports[position].configuration = config(doc.pendingExports[position].configuration); if let c = doc.pendingExports[position].profile.processing { doc.pendingExports[position].profile.processing = config(c) } }
        for position in doc.completedJobs.indices { doc.completedJobs[position].output = local(doc.completedJobs[position].output) }
        return doc
    }
    func document() -> ProjectDocument {
        var doc = ProjectDocument(); doc.name = projectName; doc.batchInputIDs = batchInputIDs; doc.editorTabIDs = editorTabs; doc.activeEditorPhotoID = editorPhotoID; doc.sources = assets; doc.edits = edits; doc.favourites = favourites; doc.classifications = index; doc.proposals = proposals; doc.privacyCoverageReviewIDs = privacyCoverageReviewIDs; doc.profiles = profiles; doc.namingTemplate = namingTemplate; doc.selectedProfiles = exportProfiles; doc.watermarkPresets = watermarkPresets; doc.collage = collage; doc.collages = savedCollages; doc.openCollageIDs = openCollageIDs; doc.activeCollageID = activeCollageID; doc.collageOutputs = collageOutputs; doc.privateEditing = privateEditing; doc.requirePrivacyReview = requirePrivacyReview; doc.pendingExports = pendingExports; doc.completedJobs = results.map { ProcessingJob(id: $0.id, sourceID: $0.source.id, output: $0.output, error: $0.error) }; return doc
    }
    var completedOutputs: [URL] { results.compactMap(\.output) + collageOutputs }
    func saveProjectCopy() async throws -> URL {
        let folder=directory.deletingLastPathComponent().appendingPathComponent("Projects",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let label=Date().formatted(.iso8601).replacingOccurrences(of:":",with:"-")
        let url=folder.appendingPathComponent("Project-"+label+"-"+UUID().uuidString.prefix(6)+".json");try await store.save(document(),to:url);return url
    }
    func stopWork() async { quickFixTask?.cancel(); await quickFixTask?.value; sensitivityTask?.cancel(); await sensitivityTask?.value; cancelImport(); await importTask?.value; await fileImportTask?.value; collageGenerationTask?.cancel(); await collageGenerationTask?.value; collageTask?.cancel(); await collageTask?.value; task?.cancel(); analysisTask?.cancel(); indexingTask?.cancel(); await task?.value; await analysisTask?.value; await indexingTask?.value }
    func newProject() async {
        guard !clearingWorkspace else { return }
        do { await stopWork(); _ = try await saveProjectCopy(); sensitivity = SensitiveReviewState();resetEditorTabs();resetCollageDocuments();projectName="Untitled Project";privacyCoverageReviewIDs=[];batchInputIDs=nil;assets=[];selected=nil;selection=[];favourites=[];duplicates=DuplicateIndex();edits=EditingSnapshot();history=EditingHistory();proposals=[:];index=ClassificationIndex();results=[];pendingExports=[];collage=CollageProject();collageOutputs=[];collageUndo=[];collageRedo=[];await flush();status="New project. Previous work remains in Recent Projects." } catch { issues.append("Could not preserve the previous project: \(error.localizedDescription)") }
    }
    func openProject(_ url:URL) async {
        guard !clearingWorkspace else { return }
        let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        do {
            let doc=relocate(try await store.load(url));if doc.privateEditing {concealed=true};await stopWork();_ = try await saveProjectCopy();sensitivity = SensitiveReviewState();resetEditorTabs();projectName=doc.name;batchInputIDs=doc.batchInputIDs;if batchInputIDs != nil {scope = .selected};assets=doc.sources;edits=doc.edits;history=EditingHistory(snapshot:edits);favourites=doc.favourites;index=doc.classifications;proposals=doc.proposals;privacyCoverageReviewIDs=doc.privacyCoverageReviewIDs;profiles=doc.profiles;collage=doc.collage ?? CollageProject();collageOutputs=doc.collageOutputs;collageUndo=[];collageRedo=[];pendingExports=doc.pendingExports;results=[];selected=assets.first?.id;selection=[];watermarkPresets=doc.watermarkPresets;namingTemplate=doc.namingTemplate;exportProfiles=doc.selectedProfiles;privateEditing=doc.privateEditing;requirePrivacyReview=doc.requirePrivacyReview
            restoreEditorTabs(doc)
            restoreCollageDocuments(doc)
            for asset in assets where !FileManager.default.fileExists(atPath:asset.url.path) {issues.append("Missing source: \(asset.name). Select it and use Projects → Relink.")};await flush();startIndexing()
        } catch {issues.append("Project could not be opened: \(error.localizedDescription)")}
    }
    func relinkSource(_ url:URL) async {
        guard !clearingWorkspace else { return }
        guard let id=selected,let i=assets.firstIndex(where:{$0.id==id}) else{return};sensitivity.invalidate(id);let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        do {var replacement=try await processor.importSnapshot(url,to:directory);replacement.id=id;assets[i]=replacement;if !configuration(for:replacement).masks.isEmpty {privacyCoverageReviewIDs.insert(id)};for j in pendingExports.indices where pendingExports[j].source.id==id {pendingExports[j].source=replacement};index.invalidate(id);proposals[id]=FramingProposal(crop:configuration(for:replacement).crop,subjects:[],reviewReasons:["Source relinked; verify retained edits."]);persist();startIndexing()}catch{issues.append(error.localizedDescription)}
    }
    func flush() async {
        publishPendingImports()
        persistenceGeneration = UUID()
        persistenceTask?.cancel(); persistenceTask = nil
        do { try await store.save(document(), to: projectURL) } catch { issues.append("Could not save session: \(error.localizedDescription)") }
    }
    func persist() {
        // Periodic checkpoints during large imports; capture the latest state at save time.
        // Repeated arrivals must not reschedule the checkpoint forever or snapshot arrays per file.
        if isImporting && persistenceTask != nil { return }
        persistenceTask?.cancel()
        let token = UUID(); persistenceGeneration = token
        let delay: Duration = isImporting ? .seconds(5) : .milliseconds(250)
        persistenceTask = Task {
            do {
                try await Task.sleep(for: delay); try Task.checkCancellation()
                let doc = document()
                try await store.save(doc, to: projectURL)
            } catch is CancellationError {} catch { issues.append("Could not save session: \(error.localizedDescription)") }
            if persistenceGeneration == token { persistenceTask = nil }
        }
    }
    func importURLs(_ urls: [URL]) async {
        guard !clearingWorkspace else { return }
        let generation = importGeneration
        while let active = fileImportTask { await active.value; await Task.yield(); if Task.isCancelled || generation != importGeneration { return } }
        guard !Task.isCancelled, generation == importGeneration else { return }
        publishedFirstImport = false
        importDiscovered = 0; importCompleted = 0; importSkipped = 0; importFailed = 0
        importBytes = 0; importSize = 0; importMessage = "Discovering images…"
        let operation = Task { [self] in
            do {
                try await sourceImporter.run(urls, destination: directory) { [self] event in await receiveImport(event) }
                status = "Imported \(importCompleted) images · \(importSkipped) duplicates skipped · \(importFailed) failed."
            } catch is CancellationError { status = "Import cancelled. \(importCompleted) completed images are retained." }
            catch { issues.append("Import failed: \(error.localizedDescription)") }
        }
        fileImportTask = operation
        await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
        publishPendingImports()
        fileImportTask = nil
        importBytes = 0; importSize = 0
        persist(); startIndexing()
    }
    private func receiveImport(_ event: SourceImportEvent) async {
        switch event {
        case .discovered: importDiscovered += 1
        case .copying(let name, let bytes, let total):
            importMessage = privateEditing ? "Copying image locally…" : "Copying \(name)…"
            importBytes = bytes; importSize = total
        case .ready(let asset, let digest):
            let unique = await duplicates.insertDigest(digest)
            if skipDuplicates && !unique {
                importSkipped += 1
                try? await sourceImporter.removeOwnedSnapshot(asset.url, from: directory)
            } else {
                pendingImportedAssets.append(asset); importCompleted += 1
                if !publishedFirstImport || pendingImportedAssets.count >= 64 { publishPendingImports() }
                else if importPublicationTask == nil {
                    importPublicationTask = Task { do { try await Task.sleep(for: .milliseconds(150)); try Task.checkCancellation(); publishPendingImports() } catch {} }
                }
            }
            importMessage = "Discovering more images…"; importBytes = 0; importSize = 0
        case .failed(let name, let message):
            importFailed += 1; issues.append("Could not import \(name): \(message)")
        }
    }
    func importData(_ data: Data, name: String) async {
        guard !clearingWorkspace else { return }
        do { let a = try await processor.importData(data, name: name, to: directory); let unique = await duplicates.insert(data); if skipDuplicates && !unique { try? FileManager.default.removeItem(at: a.url); if importing { importSkipped += 1 }; status = "Duplicate skipped."; return }; assets.append(a); selected = selected ?? a.id; if importing { importCompleted += 1 }; status = "\(assets.count) photos in your workspace."; persist(); startIndexing() }
        catch { if importing { importFailed += 1 }; status = error.localizedDescription; issues.append(status) }
    }
    func visibility(_ id: UUID, visible: Bool) { if visible { visibleIDs.insert(id) } else { visibleIDs.remove(id) } }
    func startIndexing() {
        guard !isImporting else { return }
        indexingTask?.cancel()
        indexingTask = Task {
            let ordered = assets
            let lookup = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
            var pending = Set(lookup.keys)
            var cursor = 0
            while !pending.isEmpty {
                let priority = selected.flatMap { pending.contains($0) ? $0 : nil } ?? visibleIDs.first { pending.contains($0) }
                let id: UUID
                if let priority { id = priority }
                else {
                    while cursor < ordered.count && !pending.contains(ordered[cursor].id) { cursor += 1 }
                    guard cursor < ordered.count else { break }
                    id = ordered[cursor].id; cursor += 1
                }
                pending.remove(id)
                guard let asset = lookup[id] else { continue }
                if Task.isCancelled { return }
                do {
                    let fingerprint = try SourceFingerprint.read(asset.url)
                    if index.records[asset.id]?.fingerprint == fingerprint, index.records[asset.id]?.revision == VisionAnalyzer.classificationRevision { continue }
                    index.invalidate(asset.id)
                    let image = try await processor.thumbnail(asset.url, maximum: 600)
                    let record = try await analyzer.classify(image, asset: asset); try Task.checkCancellation(); index.insert(record); indexed = index.records.count
                } catch is CancellationError { return } catch { index.invalidate(asset.id); issues.append("Could not index \(asset.name): \(error.localizedDescription)") }
            }
            persist()
        }
    }
    func autoFrame(_ mode: FramingMode, replaceManual: Bool = false, targetIDs: Set<UUID>? = nil) {
        guard !analysing else { return }; let jobs = (targetIDs.map { ids in assets.filter { ids.contains($0.id) } } ?? targets).filter { replaceManual || configuration(for: $0).crop.framing != .manual }; analysing = true; analysisCompleted = 0; analysisTotal = jobs.count
        analysisTask = Task {
            defer { analysing = false; persist() }
            for asset in jobs {
                defer { analysisCompleted += 1 }
                if Task.isCancelled { return }
                let c = configuration(for: asset)
                if configuration(for: asset).crop.framing == .manual && !replaceManual { continue }
                do {
                    let image = try await processor.analysisThumbnail(asset.url, configuration: c, maximum: 900)
                    let proposal = try await analyzer.frame(image, ratio: Double(c.width) / Double(c.height), mode: mode)
                    try Task.checkCancellation()
                    guard configuration(for: asset) == c, assets.first(where: { $0.id == asset.id })?.url == asset.url else { continue }
                    let crop = c.crop.adoptingGeometry(proposal.crop)
                    setCrop(crop, for: asset.id, manual: false)
                    var stored = proposal; stored.crop = crop
                    let original = try await processor.identify(asset.url)
                    if original.width < CGFloat(c.width) || original.height < CGFloat(c.height) { stored.reviewReasons.append("Source resolution is smaller than the requested output.") }
                    if configuration(for: asset).crop == crop { proposals[asset.id] = stored }
                } catch is CancellationError { return } catch {
                    guard configuration(for: asset) == c, assets.first(where: { $0.id == asset.id })?.url == asset.url else { continue }
                    var crop = c.crop; crop.centerX = 0.5; crop.centerY = 0.5; crop.zoom = 1; crop.mode = .fill; crop.framing = mode; setCrop(crop, for: asset.id, manual: false)
                    proposals[asset.id] = FramingProposal(crop: crop, subjects: [], reviewReasons: ["Analysis failed; centred fallback applied. \(error.localizedDescription)"])
                }
            }
            status = "Framing complete. \(proposals.values.filter(\.needsReview).count) images need review."
        }
    }
    func importWatermark(_ url: URL) async {
        guard !clearingWorkspace else { return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { let asset = try await processor.importSnapshot(url, to: directory); var c = controlConfiguration; c.watermark.imageURL = asset.url; c.watermark.kind = .image; c.watermark.enabled = true; applyChange(ConfigurationPatch(values: c, fields: [.watermark_imageURL, .watermark_kind, .watermark_enabled])) }
        catch { issues.append("Watermark import failed: \(error.localizedDescription)") }
    }
    func export(to destination: URL, retry: Bool = false, targetIDs: Set<UUID>? = nil, after: (@MainActor ([URL]) async -> Void)? = nil) {
        guard !running else { return }
        let jobs = retry ? pendingExports : plannedRequests(targetIDs: targetIDs)
        guard !jobs.isEmpty else { status = "Choose images to export."; return }
        sharingSession = nil
        if !retry { pendingExports = jobs }; persist()
        exportingRequests = jobs
        exportingPlanSummary = Self.planSummary(photos: Set(jobs.map { $0.source.id }).count, files: jobs.count, profiles: Set(jobs.map { $0.profile.id }).count)
        lastDestination = destination; running = true; total = jobs.count; completed = 0
        let usesProfileFolders = Set(jobs.map { $0.profile.id }).count > 1
        task = Task {
            let access = destination.startAccessingSecurityScopedResource(); defer { if access { destination.stopAccessingSecurityScopedResource() }; running = false; exportingPlanSummary = nil; exportingRequests = []; persist() }
            var produced: [URL] = []
            for request in jobs {
                let asset = request.source; let configuration = request.configuration; let profile = request.profile
                if Task.isCancelled { break }
                do {
                    let profileAccess = profile.destination?.startAccessingSecurityScopedResource() ?? false
                    defer { if profileAccess { profile.destination?.stopAccessingSecurityScopedResource() } }
                    let folder: URL
                    if profile.destination != nil || usesProfileFolders { let safe = profile.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".", with: "_"); folder = profile.destination ?? destination.appendingPathComponent(safe); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } else { folder = destination }
                    var result = try await processor.export(asset, configuration: configuration, to: folder, profile: profile); result.id = request.id; results.removeAll { $0.id == request.id }; results.append(result)
                    if let url = result.output { produced.append(url) }; pendingExports.removeAll { $0.id == request.id }
                } catch is CancellationError { break } catch { var result = ProcessingResult(source: asset, error: error.localizedDescription); result.id = request.id; results.removeAll { $0.id == request.id }; results.append(result) }
                completed += 1; persist()
            }
            let ids = Set(jobs.map(\.id)); let failures = results.filter { ids.contains($0.id) && $0.error != nil }.count
            status = "\(produced.count) exported · \(failures) failed\(Task.isCancelled ? " · Cancelled; completed files kept" : "")"
            if !produced.isEmpty && !Task.isCancelled { await after?(produced) }
        }
    }
}

enum InspectorTask: String, CaseIterable { case resize = "Resize", adjust = "Adjust", creative = "Create", watermark = "Watermark", output = "Export" }
