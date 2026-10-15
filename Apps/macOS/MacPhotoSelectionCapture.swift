import AppKit
import SwiftUI

/// Native click selection is separate from SwiftUI crop dragging. Browse captures
/// plain clicks; Frame captures only modifier clicks, leaving crop drags untouched.
struct MacPhotoSelectionCapture: NSViewRepresentable {
  var capturesPlainClicks: Bool
  var onSelect: (Bool, Bool, Bool) -> Void
  func makeNSView(context: Context) -> SelectionView {
    let view = SelectionView()
    updateNSView(view, context: context)
    return view
  }
  func updateNSView(_ view: SelectionView, context: Context) {
    view.capturesPlainClicks = capturesPlainClicks
    view.onSelect = onSelect
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectionView, context: Context)
    -> CGSize?
  {
    proposal.replacingUnspecifiedDimensions(by: .zero)
  }
  final class SelectionView: NSView {
    var capturesPlainClicks = true
    var onSelect: ((Bool, Bool, Bool) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
      let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
      let event = NSApp.currentEvent?.type
      if event == .rightMouseDown || event == .rightMouseUp { return nil }
      guard capturesPlainClicks || flags.contains(.command) || flags.contains(.shift) else {
        return nil
      }
      return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
      onSelect?(
        event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift),
        event.clickCount == 2)
    }
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
  }
}

/// Native transient keyboard state stays in the Mac adapter, not the shared geometry.
enum MacEditingModifiers {
  static var keepProportions: Bool { NSEvent.modifierFlags.contains(.shift) }
}
