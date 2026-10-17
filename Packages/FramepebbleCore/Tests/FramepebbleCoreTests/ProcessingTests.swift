import XCTest
import CoreImage
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


extension ProcessingTests {
    func retouchFixture() throws -> CGImage {
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 256, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
        canvas.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        return try XCTUnwrap(canvas.makeImage())
    }
    func retouchPixel(_ image: CIImage, x: Int, y: Int, context: CIContext) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return pixel
    }
    func testHealMatchesSurroundingFabricInsteadOfBlemishColourAndPreservesLegacySampling() throws {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.55, green: 0.08, blue: 0.06, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        bitmap.setFillColor(CGColor(red: 0.7, green: 0.45, blue: 0.32, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 160))
        bitmap.fillEllipse(in: CGRect(x: 70, y: 72, width: 16, height: 16))
        let image = try XCTUnwrap(bitmap.makeImage()), context = CIContext()
        let point = NormalizedPoint(78.0/160, 0.5)
        let sample = try RetouchRenderer.suggestedSource(in: image, at: point, diameter: 0.1, context: context)
        XCTAssertGreaterThan(sample.x * 160, 64, "Choose shirt fabric rather than adjacent skin matching the button")
        XCTAssertGreaterThan(hypot((sample.x-point.x)*160, (sample.y-point.y)*160), 16)
        XCTAssertEqual(sample, try RetouchRenderer.suggestedSource(in: image, at: point, diameter: 0.1, context: context))
        var stroke = RetouchStroke(); stroke.points = [point]; stroke.diameter = 0.1
        XCTAssertEqual(stroke.samplingVersion, 2)
        let data = try JSONEncoder().encode(stroke)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "samplingVersion")
        let legacy = try JSONDecoder().decode(RetouchStroke.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.samplingVersion)
        var versionOne = legacy; versionOne.samplingVersion = 1
        let source = CIImage(cgImage: image)
        let a = try RetouchRenderer.apply(to: source, strokes: [legacy], context: context)
        let b = try RetouchRenderer.apply(to: source, strokes: [versionOne], context: context)
        XCTAssertEqual(retouchPixel(a, x: 78, y: 80, context: context), retouchPixel(b, x: 78, y: 80, context: context))
        XCTAssertEqual(try JSONDecoder().decode(RetouchStroke.self, from: data), stroke)
    }

    func testVersionThreeHealExcludesEntirePaintedPathAndMatchesSurroundings() throws {
        let context = CIContext()
        // Explicit CI colour fixtures avoid the machine-dependent DeviceRGB primaries.
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x:0,y:0,width:256,height:128))
        let background = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x:0,y:0,width:128,height:128)).composited(over: blue)
        let blemish = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x:190,y:24,width:4,height:80)).composited(over: background)
        let bitmap = try XCTUnwrap(context.createCGImage(blemish, from: blemish.extent))
        var stroke = RetouchStroke(); stroke.samplingVersion = 3; stroke.diameter = 0.08; stroke.hardness = 0.8
        stroke.points = (0...20).map { NormalizedPoint(0.75, 0.2 + Double($0) * 0.03) }
        stroke.source = try RetouchRenderer.suggestedSource(in: bitmap, points: stroke.points, diameter: stroke.diameter, context: context)
        XCTAssertGreaterThan(try XCTUnwrap(stroke.source).x, 0.5)
        XCTAssertGreaterThan(abs(try XCTUnwrap(stroke.source).x-0.75), 0.04, "Do not sample any part of the long blemish itself")
        let output = try RetouchRenderer.apply(to: blemish, strokes: [stroke], context: context)
        let centre = retouchPixel(output, x:192,y:64,context:context)
        let expected = retouchPixel(background, x:192,y:64,context:context)
        for channel in 0..<3 { XCTAssertLessThan(abs(Int(centre[channel])-Int(expected[channel])), 15) }
        XCTAssertEqual(retouchPixel(output,x:20,y:20,context:context), retouchPixel(background,x:20,y:20,context:context))
        XCTAssertEqual(try JSONDecoder().decode(RetouchStroke.self, from: JSONEncoder().encode(stroke)), stroke)
    }

    func testWholeStrokeHealingKitchenStalk() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Resources/DemoWorkspace/Photos/23-warm-cast-kitchen.jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Repository demo fixture unavailable") }
        let processor = ImageProcessor(), context = CIContext()
        var c = ProcessingConfiguration(); c.nativeOutputSizing = true
        let before = try await processor.render(url, configuration: c, previewMaximum: 1000)
        var stroke = RetouchStroke(); stroke.samplingVersion = 3; stroke.diameter = 0.03; stroke.hardness = 0.65
        stroke.points = (0...24).map { i in let t = Double(i)/24; return NormalizedPoint(0.588+0.010*t,0.120+0.106*t) }
        let clock = ContinuousClock(); let start = clock.now
        stroke.source = try await processor.retouchSource(before, points: stroke.points, diameter: stroke.diameter)
        let sampled = clock.now
        c.retouchStrokes = [stroke]
        let after = try await processor.render(url, configuration: c, previewMaximum: 1000)
        print("KITCHEN RETOUCH sampling \(start.duration(to: sampled)); rendering \(sampled.duration(to: clock.now)); source \(String(describing: stroke.source))")
        let x = Int(0.596 * Double(after.width)), y = Int((1-0.173) * Double(after.height))
        let old = retouchPixel(CIImage(cgImage: before), x:x,y:y,context:context)
        let new = retouchPixel(CIImage(cgImage: after), x:x,y:y,context:context)
        let wall = retouchPixel(CIImage(cgImage: before), x: Int(0.61 * Double(after.width)), y:y,context:context)
        let oldError = zip(old.prefix(3), wall.prefix(3)).reduce(0) { $0 + abs(Int($1.0)-Int($1.1)) }
        let newError = zip(new.prefix(3), wall.prefix(3)).reduce(0) { $0 + abs(Int($1.0)-Int($1.1)) }
        XCTAssertLessThan(newError, oldError / 4, "The stalk interior must match nearby clean wall rather than copy another stalk fragment")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("ameluma-kitchen-v3.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1,nil))
        CGImageDestinationAddImage(destination, after,nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        print("KITCHEN RETOUCH image: \(output.path)")
    }

    func testRetouchPreviewTimingDiagnostic() async throws {
        let url = try fixture(width: 4000, height: 3000)
        let processor = ImageProcessor()
        var c = ProcessingConfiguration(); c.nativeOutputSizing = true
        let clock = ContinuousClock()
        var start = clock.now
        _ = try await processor.render(url, configuration: c, previewMaximum: 1000)
        print("RETOUCH TIMING cold preview: \(start.duration(to: clock.now))")
        for mode in [RetouchMode.clone, .heal] {
            c.retouchStrokes = []
            for index in 0..<12 {
                var stroke = RetouchStroke(); stroke.mode = mode
                stroke.source = NormalizedPoint(0.3, 0.4)
                stroke.points = [NormalizedPoint(0.5 + Double(index) * 0.01, 0.5)]
                c.retouchStrokes.append(stroke)
            }
            start = clock.now
            let output = try await processor.render(url, configuration: c, previewMaximum: 1000)
            XCTAssertEqual(max(output.width, output.height), 1000)
            print("RETOUCH TIMING 12 \(mode.rawValue) dabs: \(start.duration(to: clock.now))")
        }
    }

    func testPixelSizedRetouchDabIsAcceptedWithoutChangingLegacyStrokes() throws {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let image = CIImage(cgImage: try retouchFixture())
        var dab = RetouchStroke(); dab.mode = .clone
        dab.source = NormalizedPoint(0.25, 0.5); dab.points = [NormalizedPoint(0.75, 0.5)]
        dab.diameter = 0.001
        let output = try RetouchRenderer.apply(to: image, strokes: [dab], context: context)
        XCTAssertEqual(output.extent, image.extent)
        XCTAssertNotNil(context.createCGImage(output, from: output.extent))
        XCTAssertEqual(RetouchStroke().diameter, 0.03)
        dab.diameter = 0
        XCTAssertThrowsError(try RetouchRenderer.apply(to: image, strokes: [dab], context: context))
    }

    func testRetouchCloneDabsOpacityHealingAndProtectedSourcePixels() throws {
        let original = CIImage(cgImage: try retouchFixture()), context = CIContext()
        var stroke = RetouchStroke(); stroke.mode = .clone
        stroke.points = [NormalizedPoint(0.75, 0.5)]; stroke.source = NormalizedPoint(0.25, 0.5)
        stroke.diameter = 0.3; stroke.hardness = 1
        let cloned = try RetouchRenderer.apply(to: original, strokes: [stroke], context: context)
        let centre = retouchPixel(cloned, x: 192, y: 64, context: context)
        XCTAssertGreaterThan(centre[0], 240); XCTAssertLessThan(centre[2], 10)
        XCTAssertEqual(retouchPixel(cloned, x: 250, y: 64, context: context), retouchPixel(original, x: 250, y: 64, context: context))
        var tapped = stroke; tapped.points = [stroke.points[0], stroke.points[0]]
        let tap = try RetouchRenderer.apply(to: original, strokes: [tapped], context: context)
        XCTAssertGreaterThan(retouchPixel(tap, x: 192, y: 64, context: context)[0], 240, "A zero-distance pointer/touch gesture is still a brush dab")
        var line = stroke; line.points = [NormalizedPoint(0.65, 0.5), NormalizedPoint(0.85, 0.5)]; line.source = NormalizedPoint(0.15, 0.5)
        let continuous = try RetouchRenderer.apply(to: original, strokes: [line], context: context)
        XCTAssertGreaterThan(retouchPixel(continuous, x: 192, y: 64, context: context)[0], 240)
        let many = try RetouchRenderer.apply(to: original, strokes: Array(repeating: stroke, count: 9), context: context)
        XCTAssertGreaterThan(retouchPixel(many, x: 192, y: 64, context: context)[0], 240)
        let auto = try RetouchRenderer.suggestedSource(in: retouchFixture(), at: NormalizedPoint(0.75, 0.5), diameter: 0.06, context: context)
        XCTAssertEqual(auto, try RetouchRenderer.suggestedSource(in: retouchFixture(), at: NormalizedPoint(0.75, 0.5), diameter: 0.06, context: context))
        XCTAssertGreaterThan(auto.x, 0.5)
        stroke.opacity = 0.5
        let blended = try RetouchRenderer.apply(to: original, strokes: [stroke], context: context)
        let middle = retouchPixel(blended, x: 192, y: 64, context: context)
        XCTAssertGreaterThan(middle[0], 70); XCTAssertGreaterThan(middle[2], 70)
        stroke.opacity = 1; stroke.mode = .heal
        let healed = try RetouchRenderer.apply(to: original, strokes: [stroke], context: context)
        let matched = retouchPixel(healed, x: 192, y: 64, context: context)
        XCTAssertLessThan(matched[0], 15); XCTAssertGreaterThan(matched[2], 240, "Healing must match destination color rather than stamp red source color")
        let blemish = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 188, y: 60, width: 8, height: 8)).composited(over: original)
        let repaired = try RetouchRenderer.apply(to: blemish, strokes: [stroke], context: context)
        let repair = retouchPixel(repaired, x: 192, y: 64, context: context)
        XCTAssertLessThan(repair[0], 120); XCTAssertLessThan(repair[1], 120)
        XCTAssertGreaterThan(repair[2], 240, "Healing must substantially reduce the bright blemish while retaining the surrounding blue tone")
        stroke.mode = .clone
        var privacy = PrivacyMask(); privacy.x = 0; privacy.y = 0; privacy.width = 0.5; privacy.height = 1
        let protected = try RetouchRenderer.apply(to: original, strokes: [stroke], context: context, sourceMasks: [privacy])
        let concealed = retouchPixel(protected, x: 192, y: 64, context: context)
        XCTAssertLessThan(concealed[0], 10); XCTAssertLessThan(concealed[2], 10, "Cloning from a concealed source must never reveal original source pixels")
    }
    func testRetouchPersistenceSparsePatchValidationAndCancellation() async throws {
        var config = ProcessingConfiguration(), stroke = RetouchStroke()
        stroke.mode = .clone; stroke.source = NormalizedPoint(0.2, 0.2); stroke.points = [NormalizedPoint(0.7, 0.7), NormalizedPoint(0.8, 0.7)]
        config.retouchStrokes = [stroke]
        let restored = try JSONDecoder().decode(ProcessingConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
        XCTAssertTrue(try JSONDecoder().decode(ProcessingConfiguration.self, from: Data("{}".utf8)).retouchStrokes.isEmpty)
        let patch = ConfigurationPatch(from: ProcessingConfiguration(), to: config)
        XCTAssertEqual(patch.fields, [.retouchStrokes])
        let decoded = try JSONDecoder().decode(ConfigurationPatch.self, from: JSONEncoder().encode(patch))
        XCTAssertEqual(decoded.applying(to: ProcessingConfiguration()).retouchStrokes, [stroke])
        let original = CIImage(cgImage: try retouchFixture()), context = CIContext()
        var invalid = stroke; invalid.points = [NormalizedPoint(.nan, 0)]
        XCTAssertThrowsError(try RetouchRenderer.apply(to: original, strokes: [invalid], context: context))
        let cancelled = Task { () throws -> Bool in
          while !Task.isCancelled { await Task.yield() }
          _ = try RetouchRenderer.apply(to: original, strokes: [stroke], context: context)
          return true
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled retouch work must stop") } catch is CancellationError {}
    }
    func testRetouchExportReopensAndPreservesOriginal() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try retouchFixture(), nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try Data(contentsOf: url)
        var config = ProcessingConfiguration(), stroke = RetouchStroke()
        config.nativeOutputSizing = true; config.format = .png
        stroke.mode = .clone; stroke.source = NormalizedPoint(0.25, 0.5); stroke.points = [NormalizedPoint(0.75, 0.5)]; stroke.hardness = 1; stroke.diameter = 0.2
        config.retouchStrokes = [stroke]
        let processor = ImageProcessor()
        let full = try await processor.render(url, configuration: config)
        let preview = try await processor.render(url, configuration: config, previewMaximum: 128)
        let context = CIContext()
        XCTAssertGreaterThan(retouchPixel(CIImage(cgImage: full), x: 192, y: 64, context: context)[0], 240)
        XCTAssertGreaterThan(retouchPixel(CIImage(cgImage: preview), x: 96, y: 32, context: context)[0], 240)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let out = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: out) }
        let encoded = try XCTUnwrap(CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoded, full, nil); XCTAssertTrue(CGImageDestinationFinalize(encoded))
        let reopened = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(reopened), 1)
        XCTAssertEqual(try XCTUnwrap(CGImageSourceCreateImageAtIndex(reopened, 0, nil)).width, full.width)
    }
}

