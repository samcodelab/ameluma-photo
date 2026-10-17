import XCTest
import FramepebbleCore
#if os(macOS)
@testable import FramepebbleMac
#else
@testable import FramepebbleiOS
#endif

final class CreationUsabilityTests: XCTestCase {
  func testMixedTimingDoesNotImplyActiveFrameValueIsShared() {
    var first = GIFFrame(sourceID: UUID())
    var second = GIFFrame(sourceID: UUID())
    first.duration = 0.2; second.duration = 1
    XCTAssertNil(GIFControlSummary.duration(frames: [first, second], ids: [first.id, second.id]))
    XCTAssertEqual(GIFControlSummary.duration(frames: [first, second], ids: [second.id]), 1)
    XCTAssertNil(GIFControlSummary.duration(frames: [first, second], ids: []))
    second.duration = 0.2
    XCTAssertEqual(GIFControlSummary.duration(frames: [first, second], ids: [first.id, second.id]), 0.2)
  }

  func testAnnotationCoverageFollowsFrameIdentityAfterReordering() {
    let frames = (0..<3).map { _ in GIFFrame(sourceID: UUID()) }
    let annotation = GIFAnnotation(annotation: Annotation(), frameIDs: [frames[0].id, frames[2].id])
    XCTAssertEqual(GIFControlSummary.visibleIndices(annotation, frames: frames), [0, 2])
    XCTAssertEqual(GIFControlSummary.coverage(annotation, frames: frames), "Frames 1, 3")
    let reordered = [frames[1], frames[2], frames[0]]
    XCTAssertEqual(GIFControlSummary.visibleIndices(annotation, frames: reordered), [1, 2])
    XCTAssertEqual(GIFControlSummary.coverage(annotation, frames: []), "Not visible")
    XCTAssertEqual(GIFControlSummary.coverage(GIFAnnotation(annotation: Annotation()), frames: frames), "All Frames")
  }
  func testGIFPreviewIdentityIgnoresFilenameAndUnrelatedSourcesButTracksRenderInputs() {
    let source = SourceAsset(url: URL(fileURLWithPath: "/tmp/creation-original.jpg"))
    let unrelated = SourceAsset(url: URL(fileURLWithPath: "/tmp/creation-unrelated.jpg"))
    var project = GIFProject()
    project.frames = [GIFFrame(sourceID: source.id)]
    let original = GIFPreviewInput(project: project, sources: [source], allowed: true)
    var renamed = project; renamed.name = "New output filename"
    XCTAssertEqual(original, GIFPreviewInput(project: renamed, sources: [unrelated, source], allowed: true))
    var timing = project; timing.frames[0].duration = 1
    XCTAssertNotEqual(original, GIFPreviewInput(project: timing, sources: [source], allowed: true))
    var relinked = source; relinked.url = URL(fileURLWithPath: "/tmp/creation-relinked.jpg")
    XCTAssertNotEqual(original, GIFPreviewInput(project: project, sources: [relinked], allowed: true))
    XCTAssertNotEqual(original, GIFPreviewInput(project: project, sources: [], allowed: true))
    XCTAssertNotEqual(original, GIFPreviewInput(project: project, sources: [source], allowed: false))
    var edited = project; edited.frames[0].configuration.crop.quarterTurns = 1
    XCTAssertNotEqual(original, GIFPreviewInput(project: edited, sources: [source], allowed: true))
  }

  func testOutputSummaryDistinguishesRepeatedFramesFromSourcePhotos() {
    let source = UUID()
    var gif = GIFProject()
    gif.width = 960; gif.height = 540
    gif.frames = [GIFFrame(sourceID: source)]
    gif.duplicate(gif.frames[0].id)
    let summary = CreationOutputSummary.gif(gif)
    XCTAssertTrue(summary.contains("2 frames"))
    XCTAssertTrue(summary.contains("1 source photo ·"))
    XCTAssertTrue(summary.contains("GIF · 960 × 540 px"))
    var collage = CollageProject()
    collage.cells = [CollageCell(sourceID: source, x: 0, y: 0, width: 0.5, height: 1), CollageCell(sourceID: source, x: 0.5, y: 0, width: 0.5, height: 1)]
    collage.outputFormat = .png
    let collageSummary = CreationOutputSummary.collage(collage)
    XCTAssertTrue(collageSummary.contains("2 photo cells"))
    XCTAssertTrue(collageSummary.contains("1 source photo ·"))
    XCTAssertTrue(collageSummary.contains("PNG"))
    XCTAssertEqual(Set(gif.frames.map(\.sourceID)), [source])
  }

}
