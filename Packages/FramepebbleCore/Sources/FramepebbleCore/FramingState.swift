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
public struct EditingHistory: Sendable {
    public private(set) var current = EditingSnapshot()
    private var undoStack: [EditingSnapshot] = []
    private var redoStack: [EditingSnapshot] = []
    public init(snapshot: EditingSnapshot = EditingSnapshot()) { current = snapshot }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public mutating func apply(_ snapshot: EditingSnapshot) {
        guard snapshot != current else { return }
        undoStack.append(current); if undoStack.count > 80 { undoStack.removeFirst() }; current = snapshot; redoStack = []
    }
    public mutating func undo() { guard let state = undoStack.popLast() else { return }; redoStack.append(current); current = state }
    public mutating func redo() { guard let state = redoStack.popLast() else { return }; undoStack.append(current); current = state }
}