final class PhotoLookTests: XCTestCase {
  func pixel(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4)
    try bytes.withUnsafeMutableBytes { data in
      let context = try XCTUnwrap(CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
        bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return bytes
  }
  func testStrengthEndpointsBlendingAndDistinctRecipesPreserveAlpha() throws {
    let image = CIImage(color: CIColor(red: 0.58, green: 0.36, blue: 0.22, alpha: 0.65))
      .cropped(to: CGRect(x: 0, y: 0, width: 12, height: 8))
    let context = CIContext(options: [.useSoftwareRenderer: true])
    func values(_ input: CIImage) throws -> [UInt8] { try pixel(XCTUnwrap(context.createCGImage(input, from: image.extent))) }
    let original = try values(image)
    var outputs = Set<[UInt8]>()
    for look in PhotoLook.allCases {
      let zero = try values(look.apply(to: image, strength: 0))
      let full = try values(look.apply(to: image, strength: 1))
      let half = try values(look.apply(to: image, strength: 0.5))
      XCTAssertEqual(zero, original)
      XCTAssertNotEqual(full, original)
      XCTAssertEqual(Double(full[3]), Double(original[3]), accuracy: 1)
      XCTAssertEqual(Double(half[3]), Double(original[3]), accuracy: 1)
      // Colour-space conversion is nonlinear, but intermediate strength remains between endpoints.
      for i in 0..<3 {
        XCTAssertGreaterThanOrEqual(Int(half[i]), min(Int(full[i]), Int(original[i])) - 2)
        XCTAssertLessThanOrEqual(Int(half[i]), max(Int(full[i]), Int(original[i])) + 2)
      }
      outputs.insert(full)
    }
    XCTAssertEqual(outputs.count, PhotoLook.allCases.count)
    for strength in [Double.nan, .infinity, -0.1, 1.1] {
      XCTAssertThrowsError(try PhotoLook.warm.apply(to: image, strength: strength))
    }
  }
  func testLegacyDecodeAndSparsePatchRemovalPreserveOtherEdits() throws {
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(ProcessingConfiguration())) as? [String: Any])
    old.removeValue(forKey: "look"); old.removeValue(forKey: "lookStrength")
    let legacy = try decoder.decode(ProcessingConfiguration.self, from: JSONSerialization.data(withJSONObject: old))
    XCTAssertNil(legacy.look); XCTAssertEqual(legacy.lookStrength, 1)
    var edited = legacy
    edited.adjustments.exposure = 0.4; edited.crop.centerX = 0.7; edited.masks = [PrivacyMask()]
    var filtered = edited; filtered.look = .warm; filtered.lookStrength = 0.65
    let patch = ConfigurationPatch(from: edited, to: filtered)
    XCTAssertEqual(patch.fields, [.look, .lookStrength])
    let restored = try decoder.decode(ConfigurationPatch.self, from: encoder.encode(patch)).applying(to: edited)
    XCTAssertEqual(restored, filtered)
    var remove = filtered; remove.look = nil
    let removal = ConfigurationPatch(values: remove, fields: [.look])
    let result = try decoder.decode(ConfigurationPatch.self, from: encoder.encode(removal)).applying(to: restored)
    XCTAssertNil(result.look)
    XCTAssertEqual(result.adjustments, edited.adjustments); XCTAssertEqual(result.crop, edited.crop)
    XCTAssertEqual(result.masks, edited.masks); XCTAssertEqual(result.lookStrength, 0.65)
    XCTAssertEqual(try decoder.decode(ProcessingConfiguration.self, from: encoder.encode(filtered)), filtered)
  }
  func testPreviewExportAgreementCollisionAndOriginalPreservation() async throws {
    let helper = ProcessingTests()
    let source = try helper.fixture(width: 80, height: 40)
    let original = try Data(contentsOf: source)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: source) }
    let engine = ImageProcessor()
    var config = ProcessingConfiguration(); config.width = 80; config.height = 40; config.format = .png
    config.look = .cool; config.lookStrength = 0.7; config.adjustments.exposure = 0.2
    let preview = try await engine.render(source, configuration: config, previewMaximum: 160)
    let asset = SourceAsset(url: source)
    let first = try await engine.export(asset, configuration: config, to: folder)
    let second = try await engine.export(asset, configuration: config, to: folder)
    XCTAssertNotEqual(first.output, second.output)
    let url = try XCTUnwrap(first.output)
    let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let reopened = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, 0, nil))
    XCTAssertEqual(reopened.width, 80); XCTAssertEqual(reopened.height, 40)
    let a = try pixel(preview), b = try pixel(reopened)
    for i in 0..<4 { XCTAssertEqual(Double(a[i]), Double(b[i]), accuracy: 2) }
    XCTAssertEqual(try Data(contentsOf: source), original)
    config.lookStrength = .nan
    do { _ = try await engine.render(source, configuration: config); XCTFail("Invalid strength must fail") }
    catch { XCTAssertTrue(error is ProcessingError) }
  }
}
