import XCTest
@testable import FramepebbleCore

final class OverlayGeometryTests: XCTestCase {
    func testResizeIsIndependentOfPreviewScale() {
        let original = OverlayBounds(x:0.2,y:0.25,width:0.3,height:0.2)
        let small = OverlayGeometry.resized(original,handle:.bottomRight,translation:CGSize(width:80,height:60),viewport:CGSize(width:800,height:600))
        let large = OverlayGeometry.resized(original,handle:.bottomRight,translation:CGSize(width:160,height:120),viewport:CGSize(width:1600,height:1200))
        XCTAssertEqual(small,large)
        XCTAssertEqual(small.x,original.x,accuracy:0.000001)
        XCTAssertEqual(small.y,original.y,accuracy:0.000001)
        XCTAssertEqual(small.width,0.4,accuracy:0.000001)
        XCTAssertEqual(small.height,0.3,accuracy:0.000001)
    }
    func testLeftAndTopHandlesKeepOppositeEdgeFixed() {
        let original=OverlayBounds(x:0.2,y:0.25,width:0.3,height:0.2)
        let resized=OverlayGeometry.resized(original,handle:.topLeft,translation:CGSize(width:80,height:60),viewport:CGSize(width:800,height:600))
        XCTAssertEqual(resized.x+resized.width,original.x+original.width,accuracy:0.000001)
        XCTAssertEqual(resized.y+resized.height,original.y+original.height,accuracy:0.000001)
    }
    func testRotatedResizeKeepsOppositeEdgeInPlace() {
        let original=OverlayBounds(x:0.2,y:0.25,width:0.3,height:0.2,rotation:90)
        let resized=OverlayGeometry.resized(original,handle:.right,translation:CGSize(width:0,height:80),viewport:CGSize(width:800,height:600))
        let originalOppositeY=(original.y+original.height/2)*600-original.width*800/2
        let resizedOppositeY=(resized.y+resized.height/2)*600-resized.width*800/2
        XCTAssertEqual(originalOppositeY,resizedOppositeY,accuracy:0.000001)
        XCTAssertEqual(resized.width,0.4,accuracy:0.000001)
        XCTAssertEqual(resized.rotation,90)
    }
    func testExtremeResizeStaysValidAndInvalidViewportDoesNothing() {
        let original=OverlayBounds(x:0.2,y:0.25,width:0.3,height:0.2)
        for handle in OverlayResizeHandle.allCases {
            let resized=OverlayGeometry.resized(original,handle:handle,translation:CGSize(width:99999,height:-99999),viewport:CGSize(width:800,height:600))
            XCTAssertTrue((0.01...1).contains(resized.width)); XCTAssertTrue((0.01...1).contains(resized.height))
            XCTAssertGreaterThanOrEqual(resized.x,0); XCTAssertGreaterThanOrEqual(resized.y,0)
            XCTAssertLessThanOrEqual(resized.x+resized.width,1.000001)
            XCTAssertLessThanOrEqual(resized.y+resized.height,1.000001)
        }
        XCTAssertEqual(OverlayGeometry.resized(original,handle:.right,translation:.zero,viewport:.zero),original)
    }
}

extension OverlayGeometryTests {
    func testRotationHandleWorksAtAnyPreviewScale() {
        let original=OverlayBounds(x:0.25,y:0.25,width:0.5,height:0.5)
        let a=OverlayGeometry.rotated(original,from:CGPoint(x:400,y:100),to:CGPoint(x:600,y:300),viewport:CGSize(width:800,height:600))
        let b=OverlayGeometry.rotated(original,from:CGPoint(x:800,y:200),to:CGPoint(x:1200,y:600),viewport:CGSize(width:1600,height:1200))
        XCTAssertEqual(a,b);XCTAssertEqual(a.rotation,90,accuracy:0.000001)
        XCTAssertEqual(a.x,original.x);XCTAssertEqual(a.width,original.width)
    }
    func testRotationPreservesStartingAngleAndRejectsCentre() {
        let original=OverlayBounds(x:0.25,y:0.25,width:0.5,height:0.5,rotation:30)
        let rotated=OverlayGeometry.rotated(original,from:CGPoint(x:400,y:100),to:CGPoint(x:600,y:300),viewport:CGSize(width:800,height:600))
        XCTAssertEqual(rotated.rotation,120,accuracy:0.000001)
        XCTAssertEqual(OverlayGeometry.rotated(original,from:CGPoint(x:400,y:300),to:CGPoint(x:600,y:300),viewport:CGSize(width:800,height:600)),original)
    }
}


