import Foundation
import XCTest

final class DistributionResourceTests: XCTestCase {
  func testApplicationUsesNewBrandWithCompatibleIdentity() {
    #if os(macOS)
      let expected = "Ameluma Photo"
      let identifier = "com.broadframestudio.framepebble"
    #else
      let expected = "Ameluma"
      let identifier = "com.broadframestudio.framepebble.ios"
    #endif
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, expected)
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, expected)
    XCTAssertEqual(Bundle.main.bundleIdentifier, identifier)
  }
  func testPrivacyAndHelpDocumentsShipWithTheApplication() throws {
    for name in ["PrivacyPolicy", "Help"] {
      let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "md"))
      let text = try String(contentsOf: url, encoding: .utf8)
      XCTAssertGreaterThan(text.count, 400)
      XCTAssertFalse(text.contains("unsigned development build"))
    }
    XCTAssertNotNil(Bundle.main.url(forResource: "Distribution", withExtension: "plist"))
  }
  func testPrivacyManifestDeclaresNoTrackingOrCollection() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    let manifest = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any])
    XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
    XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    let reasons = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    XCTAssertEqual(
      reasons.first?["NSPrivacyAccessedAPIType"] as? String,
      "NSPrivacyAccessedAPICategoryFileTimestamp")
    XCTAssertEqual(
      Set(reasons.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []),
      ["C617.1", "3B52.1"])
  }
  func testPermissionsDoNotRequestTheWholePhotoLibrary() {
    XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription"))
    #if os(iOS)
      XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription"))
    #endif
  }
}
