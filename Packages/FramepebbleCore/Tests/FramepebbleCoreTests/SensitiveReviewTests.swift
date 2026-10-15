import FramepebbleCore
import XCTest

final class SensitiveReviewTests: XCTestCase {
  func testManualAndAutomaticFlagsHaveIndependentOrigins() {
    let id = UUID()
    let other = UUID()
    var review = SensitiveReviewState()
    review.mark(id, forReview: true)
    review.record(
      true, id: other, fingerprint: SourceFingerprint(bytes: 10, modified: .distantPast))
    XCTAssertEqual(review.flagged, [id, other])
    review.mark(other, forReview: false)
    XCTAssertTrue(
      review.flagged.contains(other), "Manual unflag does not invent a negative detector result")
    review.mark(id, forReview: false)
    XCTAssertFalse(review.flagged.contains(id))
  }
  func testRevealRequiresExplicitChoiceAndNewPositiveFindingConcealsAgain() {
    let id = UUID()
    var review = SensitiveReviewState()
    review.mark(id, forReview: true)
    XCTAssertTrue(review.concealed(id))
    review.revealed.insert(id)
    XCTAssertFalse(review.concealed(id))
    review.record(true, id: id, fingerprint: SourceFingerprint(bytes: 10, modified: .distantPast))
    XCTAssertTrue(review.concealed(id))
  }
  func testInvalidationRemovesFindingAndRevealChoice() {
    let id = UUID()
    var review = SensitiveReviewState()
    review.record(true, id: id, fingerprint: SourceFingerprint(bytes: 10, modified: .distantPast))
    review.revealed.insert(id)
    review.invalidate(id)
    XCTAssertTrue(review.flagged.isEmpty)
    XCTAssertFalse(review.revealed.contains(id))
  }
  func testRescanningRevokesApprovalWithoutReincludingExcludedImages() {
    let first = URL(fileURLWithPath: "/tmp/one.png")
    let excluded = URL(fileURLWithPath: "/tmp/two.png")
    var review = ShareReviewSession(outputs: [first, excluded])
    review.include(excluded, false)
    review.approve()
    review.revokeApproval()
    XCTAssertEqual(review.included, [first])
    XCTAssertTrue(review.approvedOutputs.isEmpty)
  }
  func testFailedAutomaticFindingInvalidationRetainsUserFlag() {
    let id = UUID()
    var review = SensitiveReviewState()
    review.mark(id, forReview: true)
    review.record(true, id: id, fingerprint: SourceFingerprint(bytes: 10, modified: .distantPast))
    review.invalidateFinding(id)
    XCTAssertTrue(review.flagged.contains(id))
  }
  func testDisabledPolicyIsNotSuccessfulAnalysis() {
    XCTAssertFalse(SensitiveAnalysisAvailability.unavailable("Permission unavailable").canAnalyze)
    XCTAssertTrue(
      SensitiveAnalysisAvailability.available(descriptiveInterventions: false).canAnalyze)
  }
}
