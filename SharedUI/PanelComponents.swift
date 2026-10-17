import FramepebbleCore
import SwiftUI


/// Shared visual language. These values affect presentation only, never processing.
enum EditorChrome {
  static let compactSpacing: CGFloat = 6
  static let spacing: CGFloat = 12
  static let controlRadius: CGFloat = 8
  static let surfaceRadius: CGFloat = 12
  static let selectionOpacity = 0.14
  #if os(macOS)
  static let toolExtent: CGFloat = 32
  #else
  static let toolExtent: CGFloat = 44
  #endif
  static func value(_ value: Double, percentage: Bool) -> String {
    percentage ? value.formatted(.percent.precision(.fractionLength(0)))
      : value.formatted(.number.precision(.fractionLength(0...2)))
  }
}

/// Neutral surroundings make the photograph the strongest colour on screen.
struct EditorCanvasBackground: View {
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    (scheme == .dark ? Color(white: 0.105) : Color(white: 0.94))
      .accessibilityHidden(true)
  }
}

/// One selected/hover/pressed treatment for inspector and canvas toolbars.
/// Native controls inside menus and forms retain their platform styles.
struct EditorToolButtonStyle: ButtonStyle {
  var selected = false
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .frame(minWidth: EditorChrome.toolExtent, minHeight: EditorChrome.toolExtent)
      .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.78))
      .background {
        RoundedRectangle(cornerRadius: EditorChrome.controlRadius)
          .fill(selected ? Color.accentColor.opacity(EditorChrome.selectionOpacity)
                : Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0))
      }
      .contentShape(RoundedRectangle(cornerRadius: EditorChrome.controlRadius))
      .opacity(enabled ? 1 : 0.4)
      .onHover { hovering = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
  }
}

extension View {
  func editorSelectionSurface(selected: Bool, idleOpacity: Double = 0) -> some View {
    background(selected ? Color.accentColor.opacity(EditorChrome.selectionOpacity) : Color.primary.opacity(idleOpacity),
      in: RoundedRectangle(cornerRadius: EditorChrome.controlRadius))
  }
  func editorInspectorSurface() -> some View {
    self.background(.bar).accessibilityElement(children: .contain)
  }
}

/// Keep the presentation chosen before typing. A keyboard height change must not
/// remove its focused field; a width/orientation change establishes a new viewport.
struct EditorPanelViewport {
  private(set) var size = CGSize.zero
  mutating func observe(_ value: CGSize) {
    if size == .zero || size.width != value.width { size = value }
  }
  func height(fallback: CGFloat) -> CGFloat { size == .zero ? fallback : size.height }
}

/// Presentation geometry only. Processing scope and editing state remain in Workspace.
enum EditorPanelLayout {
  static func usesTabletRail(_ size: CGSize, accessibility: Bool = false) -> Bool {
    !accessibility && size.width >= 900 && size.width > size.height
  }
  /// The tool rail and inspector must leave at least 540 points for direct canvas manipulation.
  static func supportsOverlayInspector(width: CGFloat, accessibility: Bool) -> Bool {
    !accessibility && width >= 920
  }
  #if os(macOS)
  static let toolRailWidth: CGFloat = 48
  #else
  static let toolRailWidth: CGFloat = 56
  #endif
  static let inspectorWidth: CGFloat = 300
  static let minimumCanvasWidth: CGFloat = 460
  static func expandedControls(height: CGFloat, accessibility: Bool) -> Bool { accessibility || height < 480 }
  static func fittedInspectorWidth(requested: CGFloat, available: CGFloat) -> CGFloat {
    min(420, min(max(280, requested), max(280, available - minimumCanvasWidth - 5)))
  }
  static func supportsInspector(_ width: CGFloat) -> Bool { width >= minimumCanvasWidth + inspectorWidth + 1 }
  /// Persistent tablet properties need a landscape viewport and usable gallery width.
  static func supportsBatchInspector(_ size: CGSize, accessibility: Bool) -> Bool {
    !accessibility && size.width >= 1000 && size.width > size.height
  }
  static func navigationVisible(width: CGFloat, editing: Bool, preference: Bool?) -> Bool {
    preference ?? !editing
  }
}

extension InspectorTask {
  var displayTitle: String { self == .output ? "Output Settings" : rawValue }
  var symbol: String {
    switch self {
    case .resize: "arrow.up.left.and.arrow.down.right"
    case .adjust: "slider.horizontal.3"
    case .filters: "camera.filters"
    case .creative: "ellipsis.circle"
    case .watermark: "signature"
    case .output: "gearshape"
    }
  }
}

