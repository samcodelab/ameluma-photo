import Foundation

/// A private, reversible draft. Nothing enters the project until the caller applies it.
/// Reuses the shared history implementation; dragging/sliders form a single undo step.
public struct OverlayEditingSession: Sendable {
    public let sourceID: UUID
    public let original: ProcessingConfiguration
    public private(set) var current: ProcessingConfiguration
    private var history: EditingHistory
    private var interacting = false
    public init(sourceID: UUID, configuration: ProcessingConfiguration) {
        self.sourceID = sourceID; original = configuration; current = configuration
        var snapshot = EditingSnapshot(); snapshot.settings = configuration
        history = EditingHistory(snapshot: snapshot)
    }
    public var canUndo: Bool { history.canUndo || (interacting && current != history.current.settings) }
    public var canRedo: Bool { history.canRedo && !interacting }
    public var hasChanges: Bool { current != original }
    public mutating func update(_ configuration: ProcessingConfiguration) {
        current = configuration
        if !interacting { checkpoint() }
    }
    public mutating func beginInteraction() { interacting = true }
    public mutating func endInteraction() { interacting = false; checkpoint() }
    private mutating func checkpoint() {
        var snapshot = EditingSnapshot(); snapshot.settings = current; history.apply(snapshot)
    }
    public mutating func undo() { endInteraction(); history.undo(); current = history.current.settings }
    public mutating func redo() { endInteraction(); history.redo(); current = history.current.settings }
    public mutating func removeArea(_ id: UUID) {
        endInteraction()
        var next = current
        next.masks.removeAll { $0.id == id }; next.annotations.removeAll { $0.id == id }
        update(next)
    }
    /// Move one authored area in normalized final-output coordinates. Rotation, size,
    /// effects and unrelated areas stay unchanged. Call begin/endInteraction for repeats.
    public mutating func moveArea(_ id: UUID, dx: Double, dy: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        var next = current
        if let index = next.masks.firstIndex(where: { $0.id == id }) {
            let area = next.masks[index]
            next.masks[index].x = min(max(0, 1 - area.width), max(0, area.x + dx))
            next.masks[index].y = min(max(0, 1 - area.height), max(0, area.y + dy))
        } else if let index = next.annotations.firstIndex(where: { $0.id == id }) {
            let area = next.annotations[index]
            next.annotations[index].x = min(max(0, 1 - area.width), max(0, area.x + dx))
            next.annotations[index].y = min(max(0, 1 - area.height), max(0, area.y + dy))
        } else { return }
        update(next)
    }
    public mutating func cancel() {
        current = original; interacting = false
        var snapshot = EditingSnapshot(); snapshot.settings = original
        history = EditingHistory(snapshot: snapshot)
    }
}
