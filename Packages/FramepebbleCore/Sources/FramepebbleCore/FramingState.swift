import Foundation

public struct EditingSnapshot: Codable, Sendable, Equatable {
    public var settings = ProcessingConfiguration()
    public var overrides: [UUID: ImageOverride] = [:]
    public init() {}
    public func configuration(for id: UUID) -> ProcessingConfiguration {
        var c = overrides[id]?.patch?.applying(to: settings) ?? overrides[id]?.processing ?? settings
        if let override = overrides[id] { if override.patch == nil { c.crop = override.crop }; if let dimensions = override.dimensions {
            if dimensions.followsBatchWidth == true {
                let ratio = override.crop.aspectRatio ?? Double(dimensions.width) / Double(max(1, dimensions.height))
                let height = Double(c.width) / ratio
                c.height = height.isFinite && height >= 1 && height <= 20000 ? Int(height) : 0
            } else { c.width = dimensions.width; c.height = dimensions.height }
        } }
        return c
    }
    /// Schema 2/3 snapshots become minimal patches relative to their saved batch settings.
    /// Explicit dimension rules are retained, including followsBatchWidth.
    public mutating func migrateLegacyOverrides() {
        for id in Array(overrides.keys) { migrateLegacyOverride(for: id) }
    }
    private mutating func migrateLegacyOverride(for id: UUID) {
        guard var value = overrides[id], value.patch == nil else { return }
        var effective = value.processing ?? settings
        effective.crop = value.crop
        var fields: Set<ConfigurationField> = []
        if let dimensions = value.dimensions, dimensions.followsBatchWidth != true {
            effective.width = dimensions.width; effective.height = dimensions.height
            fields = [.width, .height]; value.dimensions = nil
        }
        var patch = ConfigurationPatch(from: settings, to: effective)
        patch.fields.formUnion(fields)
        value.patch = patch; value.processing = nil
        overrides[id] = value
    }
    public mutating func apply(_ change: ConfigurationPatch, to id: UUID) {
        migrateLegacyOverride(for: id)
        var value = overrides[id] ?? ImageOverride(crop: settings.crop)
        var patch = value.patch ?? ConfigurationPatch(values: settings, fields: [])
        patch.merge(change)
        value.patch = patch; value.processing = nil
        // Width-only changes retain an aspect-derived height. Explicit height changes
        // stop that derivation without freezing the independently inherited width.
        if change.fields.contains(.height) { value.dimensions = nil }
        value.crop = patch.applying(to: settings).crop
        overrides[id] = value
    }
    /// Reveal the complete oriented source at native size, retaining every
    /// unrelated edit. Explicit height clears legacy aspect-derived dimensions.
    public mutating func restoreFullImageCrop(for id: UUID, sourceSize: CGSize) {
        var value = configuration(for: id)
        let size = ImageProcessor.transformedSize(sourceSize, configuration: value)
        value.width = Int(size.width.rounded()); value.height = Int(size.height.rounded())
        value.crop.mode = .manualCrop
        value.crop.framing = .centre
        value.crop.centerX = 0.5; value.crop.centerY = 0.5
        value.crop.zoom = 1; value.crop.aspectRatio = nil
        value.resizeBasis = .percentage; value.percentage = 100
        apply(ConfigurationPatch(values: value, fields: [
            .crop_mode, .crop_framing, .crop_centerX, .crop_centerY,
            .crop_zoom, .crop_aspectRatio, .resizeBasis, .percentage, .width, .height
        ]), to: id)
    }
    /// Restore source appearance and native dimensions for one photo, even when
    /// batch defaults contain edits. Encoding and metadata protection are retained.
    public mutating func restoreOriginalAppearance(for id: UUID) {
        var neutral = ProcessingConfiguration()
        neutral.crop.mode = .preserveAspectRatio
        neutral.resizeBasis = .percentage
        neutral.percentage = 100
        let fields = Set(ConfigurationField.allCases.filter {
            $0.category != .output && $0 != .privacyExport
        })
        apply(ConfigurationPatch(values: neutral, fields: fields), to: id)
    }
    public mutating func reset(_ categories: Set<EditCategory>, for id: UUID) {
        migrateLegacyOverrides()
        guard var value = overrides[id], var patch = value.patch else { return }
        patch.fields = patch.fields.filter { !categories.contains($0.category) }
        value.patch = patch
        if categories.contains(.sizeAndCanvas) || categories.contains(.framing) { value.dimensions = nil }
        value.crop = patch.applying(to: settings).crop
        if patch.fields.isEmpty && value.dimensions == nil { overrides.removeValue(forKey: id) }
        else { overrides[id] = value }
    }
}
/// One state store is used by thumbnails, precision controls, presets and exports.
public struct EditingHistoryStep: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let isCurrent: Bool
    public let isRedo: Bool
}
public struct EditingHistory: Sendable {
    private struct State: Sendable {
        var id = UUID()
        var title: String
        var snapshot: EditingSnapshot
    }
    private var state: State
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    public var current: EditingSnapshot { state.snapshot }
    /// Session Undo/Redo can still need an image watermark after the current edit removes it.
    public var referencedWatermarkURLs: Set<URL> {
        var urls: Set<URL> = []
        for snapshot in undoStack.map(\.snapshot) + [state.snapshot] + redoStack.map(\.snapshot) {
            if let url = snapshot.settings.watermark.imageURL { urls.insert(url) }
            for override in snapshot.overrides.values {
                if let url = override.processing?.watermark.imageURL { urls.insert(url) }
                if let url = override.patch?.values.watermark.imageURL { urls.insert(url) }
            }
        }
        return urls
    }
    public init(snapshot: EditingSnapshot = EditingSnapshot()) {
        state = State(title: "Session Start", snapshot: snapshot)
    }
    public var undoTitle: String { state.title }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var steps: [EditingHistoryStep] {
        undoStack.map { EditingHistoryStep(id: $0.id, title: $0.title, isCurrent: false, isRedo: false) }
        + [EditingHistoryStep(id: state.id, title: state.title, isCurrent: true, isRedo: false)]
        + redoStack.reversed().map { EditingHistoryStep(id: $0.id, title: $0.title, isCurrent: false, isRedo: true) }
    }
    public mutating func apply(_ snapshot: EditingSnapshot, title: String? = nil) {
        guard snapshot != current else { return }
        let batchFields = ConfigurationPatch(from: current.settings, to: snapshot.settings).fields
        let ids = Set(current.overrides.keys).union(snapshot.overrides.keys).filter {
            current.overrides[$0] != snapshot.overrides[$0]
        }
        var fields = batchFields
        for id in ids {
            fields.formUnion(ConfigurationPatch(from: current.configuration(for: id), to: snapshot.configuration(for: id)).fields)
        }
        let detail = fields.count == 1 ? (fields.first?.displayName ?? "Edit")
            : Set(fields.map { $0.category.rawValue }).sorted().joined(separator: ", ")
        let scope = !batchFields.isEmpty ? "Batch" : "\(ids.count) \(ids.count == 1 ? "photo" : "photos")"
        let label = title ?? (detail.isEmpty ? "Edit settings" : scope + " · " + detail)
        undoStack.append(state)
        if undoStack.count > 80 { undoStack.removeFirst() }
        state = State(title: label, snapshot: snapshot)
        redoStack = []
    }
    /// Import is outside edit history. Give a new finished source the same
    /// independent baseline in every existing state, preserving prior Undo/Redo.
    public mutating func registerSource(_ id: UUID, configuration: ProcessingConfiguration) {
        let patch = ConfigurationPatch(values: configuration, fields: Set(ConfigurationField.allCases))
        state.snapshot.apply(patch, to: id)
        for index in undoStack.indices { undoStack[index].snapshot.apply(patch, to: id) }
        for index in redoStack.indices { redoStack[index].snapshot.apply(patch, to: id) }
    }
    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state); state = previous
    }
    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state); state = next
    }
    /// Moving along the timeline retains the redo branch until a new edit is made.
    public mutating func move(to id: UUID) {
        if undoStack.contains(where: { $0.id == id }) {
            while state.id != id && canUndo { undo() }
        } else if redoStack.contains(where: { $0.id == id }) {
            while state.id != id && canRedo { redo() }
        }
    }
}
