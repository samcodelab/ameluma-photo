import Foundation
import Darwin
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// One full-resolution operation at a time; thumbnail cache has a strict cost/count budget.
public actor ImageProcessor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let filterContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
    private let cache = NSCache<NSString, CGImage>()
    private let maximumSourcePixels: Int
    private var privateMode = false
    public func setPrivateMode(_ enabled: Bool) { privateMode = enabled; cache.removeAllObjects() }
    public init(maximumSourcePixels: Int = 100_000_000) { self.maximumSourcePixels = max(1, maximumSourcePixels); cache.totalCostLimit = 32 * 1024 * 1024; cache.countLimit = 128 }
    public nonisolated static var inputTypes: [String] { CGImageSourceCopyTypeIdentifiers() as? [String] ?? [] }
    public nonisolated static var outputFormats: [OutputFormat] {
        let native = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return OutputFormat.allCases.filter { native.contains($0.typeIdentifier) }
    }
    public nonisolated static var importTypes: [UTType] { [.jpeg, .png, .heic, .tiff, .webP].filter { inputTypes.contains($0.identifier) } }
    public func importSnapshot(_ url: URL, to directory: URL) throws -> SourceAsset {
        try Task.checkCancellation(); _ = try identify(url)
        let copy = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        do { try FileManager.default.copyItem(at: url.resolvingSymlinksInPath(), to: copy); try Task.checkCancellation(); _ = try identify(copy); return SourceAsset(url: copy, name: url.lastPathComponent) }
        catch { if (error as NSError).code != CocoaError.fileWriteFileExists.rawValue { try? FileManager.default.removeItem(at: copy) }; throw error }
    }
    public func importData(_ data: Data, name: String, to directory: URL) throws -> SourceAsset {
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension((name as NSString).pathExtension)
        do { try data.write(to: url, options: .atomic); _ = try identify(url); return SourceAsset(url: url, name: name) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }
    public func folderImages(_ folder: URL) throws -> [URL] {
        guard folder.isFileURL else { throw ProcessingError.invalidImage }
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw ProcessingError.destination }
        var urls: [URL] = []
        for case let url as URL in walker {
            try Task.checkCancellation(); let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            if let type = UTType(filenameExtension: url.pathExtension), Self.importTypes.contains(where: { type.conforms(to: $0) }) { urls.append(url) }
        }
        return urls.sorted { $0.path < $1.path }
    }
    public func identify(_ url: URL) throws -> CGSize {
        guard url.isFileURL else { throw ProcessingError.invalidImage }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetStatus(source) == .statusComplete, let type = CGImageSourceGetType(source), Self.importTypes.contains(where: { $0.identifier == type as String }), let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { throw ProcessingError.invalidImage }
        guard Double(w) * Double(h) <= Double(maximumSourcePixels) else { throw ProcessingError.sourceTooLarge }
        let storedOrientation = p[kCGImagePropertyOrientation] as? Int ?? 1
        let orientation = (1...8).contains(storedOrientation) ? storedOrientation : 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
    public func thumbnail(_ url: URL, maximum: Int = 240) throws -> CGImage {
        try Task.checkCancellation()
        guard maximum > 0, maximum <= 20000 else { throw ProcessingError.invalidConfiguration }
        _ = try identify(url)
        let fingerprint = try SourceFingerprint.read(url)
        let key = "\(url.path)|\(maximum)|\(fingerprint.modified.timeIntervalSince1970)|\(fingerprint.bytes)" as NSString
        if !privateMode, let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximum] as CFDictionary) else { throw ProcessingError.invalidImage }
        if !privateMode { cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height) }; return image
    }
    private func transform(_ source: CIImage, configuration c: ProcessingConfiguration) -> CIImage {
        var image = source
        let turns = ((c.quarterTurns % 4 + c.crop.quarterTurns % 4) % 4 + 4) % 4
        if turns != 0 { image = image.oriented(forExifOrientation: [1, 6, 3, 8][turns]) }
        if c.flipHorizontal != c.crop.flipHorizontal { image = image.oriented(.upMirrored) }
        if c.flipVertical != c.crop.flipVertical { image = image.oriented(.downMirrored) }
        if c.straighten + c.crop.straighten != 0 { image = image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(c.straighten + c.crop.straighten) * .pi / 180)) }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
    public func analysisThumbnail(_ url: URL, configuration c: ProcessingConfiguration, maximum: Int = 1200) throws -> CGImage {
        let cg = try thumbnail(url, maximum: maximum); let image = transform(CIImage(cgImage: cg), configuration: c)
        guard let result = context.createCGImage(image, from: image.extent) else { throw ProcessingError.invalidImage }; return result
    }
    public nonisolated static func transformedSize(_ source: CGSize, configuration c: ProcessingConfiguration) -> CGSize {
        let turns = ((c.quarterTurns % 4 + c.crop.quarterTurns % 4) % 4 + 4) % 4
        let rotated = turns % 2 == 0 ? source : CGSize(width: source.height, height: source.width)
        let angle = abs(CGFloat(c.straighten + c.crop.straighten) * .pi / 180)
        return CGSize(width: rotated.width * cos(angle) + rotated.height * sin(angle), height: rotated.height * cos(angle) + rotated.width * sin(angle))
    }
    public nonisolated static func outputSize(source: CGSize, configuration c: ProcessingConfiguration) -> CGSize {
        if c.nativeOutputSizing == true {
            if c.crop.mode == .fill || c.crop.mode == .manualCrop {
                let crop = CropGeometry.rect(source: source, ratio: Double(c.width) / Double(max(1, c.height)), crop: c.crop)
                return CGSize(width: max(1, crop.width.rounded()), height: max(1, crop.height.rounded()))
            }
            if c.crop.mode == .canvas || c.crop.mode == .stretch {
                let factor = max(source.width, source.height) / CGFloat(max(c.width, c.height, 1))
                return CGSize(width: max(1, (CGFloat(c.width) * factor).rounded()), height: max(1, (CGFloat(c.height) * factor).rounded()))
            }
            return CGSize(width: max(1, source.width.rounded()), height: max(1, source.height.rounded()))
        }
        var w = CGFloat(c.width); var h = CGFloat(c.height)
        if c.crop.mode == .preserveAspectRatio {
            switch c.resizeBasis {
            case .width: h = (w * source.height / source.width).rounded()
            case .height: w = (h * source.width / source.height).rounded()
            case .longestEdge: let scale = w / max(source.width, source.height); w = (source.width * scale).rounded(); h = (source.height * scale).rounded()
            case .percentage: w = (source.width * c.percentage / 100).rounded(); h = (source.height * c.percentage / 100).rounded()
            }
        }
        return CGSize(width: max(1, w), height: max(1, h))
    }
    public func retouchSource(_ image: CGImage, at point: NormalizedPoint, diameter: Double) throws -> NormalizedPoint {
        try Task.checkCancellation()
        return try RetouchRenderer.suggestedSource(in: image, at: point, diameter: diameter, context: context)
    }
    public func render(_ url: URL, configuration c: ProcessingConfiguration, previewMaximum: Int? = nil, decodeMaximum: Int? = nil) throws -> CGImage {
        try Task.checkCancellation()
        guard c.width > 0, c.height > 0, c.width <= 20000, c.height <= 20000, Double(c.width) * Double(c.height) <= 100_000_000, c.quality.isFinite, (0...1).contains(c.quality), c.percentage.isFinite, c.percentage > 0, c.crop.centerX.isFinite, c.crop.centerY.isFinite, c.crop.zoom.isFinite, (1...20).contains(c.crop.zoom), c.straighten.isFinite, c.crop.straighten.isFinite, abs(c.straighten + c.crop.straighten) <= 45, c.crop.aspectRatio.map({ $0.isFinite && $0 > 0 }) ?? true else { throw ProcessingError.invalidConfiguration }
        guard [c.background.red, c.background.green, c.background.blue, c.background.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ProcessingError.invalidConfiguration }
        let nominal = try identify(url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ProcessingError.invalidImage }
        let cg: CGImage; var image: CIImage
        if let maximum = previewMaximum {
            guard maximum > 0 else { throw ProcessingError.invalidConfiguration }
            cg = try thumbnail(url, maximum: min(20000, max(1, decodeMaximum ?? max(maximum, 1200)))); image = CIImage(cgImage: cg)
        } else {
            guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ProcessingError.invalidImage }
            cg = decoded; let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
            image = CIImage(cgImage: decoded).oriented(forExifOrientation: Int32((1...8).contains(orientation) ? orientation : 1))
        }
        guard c.lookStrength.isFinite, (0...1).contains(c.lookStrength) else { throw ProcessingError.invalidConfiguration }
        image = try c.adjustments.apply(to: transform(image, configuration: c))
        if let look = c.look { image = try look.apply(to: image, strength: c.lookStrength) }
        // Nominal geometry is computed before downsampling so percentage/longest-edge match export.
        let fullSize = Self.transformedSize(nominal, configuration: c)
        let fullOutput = Self.outputSize(source: fullSize, configuration: c)
        guard fullOutput.width <= 20000, fullOutput.height <= 20000, fullOutput.width * fullOutput.height <= 100_000_000 else { throw ProcessingError.invalidConfiguration }
        var size = fullOutput
        if let limit = previewMaximum { let scale = min(1, CGFloat(limit) / max(size.width, size.height)); size = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded())) }
        let layout = FramingLayout(source: fullSize, output: fullOutput, configuration: c)
        let sourceScaleX = image.extent.width / fullSize.width; let sourceScaleY = image.extent.height / fullSize.height
        let top = CGRect(x: layout.cropRect.minX * sourceScaleX, y: layout.cropRect.minY * sourceScaleY, width: layout.cropRect.width * sourceScaleX, height: layout.cropRect.height * sourceScaleY)
        let rect = CGRect(x: top.minX, y: image.extent.height - top.maxY, width: top.width, height: top.height)
        image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let canvasScaleX = size.width / fullOutput.width; let canvasScaleY = size.height / fullOutput.height
        image = image.transformed(by: CGAffineTransform(scaleX: layout.scaleX * canvasScaleX / sourceScaleX, y: layout.scaleY * canvasScaleY / sourceScaleY))
        image = image.transformed(by: CGAffineTransform(translationX: layout.contentRect.minX * canvasScaleX, y: size.height - layout.contentRect.maxY * canvasScaleY))
        let bounds = CGRect(origin: .zero, size: size)
        if c.filterEdit?.presetID != nil || c.autoEnhance?.enabled == true {
            let spaceName = cg.colorSpace?.name as String? ?? ""
            if cg.contentHeadroom > 1 || CGImageSourceCopyAuxiliaryDataInfoAtIndex(source,0,kCGImageAuxiliaryDataTypeHDRGainMap) != nil || spaceName.localizedCaseInsensitiveContains("PQ") || spaceName.localizedCaseInsensitiveContains("HLG") || spaceName.localizedCaseInsensitiveContains("2100") { throw CreativeFilterError.hdr }
            // New SDR recipes operate on the framed photo, before canvas, retouch,
            // protective overlays and watermarks. Legacy looks retain their old order.
            if let enhancement = c.autoEnhance { image = try enhancement.apply(to: image) }
            image = try CreativeFilterRenderer.apply(c.filterEdit, to: image, fullSize: CGSize(width:image.extent.width/canvasScaleX,height:image.extent.height/canvasScaleY))
        }
        var colour = c.background
        if !c.format.preservesAlpha && colour.alpha < 1 {
            colour.red = colour.red * colour.alpha + 1 - colour.alpha; colour.green = colour.green * colour.alpha + 1 - colour.alpha; colour.blue = colour.blue * colour.alpha + 1 - colour.alpha; colour.alpha = 1
        }
        let background = CIImage(color: CIColor(cgColor: colour.cgColor)).cropped(to: bounds)
        if c.canvasStyle.shadow {
            let distance=min(size.width,size.height)*0.012
            let shadow=image.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:0,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:0,w:0),"inputAVector":CIVector(x:0,y:0,z:0,w:0.3)]).applyingFilter("CIGaussianBlur",parameters:["inputRadius":distance]).transformed(by:CGAffineTransform(translationX:distance,y:-distance))
            image=image.composited(over:shadow)
        }
        image = image.composited(over: background).cropped(to: bounds)
        image = try RetouchRenderer.apply(to: image, strokes: c.retouchStrokes, context: context, sourceMasks: c.masks)
        image = try PrivacyRenderer.apply(to: image, masks: c.masks)
        if !c.annotations.isEmpty || c.canvasStyle != CanvasStyle() { image = try AnnotationRenderer.apply(to: image, annotations: c.annotations, canvas: c.canvasStyle) }
        image = try WatermarkRenderer.apply(to: image, configuration: c.watermark)
        if !c.format.preservesAlpha { image = image.composited(over: background).cropped(to: bounds) }
        try Task.checkCancellation()
        let space = c.colourPolicy == .preserve && cg.colorSpace?.model == .rgb ? cg.colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
        let renderingContext = (c.filterEdit?.presetID != nil && (c.filterEdit?.intensity ?? 0) > 0) || c.autoEnhance?.enabled == true ? filterContext : context
        guard let space, let result = renderingContext.createCGImage(image, from: bounds, format: .RGBA8, colorSpace: space) else { throw ProcessingError.encoding }
        return result
    }
    public func validateCreativeSource(_ url: URL) throws {
        _ = try identify(url)
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil) else { throw ProcessingError.invalidImage }
        if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source,0,kCGImageAuxiliaryDataTypeHDRGainMap) != nil { throw CreativeFilterError.hdr }
        let p=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] ?? [:]
        let profile=p[kCGImagePropertyProfileName] as? String ?? ""
        if ["PQ","HLG","2100"].contains(where:{profile.localizedCaseInsensitiveContains($0)}) { throw CreativeFilterError.hdr }
    }
    public func resolveAutoEnhance(_ url: URL, configuration: ProcessingConfiguration) throws -> AutoEnhanceEdit {
        var c = configuration; c.filterEdit = nil; c.look = nil; c.autoEnhance = nil
        c.watermark.enabled = false; c.annotations = []; c.masks = []; c.retouchStrokes = []
        let cg = try render(url, configuration:c, previewMaximum:1024, decodeMaximum:1200)
        try Task.checkCancellation()
        let filters = CIImage(cgImage:cg).autoAdjustmentFilters(options:[.enhance:true,.redEye:false,.crop:false,.level:false])
        return AutoEnhanceEdit(resolvedAdjustments:filters.compactMap(SerializedAdjustment.capture))
    }
    public func quickFix(_ fix: QuickFix, url: URL, configuration: ProcessingConfiguration) throws -> ProcessingConfiguration {
        var c = configuration
        if fix == .sharing { c.width = 1600; c.height = 1600; c.crop.mode = .fit; c.metadata = .removeLocation; return c }
        let image = CIImage(cgImage: try thumbnail(url, maximum: 800))
        let average=image.applyingFilter("CIAreaAverage", parameters:["inputExtent":CIVector(cgRect:image.extent)])
        var values=[Float](repeating:0,count:4)
        values.withUnsafeMutableBytes { buffer in if let address=buffer.baseAddress { context.render(average,toBitmap:address,rowBytes:16,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.linearSRGB)) } }
        let luminance=max(0.001,Double(values[0])*0.2126+Double(values[1])*0.7152+Double(values[2])*0.0722)
        if fix == .autoEnhance || fix == .lighting { c.adjustments.exposure=min(0.75,max(-0.75,log2(0.3/luminance))); c.adjustments.shadows=luminance < 0.2 ? 0.2 : 0 }
        if fix == .autoEnhance || fix == .colour { let ratio=Double(max(0.001,values[2]))/Double(max(0.001,values[0])); c.adjustments.warmth=min(0.25,max(-0.25,log2(ratio)*0.15)) }
        let filters = image.autoAdjustmentFilters(options: [.enhance: true, .redEye: false, .crop: false, .level: true])
        for filter in filters {
            if fix == .straighten, filter.name == "CIStraightenFilter", let angle = filter.value(forKey: "inputAngle") as? NSNumber { c.straighten = min(20, max(-20, -angle.doubleValue * 180 / .pi)) }
            if (fix == .autoEnhance || fix == .lighting), filter.name == "CIExposureAdjust", let ev = filter.value(forKey: "inputEV") as? NSNumber { c.adjustments.exposure = min(1, max(-1, ev.doubleValue)) }
            if (fix == .autoEnhance || fix == .lighting), filter.name == "CIHighlightShadowAdjust" { c.adjustments.shadows = min(0.5, max(0, (filter.value(forKey: "inputShadowAmount") as? NSNumber)?.doubleValue ?? 0)); c.adjustments.highlights = min(1, max(0.5, (filter.value(forKey: "inputHighlightAmount") as? NSNumber)?.doubleValue ?? 1)) }
            if (fix == .autoEnhance || fix == .colour), filter.name == "CIVibrance" { c.adjustments.saturation = min(1.25, max(0.8, 1 + ((filter.value(forKey: "inputAmount") as? NSNumber)?.doubleValue ?? 0) * 0.3)) }
        }
        return c
    }
    private func metadata(_ source: URL, image: CGImage, configuration c: ProcessingConfiguration) -> [CFString: Any] {
        var result: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if !c.privacyExport && c.masks.isEmpty && c.metadata != .remove, let source = CGImageSourceCreateWithURL(source as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary] { result[key] = props[key] }
            if c.metadata == .preserve { result[kCGImagePropertyGPSDictionary] = props[kCGImagePropertyGPSDictionary] }
            var exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            exif[kCGImagePropertyExifPixelXDimension] = image.width; exif[kCGImagePropertyExifPixelYDimension] = image.height; result[kCGImagePropertyExifDictionary] = exif
            var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]; tiff[kCGImagePropertyTIFFOrientation] = 1; result[kCGImagePropertyTIFFDictionary] = tiff
        }
        return result
    }
    public func encode(_ image: CGImage, format: OutputFormat, quality: Double, properties: [CFString: Any] = [:]) throws -> Data {
        guard Self.outputFormats.contains(format) else { throw ProcessingError.unsupportedFormat }
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else { throw ProcessingError.encoding }
        var props = properties; if format.supportsQuality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(encoder, image, props as CFDictionary); guard CGImageDestinationFinalize(encoder) else { throw ProcessingError.encoding }; return data as Data
    }
    public func export(_ asset: SourceAsset, configuration c: ProcessingConfiguration, to directory: URL, profile: ExportProfile = ExportProfile()) throws -> ProcessingResult {
        try Task.checkCancellation(); guard directory.isFileURL else { throw ProcessingError.destination }; guard Self.outputFormats.contains(c.format) else { throw ProcessingError.unsupportedFormat }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw ProcessingError.destination }
        let image = try render(asset.url, configuration: c); let props = metadata(asset.url, image: image, configuration: c)
        return try publish(image, asset: asset, configuration: c, to: directory, profile: profile, properties: props)
    }
    private func encodedData(_ input: CGImage, configuration c: ProcessingConfiguration, properties props: [CFString: Any], flattenTransparency: Bool = false) throws -> Data {
        guard c.quality.isFinite, (0...1).contains(c.quality), input.width <= 20000, input.height <= 20000, Double(input.width) * Double(input.height) <= 100_000_000 else { throw ProcessingError.invalidConfiguration }
        let image: CGImage
        if flattenTransparency && !c.format.preservesAlpha && input.alphaInfo != .none && input.alphaInfo != .noneSkipFirst && input.alphaInfo != .noneSkipLast {
            let source = CIImage(cgImage: input)
            let matte = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: source.extent)
            guard let flattened = context.createCGImage(source.composited(over: matte), from: source.extent, format: .RGBA8, colorSpace: input.colorSpace ?? CGColorSpaceCreateDeviceRGB()) else { throw ProcessingError.encoding }
            image = flattened
        } else { image = input }
        var data = try encode(image, format: c.format, quality: c.quality, properties: props)
        if let target = c.targetBytes {
            guard target > 0, c.minimumQuality.isFinite, c.minimumQuality >= 0.1, c.minimumQuality <= c.quality else { throw ProcessingError.invalidConfiguration }
            if data.count > target {
                guard c.format.supportsQuality else { throw ProcessingError.targetSizeUnreachable }
                var lower = c.minimumQuality; var upper = c.quality
                var best = try encode(image, format: c.format, quality: lower, properties: props)
                guard best.count <= target else { throw ProcessingError.targetSizeUnreachable }
                for _ in 0..<7 { try Task.checkCancellation(); let mid = (lower + upper) / 2; let candidate = try encode(image, format: c.format, quality: mid, properties: props); if candidate.count <= target { best = candidate; lower = mid } else { upper = mid } }
                data = best
            }
        }
        return data
    }
    /// Full-resolution encoded preview uses precisely the export encoding/compression path.
    public func encodedPreview(_ url: URL, configuration c: ProcessingConfiguration) throws -> EncodedOutputPreview {
        let rendered = try render(url, configuration: c)
        let data = try encodedData(rendered, configuration: c, properties: metadata(url, image: rendered, configuration: c))
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetStatus(source) == .statusComplete,
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil), decoded.width == rendered.width, decoded.height == rendered.height else { throw ProcessingError.validation }
        return EncodedOutputPreview(image: decoded, byteCount: data.count)
    }
    /// Proof of an already composed image uses the exact same encoder as publication.
    public func encodedPreview(_ image: CGImage, configuration c: ProcessingConfiguration) throws -> EncodedOutputPreview {
        let data = try encodedData(image, configuration: c, properties: [:], flattenTransparency: true)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetStatus(source) == .statusComplete,
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil), decoded.width == image.width, decoded.height == image.height else { throw ProcessingError.validation }
        return EncodedOutputPreview(image: decoded, byteCount: data.count)
    }
    public func publish(_ image: CGImage, asset: SourceAsset, configuration c: ProcessingConfiguration, to directory: URL, profile: ExportProfile = ExportProfile(), properties props: [CFString: Any] = [:], flattenTransparency: Bool = false) throws -> ProcessingResult {
        try Task.checkCancellation()
        let data = try encodedData(image, configuration: c, properties: props, flattenTransparency: flattenTransparency)
        try Task.checkCancellation()
        let staging = directory.appendingPathComponent(".framepebble-\(UUID().uuidString).tmp")
        try StagingWriter.write(data, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard let source = CGImageSourceCreateWithURL(staging as CFURL, nil), CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetType(source) as String? == c.format.typeIdentifier, let validated = CGImageSourceCreateImageAtIndex(source, 0, nil), validated.width == image.width, validated.height == image.height else { throw ProcessingError.validation }
        try Task.checkCancellation()
        let stem = (Self.proposedFilename(asset: asset, profile: profile, format: c.format) as NSString).deletingPathExtension
        let output = try publishStaging(staging, sourceURL: asset.url, stem: stem, fileExtension: c.format.fileExtension, directory: directory)
        return ProcessingResult(source: asset, output: output)
    }
    private func publishStaging(_ staging: URL, sourceURL: URL, stem: String, fileExtension: String, directory: URL) throws -> URL {
        for n in 0..<10000 {
            try Task.checkCancellation()
            let output = directory.appendingPathComponent(stem + (n == 0 ? "" : "-\(n)") + "." + fileExtension)
            if output.resolvingSymlinksInPath().standardizedFileURL == sourceURL.resolvingSymlinksInPath().standardizedFileURL { continue }
            let code = staging.withUnsafeFileSystemRepresentation { from in output.withUnsafeFileSystemRepresentation { to in guard let from, let to else { return Int32(-1) }; return renamex_np(from, to, UInt32(RENAME_EXCL)) } }
            if code == 0 { return output }; if errno == EEXIST { continue }; throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        throw ProcessingError.destination
    }
}

public struct EncodedOutputPreview: @unchecked Sendable { public let image: CGImage; public let byteCount: Int }

extension ImageProcessor {
    /// Copies already flattened, validated outputs without recompression. Publication
    /// shares the exclusive staging path with ordinary image export.
    public func copyValidatedOutput(_ sourceURL: URL, to directory: URL) throws -> URL {
        guard sourceURL.isFileURL, directory.isFileURL else { throw ProcessingError.destination }
        try Task.checkCancellation()
        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetStatus(source) == .statusComplete,
          let type = CGImageSourceGetType(source) as String? else { throw ProcessingError.validation }
        let isGIF = type == UTType.gif.identifier
        let format = OutputFormat.allCases.first(where: { $0.typeIdentifier == type })
        guard isGIF || (CGImageSourceGetCount(source) == 1 && format != nil) else { throw ProcessingError.validation }
        for index in 0..<CGImageSourceGetCount(source) {
            try Task.checkCancellation()
            try autoreleasepool {
                guard CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { throw ProcessingError.validation }
            }
        }
        let staging = directory.appendingPathComponent(".framepebble-" + UUID().uuidString + ".tmp")
        try StagingWriter.write(data, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard let check = CGImageSourceCreateWithURL(staging as CFURL, nil), CGImageSourceGetStatus(check) == .statusComplete else { throw ProcessingError.validation }
        var profile = ExportProfile(); profile.suffix = ""; profile.namingTemplate = "{name}"
        let asset = SourceAsset(url: sourceURL)
        let stem = (Self.proposedFilename(asset: asset, profile: profile, format: format ?? .png) as NSString).deletingPathExtension
        return try publishStaging(staging, sourceURL: sourceURL, stem: stem, fileExtension: isGIF ? "gif" : (format ?? .png).fileExtension, directory: directory)
    }
    public nonisolated static func proposedFilename(asset: SourceAsset, profile: ExportProfile, format: OutputFormat) -> String {
        let raw = (asset.name as NSString).deletingPathExtension
        let proposed = profile.namingTemplate.replacingOccurrences(of: "{name}", with: raw).replacingOccurrences(of: "{suffix}", with: profile.suffix).replacingOccurrences(of: "{id}", with: asset.id.uuidString.prefix(8))
        let safe = String(proposed.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character(String($0)) : "_" }.prefix(140))
        var bounded = ""
        for character in safe { let next = bounded + String(character); if next.utf8.count > 180 { break }; bounded = next }
        let stem = bounded.isEmpty ? "image" : bounded
        return stem + "." + format.fileExtension
    }
    public func watermarkBounds(_ configuration: WatermarkConfiguration, output: CGSize) throws -> CGRect {
        let stamp = try WatermarkRenderer.stamp(configuration, outputWidth: output.width)
        let rotated = stamp.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(configuration.rotation) * .pi / 180))
        return WatermarkRenderer.placement(size: rotated.extent.size, output: output, configuration: configuration)
    }
}