extension OverlayGeometryTests {
    func testAreaMovementPreservesEditsAndGroupsRepeatedKeysForUndo() {
        var config = ProcessingConfiguration()
        var mask = PrivacyMask(); mask.x = 0.2; mask.y = 0.3; mask.rotation = 25
        config.masks = [mask, PrivacyMask()]
        config.annotations = [Annotation()]
        config.adjustments.exposure = 0.8
        var session = OverlayEditingSession(sourceID: UUID(), configuration: config)
        session.beginInteraction()
        for _ in 0..<10 { session.moveArea(mask.id, dx: 0.001, dy: -0.001) }
        session.endInteraction()
        XCTAssertEqual(session.current.masks[0].x, 0.21, accuracy: 0.000001)
        XCTAssertEqual(session.current.masks[0].y, 0.29, accuracy: 0.000001)
        XCTAssertEqual(session.current.masks[0].rotation, 25)
        XCTAssertEqual(session.current.masks[1], config.masks[1])
        XCTAssertEqual(session.current.annotations, config.annotations)
        XCTAssertEqual(session.current.adjustments, config.adjustments)
        session.undo(); XCTAssertEqual(session.current, config)
        session.redo(); XCTAssertEqual(session.current.masks[0].x, 0.21, accuracy: 0.000001)
        session.cancel(); XCTAssertEqual(session.current, config)
    }
    func testAnnotationMovementClampsBoundsAndRejectsInvalidInput() {
        var config = ProcessingConfiguration()
        var annotation = Annotation(); annotation.x = 0.3; annotation.y = 0.4
        annotation.width = 0.2; annotation.height = 0.1
        config.annotations = [annotation]
        var session = OverlayEditingSession(sourceID: UUID(), configuration: config)
        session.moveArea(annotation.id, dx: 10, dy: -10)
        XCTAssertEqual(session.current.annotations[0].x, 0.8, accuracy: 0.000001)
        XCTAssertEqual(session.current.annotations[0].y, 0)
        let moved = session.current
        session.moveArea(annotation.id, dx: .nan, dy: 0)
        session.moveArea(UUID(), dx: 0.1, dy: 0.1)
        XCTAssertEqual(session.current, moved)
        session.undo(); XCTAssertEqual(session.current, config)
    }
}

extension OverlayGeometryTests {
    func testProportionalCornerResizeKeepsRatioAndOppositeCornerAtAnyScale() {
        let start = OverlayBounds(x: 0.3, y: 0.3, width: 0.2, height: 0.1, rotation: 30)
        let viewport = CGSize(width: 800, height: 600)
        let a = OverlayGeometry.resized(start, handle: .bottomRight,
            translation: CGSize(width: 40, height: 20), viewport: viewport, preserveAspect: true)
        let b = OverlayGeometry.resized(start, handle: .bottomRight,
            translation: CGSize(width: 80, height: 40), viewport: CGSize(width: 1600, height: 1200), preserveAspect: true)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.width / a.height, start.width / start.height, accuracy: 0.000001)
        func oppositeCorner(_ bounds: OverlayBounds) -> CGPoint {
            let c = cos(bounds.rotation * .pi / 180), s = sin(bounds.rotation * .pi / 180)
            return CGPoint(x: (bounds.x + bounds.width/2) * 800 - c*bounds.width*400 + s*bounds.height*300,
                           y: (bounds.y + bounds.height/2) * 600 - s*bounds.width*400 - c*bounds.height*300)
        }
        XCTAssertEqual(oppositeCorner(a).x, oppositeCorner(start).x, accuracy: 0.000001)
        XCTAssertEqual(oppositeCorner(a).y, oppositeCorner(start).y, accuracy: 0.000001)
    }
    func testProportionalEdgeAndExtremeResizeRemainValid() {
        let start = OverlayBounds(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let edge = OverlayGeometry.resized(start, handle: .right,
            translation: CGSize(width: 40, height: 0), viewport: CGSize(width: 800, height: 600), preserveAspect: true)
        XCTAssertEqual(edge.x, start.x, accuracy: 0.000001)
        XCTAssertEqual(edge.y + edge.height/2, start.y + start.height/2, accuracy: 0.000001)
        for handle in OverlayResizeHandle.allCases {
            for delta in [-100000.0, 100000.0] {
                let result = OverlayGeometry.resized(start, handle: handle,
                    translation: CGSize(width: delta, height: delta), viewport: CGSize(width: 800, height: 600), preserveAspect: true)
                XCTAssertEqual(result.width/result.height, 2, accuracy: 0.000001)
                XCTAssertGreaterThanOrEqual(result.x, 0); XCTAssertGreaterThanOrEqual(result.y, 0)
                XCTAssertLessThanOrEqual(result.x + result.width, 1.000001)
                XCTAssertLessThanOrEqual(result.y + result.height, 1.000001)
                XCTAssertGreaterThanOrEqual(result.width, 0.01); XCTAssertGreaterThanOrEqual(result.height, 0.01)
            }
        }
    }
}
