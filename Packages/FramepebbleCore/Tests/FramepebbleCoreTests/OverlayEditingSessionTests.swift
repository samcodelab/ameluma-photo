import XCTest
@testable import FramepebbleCore

final class OverlayEditingSessionTests: XCTestCase {
    func testMultipleAreasDeleteUndoRedoAndCancelRestoreOriginal() {
        var original = ProcessingConfiguration()
        var existing = PrivacyMask(); existing.effect = .pixelate
        original.masks = [existing]
        var session = OverlayEditingSession(sourceID: UUID(), configuration: original)
        var next = session.current
        var frosted = PrivacyMask(); frosted.effect = .frosted
        next.masks.append(frosted); session.update(next)
        var cover = PrivacyMask(); cover.effect = .cover
        next.masks.append(cover); session.update(next)
        XCTAssertEqual(session.current.masks.count, 3)
        session.removeArea(frosted.id)
        XCTAssertEqual(session.current.masks.map(\.id), [existing.id, cover.id])
        session.undo(); XCTAssertEqual(session.current.masks.count, 3)
        session.redo(); XCTAssertEqual(session.current.masks.count, 2)
        session.undo(); session.undo(); XCTAssertEqual(session.current.masks.map(\.id), [existing.id, frosted.id])
        session.cancel(); XCTAssertEqual(session.current, original)
        XCTAssertFalse(session.canUndo); XCTAssertFalse(session.hasChanges)
        XCTAssertEqual(original.masks.map(\.id), [existing.id])
    }
    func testDragIsOneUndoStepAndNewEditClearsRedo() {
        var original = ProcessingConfiguration(); let mask = PrivacyMask(); original.masks = [mask]
        var session = OverlayEditingSession(sourceID: UUID(), configuration: original)
        session.beginInteraction()
        for value in [0.3, 0.35, 0.4] { var c = session.current; c.masks[0].x = value; session.update(c) }
        session.endInteraction(); session.undo()
        XCTAssertEqual(session.current, original)
        XCTAssertFalse(session.canUndo)
        session.redo(); XCTAssertEqual(session.current.masks[0].x, 0.4)
        session.undo(); session.removeArea(mask.id)
        XCTAssertFalse(session.canRedo)
        session.undo(); XCTAssertEqual(session.current, original)
    }
    func testAnnotationDeletionIsReversibleAndKeepsMasks() {
        var c = ProcessingConfiguration(); let a = Annotation(); let mask = PrivacyMask()
        c.annotations = [a]; c.masks = [mask]
        var session = OverlayEditingSession(sourceID: UUID(), configuration: c)
        session.removeArea(a.id); XCTAssertTrue(session.current.annotations.isEmpty)
        XCTAssertEqual(session.current.masks, [mask])
        session.undo(); XCTAssertEqual(session.current, c)
    }
}