struct InspectorToolPicker: View {
  @Bindable var model: Workspace
  var recipeEditing = false
  @Environment(\.dynamicTypeSize) private var typeSize
  var tools: [InspectorTask] { InspectorTask.allCases.filter { !recipeEditing || $0 != .creative } }
  var buttonSize: CGSize {
    #if os(macOS)
    CGSize(width: 30, height: 28)
    #else
    CGSize(width: 44, height: 44)
    #endif
  }
  var body: some View {
    ViewThatFits(in: .horizontal) {
      if !typeSize.isAccessibilitySize { HStack(spacing: 4) {
        ForEach(tools, id: \.self) { task in
          Button { model.choosePhotoInspector(task) } label: {
            Image(systemName: task.symbol).frame(width: buttonSize.width, height: buttonSize.height)
          }.buttonStyle(EditorToolButtonStyle(selected: model.inspectorTask == task))
            .toolNameHint(task == .output ? "Output Settings" : task.rawValue).accessibilityLabel(task == .output ? "Output Settings" : task.rawValue)
            .accessibilityAddTraits(model.inspectorTask == task ? .isSelected : [])
        }
      } }
      Menu("Tools", systemImage: "slider.horizontal.3") {
        ForEach(tools, id: \.self) { task in Button(task.rawValue, systemImage: task.symbol) { model.choosePhotoInspector(task) } }
      }
    }.accessibilityIdentifier("editor.toolPicker")
  }
}

struct OperationContextHeader: View {
  @Bindable var model: Workspace
  var allowsChangingInputs = true
  var title: String { model.operationTitle }
  var displayTitle: String { "Editing \(model.targets.count) \(model.targets.count == 1 ? "photo" : "photos")" }
  var body: some View {
    Group {
      if model.workflow == .photo { Text(title).font(.headline) }
      else if !allowsChangingInputs && model.operationSelectionSummary == nil { Text(displayTitle).font(.headline) }
      else { scopeMenu }
    }
  }
  var scopeMenu: some View {
    Menu {
      if let detail = model.operationSelectionSummary {
        Text(detail)
        Text("Changing Workspace selection or filters does not change these operation inputs.")
        Divider()
      }
      if model.workflow == .batch && allowsChangingInputs {
        Button("Change Inputs…") { model.selectPhotos(for: model.conversionInputIDs == nil ? .batch : .convert) }
        if model.conversionInputIDs == nil {
          Button("Keep Current Inputs") { model.batchInputIDs = Set(model.targets.map(\.id)); model.scope = .selected; model.persist() }
            .disabled(model.batchInputIDs != nil)
          Button("Use Live Selection") { model.batchInputIDs = nil; model.scope = .selected; model.persist() }
          Button("Use Entire Workspace") { model.batchInputIDs = nil; model.scope = .all; model.persist() }
          Button("Use Filter Results") { model.batchInputIDs = nil; model.scope = .results; model.persist() }
        }
        if !model.edits.overrides.isEmpty { Button("Review Individual Changes") { model.showLibrary(.exceptions, clearSearch: true) } }
      }
    } label: {
      Label(displayTitle, systemImage: "photo.stack").font(.headline).lineLimit(1)
    }.comfortableHitTarget()
      .accessibilityLabel(title + "; operation photos and scope")
      .accessibilityValue(model.operationSelectionSummary ?? "")
      .accessibilityIdentifier("editor.operationScope")
      .help("Change Inputs and operation scope")
      .disabled(model.overlayEditor || model.running)
  }
}

extension Workspace {
  func galleryPhotos(operationOnly: Bool) -> [SourceAsset] {
    guard operationOnly, workflow == .batch, !browsingLibrary, gifSelectionContext == nil else { return filtered }
    let ids = Set(targets.map(\.id))
    return filtered.filter { ids.contains($0.id) }
  }
  var operationGalleryStatus: String {
    let hidden = selection.subtracting(Set(filtered.map(\.id))).count
    return "\(workspaceAssets.count) in workspace · \(selection.count) selected" + (hidden > 0 ? " · \(hidden) hidden" : "")
  }
  var workspaceSelectionStatus: String {
    let hidden = selection.subtracting(Set(filtered.map(\.id))).count
    return "\(selection.count) selected · \(hidden) hidden"
  }
  var operationSelectionSummary: String? {
    guard workflow == .batch, batchInputIDs != nil, !browsingLibrary else { return nil }
    return "\(targets.count) fixed \(targets.count == 1 ? "input" : "inputs") · \(workspaceAssets.count) in Workspace · \(selection.count) selected"
  }
  var operationTitle: String {
    if workflow == .photo { return "This photo" }
    let task = conversionInputIDs == nil ? "Batch Edit" : "Convert"
    return "\(task) · \(targets.count) \(targets.count == 1 ? "photo" : "photos")"
  }
}

