import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FramepebbleCore

final class ProcessingTests: XCTestCase {
    func fixture(width: Int = 80, height: Int = 40, orientation: Int = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest)); addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testLandscapePortraitSquareFitFill() async throws {
        let engine = ImageProcessor()
        for source in [(80,40),(40,80),(60,60)] {
            let url = try fixture(width: source.0, height: source.1)
            for mode in [CropMode.fit, .fill, .manualCrop] {
                var c = ProcessingConfiguration(); c.width = 30; c.height = 20; c.crop.mode = mode
                let output = try await engine.render(url, configuration: c)
                XCTAssertEqual(output.width,30); XCTAssertEqual(output.height,20)
            }
        }
    }
    func testPreserveAspectAndRotation() async throws {
        let url = try fixture(); let engine = ImageProcessor(); var c = ProcessingConfiguration(); c.width = 40; c.crop.mode = .preserveAspectRatio
        let normal = try await engine.render(url, configuration: c); XCTAssertEqual(normal.height,20)
        c.quarterTurns = 1
        let rotated = try await engine.render(url, configuration: c); XCTAssertEqual(rotated.height,80)
    }
    func testCropGeometry() {
        var c = CropConfiguration(); c.centerX = 1; c.centerY = 0; c.zoom = 2
        let rect = CropGeometry.rect(source: CGSize(width: 800,height: 400), ratio: 1, crop: c)
        XCTAssertEqual(rect, CGRect(x: 600,y: 0,width: 200,height: 200))
    }
    func testEXIFOrientation() async throws {
        let engine = ImageProcessor(); let url = try fixture(orientation: 6)
        let size = try await engine.identify(url); XCTAssertEqual(size, CGSize(width:40,height:80))
        var c = ProcessingConfiguration(); c.width = 20; c.crop.mode = .preserveAspectRatio
        let result = try await engine.render(url,configuration:c); XCTAssertEqual(result.height,40)
    }
    func testEncodingDimensionsCollisionsAndOriginalPreservation() async throws {
        let url = try fixture(); let original = try Data(contentsOf: url); let engine = ImageProcessor()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
        let asset = SourceAsset(url:url,name:"../unsafe.png")
        for format in ImageProcessor.outputFormats {
            var c = ProcessingConfiguration(); c.width = 24; c.height = 18; c.format = format
            let a = try await engine.export(asset,configuration:c,to:dir); let b = try await engine.export(asset,configuration:c,to:dir)
            XCTAssertNotEqual(a.output,b.output)
            let output = try XCTUnwrap(a.output); let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL,nil)); let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
            XCTAssertEqual(image.width,24); XCTAssertEqual(image.height,18)
            XCTAssertEqual(CGImageSourceGetType(source) as String?, format.typeIdentifier)
        }
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    func testInvalidAndMissingImages() async throws {
        let engine = ImageProcessor(); let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("invalid".utf8).write(to:url); defer { try? FileManager.default.removeItem(at:url) }
        do { _ = try await engine.render(url,configuration:ProcessingConfiguration()); XCTFail() } catch { XCTAssertTrue(error is ProcessingError) }
        do { _ = try await engine.identify(url.appendingPathExtension("missing")); XCTFail() } catch { XCTAssertTrue(error is ProcessingError) }
    }
    func testCancellation() async throws {
        let engine = ImageProcessor(); let url = try fixture()
        let task = Task { try Task.checkCancellation(); return try await engine.render(url,configuration:ProcessingConfiguration()) }; task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testInvalidConfiguration() async throws {
        let url = try fixture(); var c = ProcessingConfiguration(); c.width = -1
        do { _ = try await ImageProcessor().render(url,configuration:c); XCTFail() } catch { XCTAssertTrue(error is ProcessingError) }
    }
    func pixels(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try data.withUnsafeMutableBytes { buffer in
            let ctx = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
    func testFitPaddingFillAndJPEGFlattening() async throws {
        let url = try fixture(); let engine = ImageProcessor(); var c = ProcessingConfiguration()
        c.width = 40; c.height = 40; c.format = .png
        let fit = try await engine.render(url, configuration: c); let fitPixels = try pixels(fit)
        XCTAssertEqual(fitPixels[3], 0, "Fit leaves transparent padding for PNG")
        c.crop.mode = .fill
        let fill = try await engine.render(url, configuration: c); let fillPixels = try pixels(fill)
        XCTAssertGreaterThan(fillPixels[3], 100, "Fill covers the canvas")
        XCTAssertLessThan(fillPixels[3], 160, "PNG preserves source alpha")
        c.crop.mode = .fit; c.format = .jpeg
        let jpeg = try await engine.render(url, configuration: c); let jpegPixels = try pixels(jpeg)
        XCTAssertEqual(Array(jpegPixels.prefix(4)), [255, 255, 255, 255], "JPEG padding is white and opaque")
        XCTAssertEqual(jpeg.colorSpace?.name, CGColorSpace.sRGB)
    }
    func testAllEXIFOrientationsPreviewAndExportAgree() async throws {
        let engine = ImageProcessor()
        for orientation in 1...8 {
            let url = try fixture(orientation: orientation); var c = ProcessingConfiguration()
            c.width = 40; c.crop.mode = .preserveAspectRatio
            let preview = try await engine.render(url, configuration: c, previewMaximum: 100)
            let final = try await engine.render(url, configuration: c)
            XCTAssertEqual(preview.width, final.width); XCTAssertEqual(preview.height, final.height)
            XCTAssertEqual(final.height, orientation >= 5 ? 80 : 20)
        }
    }
    func testCancellationLeavesNoStagingOrOutput() async throws {
        let engine = ImageProcessor(); let url = try fixture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = Task { try Task.checkCancellation(); return try await engine.export(SourceAsset(url: url), configuration: ProcessingConfiguration(), to: dir) }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
    func testInvalidDestination() async throws {
        let url = try fixture()
        do { _ = try await ImageProcessor().export(SourceAsset(url: url), configuration: ProcessingConfiguration(), to: url); XCTFail() }
        catch { XCTAssertTrue(error is ProcessingError) }
    }

    func testSourceAliasAndProfileNaming() async throws {
        let source = try fixture(); let original = try Data(contentsOf: source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let alias = directory.appendingPathComponent("input-framepebble.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        var c = ProcessingConfiguration(); c.width = 10; c.height = 10; c.format = .png
        let result = try await ImageProcessor().export(SourceAsset(url: source, name: "input.png"), configuration: c, to: directory)
        XCTAssertEqual(result.output?.lastPathComponent, "input-framepebble-1.png")
        XCTAssertEqual(try Data(contentsOf: source), original)
        var profile = ExportProfile(); profile.suffix = "-small"
        let custom = try await ImageProcessor().export(SourceAsset(url: source, name: "input.png"), configuration: c, to: directory, profile: profile)
        XCTAssertEqual(custom.output?.lastPathComponent, "input-small.png")
    }
    func testPreservedAspectCannotExceedOutputLimits() async throws {
        let source = try fixture(width: 1, height: 400)
        var c = ProcessingConfiguration(); c.width = 1000; c.height = 1; c.crop.mode = .preserveAspectRatio
        do { _ = try await ImageProcessor().render(source, configuration: c); XCTFail() }
        catch { XCTAssertTrue(error is ProcessingError) }
    }

    func testClockwiseRotationPixelOrder() async throws {
        let data = Data([255, 0, 0, 255, 0, 0, 255, 255])
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        var c = ProcessingConfiguration(); c.width = 1; c.height = 2; c.format = .png; c.quarterTurns = 1; c.crop.mode = .fill
        let result = try await ImageProcessor().render(url, configuration: c)
        XCTAssertEqual(try pixels(result), [255, 0, 0, 255, 0, 0, 255, 255])
        c.quarterTurns = 3
        let reverse = try await ImageProcessor().render(url, configuration: c)
        XCTAssertEqual(try pixels(reverse), [0, 0, 255, 255, 255, 0, 0, 255])
    }

}
