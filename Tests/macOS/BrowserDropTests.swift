import AppKit
import CoreGraphics
import FramepebbleCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import FramepebbleMac

@MainActor final class BrowserDropTests: XCTestCase {
  func workspace() throws -> Workspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = Workspace(directory: root)
    addTeardownBlock {
      await model.stopWork()
      await model.flush()
      try? FileManager.default.removeItem(at: root)
    }
    return model
  }
  func testBrowserBytesTakePriorityOverAnInaccessibleWebLink() async throws {
    let model = try workspace()
    let provider = NSItemProvider(
      item: DropURLProtocol.image as NSData, typeIdentifier: UTType.png.identifier)
    provider.suggestedName = "Photo.jpg"
    provider.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all)
    { done in
      done(URL(string: "https://unreachable.invalid/photo")?.dataRepresentation, nil)
      return nil
    }
    XCTAssertTrue(BrowserDropImporter.start([provider], model: model))
    await model.importTask?.value
    XCTAssertEqual(model.assets.count, 1)
    XCTAssertEqual(model.assets.first?.name, "Photo.png")
    XCTAssertTrue(model.issues.isEmpty)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.assets.first?.url)), DropURLProtocol.image)
  }
  func testFinderFolderDropIncludesNestedImagesAndPreservesOriginals() async throws {
    let model = try workspace()
    let folder = model.directory.deletingLastPathComponent().appendingPathComponent("Input/Nested")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let original = folder.appendingPathComponent("Source.png")
    try DropURLProtocol.image.write(to: original)
    let provider = NSItemProvider(
      item: folder.deletingLastPathComponent() as NSURL, typeIdentifier: UTType.fileURL.identifier)
    XCTAssertTrue(BrowserDropImporter.start([provider], model: model))
    await model.importTask?.value
    XCTAssertEqual(model.assets.count, 1)
    XCTAssertNotEqual(model.assets.first?.url, original)
    XCTAssertEqual(try Data(contentsOf: original), DropURLProtocol.image)
  }
  func testBrokenFileRepresentationFallsBackToImageBytes() async throws {
    let model = try workspace()
    let provider = NSItemProvider(
      item: Data("not a file".utf8) as NSData, typeIdentifier: UTType.fileURL.identifier)
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all)
    { done in
      done(DropURLProtocol.image, nil)
      return nil
    }
    XCTAssertTrue(BrowserDropImporter.start([provider], model: model))
    await model.importTask?.value
    XCTAssertEqual(model.assets.count, 1)
  }
  func testCorruptImageDropReportsFailure() async throws {
    let model = try workspace()
    let provider = NSItemProvider(
      item: Data("not an image".utf8) as NSData, typeIdentifier: UTType.png.identifier)
    XCTAssertTrue(BrowserDropImporter.start([provider], model: model))
    await model.importTask?.value
    XCTAssertTrue(model.assets.isEmpty)
    XCTAssertFalse(model.issues.isEmpty)
    XCTAssertFalse(model.importing)
  }
  func testCancelRetainsTheWorkspaceAndStopsNewItems() async throws {
    let model = try workspace()
    await model.importData(DropURLProtocol.image, name: "Existing.png")
    let provider = NSItemProvider(
      item: DropURLProtocol.image as NSData, typeIdentifier: UTType.png.identifier)
    XCTAssertTrue(BrowserDropImporter.start([provider], model: model))
    model.importTask?.cancel()
    await model.importTask?.value
    XCTAssertEqual(model.assets.count, 1)
    XCTAssertTrue(model.status.contains("cancelled"))
    XCTAssertFalse(model.importing)
  }
  func testCancelUnresponsiveProviderDoesNotWaitForItsCallback() async throws {
    let started = expectation(description: "Provider started")
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all)
    { _ in
      started.fulfill()
      return Progress(totalUnitCount: 1)
    }
    let task = Task { try await BrowserDropImporter.data(provider, type: UTType.png.identifier) }
    await fulfillment(of: [started], timeout: 3)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled provider should not complete")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testOnlyHTTPSWithoutEmbeddedCredentialsIsAccepted() {
    for value in [
      "http://site.test/photo", "file:///tmp/photo", "https://user:secret@site.test/photo",
      "data:image/png;base64,abc",
    ] {
      XCTAssertFalse(WebImageDownload.permits(URL(string: value)!))
    }
    XCTAssertTrue(WebImageDownload.permits(URL(string: "https://site.test/photo?token=123")!))
  }
  func testBoundedDownloadUsesActualImageBytes() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DropURLProtocol.self]
    let bytes = try await WebImageDownload.fetch(
      URL(string: "https://site.test/image")!, configuration: configuration)
    XCTAssertEqual(bytes, DropURLProtocol.image)
    XCTAssertEqual(
      try BrowserDropImporter.imageName(bytes, suggested: "picture.jpeg"), "picture.png")
  }
  func testDownloadRejectsTooLargeTransferAndServerFailure() async throws {
    for path in ["oversize", "missing", "stream-too-large"] {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [DropURLProtocol.self]
      do {
        _ = try await WebImageDownload.fetch(
          URL(string: "https://site.test/\(path)")!, configuration: configuration, maximumBytes: 16)
        XCTFail("The invalid response should fail")
      } catch { XCTAssertTrue(error is DropError) }
    }
  }
  func testHTMLIsNotImportedAsAnImage() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DropURLProtocol.self]
    let bytes = try await WebImageDownload.fetch(
      URL(string: "https://site.test/page")!, configuration: configuration)
    XCTAssertThrowsError(try BrowserDropImporter.imageName(bytes, suggested: "page.png"))
  }
}

private final class DropURLProtocol: URLProtocol, @unchecked Sendable {
  static let image: Data = {
    let data = NSMutableData()
    let context = CGContext(
      data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
    let destination = CGImageDestinationCreateWithData(
      data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url!.lastPathComponent
    let bytes = path == "page" ? Data("<html>Not an image</html>".utf8) : Self.image
    let status = path == "missing" ? 404 : 200
    var headers = ["Content-Type": path == "page" ? "text/html" : "image/png"]
    if path == "oversize" { headers["Content-Length"] = "100000000" }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: bytes)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
