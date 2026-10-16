import SwiftUI
import ImageIO

/// Inspect the encoded frames, including quantisation, rather than a still-image thumbnail.
struct GIFOutputPreview: View {
  let url: URL
  @State private var image: CGImage?
  @State private var index = 0
  @State private var count = 1
  @State private var delay = 0.5
  @State private var playing = false
  var body: some View {
    VStack {
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 190) }
      HStack {
        Button(playing ? "Pause" : "Play") { playing.toggle() }
        Stepper("Frame \(index + 1) of \(count)", value: $index, in: 0...max(0, count - 1)).disabled(playing)
      }
      Text("Review every frame before sharing.").font(.caption)
    }.task(id: index) { await load() }
      .task(id: playing) {
        guard playing else { return }
        do { while !Task.isCancelled {
          try await Task.sleep(for: .seconds(delay)); index = (index + 1) % max(1, count)
        } } catch {}
      }
  }
  func load() async {
    let position = index
    let result = await Task.detached { () -> (CGImage?, Int, Double) in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return (nil, 1, 0.5) }
      let count = CGImageSourceGetCount(source)
      let info = CGImageSourceCopyPropertiesAtIndex(source, position, nil) as? [CFString: Any]
      let gif = info?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]) as? Double ?? 0.5
      return (CGImageSourceCreateThumbnailAtIndex(source, position, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 480] as CFDictionary), count, max(0.1, delay))
    }.value
    guard !Task.isCancelled else { return }; image = result.0; count = result.1; delay = result.2
  }
}