struct EditorHistoryButtons: View {
  @Bindable var model: Workspace
  var body: some View {
    HStack(spacing: 4) {
      Button { model.undoActiveWorkspace() } label: { Image(systemName: "arrow.uturn.backward") }
        .comfortableHitTarget().disabled(!model.canUndoActiveWorkspace).accessibilityLabel(model.undoActionTitle).help(model.undoActionTitle)
      Button { model.redoActiveWorkspace() } label: { Image(systemName: "arrow.uturn.forward") }
        .comfortableHitTarget().disabled(!model.canRedoActiveWorkspace).accessibilityLabel(model.redoActionTitle).help(model.redoActionTitle)
    }.buttonStyle(.borderless)
  }
}

struct InspectorHeading: View {
  let title: String
  var subtitle: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.weight(.semibold))
      if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Menu rows reserve their actual label width; large text stacks instead of wrapping a value.
struct InspectorMenuRow<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    ViewThatFits(in: .horizontal) {
      if !typeSize.isAccessibilitySize {
        HStack {
          Text(title).fixedSize()
          Spacer(minLength: 8)
          content.fixedSize(horizontal: true, vertical: false)
        }
      }
      VStack(alignment: .leading, spacing: EditorChrome.compactSpacing) {
        Text(title)
        content
      }
    }
  }
}

struct InspectorSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  var percentage = false
  var interaction: (Bool) -> Void = { _ in }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Text(EditorChrome.value(value, percentage: percentage))
          .font(.caption).monospacedDigit().foregroundStyle(.secondary)
      }
      Slider(value: $value, in: range, onEditingChanged: interaction).accessibilityLabel(title)
        .accessibilityValue(EditorChrome.value(value, percentage: percentage))
    }
  }
}

/// Defaults for newly authored areas only; stored masks retain their original settings.
enum PrivacyToolDefaults {
  static let effects: [MaskEffect] = [.pixelate, .cover, .blur, .frosted]
  static let shapes: [OverlayShape] = [.freehand, .rectangle, .ellipse]
  static func mask(points: [NormalizedPoint], effect: MaskEffect = .pixelate,
                   shape: OverlayShape = .freehand) -> PrivacyMask? {
    guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
    let points = points.map { NormalizedPoint(min(1, max(0, $0.x)), min(1, max(0, $0.y))) }
    guard points.count >= (shape == .freehand ? 3 : 2),
      let x = points.map(\.x).min(), let y = points.map(\.y).min(),
      let right = points.map(\.x).max(), let bottom = points.map(\.y).max(),
      right - x >= 0.003, bottom - y >= 0.003 else { return nil }
    if shape == .freehand {
      let area = points.indices.reduce(0.0) { sum, i in
        let next = points[(i + 1) % points.count]
        return sum + points[i].x * next.y - next.x * points[i].y
      }
      guard abs(area) > 0.00001 else { return nil }
    }
    var mask = PrivacyMask()
    mask.x = x; mask.y = y; mask.width = right - x; mask.height = bottom - y
    mask.effect = effect; mask.shape = shape
    mask.points = points.map { NormalizedPoint(($0.x - x) / mask.width, ($0.y - y) / mask.height) }
    return mask
  }
}

/// A bounded surface for immediate tool controls; detailed properties stay optional.
struct ToolOptionsSurface<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(EditorChrome.spacing)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: EditorChrome.surfaceRadius))
      .overlay(RoundedRectangle(cornerRadius: EditorChrome.surfaceRadius).strokeBorder(.primary.opacity(0.08)))
      .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
  }
}

/// Native picker cancellation is an intentional exit, not a recoverable failure.
extension Error {
  var isUserCancellation: Bool {
    self is CancellationError || ((self as NSError).domain == NSCocoaErrorDomain && (self as NSError).code == NSUserCancelledError)
  }
}

