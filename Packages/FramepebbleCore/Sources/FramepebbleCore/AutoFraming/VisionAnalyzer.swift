import Foundation
import Vision
import CoreML
import CoreGraphics

public struct FramingProposal: Codable, Sendable {
    public var crop: CropConfiguration
    public var subjects: [CGRect]
    public var reviewReasons: [String]
    public init(crop: CropConfiguration, subjects: [CGRect], reviewReasons: [String]) { self.crop = crop; self.subjects = subjects; self.reviewReasons = reviewReasons }
    public var needsReview: Bool { !reviewReasons.isEmpty }
}
public enum AutoFramingGeometry {
    /// Spatial detections are top-left normalized rectangles, distinct from classification labels.
    public static func propose(source: CGSize, ratio: Double, subjects: [CGRect], mode: FramingMode) -> FramingProposal {
        var crop = CropConfiguration(); crop.mode = .fill; crop.framing = mode
        let valid = subjects.filter { !$0.isEmpty && !$0.isNull && $0.minX.isFinite && $0.minY.isFinite }.map { $0.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }.filter { !$0.isNull && !$0.isEmpty }
        guard mode != .centre else { return FramingProposal(crop: crop, subjects: valid, reviewReasons: []) }
        guard source.width > 0, source.height > 0, ratio.isFinite, ratio > 0, let first = valid.first else { return FramingProposal(crop: crop, subjects: [], reviewReasons: ["No reliable subject region was found; using centred framing."]) }
        let region = mode == .keepSubjects ? valid.dropFirst().reduce(first) { $0.union($1) } : first
        crop.centerX = Double(region.midX); crop.centerY = Double(region.midY)
        let visible = CropGeometry.rect(source: source, ratio: ratio, crop: crop)
        crop.centerX = Double(visible.midX / source.width); crop.centerY = Double(visible.midY / source.height)
        let normalized = CGRect(x: visible.minX / source.width, y: visible.minY / source.height, width: visible.width / source.width, height: visible.height / source.height)
        let omitted = valid.contains { !normalized.insetBy(dx: -0.005, dy: -0.005).contains($0) }
        var reasons: [String] = []
        if omitted { reasons.append("The output aspect ratio cannot contain every detected subject. Review framing or use Fit.") }
        if mode == .smart && valid.count > 1 { reasons.append("Multiple subject regions were detected; review the chosen framing.") }
        return FramingProposal(crop: crop, subjects: valid, reviewReasons: reasons)
    }
}
/// Separate serial analysis actor prevents Vision work from blocking the rendering actor.
/// A future local vision-language implementation can supply labels without changing index/search state.
public protocol ImageContentAnalyzing: Sendable {
    func classify(_ image: CGImage, asset: SourceAsset) async throws -> ClassificationRecord
}
public protocol SpatialFramingAnalyzing: Sendable {
    func frame(_ image: CGImage, ratio: Double, mode: FramingMode) async throws -> FramingProposal
}
public actor VisionAnalyzer: ImageContentAnalyzing, SpatialFramingAnalyzing {
    public nonisolated static var classificationRevision: Int { VNClassifyImageRequest().revision }
    public init() {}
    private func perform(_ requests: [VNRequest], using handler: VNImageRequestHandler) throws {
        #if targetEnvironment(simulator)
        for request in requests {
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) { request.setComputeDevice(cpu, for: stage) }
            }
        }
        #endif
        try handler.perform(requests)
    }
    public func classify(_ image: CGImage, asset: SourceAsset) throws -> ClassificationRecord {
        try Task.checkCancellation()
        let request = VNClassifyImageRequest(); let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try perform([request], using: handler); try Task.checkCancellation()
        let labels = (request.results ?? []).filter { $0.confidence >= 0.05 }.map { ClassificationLabel($0.identifier, confidence: $0.confidence) }
        return ClassificationRecord(assetID: asset.id, labels: labels, revision: request.revision, fingerprint: try SourceFingerprint.read(asset.url))
    }
    public func frame(_ image: CGImage, ratio: Double, mode: FramingMode) throws -> FramingProposal {
        try Task.checkCancellation()
        let size = CGSize(width: image.width, height: image.height)
        if mode == .centre { return AutoFramingGeometry.propose(source: size, ratio: ratio, subjects: [], mode: .centre) }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        var boxes: [CGRect] = []; var failures: [String] = []
        func top(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height) }
        let faces = VNDetectFaceRectanglesRequest(); let humans = VNDetectHumanRectanglesRequest(); let animals = VNRecognizeAnimalsRequest()
        do { try perform([faces], using: handler); boxes += (faces.results ?? []).map { top($0.boundingBox) } } catch { failures.append("Face analysis was unavailable.") }
        try Task.checkCancellation()
        do { try perform([humans], using: handler); boxes += (humans.results ?? []).filter { $0.confidence >= 0.3 }.map { top($0.boundingBox) } } catch { failures.append("Human analysis was unavailable.") }
        do { try perform([animals], using: handler); boxes += (animals.results ?? []).filter { $0.confidence >= 0.3 }.map { top($0.boundingBox) } } catch { failures.append("Animal analysis was unavailable.") }
        if boxes.isEmpty {
            let attention = VNGenerateAttentionBasedSaliencyImageRequest(); let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
            do { try perform([attention], using: handler); boxes += (attention.results?.first?.salientObjects ?? []).map { top($0.boundingBox) } } catch { failures.append("Attention analysis was unavailable.") }
            if boxes.isEmpty { do { try perform([objects], using: handler); boxes += (objects.results?.first?.salientObjects ?? []).map { top($0.boundingBox) } } catch { failures.append("Object saliency was unavailable.") } }
        }
        try Task.checkCancellation()
        // Prefer larger spatial regions; avoid counting contained face/body boxes as separate subjects.
        boxes.sort { $0.width * $0.height > $1.width * $1.height }
        var distinct: [CGRect] = []
        for box in boxes where !distinct.contains(where: { $0.contains(box) }) { distinct.append(box) }
        var proposal = AutoFramingGeometry.propose(source: size, ratio: ratio, subjects: distinct, mode: mode)
        proposal.reviewReasons += failures
        return proposal
    }
}
