import CoreGraphics
import Foundation

public struct CollageArtProgress: Sendable {
  public var phase: String
  public var completed: Int
  public var total: Int
  public init(_ phase: String, _ completed: Int, _ total: Int) { self.phase = phase; self.completed = completed; self.total = total }
}
public struct CollageArtResult: Sendable {
  public var project: CollageProject
  public var skippedSources: Int
}
/// CPU work runs on this actor, never on the UI actor. No persistent image cache.
public actor CollageArtBuilder {
  private let processor = ImageProcessor()
  public init() {}
  public func shape(project: CollageProject, sources: [UUID], count: Int, shape: CollageShape, text: String) throws -> CollageProject {
    guard !sources.isEmpty, (1...CollageProject.maximumCells).contains(count), project.width > 0, project.height > 0 else { throw ProcessingError.invalidConfiguration }
    let rects = try Self.partition(shape: shape, text: text, count: count, aspect: Double(project.width) / Double(project.height))
    var result = project
    result.silhouette = shape; result.silhouetteText = text
    result.templateID = nil; result.mosaicReferenceID = nil
    result.spacing = min(result.spacing, 0.002)
    result.cells = rects.enumerated().map { i, rect in
      CollageCell(sourceID: sources[i % sources.count], x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
    return result
  }
  private struct Region {
    var x: Int; var y: Int; var w: Int; var h: Int; var mass: Int
  }
  /// An integral mask and mass-balanced partitions cover the entire silhouette
  /// with exactly N non-empty photo regions, including disconnected text glyphs.
  private static func partition(shape: CollageShape, text: String, count: Int, aspect: Double) throws -> [CGRect] {
    let resolution = 512, stride = resolution + 1
    let path = shape.path(in: CGRect(x: 0, y: 0, width: 1, height: 1), text: text)
    guard !path.isEmpty else { throw ProcessingError.invalidConfiguration }
    var sums = [Int](repeating: 0, count: stride * stride)
    for y in 0..<resolution {
      try Task.checkCancellation()
      for x in 0..<resolution {
        let inside = path.contains(CGPoint(x: (Double(x)+0.5)/Double(resolution), y: (Double(y)+0.5)/Double(resolution)), using: .evenOdd)
        sums[(y+1)*stride+x+1] = (inside ? 1 : 0) + sums[y*stride+x+1] + sums[(y+1)*stride+x] - sums[y*stride+x]
      }
    }
    func mass(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Int {
      sums[(y+h)*stride+x+w] - sums[y*stride+x+w] - sums[(y+h)*stride+x] + sums[y*stride+x]
    }
    var heap = [Region(x: 0, y: 0, w: resolution, h: resolution, mass: mass(0,0,resolution,resolution))]
    guard heap[0].mass >= count else { throw ProcessingError.invalidConfiguration }
    func push(_ item: Region) {
      heap.append(item); var i = heap.count-1
      while i > 0 { let parent = (i-1)/2; if heap[parent].mass >= heap[i].mass { break }; heap.swapAt(i,parent); i=parent }
    }
    func pop() -> Region {
      let result = heap[0], last = heap.removeLast()
      if !heap.isEmpty {
        heap[0] = last; var i = 0
        while i*2+1 < heap.count {
          var child = i*2+1
          if child+1 < heap.count && heap[child+1].mass > heap[child].mass { child += 1 }
          if heap[i].mass >= heap[child].mass { break }; heap.swapAt(i,child); i=child
        }
      }
      return result
    }
    var terminal: [Region] = []
    while heap.count + terminal.count < count {
      try Task.checkCancellation()
      guard !heap.isEmpty else { throw ProcessingError.invalidConfiguration }
      let r = pop()
      var split: (Region, Region)?
      let horizontal = Double(r.w) * aspect >= Double(r.h)
      for vertical in [horizontal, !horizontal] {
        let length = vertical ? r.w : r.h
        guard length > 1 else { continue }
        var low = 1, high = length-1
        while low < high {
          let mid = (low+high)/2
          let value = vertical ? mass(r.x,r.y,mid,r.h) : mass(r.x,r.y,r.w,mid)
          if value < r.mass/2 { low=mid+1 } else { high=mid }
        }
        let m = vertical ? mass(r.x,r.y,low,r.h) : mass(r.x,r.y,r.w,low)
        guard m > 0, m < r.mass else { continue }
        split = vertical
          ? (Region(x:r.x,y:r.y,w:low,h:r.h,mass:m), Region(x:r.x+low,y:r.y,w:r.w-low,h:r.h,mass:r.mass-m))
          : (Region(x:r.x,y:r.y,w:r.w,h:low,mass:m), Region(x:r.x,y:r.y+low,w:r.w,h:r.h-low,mass:r.mass-m))
        break
      }
      if let (a,b) = split { push(a); push(b) } else { terminal.append(r) }
    }
    return (heap+terminal).sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }.map {
      CGRect(x: Double($0.x)/Double(resolution), y: Double($0.y)/Double(resolution), width: Double($0.w)/Double(resolution), height: Double($0.h)/Double(resolution))
    }
  }

  /// Match real source thumbnails to reference regions. Photos are not tinted or
  /// replaced by pieces of the reference; a limited source palette limits fidelity.
  public func photomosaic(project: CollageProject, sources: [SourceAsset], reference: SourceAsset,
    edits: EditingSnapshot, count: Int, allowReuse: Bool,
    progress: @Sendable (CollageArtProgress) async -> Void) async throws -> CollageArtResult {
    guard !sources.isEmpty, (1...CollageProject.maximumCells).contains(count),
      allowReuse || sources.count >= count, project.width > 0, project.height > 0 else { throw ProcessingError.invalidConfiguration }
    await processor.setPrivateMode(true)
    let columns = max(1, Int(sqrt(Double(count) * Double(project.width) / Double(project.height)).rounded()))
    let rows = Int(ceil(Double(count)/Double(columns)))
    var refConfig = edits.configuration(for: reference.id)
    refConfig.width = columns*2; refConfig.height = rows*2; refConfig.crop.mode = .fill
    refConfig.crop.zoom = 1; refConfig.format = .png; refConfig.canvasStyle = CanvasStyle()
    let refImage = try await processor.render(reference.url, configuration: refConfig, previewMaximum: max(columns*2, rows*2))
    let referencePixels = try Self.pixels(refImage, width: columns*2, height: rows*2)
    var features: [[Double]] = [], ids: [UUID] = [], skipped = 0
    for (index, source) in sources.enumerated() {
      try Task.checkCancellation()
      do {
        var c = edits.configuration(for: source.id)
        c.width = 32; c.height = 32
        var tileCrop=CropConfiguration();tileCrop.mode = .fill
        c.crop=c.crop.adoptingGeometry(tileCrop)
        c.format = .png; c.canvasStyle = CanvasStyle()
        let image = try await processor.render(source.url, configuration: c, previewMaximum: 64, decodeMaximum: 128)
        features.append(try Self.pixels(image, width: 2, height: 2).map { Double($0)/255 })
        ids.append(source.id)
      } catch is CancellationError { throw CancellationError() } catch { skipped += 1 }
      if index % 5 == 0 || index+1 == sources.count { await progress(CollageArtProgress("Analysing source colours", index+1, sources.count)) }
    }
    guard !ids.isEmpty, allowReuse || ids.count >= count else { throw ProcessingError.invalidImage }
    let points = features.map(Self.mean)
    let tree = MosaicColourIndex(points)
    var usage = [Int](repeating: 0, count: ids.count)
    var result = project
    result.silhouette = nil; result.templateID = nil; result.mosaicReferenceID = reference.id
    result.spacing = 0; result.cells = []
    for i in 0..<count {
      try Task.checkCancellation()
      let row = i/columns, col = i%columns
      let rowCount = min(columns, count-row*columns)
      // Last row spans the whole canvas, as do all ordinary grid templates.
      let x = Double(col)/Double(rowCount), width = 1/Double(rowCount)
      var sample: [Double] = []
      for dy in 0..<2 { for dx in 0..<2 {
        let sx = min(columns*2-1, Int((x + width*(Double(dx)+0.5)/2)*Double(columns*2)))
        let sy = min(rows*2-1, row*2+dy)
        let offset = (sy*columns*2+sx)*3
        sample += referencePixels[offset..<offset+3].map { Double($0)/255 }
      } }
      let candidates = Array(Set(tree.nearest(Self.mean(sample), count: min(32, ids.count)) + [i % ids.count, (i*7919) % ids.count])).sorted()
      var best: Int?, bestScore = Double.infinity
      for j in candidates where allowReuse || usage[j] == 0 {
        var score = allowReuse ? Double(usage[j])*0.015 : 0
        for k in sample.indices { score += pow(features[j][k]-sample[k],2) }
        if score < bestScore { bestScore=score; best=j }
      }
      if best == nil {
        for j in ids.indices where usage[j] == 0 {
          var score=0.0
          for k in sample.indices { score += pow(features[j][k]-sample[k],2) }
          if score < bestScore { bestScore=score; best=j }
        }
      }
      guard let chosen = best else { throw ProcessingError.invalidConfiguration }
      usage[chosen] += 1
      result.cells.append(CollageCell(sourceID: ids[chosen], x:x, y:Double(row)/Double(rows), width:width, height:1/Double(rows)))
      if i % 25 == 0 || i+1 == count { await progress(CollageArtProgress("Matching mosaic tiles", i+1, count)) }
    }
    return CollageArtResult(project: result, skippedSources: skipped)
  }
  private static func pixels(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width*height*4)
    try bytes.withUnsafeMutableBytes { buffer in
      guard let space = CGColorSpace(name: CGColorSpace.sRGB), let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProcessingError.encoding }
      ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x:0,y:0,width:width,height:height))
      ctx.translateBy(x:0,y:CGFloat(height)); ctx.scaleBy(x:1,y:-1)
      ctx.interpolationQuality = .high
      ctx.draw(image, in: CGRect(x:0,y:0,width:width,height:height))
    }
    return stride(from: 0, to: bytes.count, by: 4).flatMap { [bytes[$0],bytes[$0+1],bytes[$0+2]] }
  }
  private static func mean(_ values: [Double]) -> [Double] {
    (0..<3).map { channel in stride(from: channel, to: values.count, by: 3).reduce(0.0) { $0 + values[$1] } / Double(max(1,values.count/3)) }
  }
}