/// View-only placement. Stored preferences never enter a photo's crop or export settings.
enum ToolPanelPosition: String, CaseIterable {
  case toolEdge, topLeading, topTrailing, bottomLeading, bottomTrailing
  var title: String {
    switch self {
    case .toolEdge: "Beside Tool"
    case .topLeading: "Top Left"
    case .topTrailing: "Top Right"
    case .bottomLeading: "Bottom Left"
    case .bottomTrailing: "Bottom Right"
    }
  }
  func origin(in available: CGSize, panel: CGSize, toolIndex: Int) -> CGPoint {
    let inset: CGFloat = 12
    let right = max(inset, available.width - panel.width - inset)
    let bottom = max(inset, available.height - panel.height - inset)
    switch self {
    case .toolEdge: return CGPoint(x: right, y: min(bottom, max(inset, CGFloat(toolIndex) * (EditorChrome.toolExtent + 6))))
    case .topLeading: return CGPoint(x: inset, y: inset)
    case .topTrailing: return CGPoint(x: right, y: inset)
    case .bottomLeading: return CGPoint(x: inset, y: bottom)
    case .bottomTrailing: return CGPoint(x: right, y: bottom)
    }
  }
  static func snapped(origin: CGPoint, panel: CGSize, available: CGSize) -> Self {
    let left = origin.x + panel.width / 2 < available.width / 2
    let top = origin.y + panel.height / 2 < available.height / 2
    return top ? (left ? .topLeading : .topTrailing) : (left ? .bottomLeading : .bottomTrailing)
  }
}

/// A small number of discoverable, reachable positions rather than free-form window management.
struct FloatingToolOptions<Content: View>: View {
  let title: String
  let toolIndex: Int
  var pin: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content
  @AppStorage("editor.toolPanel.landscapePosition") private var landscapePosition = ToolPanelPosition.toolEdge.rawValue
  @AppStorage("editor.toolPanel.portraitPosition") private var portraitPosition = ToolPanelPosition.toolEdge.rawValue
  @State private var panelSize = CGSize(width: 340, height: 200)
  @GestureState private var movement = CGSize.zero
  @State private var choosingPosition = false
  var body: some View {
    GeometryReader { geometry in
      let landscape = geometry.size.width > geometry.size.height
      let chosen = ToolPanelPosition(rawValue: landscape ? landscapePosition : portraitPosition) ?? .toolEdge
      let width = max(1, min(340, geometry.size.width - 24))
      let measured = CGSize(width: width, height: min(panelSize.height, max(44, geometry.size.height - 24)))
      let origin = chosen.origin(in: geometry.size, panel: measured, toolIndex: toolIndex)
      ToolOptionsSurface {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            HStack(spacing: 6) {
              Image(systemName: "line.3.horizontal")
              Text(title).font(.caption.weight(.semibold))
            }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
              .contentShape(Rectangle())
              .gesture(DragGesture(minimumDistance: 5)
                .updating($movement) { value, state, _ in state = value.translation }
                .onEnded { value in
                  let destination = ToolPanelPosition.snapped(
                    origin: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height),
                    panel: measured, available: geometry.size)
                  set(destination, landscape: landscape)
                })
              .accessibilityLabel(title + " options; drag to move")
              .help("Drag options to a corner, or choose Panel Position")
            Button("Position") { choosingPosition = true }
              .font(.caption.weight(.medium)).buttonStyle(.plain)
              .frame(minWidth: 64, minHeight: 44)
              .accessibilityLabel("Panel Position and Pin Settings")
              .popover(isPresented: $choosingPosition) {
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(ToolPanelPosition.allCases, id: \.self) { position in
                    Button(position.title, systemImage: chosen == position ? "checkmark" : "rectangle") {
                      set(position, landscape: landscape); choosingPosition = false
                    }.comfortableHitTarget()
                  }
                  if let pin {
                    Divider()
                    Button("Pin Tool Settings", systemImage: "sidebar.right") { choosingPosition = false; pin() }.comfortableHitTarget()
                  }
                }.padding(12).presentationCompactAdaptation(.popover)
              }
          }.foregroundStyle(.secondary)
          content()
        }
      }.frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
        .frame(height: measured.height, alignment: .top)
        .position(x: origin.x + measured.width / 2 + movement.width,
                  y: origin.y + measured.height / 2 + movement.height)
    }
  }
  private func set(_ position: ToolPanelPosition, landscape: Bool) {
    if landscape { landscapePosition = position.rawValue } else { portraitPosition = position.rawValue }
  }
}

private struct ToolNameHint: ViewModifier {
  let name: String
  @State private var showing = false
  func body(content: Content) -> some View {
    content.help(name)
      .highPriorityGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in showing = true })
      .popover(isPresented: $showing) {
        Text(name).font(.callout.weight(.medium)).padding(12)
          .presentationCompactAdaptation(.popover)
      }
  }
}
extension View {
  /// Touch names complement native pointer help and VoiceOver labels.
  func toolNameHint(_ name: String) -> some View { modifier(ToolNameHint(name: name)) }
}
