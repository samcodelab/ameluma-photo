import AppKit
import FramepebbleCore
import XCTest

@testable import FramepebbleMac

@MainActor final class SelectionAdapterTests: XCTestCase {
  func testNativeModifierEventsPreserveGroupAndPrecisionScope() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = Workspace(directory: root)
    model.assets = (0..<4).map { SourceAsset(url: root.appendingPathComponent("\($0).png")) }
    model.selected = model.assets[0].id
    let view = MacPhotoSelectionCapture.SelectionView()
    var target = model.assets[0]
    view.onSelect = { command, shift, double in
      if double {
        model.selected = target.id
        model.precision = true
      } else {
        model.select(target, extending: command, range: shift)
      }
    }
    func click(_ flags: NSEvent.ModifierFlags = [], count: Int = 1) throws {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: .zero, modifierFlags: flags,
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
          eventNumber: 1, clickCount: count, pressure: 1))
      view.mouseDown(with: event)
    }
    try click()
    target = model.assets[2]
    try click(.command)
    XCTAssertEqual(model.selection, [model.assets[0].id, model.assets[2].id])
    XCTAssertEqual(model.scope, .selected)
    target = model.assets[3]
    try click(.shift)
    XCTAssertEqual(model.selection, [model.assets[2].id, model.assets[3].id])
    let group = model.selection
    target = model.assets[2]
    try click()
    try click(count: 2)
    XCTAssertTrue(model.precision)
    XCTAssertEqual(model.selected, target.id)
    XCTAssertEqual(model.selection, group)
    XCTAssertEqual(model.scope, .selected)
    model.persistenceTask?.cancel()
  }
}
