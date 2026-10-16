import Foundation
import CoreGraphics

public struct SourceAsset: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var url: URL
    public var name: String
    public init(url: URL, name: String? = nil) { id = UUID(); self.url = url; self.name = name ?? url.lastPathComponent }
}
public enum CropMode: String, Codable, Sendable, CaseIterable { case fit, fill, stretch, preserveAspectRatio, canvas, manualCrop }
public enum FramingMode: String, Codable, Sendable, CaseIterable { case centre, smart, keepSubjects, manual }
public enum ResizeBasis: String, Codable, Sendable, CaseIterable { case width, height, longestEdge, percentage }
public enum MetadataPolicy: String, Codable, Sendable, CaseIterable { case remove, preserve, removeLocation }
public enum ColourPolicy: String, Codable, Sendable, CaseIterable { case sRGB, preserve }
public enum OutputFormat: String, Codable, Sendable, CaseIterable {
    case jpeg, png, heic, tiff, webp
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var typeIdentifier: String { switch self { case .jpeg: "public.jpeg"; case .png: "public.png"; case .heic: "public.heic"; case .tiff: "public.tiff"; case .webp: "org.webmproject.webp" } }
    public var supportsQuality: Bool { self == .jpeg || self == .heic || self == .webp }
    public var preservesAlpha: Bool { self == .png || self == .tiff || self == .webp }
}
public struct RGBAColour: Codable, Sendable, Hashable {
    public var red: Double; public var green: Double; public var blue: Double; public var alpha: Double
    public init(_ red: Double = 1, _ green: Double = 1, _ blue: Double = 1, _ alpha: Double = 0) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
    public var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
}
/// Top-left normalized coordinates on the EXIF-oriented, user-rotated source.
/// The output frame remains fixed. Position describes its centre within the source.
public struct CropConfiguration: Codable, Sendable, Equatable, Hashable {
    public var mode: CropMode = .fit
    public var framing: FramingMode = .centre
    public var centerX: Double = 0.5
    public var centerY: Double = 0.5
    public var zoom: Double = 1
    public var aspectRatio: Double? = nil
    public var quarterTurns: Int = 0
    public var straighten: Double = 0
    public var flipHorizontal = false
    public var flipVertical = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case mode, framing, centerX, centerY, zoom, aspectRatio, quarterTurns, straighten, flipHorizontal, flipVertical }
    public init(from decoder: Decoder) throws {
        self.init(); let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(CropMode.self, forKey: .mode) ?? mode
        framing = try container.decodeIfPresent(FramingMode.self, forKey: .framing) ?? framing
        centerX = try container.decodeIfPresent(Double.self, forKey: .centerX) ?? centerX
        centerY = try container.decodeIfPresent(Double.self, forKey: .centerY) ?? centerY
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? zoom
        aspectRatio = try container.decodeIfPresent(Double.self, forKey: .aspectRatio)
        quarterTurns = (try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? quarterTurns) % 4
        straighten = try container.decodeIfPresent(Double.self, forKey: .straighten) ?? straighten
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? flipHorizontal
        flipVertical = try container.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? flipVertical
    }
}
public enum WatermarkKind: String, Codable, Sendable, CaseIterable { case text, image }
public enum WatermarkAnchor: Int, Codable, Sendable, CaseIterable { case topLeft, topCentre, topRight, middleLeft, centre, middleRight, bottomLeft, bottomCentre, bottomRight }
public struct WatermarkConfiguration: Codable, Sendable, Equatable {
    public var enabled = false
    public var kind: WatermarkKind = .text
    public var text = "© Broad Frame Studio"
    public var imageURL: URL?
    public var fontName = "HelveticaNeue-Medium"
    public var colour = RGBAColour(1, 1, 1, 1)
    public var relativeWidth: Double = 0.25
    public var opacity: Double = 0.65
    public var rotation: Double = 0
    public var margin: Double = 0.03
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var anchor: WatermarkAnchor = .bottomRight
    public var tiled = false
    public init() {}
}
public struct ProcessingConfiguration: Codable, Sendable, Equatable {
    /// Opt-in operation sizing. Absent in legacy projects/presets; their output is unchanged.
    public var nativeOutputSizing: Bool?
    public var width: Int = 1600
    public var height: Int = 1200
    public var quarterTurns: Int = 0
    public var flipHorizontal = false
    public var flipVertical = false
    public var straighten: Double = 0
    public var crop = CropConfiguration()
    public var resizeBasis: ResizeBasis = .width
    public var percentage: Double = 100
    public var preventUpscaling = false
    public var background = RGBAColour()
    public var canvasAlignment: WatermarkAnchor = .centre
    public var format: OutputFormat = .jpeg
    public var quality: Double = 0.85
    public var targetBytes: Int?
    public var minimumQuality: Double = 0.35
    public var colourPolicy: ColourPolicy = .sRGB
    public var metadata: MetadataPolicy = .remove
    public var watermark = WatermarkConfiguration()
    public var adjustments = PhotoAdjustments()
    public var privacyExport = false
    public var masks: [PrivacyMask] = []
    public var annotations: [Annotation] = []
    public var canvasStyle = CanvasStyle()
    public init() {}
    private enum CodingKeys: String, CodingKey { case nativeOutputSizing, width, height, quarterTurns, flipHorizontal, flipVertical, straighten, crop, resizeBasis, percentage, preventUpscaling, background, canvasAlignment, format, quality, targetBytes, minimumQuality, colourPolicy, metadata, watermark, adjustments, masks, privacyExport, annotations, canvasStyle }
    public init(from decoder: Decoder) throws {
        self.init(); let container = try decoder.container(keyedBy: CodingKeys.self)
        nativeOutputSizing = try container.decodeIfPresent(Bool.self, forKey: .nativeOutputSizing)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? height
        quarterTurns = (try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? quarterTurns) % 4
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? flipHorizontal
        flipVertical = try container.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? flipVertical
        straighten = try container.decodeIfPresent(Double.self, forKey: .straighten) ?? straighten
        crop = try container.decodeIfPresent(CropConfiguration.self, forKey: .crop) ?? crop
        resizeBasis = try container.decodeIfPresent(ResizeBasis.self, forKey: .resizeBasis) ?? resizeBasis
        percentage = try container.decodeIfPresent(Double.self, forKey: .percentage) ?? percentage
        preventUpscaling = try container.decodeIfPresent(Bool.self, forKey: .preventUpscaling) ?? preventUpscaling
        background = try container.decodeIfPresent(RGBAColour.self, forKey: .background) ?? background
        canvasAlignment = try container.decodeIfPresent(WatermarkAnchor.self, forKey: .canvasAlignment) ?? canvasAlignment
        format = try container.decodeIfPresent(OutputFormat.self, forKey: .format) ?? format
        quality = try container.decodeIfPresent(Double.self, forKey: .quality) ?? quality
        targetBytes = try container.decodeIfPresent(Int.self, forKey: .targetBytes)
        minimumQuality = try container.decodeIfPresent(Double.self, forKey: .minimumQuality) ?? minimumQuality
        colourPolicy = try container.decodeIfPresent(ColourPolicy.self, forKey: .colourPolicy) ?? colourPolicy
        metadata = try container.decodeIfPresent(MetadataPolicy.self, forKey: .metadata) ?? metadata
        watermark = try container.decodeIfPresent(WatermarkConfiguration.self, forKey: .watermark) ?? watermark
        adjustments = try container.decodeIfPresent(PhotoAdjustments.self, forKey: .adjustments) ?? adjustments
        masks = try container.decodeIfPresent([PrivacyMask].self, forKey: .masks) ?? masks
        privacyExport = try container.decodeIfPresent(Bool.self, forKey: .privacyExport) ?? false
        annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations) ?? annotations
        canvasStyle = try container.decodeIfPresent(CanvasStyle.self, forKey: .canvasStyle) ?? canvasStyle
    }
}
public struct BatchSettings: Codable, Sendable { public var version = 2; public var processing = ProcessingConfiguration(); public init() {} }
public struct PixelDimensions: Codable, Sendable, Equatable {
    public var width: Int; public var height: Int
    public var followsBatchWidth: Bool?
    public init(width: Int, height: Int, followsBatchWidth: Bool = false) { self.width = width; self.height = height; self.followsBatchWidth = followsBatchWidth }
}
public struct ImageOverride: Codable, Sendable, Equatable {
    public var patch: ConfigurationPatch? = nil
    public var crop: CropConfiguration
    public var processing: ProcessingConfiguration?
    public var dimensions: PixelDimensions?
    public init(crop: CropConfiguration, processing: ProcessingConfiguration? = nil, dimensions: PixelDimensions? = nil) { self.crop = crop; self.processing = processing; self.dimensions = dimensions }
}
public struct ExportProfile: Identifiable, Codable, Sendable, Equatable {
    public var id = UUID()
    public var version = 2
    public var name = "Default"
    public var suffix = "-framepebble"
    public var namingTemplate = "{name}{suffix}"
    public var processing: ProcessingConfiguration?
    public var destination: URL?
    public init() {}
}
public struct ProcessingResult: Identifiable, Sendable {
    public var id: UUID; public var source: SourceAsset; public var output: URL?; public var error: String?
    public init(source: SourceAsset, output: URL? = nil, error: String? = nil) { id = UUID(); self.source = source; self.output = output; self.error = error }
}
public enum ProcessingError: Error, LocalizedError {
    case invalidImage, invalidConfiguration, encoding, validation, destination, unsupportedFormat, targetSizeUnreachable, sourceTooLarge
    public var errorDescription: String? { switch self {
    case .sourceTooLarge: "The source exceeds the configured image-memory safety limit."
    case .invalidImage: "The source is missing, unsupported or damaged."
    case .invalidConfiguration: "Dimensions, framing or quality are invalid. Output is limited to 100 million pixels and 20,000 pixels per edge."
    case .encoding: "Image encoding failed."
    case .validation: "The output failed validation."
    case .destination: "The destination is not a writable folder."
    case .unsupportedFormat: "This format is not supported by the installed native encoder."
    case .targetSizeUnreachable: "The target size cannot be met within the minimum quality limit. Increase the size limit or reduce dimensions."
    } }
}
public struct CropGeometry {
    /// Inverse of rect: a top-left source-pixel rectangle becomes the same
    /// normalized crop state used by batch framing and final rendering.
    public static func crop(selecting rectangle: CGRect, source: CGSize, existing: CropConfiguration) -> CropConfiguration {
        guard source.width > 0, source.height > 0,
              rectangle.minX.isFinite, rectangle.minY.isFinite,
              rectangle.width.isFinite, rectangle.height.isFinite else { return existing }
        let rect = rectangle.standardized.intersection(CGRect(origin: .zero, size: source))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return existing }
        var result = existing
        let ratio = Double(rect.width / rect.height)
        let base = self.rect(source: source, ratio: ratio, crop: CropConfiguration())
        result.mode = .manualCrop; result.framing = .manual
        result.aspectRatio = ratio
        result.centerX = Double(rect.midX / source.width)
        result.centerY = Double(rect.midY / source.height)
        result.zoom = min(20, max(1, Double(base.width / rect.width)))
        return result
    }

    public static func rect(source: CGSize, ratio: Double, crop: CropConfiguration) -> CGRect {
        guard source.width > 0, source.height > 0, ratio.isFinite, ratio > 0, crop.zoom.isFinite, crop.centerX.isFinite, crop.centerY.isFinite else { return .zero }
        let r = CGFloat(ratio)
        var w = source.width; var h = w / r
        if h > source.height { h = source.height; w = h * r }
        w /= CGFloat(max(1, crop.zoom)); h /= CGFloat(max(1, crop.zoom))
        let x = min(max(CGFloat(crop.centerX) * source.width - w / 2, 0), source.width - w)
        let y = min(max(CGFloat(crop.centerY) * source.height - h / 2, 0), source.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    /// Translation is measured in the displayed output frame, not in screen/source pixels.
    public static func dragged(_ crop: CropConfiguration, source: CGSize, frame: CGSize, translation: CGSize, ratio: Double, nativeOutput: CGSize? = nil, preventUpscaling: Bool = false) -> CropConfiguration {
        guard frame.width > 0, frame.height > 0, source.width > 0, source.height > 0 else { return crop }
        var result = crop; let visible = rect(source: source, ratio: ratio, crop: crop)
        var factor: CGFloat = 1
        if preventUpscaling, let output = nativeOutput { factor = max(1, min(output.width / max(0.0001, visible.width), output.height / max(0.0001, visible.height))) }
        result.centerX -= Double(translation.width / frame.width * visible.width / source.width * factor)
        result.centerY -= Double(translation.height / frame.height * visible.height / source.height * factor)
        result.mode = .manualCrop; result.framing = .manual
        let clamped = rect(source: source, ratio: ratio, crop: result)
        result.centerX = Double(clamped.midX / source.width); result.centerY = Double(clamped.midY / source.height)
        return result
    }
    public static func rotated(_ crop: CropConfiguration, turns: Int) -> CropConfiguration {
        var result = crop
        for _ in 0..<((turns % 4 + 4) % 4) { let x = result.centerX; result.centerX = 1 - result.centerY; result.centerY = x }
        result.quarterTurns += turns; return result
    }
    public static func zoomed(_ crop: CropConfiguration, factor: Double) -> CropConfiguration {
        var result = crop; guard factor.isFinite, factor > 0 else { return result }
        result.zoom = min(20, max(1, crop.zoom * factor)); result.mode = .manualCrop; result.framing = .manual; return result
    }
}

extension CropConfiguration {
    /// Adopt new viewport geometry while keeping source-space orientation transforms.
    public func adoptingGeometry(_ geometry: CropConfiguration) -> CropConfiguration {
        var value=geometry
        value.quarterTurns=quarterTurns;value.flipHorizontal=flipHorizontal;value.flipVertical=flipVertical;value.straighten=straighten
        return value
    }
}
