import Foundation

/// Serializable, explicitly scoped fields. Unlisted properties continue to inherit batch settings.
public enum ConfigurationField: String, CodingKey, Codable, Sendable, CaseIterable {
  case nativeOutputSizing = "nativeOutputSizing"
  case width = "width"
  case height = "height"
  case quarterTurns = "quarterTurns"
  case flipHorizontal = "flipHorizontal"
  case flipVertical = "flipVertical"
  case straighten = "straighten"
  case resizeBasis = "resizeBasis"
  case percentage = "percentage"
  case preventUpscaling = "preventUpscaling"
  case background = "background"
  case canvasAlignment = "canvasAlignment"
  case format = "format"
  case quality = "quality"
  case targetBytes = "targetBytes"
  case minimumQuality = "minimumQuality"
  case colourPolicy = "colourPolicy"
  case metadata = "metadata"
  case privacyExport = "privacyExport"
  case retouchStrokes = "retouchStrokes"
  case masks = "masks"
  case colourReplacements = "colourReplacements"
  case annotations = "annotations"
  case canvasStyle = "canvasStyle"
  case crop_mode = "crop.mode"
  case crop_framing = "crop.framing"
  case crop_centerX = "crop.centerX"
  case crop_centerY = "crop.centerY"
  case crop_zoom = "crop.zoom"
  case crop_aspectRatio = "crop.aspectRatio"
  case crop_quarterTurns = "crop.quarterTurns"
  case crop_straighten = "crop.straighten"
  case crop_flipHorizontal = "crop.flipHorizontal"
  case crop_flipVertical = "crop.flipVertical"
  case filterEdit = "filterEdit"
  case autoEnhance = "autoEnhance"
  case look = "look"
  case lookStrength = "lookStrength"
  case adjustments_vibrance = "adjustments.vibrance"
  case adjustments_tint = "adjustments.tint"
  case adjustments_redHue = "adjustments.redHue"
  case adjustments_redSaturation = "adjustments.redSaturation"
  case adjustments_redLightness = "adjustments.redLightness"
  case adjustments_orangeHue = "adjustments.orangeHue"
  case adjustments_orangeSaturation = "adjustments.orangeSaturation"
  case adjustments_orangeLightness = "adjustments.orangeLightness"
  case adjustments_yellowHue = "adjustments.yellowHue"
  case adjustments_yellowSaturation = "adjustments.yellowSaturation"
  case adjustments_yellowLightness = "adjustments.yellowLightness"
  case adjustments_greenHue = "adjustments.greenHue"
  case adjustments_greenSaturation = "adjustments.greenSaturation"
  case adjustments_greenLightness = "adjustments.greenLightness"
  case adjustments_aquaHue = "adjustments.aquaHue"
  case adjustments_aquaSaturation = "adjustments.aquaSaturation"
  case adjustments_aquaLightness = "adjustments.aquaLightness"
  case adjustments_blueHue = "adjustments.blueHue"
  case adjustments_blueSaturation = "adjustments.blueSaturation"
  case adjustments_blueLightness = "adjustments.blueLightness"
  case adjustments_purpleHue = "adjustments.purpleHue"
  case adjustments_purpleSaturation = "adjustments.purpleSaturation"
  case adjustments_purpleLightness = "adjustments.purpleLightness"
  case adjustments_magentaHue = "adjustments.magentaHue"
  case adjustments_magentaSaturation = "adjustments.magentaSaturation"
  case adjustments_magentaLightness = "adjustments.magentaLightness"
  case adjustments_exposure = "adjustments.exposure"
  case adjustments_brightness = "adjustments.brightness"
  case adjustments_contrast = "adjustments.contrast"
  case adjustments_saturation = "adjustments.saturation"
  case adjustments_warmth = "adjustments.warmth"
  case adjustments_highlights = "adjustments.highlights"
  case adjustments_shadows = "adjustments.shadows"
  case watermark_enabled = "watermark.enabled"
  case watermark_kind = "watermark.kind"
  case watermark_text = "watermark.text"
  case watermark_imageURL = "watermark.imageURL"
  case watermark_fontName = "watermark.fontName"
  case watermark_colour = "watermark.colour"
  case watermark_relativeWidth = "watermark.relativeWidth"
  case watermark_opacity = "watermark.opacity"
  case watermark_rotation = "watermark.rotation"
  case watermark_margin = "watermark.margin"
  case watermark_offsetX = "watermark.offsetX"
  case watermark_offsetY = "watermark.offsetY"
  case watermark_anchor = "watermark.anchor"
  case watermark_tiled = "watermark.tiled"
  public var displayName: String {
    switch self {
    case .filterEdit: return "Creative filter"
    case .autoEnhance: return "Auto Enhance"
    case .look: return "Photo filter"
    case .lookStrength: return "Filter strength"
    case .privacyExport: return "Privacy protection"
    case .masks: return "Privacy masks"
    case .quarterTurns: return "Rotation"
    case .targetBytes: return "Target file size"
    default:
      let text = rawValue.hasPrefix("adjustments.") ? String(rawValue.dropFirst("adjustments.".count)) : rawValue.replacingOccurrences(of: ".", with: " ")
      var label = ""
      for character in text {
        if character.isUppercase, let previous = label.last, previous.isLowercase { label.append(" ") }
        label.append(character)
      }
      return label.prefix(1).uppercased() + label.dropFirst()
    }
  }
  public var category: EditCategory {
    if rawValue.hasPrefix("adjustments.") || self == .filterEdit || self == .autoEnhance || self == .look || self == .lookStrength || self == .colourReplacements { return .adjustments }
    if rawValue.hasPrefix("watermark.") { return .watermark }
    if rawValue.hasPrefix("crop.") { return .framing }
    switch self {
    case .nativeOutputSizing, .width, .height, .resizeBasis, .percentage, .preventUpscaling, .background,
      .canvasAlignment, .canvasStyle:
      return .sizeAndCanvas
    case .quarterTurns, .flipHorizontal, .flipVertical, .straighten: return .orientation
    case .masks, .privacyExport: return .privacy
    case .retouchStrokes: return .retouch
    case .annotations: return .annotations
    default: return .output
    }
  }
}
public enum EditCategory: String, Codable, CaseIterable, Sendable {
  case adjustments = "Adjustments"
  case framing = "Framing"
  case orientation = "Rotation & Flip"
  case sizeAndCanvas = "Size & Canvas"
  case watermark = "Watermark"
  case privacy = "Privacy Masks"
  case retouch = "Retouch"
  case annotations = "Annotations"
  case output = "Format & Compression"
}
public struct ConfigurationPatch: Codable, Equatable, Sendable {
  public var values: ProcessingConfiguration
  public var fields: Set<ConfigurationField>
  public init(values: ProcessingConfiguration, fields: Set<ConfigurationField>) {
    self.values = values
    self.fields = fields
  }
  public init(from previous: ProcessingConfiguration, to value: ProcessingConfiguration) {
    values = value
    fields = []
    if previous.nativeOutputSizing != value.nativeOutputSizing { fields.insert(.nativeOutputSizing) }
    if previous.width != value.width { fields.insert(.width) }
    if previous.height != value.height { fields.insert(.height) }
    if previous.quarterTurns != value.quarterTurns { fields.insert(.quarterTurns) }
    if previous.flipHorizontal != value.flipHorizontal { fields.insert(.flipHorizontal) }
    if previous.flipVertical != value.flipVertical { fields.insert(.flipVertical) }
    if previous.straighten != value.straighten { fields.insert(.straighten) }
    if previous.resizeBasis != value.resizeBasis { fields.insert(.resizeBasis) }
    if previous.percentage != value.percentage { fields.insert(.percentage) }
    if previous.preventUpscaling != value.preventUpscaling { fields.insert(.preventUpscaling) }
    if previous.background != value.background { fields.insert(.background) }
    if previous.canvasAlignment != value.canvasAlignment { fields.insert(.canvasAlignment) }
    if previous.format != value.format { fields.insert(.format) }
    if previous.quality != value.quality { fields.insert(.quality) }
    if previous.targetBytes != value.targetBytes { fields.insert(.targetBytes) }
    if previous.minimumQuality != value.minimumQuality { fields.insert(.minimumQuality) }
    if previous.colourPolicy != value.colourPolicy { fields.insert(.colourPolicy) }
    if previous.metadata != value.metadata { fields.insert(.metadata) }
    if previous.privacyExport != value.privacyExport { fields.insert(.privacyExport) }
    if previous.retouchStrokes != value.retouchStrokes { fields.insert(.retouchStrokes) }
    if previous.masks != value.masks { fields.insert(.masks) }
    if previous.colourReplacements != value.colourReplacements { fields.insert(.colourReplacements) }
    if previous.annotations != value.annotations { fields.insert(.annotations) }
    if previous.canvasStyle != value.canvasStyle { fields.insert(.canvasStyle) }
    if previous.crop.mode != value.crop.mode { fields.insert(.crop_mode) }
    if previous.crop.framing != value.crop.framing { fields.insert(.crop_framing) }
    if previous.crop.centerX != value.crop.centerX { fields.insert(.crop_centerX) }
    if previous.crop.centerY != value.crop.centerY { fields.insert(.crop_centerY) }
    if previous.crop.zoom != value.crop.zoom { fields.insert(.crop_zoom) }
    if previous.crop.aspectRatio != value.crop.aspectRatio { fields.insert(.crop_aspectRatio) }
    if previous.crop.quarterTurns != value.crop.quarterTurns { fields.insert(.crop_quarterTurns) }
    if previous.crop.straighten != value.crop.straighten { fields.insert(.crop_straighten) }
    if previous.crop.flipHorizontal != value.crop.flipHorizontal {
      fields.insert(.crop_flipHorizontal)
    }
    if previous.crop.flipVertical != value.crop.flipVertical { fields.insert(.crop_flipVertical) }
    if previous.filterEdit != value.filterEdit { fields.insert(.filterEdit) }
    if previous.autoEnhance != value.autoEnhance { fields.insert(.autoEnhance) }
    if previous.look != value.look { fields.insert(.look) }
    if previous.lookStrength != value.lookStrength { fields.insert(.lookStrength) }
    if previous.adjustments.vibrance != value.adjustments.vibrance { fields.insert(.adjustments_vibrance) }
    if previous.adjustments.tint != value.adjustments.tint { fields.insert(.adjustments_tint) }
    if previous.adjustments.redHue != value.adjustments.redHue { fields.insert(.adjustments_redHue) }
    if previous.adjustments.redSaturation != value.adjustments.redSaturation { fields.insert(.adjustments_redSaturation) }
    if previous.adjustments.redLightness != value.adjustments.redLightness { fields.insert(.adjustments_redLightness) }
    if previous.adjustments.orangeHue != value.adjustments.orangeHue { fields.insert(.adjustments_orangeHue) }
    if previous.adjustments.orangeSaturation != value.adjustments.orangeSaturation { fields.insert(.adjustments_orangeSaturation) }
    if previous.adjustments.orangeLightness != value.adjustments.orangeLightness { fields.insert(.adjustments_orangeLightness) }
    if previous.adjustments.yellowHue != value.adjustments.yellowHue { fields.insert(.adjustments_yellowHue) }
    if previous.adjustments.yellowSaturation != value.adjustments.yellowSaturation { fields.insert(.adjustments_yellowSaturation) }
    if previous.adjustments.yellowLightness != value.adjustments.yellowLightness { fields.insert(.adjustments_yellowLightness) }
    if previous.adjustments.greenHue != value.adjustments.greenHue { fields.insert(.adjustments_greenHue) }
    if previous.adjustments.greenSaturation != value.adjustments.greenSaturation { fields.insert(.adjustments_greenSaturation) }
    if previous.adjustments.greenLightness != value.adjustments.greenLightness { fields.insert(.adjustments_greenLightness) }
    if previous.adjustments.aquaHue != value.adjustments.aquaHue { fields.insert(.adjustments_aquaHue) }
    if previous.adjustments.aquaSaturation != value.adjustments.aquaSaturation { fields.insert(.adjustments_aquaSaturation) }
    if previous.adjustments.aquaLightness != value.adjustments.aquaLightness { fields.insert(.adjustments_aquaLightness) }
    if previous.adjustments.blueHue != value.adjustments.blueHue { fields.insert(.adjustments_blueHue) }
    if previous.adjustments.blueSaturation != value.adjustments.blueSaturation { fields.insert(.adjustments_blueSaturation) }
    if previous.adjustments.blueLightness != value.adjustments.blueLightness { fields.insert(.adjustments_blueLightness) }
    if previous.adjustments.purpleHue != value.adjustments.purpleHue { fields.insert(.adjustments_purpleHue) }
    if previous.adjustments.purpleSaturation != value.adjustments.purpleSaturation { fields.insert(.adjustments_purpleSaturation) }
    if previous.adjustments.purpleLightness != value.adjustments.purpleLightness { fields.insert(.adjustments_purpleLightness) }
    if previous.adjustments.magentaHue != value.adjustments.magentaHue { fields.insert(.adjustments_magentaHue) }
    if previous.adjustments.magentaSaturation != value.adjustments.magentaSaturation { fields.insert(.adjustments_magentaSaturation) }
    if previous.adjustments.magentaLightness != value.adjustments.magentaLightness { fields.insert(.adjustments_magentaLightness) }
    if previous.adjustments.exposure != value.adjustments.exposure {
      fields.insert(.adjustments_exposure)
    }
    if previous.adjustments.brightness != value.adjustments.brightness {
      fields.insert(.adjustments_brightness)
    }
    if previous.adjustments.contrast != value.adjustments.contrast {
      fields.insert(.adjustments_contrast)
    }
    if previous.adjustments.saturation != value.adjustments.saturation {
      fields.insert(.adjustments_saturation)
    }
    if previous.adjustments.warmth != value.adjustments.warmth {
      fields.insert(.adjustments_warmth)
    }
    if previous.adjustments.highlights != value.adjustments.highlights {
      fields.insert(.adjustments_highlights)
    }
    if previous.adjustments.shadows != value.adjustments.shadows {
      fields.insert(.adjustments_shadows)
    }
    if previous.watermark.enabled != value.watermark.enabled { fields.insert(.watermark_enabled) }
    if previous.watermark.kind != value.watermark.kind { fields.insert(.watermark_kind) }
    if previous.watermark.text != value.watermark.text { fields.insert(.watermark_text) }
    if previous.watermark.imageURL != value.watermark.imageURL {
      fields.insert(.watermark_imageURL)
    }
    if previous.watermark.fontName != value.watermark.fontName {
      fields.insert(.watermark_fontName)
    }
    if previous.watermark.colour != value.watermark.colour { fields.insert(.watermark_colour) }
    if previous.watermark.relativeWidth != value.watermark.relativeWidth {
      fields.insert(.watermark_relativeWidth)
    }
    if previous.watermark.opacity != value.watermark.opacity { fields.insert(.watermark_opacity) }
    if previous.watermark.rotation != value.watermark.rotation {
      fields.insert(.watermark_rotation)
    }
    if previous.watermark.margin != value.watermark.margin { fields.insert(.watermark_margin) }
    if previous.watermark.offsetX != value.watermark.offsetX { fields.insert(.watermark_offsetX) }
    if previous.watermark.offsetY != value.watermark.offsetY { fields.insert(.watermark_offsetY) }
    if previous.watermark.anchor != value.watermark.anchor { fields.insert(.watermark_anchor) }
    if previous.watermark.tiled != value.watermark.tiled { fields.insert(.watermark_tiled) }
  }
  public func applying(to original: ProcessingConfiguration) -> ProcessingConfiguration {
    var value = original
    for field in fields {
      switch field {
      case .nativeOutputSizing: value.nativeOutputSizing = values.nativeOutputSizing
      case .width: value.width = values.width
      case .height: value.height = values.height
      case .quarterTurns: value.quarterTurns = values.quarterTurns
      case .flipHorizontal: value.flipHorizontal = values.flipHorizontal
      case .flipVertical: value.flipVertical = values.flipVertical
      case .straighten: value.straighten = values.straighten
      case .resizeBasis: value.resizeBasis = values.resizeBasis
      case .percentage: value.percentage = values.percentage
      case .preventUpscaling: value.preventUpscaling = values.preventUpscaling
      case .background: value.background = values.background
      case .canvasAlignment: value.canvasAlignment = values.canvasAlignment
      case .format: value.format = values.format
      case .quality: value.quality = values.quality
      case .targetBytes: value.targetBytes = values.targetBytes
      case .minimumQuality: value.minimumQuality = values.minimumQuality
      case .colourPolicy: value.colourPolicy = values.colourPolicy
      case .metadata: value.metadata = values.metadata
      case .privacyExport: value.privacyExport = values.privacyExport
      case .retouchStrokes: value.retouchStrokes = values.retouchStrokes
      case .masks: value.masks = values.masks
      case .colourReplacements: value.colourReplacements = values.colourReplacements
      case .annotations: value.annotations = values.annotations
      case .canvasStyle: value.canvasStyle = values.canvasStyle
      case .crop_mode: value.crop.mode = values.crop.mode
      case .crop_framing: value.crop.framing = values.crop.framing
      case .crop_centerX: value.crop.centerX = values.crop.centerX
      case .crop_centerY: value.crop.centerY = values.crop.centerY
      case .crop_zoom: value.crop.zoom = values.crop.zoom
      case .crop_aspectRatio: value.crop.aspectRatio = values.crop.aspectRatio
      case .crop_quarterTurns: value.crop.quarterTurns = values.crop.quarterTurns
      case .crop_straighten: value.crop.straighten = values.crop.straighten
      case .crop_flipHorizontal: value.crop.flipHorizontal = values.crop.flipHorizontal
      case .crop_flipVertical: value.crop.flipVertical = values.crop.flipVertical
      case .filterEdit: value.filterEdit = values.filterEdit
      case .autoEnhance: value.autoEnhance = values.autoEnhance
      case .look: value.look = values.look
      case .lookStrength: value.lookStrength = values.lookStrength
      case .adjustments_vibrance: value.adjustments.vibrance = values.adjustments.vibrance
      case .adjustments_tint: value.adjustments.tint = values.adjustments.tint
      case .adjustments_redHue: value.adjustments.redHue = values.adjustments.redHue
      case .adjustments_redSaturation: value.adjustments.redSaturation = values.adjustments.redSaturation
      case .adjustments_redLightness: value.adjustments.redLightness = values.adjustments.redLightness
      case .adjustments_orangeHue: value.adjustments.orangeHue = values.adjustments.orangeHue
      case .adjustments_orangeSaturation: value.adjustments.orangeSaturation = values.adjustments.orangeSaturation
      case .adjustments_orangeLightness: value.adjustments.orangeLightness = values.adjustments.orangeLightness
      case .adjustments_yellowHue: value.adjustments.yellowHue = values.adjustments.yellowHue
      case .adjustments_yellowSaturation: value.adjustments.yellowSaturation = values.adjustments.yellowSaturation
      case .adjustments_yellowLightness: value.adjustments.yellowLightness = values.adjustments.yellowLightness
      case .adjustments_greenHue: value.adjustments.greenHue = values.adjustments.greenHue
      case .adjustments_greenSaturation: value.adjustments.greenSaturation = values.adjustments.greenSaturation
      case .adjustments_greenLightness: value.adjustments.greenLightness = values.adjustments.greenLightness
      case .adjustments_aquaHue: value.adjustments.aquaHue = values.adjustments.aquaHue
      case .adjustments_aquaSaturation: value.adjustments.aquaSaturation = values.adjustments.aquaSaturation
      case .adjustments_aquaLightness: value.adjustments.aquaLightness = values.adjustments.aquaLightness
      case .adjustments_blueHue: value.adjustments.blueHue = values.adjustments.blueHue
      case .adjustments_blueSaturation: value.adjustments.blueSaturation = values.adjustments.blueSaturation
      case .adjustments_blueLightness: value.adjustments.blueLightness = values.adjustments.blueLightness
      case .adjustments_purpleHue: value.adjustments.purpleHue = values.adjustments.purpleHue
      case .adjustments_purpleSaturation: value.adjustments.purpleSaturation = values.adjustments.purpleSaturation
      case .adjustments_purpleLightness: value.adjustments.purpleLightness = values.adjustments.purpleLightness
      case .adjustments_magentaHue: value.adjustments.magentaHue = values.adjustments.magentaHue
      case .adjustments_magentaSaturation: value.adjustments.magentaSaturation = values.adjustments.magentaSaturation
      case .adjustments_magentaLightness: value.adjustments.magentaLightness = values.adjustments.magentaLightness
      case .adjustments_exposure: value.adjustments.exposure = values.adjustments.exposure
      case .adjustments_brightness: value.adjustments.brightness = values.adjustments.brightness
      case .adjustments_contrast: value.adjustments.contrast = values.adjustments.contrast
      case .adjustments_saturation: value.adjustments.saturation = values.adjustments.saturation
      case .adjustments_warmth: value.adjustments.warmth = values.adjustments.warmth
      case .adjustments_highlights: value.adjustments.highlights = values.adjustments.highlights
      case .adjustments_shadows: value.adjustments.shadows = values.adjustments.shadows
      case .watermark_enabled: value.watermark.enabled = values.watermark.enabled
      case .watermark_kind: value.watermark.kind = values.watermark.kind
      case .watermark_text: value.watermark.text = values.watermark.text
      case .watermark_imageURL: value.watermark.imageURL = values.watermark.imageURL
      case .watermark_fontName: value.watermark.fontName = values.watermark.fontName
      case .watermark_colour: value.watermark.colour = values.watermark.colour
      case .watermark_relativeWidth: value.watermark.relativeWidth = values.watermark.relativeWidth
      case .watermark_opacity: value.watermark.opacity = values.watermark.opacity
      case .watermark_rotation: value.watermark.rotation = values.watermark.rotation
      case .watermark_margin: value.watermark.margin = values.watermark.margin
      case .watermark_offsetX: value.watermark.offsetX = values.watermark.offsetX
      case .watermark_offsetY: value.watermark.offsetY = values.watermark.offsetY
      case .watermark_anchor: value.watermark.anchor = values.watermark.anchor
      case .watermark_tiled: value.watermark.tiled = values.watermark.tiled
      }
    }
    return value
  }
  public mutating func merge(_ change: ConfigurationPatch) {
    values = change.applying(to: values)
    fields.formUnion(change.fields)
  }
  public static func == (lhs: ConfigurationPatch, rhs: ConfigurationPatch) -> Bool {
    lhs.fields == rhs.fields
      && lhs.applying(to: ProcessingConfiguration()) == rhs.applying(to: ProcessingConfiguration())
  }
  private enum CodingKeys: String, CodingKey { case values, fields }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fields = try container.decode(Set<ConfigurationField>.self, forKey: .fields)
    values = ProcessingConfiguration()
    let payload = try container.nestedContainer(keyedBy: ConfigurationField.self, forKey: .values)
    func read<T: Decodable>(
      _ key: WritableKeyPath<ProcessingConfiguration, T>, _ field: ConfigurationField
    ) throws -> T {
      try payload.decode(T.self, forKey: field)
    }
    for field in fields {
      switch field {
      case .filterEdit: values.filterEdit = try read(\.filterEdit, field)
      case .autoEnhance: values.autoEnhance = try read(\.autoEnhance, field)
      case .look: values.look = try read(\.look, field)
      case .lookStrength: values.lookStrength = try read(\.lookStrength, field)
      case .nativeOutputSizing: values.nativeOutputSizing = try read(\.nativeOutputSizing, field)
      case .width: values.width = try read(\.width, field)
      case .height: values.height = try read(\.height, field)
      case .quarterTurns: values.quarterTurns = try read(\.quarterTurns, field)
      case .flipHorizontal: values.flipHorizontal = try read(\.flipHorizontal, field)
      case .flipVertical: values.flipVertical = try read(\.flipVertical, field)
      case .straighten: values.straighten = try read(\.straighten, field)
      case .resizeBasis: values.resizeBasis = try read(\.resizeBasis, field)
      case .percentage: values.percentage = try read(\.percentage, field)
      case .preventUpscaling: values.preventUpscaling = try read(\.preventUpscaling, field)
      case .background: values.background = try read(\.background, field)
      case .canvasAlignment: values.canvasAlignment = try read(\.canvasAlignment, field)
      case .format: values.format = try read(\.format, field)
      case .quality: values.quality = try read(\.quality, field)
      case .targetBytes: values.targetBytes = try read(\.targetBytes, field)
      case .minimumQuality: values.minimumQuality = try read(\.minimumQuality, field)
      case .colourPolicy: values.colourPolicy = try read(\.colourPolicy, field)
      case .metadata: values.metadata = try read(\.metadata, field)
      case .privacyExport: values.privacyExport = try read(\.privacyExport, field)
      case .retouchStrokes: values.retouchStrokes = try read(\.retouchStrokes, field)
      case .masks: values.masks = try read(\.masks, field)
      case .colourReplacements: values.colourReplacements = try read(\.colourReplacements, field)
      case .annotations: values.annotations = try read(\.annotations, field)
      case .canvasStyle: values.canvasStyle = try read(\.canvasStyle, field)
      case .crop_mode: values.crop.mode = try read(\.crop.mode, field)
      case .crop_framing: values.crop.framing = try read(\.crop.framing, field)
      case .crop_centerX: values.crop.centerX = try read(\.crop.centerX, field)
      case .crop_centerY: values.crop.centerY = try read(\.crop.centerY, field)
      case .crop_zoom: values.crop.zoom = try read(\.crop.zoom, field)
      case .crop_aspectRatio: values.crop.aspectRatio = try read(\.crop.aspectRatio, field)
      case .crop_quarterTurns: values.crop.quarterTurns = try read(\.crop.quarterTurns, field)
      case .crop_straighten: values.crop.straighten = try read(\.crop.straighten, field)
      case .crop_flipHorizontal: values.crop.flipHorizontal = try read(\.crop.flipHorizontal, field)
      case .crop_flipVertical: values.crop.flipVertical = try read(\.crop.flipVertical, field)
      case .adjustments_vibrance: values.adjustments.vibrance = try read(\.adjustments.vibrance, field)
      case .adjustments_tint: values.adjustments.tint = try read(\.adjustments.tint, field)
      case .adjustments_redHue: values.adjustments.redHue = try read(\.adjustments.redHue, field)
      case .adjustments_redSaturation: values.adjustments.redSaturation = try read(\.adjustments.redSaturation, field)
      case .adjustments_redLightness: values.adjustments.redLightness = try read(\.adjustments.redLightness, field)
      case .adjustments_orangeHue: values.adjustments.orangeHue = try read(\.adjustments.orangeHue, field)
      case .adjustments_orangeSaturation: values.adjustments.orangeSaturation = try read(\.adjustments.orangeSaturation, field)
      case .adjustments_orangeLightness: values.adjustments.orangeLightness = try read(\.adjustments.orangeLightness, field)
      case .adjustments_yellowHue: values.adjustments.yellowHue = try read(\.adjustments.yellowHue, field)
      case .adjustments_yellowSaturation: values.adjustments.yellowSaturation = try read(\.adjustments.yellowSaturation, field)
      case .adjustments_yellowLightness: values.adjustments.yellowLightness = try read(\.adjustments.yellowLightness, field)
      case .adjustments_greenHue: values.adjustments.greenHue = try read(\.adjustments.greenHue, field)
      case .adjustments_greenSaturation: values.adjustments.greenSaturation = try read(\.adjustments.greenSaturation, field)
      case .adjustments_greenLightness: values.adjustments.greenLightness = try read(\.adjustments.greenLightness, field)
      case .adjustments_aquaHue: values.adjustments.aquaHue = try read(\.adjustments.aquaHue, field)
      case .adjustments_aquaSaturation: values.adjustments.aquaSaturation = try read(\.adjustments.aquaSaturation, field)
      case .adjustments_aquaLightness: values.adjustments.aquaLightness = try read(\.adjustments.aquaLightness, field)
      case .adjustments_blueHue: values.adjustments.blueHue = try read(\.adjustments.blueHue, field)
      case .adjustments_blueSaturation: values.adjustments.blueSaturation = try read(\.adjustments.blueSaturation, field)
      case .adjustments_blueLightness: values.adjustments.blueLightness = try read(\.adjustments.blueLightness, field)
      case .adjustments_purpleHue: values.adjustments.purpleHue = try read(\.adjustments.purpleHue, field)
      case .adjustments_purpleSaturation: values.adjustments.purpleSaturation = try read(\.adjustments.purpleSaturation, field)
      case .adjustments_purpleLightness: values.adjustments.purpleLightness = try read(\.adjustments.purpleLightness, field)
      case .adjustments_magentaHue: values.adjustments.magentaHue = try read(\.adjustments.magentaHue, field)
      case .adjustments_magentaSaturation: values.adjustments.magentaSaturation = try read(\.adjustments.magentaSaturation, field)
      case .adjustments_magentaLightness: values.adjustments.magentaLightness = try read(\.adjustments.magentaLightness, field)
      case .adjustments_exposure:
        values.adjustments.exposure = try read(\.adjustments.exposure, field)
      case .adjustments_brightness:
        values.adjustments.brightness = try read(\.adjustments.brightness, field)
      case .adjustments_contrast:
        values.adjustments.contrast = try read(\.adjustments.contrast, field)
      case .adjustments_saturation:
        values.adjustments.saturation = try read(\.adjustments.saturation, field)
      case .adjustments_warmth: values.adjustments.warmth = try read(\.adjustments.warmth, field)
      case .adjustments_highlights:
        values.adjustments.highlights = try read(\.adjustments.highlights, field)
      case .adjustments_shadows: values.adjustments.shadows = try read(\.adjustments.shadows, field)
      case .watermark_enabled: values.watermark.enabled = try read(\.watermark.enabled, field)
      case .watermark_kind: values.watermark.kind = try read(\.watermark.kind, field)
      case .watermark_text: values.watermark.text = try read(\.watermark.text, field)
      case .watermark_imageURL: values.watermark.imageURL = try read(\.watermark.imageURL, field)
      case .watermark_fontName: values.watermark.fontName = try read(\.watermark.fontName, field)
      case .watermark_colour: values.watermark.colour = try read(\.watermark.colour, field)
      case .watermark_relativeWidth:
        values.watermark.relativeWidth = try read(\.watermark.relativeWidth, field)
      case .watermark_opacity: values.watermark.opacity = try read(\.watermark.opacity, field)
      case .watermark_rotation: values.watermark.rotation = try read(\.watermark.rotation, field)
      case .watermark_margin: values.watermark.margin = try read(\.watermark.margin, field)
      case .watermark_offsetX: values.watermark.offsetX = try read(\.watermark.offsetX, field)
      case .watermark_offsetY: values.watermark.offsetY = try read(\.watermark.offsetY, field)
      case .watermark_anchor: values.watermark.anchor = try read(\.watermark.anchor, field)
      case .watermark_tiled: values.watermark.tiled = try read(\.watermark.tiled, field)
      }
    }
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(fields, forKey: .fields)
    var payload = container.nestedContainer(keyedBy: ConfigurationField.self, forKey: .values)
    for field in fields {
      switch field {
      case .filterEdit: try payload.encode(values.filterEdit, forKey: field)
      case .autoEnhance: try payload.encode(values.autoEnhance, forKey: field)
      case .look: try payload.encode(values.look, forKey: field)
      case .lookStrength: try payload.encode(values.lookStrength, forKey: field)
      case .nativeOutputSizing: try payload.encode(values.nativeOutputSizing, forKey: field)
      case .width: try payload.encode(values.width, forKey: field)
      case .height: try payload.encode(values.height, forKey: field)
      case .quarterTurns: try payload.encode(values.quarterTurns, forKey: field)
      case .flipHorizontal: try payload.encode(values.flipHorizontal, forKey: field)
      case .flipVertical: try payload.encode(values.flipVertical, forKey: field)
      case .straighten: try payload.encode(values.straighten, forKey: field)
      case .resizeBasis: try payload.encode(values.resizeBasis, forKey: field)
      case .percentage: try payload.encode(values.percentage, forKey: field)
      case .preventUpscaling: try payload.encode(values.preventUpscaling, forKey: field)
      case .background: try payload.encode(values.background, forKey: field)
      case .canvasAlignment: try payload.encode(values.canvasAlignment, forKey: field)
      case .format: try payload.encode(values.format, forKey: field)
      case .quality: try payload.encode(values.quality, forKey: field)
      case .targetBytes: try payload.encode(values.targetBytes, forKey: field)
      case .minimumQuality: try payload.encode(values.minimumQuality, forKey: field)
      case .colourPolicy: try payload.encode(values.colourPolicy, forKey: field)
      case .metadata: try payload.encode(values.metadata, forKey: field)
      case .privacyExport: try payload.encode(values.privacyExport, forKey: field)
      case .retouchStrokes: try payload.encode(values.retouchStrokes, forKey: field)
      case .masks: try payload.encode(values.masks, forKey: field)
      case .colourReplacements: try payload.encode(values.colourReplacements, forKey: field)
      case .annotations: try payload.encode(values.annotations, forKey: field)
      case .canvasStyle: try payload.encode(values.canvasStyle, forKey: field)
      case .crop_mode: try payload.encode(values.crop.mode, forKey: field)
      case .crop_framing: try payload.encode(values.crop.framing, forKey: field)
      case .crop_centerX: try payload.encode(values.crop.centerX, forKey: field)
      case .crop_centerY: try payload.encode(values.crop.centerY, forKey: field)
      case .crop_zoom: try payload.encode(values.crop.zoom, forKey: field)
      case .crop_aspectRatio: try payload.encode(values.crop.aspectRatio, forKey: field)
      case .crop_quarterTurns: try payload.encode(values.crop.quarterTurns, forKey: field)
      case .crop_straighten: try payload.encode(values.crop.straighten, forKey: field)
      case .crop_flipHorizontal: try payload.encode(values.crop.flipHorizontal, forKey: field)
      case .crop_flipVertical: try payload.encode(values.crop.flipVertical, forKey: field)
      case .adjustments_vibrance: try payload.encode(values.adjustments.vibrance, forKey: field)
      case .adjustments_tint: try payload.encode(values.adjustments.tint, forKey: field)
      case .adjustments_redHue: try payload.encode(values.adjustments.redHue, forKey: field)
      case .adjustments_redSaturation: try payload.encode(values.adjustments.redSaturation, forKey: field)
      case .adjustments_redLightness: try payload.encode(values.adjustments.redLightness, forKey: field)
      case .adjustments_orangeHue: try payload.encode(values.adjustments.orangeHue, forKey: field)
      case .adjustments_orangeSaturation: try payload.encode(values.adjustments.orangeSaturation, forKey: field)
      case .adjustments_orangeLightness: try payload.encode(values.adjustments.orangeLightness, forKey: field)
      case .adjustments_yellowHue: try payload.encode(values.adjustments.yellowHue, forKey: field)
      case .adjustments_yellowSaturation: try payload.encode(values.adjustments.yellowSaturation, forKey: field)
      case .adjustments_yellowLightness: try payload.encode(values.adjustments.yellowLightness, forKey: field)
      case .adjustments_greenHue: try payload.encode(values.adjustments.greenHue, forKey: field)
      case .adjustments_greenSaturation: try payload.encode(values.adjustments.greenSaturation, forKey: field)
      case .adjustments_greenLightness: try payload.encode(values.adjustments.greenLightness, forKey: field)
      case .adjustments_aquaHue: try payload.encode(values.adjustments.aquaHue, forKey: field)
      case .adjustments_aquaSaturation: try payload.encode(values.adjustments.aquaSaturation, forKey: field)
      case .adjustments_aquaLightness: try payload.encode(values.adjustments.aquaLightness, forKey: field)
      case .adjustments_blueHue: try payload.encode(values.adjustments.blueHue, forKey: field)
      case .adjustments_blueSaturation: try payload.encode(values.adjustments.blueSaturation, forKey: field)
      case .adjustments_blueLightness: try payload.encode(values.adjustments.blueLightness, forKey: field)
      case .adjustments_purpleHue: try payload.encode(values.adjustments.purpleHue, forKey: field)
      case .adjustments_purpleSaturation: try payload.encode(values.adjustments.purpleSaturation, forKey: field)
      case .adjustments_purpleLightness: try payload.encode(values.adjustments.purpleLightness, forKey: field)
      case .adjustments_magentaHue: try payload.encode(values.adjustments.magentaHue, forKey: field)
      case .adjustments_magentaSaturation: try payload.encode(values.adjustments.magentaSaturation, forKey: field)
      case .adjustments_magentaLightness: try payload.encode(values.adjustments.magentaLightness, forKey: field)
      case .adjustments_exposure: try payload.encode(values.adjustments.exposure, forKey: field)
      case .adjustments_brightness: try payload.encode(values.adjustments.brightness, forKey: field)
      case .adjustments_contrast: try payload.encode(values.adjustments.contrast, forKey: field)
      case .adjustments_saturation: try payload.encode(values.adjustments.saturation, forKey: field)
      case .adjustments_warmth: try payload.encode(values.adjustments.warmth, forKey: field)
      case .adjustments_highlights: try payload.encode(values.adjustments.highlights, forKey: field)
      case .adjustments_shadows: try payload.encode(values.adjustments.shadows, forKey: field)
      case .watermark_enabled: try payload.encode(values.watermark.enabled, forKey: field)
      case .watermark_kind: try payload.encode(values.watermark.kind, forKey: field)
      case .watermark_text: try payload.encode(values.watermark.text, forKey: field)
      case .watermark_imageURL: try payload.encode(values.watermark.imageURL, forKey: field)
      case .watermark_fontName: try payload.encode(values.watermark.fontName, forKey: field)
      case .watermark_colour: try payload.encode(values.watermark.colour, forKey: field)
      case .watermark_relativeWidth:
        try payload.encode(values.watermark.relativeWidth, forKey: field)
      case .watermark_opacity: try payload.encode(values.watermark.opacity, forKey: field)
      case .watermark_rotation: try payload.encode(values.watermark.rotation, forKey: field)
      case .watermark_margin: try payload.encode(values.watermark.margin, forKey: field)
      case .watermark_offsetX: try payload.encode(values.watermark.offsetX, forKey: field)
      case .watermark_offsetY: try payload.encode(values.watermark.offsetY, forKey: field)
      case .watermark_anchor: try payload.encode(values.watermark.anchor, forKey: field)
      case .watermark_tiled: try payload.encode(values.watermark.tiled, forKey: field)
      }
    }
  }
  public func choosing(_ categories: Set<EditCategory>) -> ConfigurationPatch {
    ConfigurationPatch(values: values, fields: fields.filter { categories.contains($0.category) })
  }
}
