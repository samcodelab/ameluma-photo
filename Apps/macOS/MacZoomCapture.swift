import SwiftUI
import AppKit

/// Only Option-scroll inside the framing surface is consumed; ordinary scrolling remains native.
struct MacZoomCapture: NSViewRepresentable {
    var onZoom: (Double) -> Void
    func makeNSView(context: Context) -> ZoomView { let view = ZoomView(); view.onZoom = onZoom; return view }
    func updateNSView(_ view: ZoomView, context: Context) { view.onZoom = onZoom }
    final class ZoomView: NSView {
        var onZoom: ((Double) -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if window != nil { monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, event.modifierFlags.contains(.option) else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.onZoom?(Double(event.scrollingDeltaY)); return nil
            } }
        }
        isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