/// Three-dimensional colour kd-tree bounds nearest-neighbour work for large libraries.
private struct MosaicColourIndex {
  private struct Node { var index: Int; var axis: Int; var left: Int?; var right: Int? }
  private var nodes: [Node] = []
  private var root: Int?
  private var points: [[Double]]
  init(_ points: [[Double]]) {
    self.points = points
    func build(_ ids: [Int], _ depth: Int) -> Int? {
      guard !ids.isEmpty else { return nil }
      let axis = depth%3
      let sorted = ids.sorted { points[$0][axis] == points[$1][axis] ? $0 < $1 : points[$0][axis] < points[$1][axis] }
      let middle = sorted.count/2, id = nodes.count
      nodes.append(Node(index:sorted[middle],axis:axis))
      nodes[id].left = build(Array(sorted[..<middle]),depth+1)
      nodes[id].right = build(Array(sorted[(middle+1)...]),depth+1)
      return id
    }
    root = build(Array(points.indices),0)
  }
  func nearest(_ point: [Double], count: Int) -> [Int] {
    var found: [(Int,Double)] = []
    func visit(_ id: Int?) {
      guard let id else { return }
      let n = nodes[id], p = points[n.index]
      let distance = zip(point,p).reduce(0.0) { $0+pow($1.0-$1.1,2) }
      found.append((n.index,distance)); found.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
      if found.count > count { found.removeLast() }
      let delta = point[n.axis]-p[n.axis]
      visit(delta < 0 ? n.left : n.right)
      if found.count < count || delta*delta < (found.last?.1 ?? .infinity) { visit(delta < 0 ? n.right : n.left) }
    }
    visit(root)
    return found.map(\.0)
  }
}
