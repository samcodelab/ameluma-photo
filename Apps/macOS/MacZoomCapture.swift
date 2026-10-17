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

/// A transparent native cursor lets the canvas draw an accurately scaled brush footprint.
struct MacRetouchCursor: NSViewRepresentable {
    var active: Bool
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.active = active
        view.window?.invalidateCursorRects(for: view)
    }
    final class CursorView: NSView {
        var active = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            if active {
                let image = NSImage(size: NSSize(width: 1, height: 1))
                addCursorRect(bounds, cursor: NSCursor(image: image, hotSpot: .zero))
            }
        }
    }
}

/// Own mouse painting directly so NSScrollView/SwiftUI gesture arbitration cannot swallow a stroke.
struct MacRetouchInput: NSViewRepresentable {
    var active: Bool
    var began: (CGPoint, Bool) -> Void
    var moved: (CGPoint) -> Void
    var ended: (CGPoint) -> Void
    var hovered: (CGPoint?) -> Void
    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.active = active; view.began = began; view.moved = moved; view.ended = ended; view.hovered = hovered
    }
    final class InputView: NSView {
        var active = false
        var began: ((CGPoint, Bool) -> Void)?
        var moved: ((CGPoint) -> Void)?
        var ended: ((CGPoint) -> Void)?
        var hovered: ((CGPoint?) -> Void)?
        private var tracking: NSTrackingArea?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { active ? super.hitTest(point) : nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
            addTrackingArea(area); tracking = area
        }
        override func mouseDown(with event: NSEvent) { let p = convert(event.locationInWindow, from: nil); hovered?(p); began?(p, event.modifierFlags.contains(.option)) }
        override func mouseDragged(with event: NSEvent) { let p = convert(event.locationInWindow, from: nil); hovered?(p); moved?(p) }
        override func mouseUp(with event: NSEvent) { ended?(convert(event.locationInWindow, from: nil)) }
        override func mouseMoved(with event: NSEvent) { if active { hovered?(convert(event.locationInWindow, from: nil)) } }
        override func mouseExited(with event: NSEvent) { hovered?(nil) }
    }
}
