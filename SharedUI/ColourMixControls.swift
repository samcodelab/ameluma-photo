import FramepebbleCore
import SwiftUI

struct ColourMixControls: View {
  @Bindable var model: Workspace
  @State private var band = 0
  @State private var expanded: Bool
  init(model: Workspace, expanded: Bool = false) { self.model = model; _expanded = State(initialValue: expanded) }
  private let names = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
  private let colours: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
  var body: some View {
    DisclosureGroup("Colour Mix", isExpanded: $expanded) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 4) { swatches }
        ScrollView(.horizontal) { HStack(spacing: 4) { swatches } }.frame(height: 48)
      }
      Text(names[band]).font(.caption.weight(.medium))
      control("Hue", 0)
      control("Saturation", 1)
      control("Lightness", 2)
      Button("Reset " + names[band]) {
        var config = model.controlConfiguration
        for index in 0..<3 { let (key, _) = properties[index]; config[keyPath: key] = 0 }
        model.applyChange(ConfigurationPatch(values: config, fields: Set(properties.map { $0.1 })))
      }.font(.caption).buttonStyle(.plain).foregroundStyle(.primary).comfortableHitTarget()
    }
  }
  var swatches: some View {
    ForEach(names.indices, id: \.self) { index in
      Button { band = index } label: {
        ZStack {
          Circle().fill(colours[index]).frame(width: 22, height: 22)
          if band == index { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(index == 2 ? .black : .white) }
        }.frame(minWidth: 28, minHeight: 44)
      }.buttonStyle(.plain).comfortableHitTarget().accessibilityLabel(names[index])
        .accessibilityAddTraits(band == index ? [.isSelected] : [])
    }
  }
  func control(_ title: String, _ index: Int) -> some View {
    let (key, field) = properties[index]
    let scale = index == 0 ? 60.0 : 100.0
    return AdjustmentControl(title: title + (index == 0 ? " (°)" : " (%)"), value: Binding(
      get: { model.controlConfiguration[keyPath: key] * scale },
      set: { value in var config = model.controlConfiguration; config[keyPath: key] = value / scale; model.applyChange(ConfigurationPatch(values: config, fields: [field])) }),
      range: -scale...scale, neutral: 0, mixed: model.mixedFields.contains(field),
      interaction: { active in if active { model.beginInteraction() } else { model.endInteraction() } }, interactionAvailable: { !model.interactionInProgress }, targetIDs: model.targets.map(\.id))
  }
  var properties: [(WritableKeyPath<ProcessingConfiguration, Double>, ConfigurationField)] {
    switch band {
    case 0: return [(\.adjustments.redHue, .adjustments_redHue), (\.adjustments.redSaturation, .adjustments_redSaturation), (\.adjustments.redLightness, .adjustments_redLightness)]
    case 1: return [(\.adjustments.orangeHue, .adjustments_orangeHue), (\.adjustments.orangeSaturation, .adjustments_orangeSaturation), (\.adjustments.orangeLightness, .adjustments_orangeLightness)]
    case 2: return [(\.adjustments.yellowHue, .adjustments_yellowHue), (\.adjustments.yellowSaturation, .adjustments_yellowSaturation), (\.adjustments.yellowLightness, .adjustments_yellowLightness)]
    case 3: return [(\.adjustments.greenHue, .adjustments_greenHue), (\.adjustments.greenSaturation, .adjustments_greenSaturation), (\.adjustments.greenLightness, .adjustments_greenLightness)]
    case 4: return [(\.adjustments.aquaHue, .adjustments_aquaHue), (\.adjustments.aquaSaturation, .adjustments_aquaSaturation), (\.adjustments.aquaLightness, .adjustments_aquaLightness)]
    case 5: return [(\.adjustments.blueHue, .adjustments_blueHue), (\.adjustments.blueSaturation, .adjustments_blueSaturation), (\.adjustments.blueLightness, .adjustments_blueLightness)]
    case 6: return [(\.adjustments.purpleHue, .adjustments_purpleHue), (\.adjustments.purpleSaturation, .adjustments_purpleSaturation), (\.adjustments.purpleLightness, .adjustments_purpleLightness)]
    case 7: return [(\.adjustments.magentaHue, .adjustments_magentaHue), (\.adjustments.magentaSaturation, .adjustments_magentaSaturation), (\.adjustments.magentaLightness, .adjustments_magentaLightness)]
    default: return []
    }
  }
}
