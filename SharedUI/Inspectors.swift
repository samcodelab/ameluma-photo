import FramepebbleCore
import SwiftUI

enum EditorDestination { case framing, collage, overlays, projects }

struct SettingsEditor: View {
  @Bindable var model: Workspace
  var focused = false
  var recipeEditing = false
  var openEditor: ((EditorDestination) -> Void)? = nil
  @State private var watermarkImport = false
  @State private var savePreset = false
  @State private var presetName = ""
  @Environment(\.self) private var environment
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  func open(_ destination: EditorDestination) {
    if let openEditor {
      openEditor(destination)
      return
    }
    switch destination {
    case .framing: model.precision = true
    case .collage: model.switchWorkflow(.collages)
    case .overlays: if let asset = model.current { model.openOverlayEditor(for: asset) }
    case .projects: model.projectsView = true
    }
  }
  var config: Binding<ProcessingConfiguration> {
    Binding(get: { model.controlConfiguration }, set: { model.controlConfiguration = $0 })
  }
  func field<T>(_ key: WritableKeyPath<ProcessingConfiguration, T>, _ fields: Set<ConfigurationField>) -> Binding<T> {
    Binding(get: { model.controlConfiguration[keyPath: key] }, set: { model.updateField(key, value: $0, fields: fields) })
  }
  var body: some View {
    Form {
      Section {
        if focused || typeSize.isAccessibilitySize {
          Menu("More tools", systemImage: "ellipsis.circle") {
            ForEach(InspectorTask.allCases.filter { !recipeEditing || $0 != .creative }, id: \.self) { task in
              Button(task.rawValue) { model.inspectorTask = task }
            }
          }
        } else {
          Picker("Tool", selection: $model.inspectorTask) {
            ForEach(InspectorTask.allCases.filter { !recipeEditing || $0 != .creative }, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented)
        }
        if !recipeEditing && model.workflow == .batch {
          Label(model.editScopeHeading, systemImage: "person.2.crop.square.stack").font(.headline)
          Text("Selection does not change this target. Choose the batch inputs below before editing.").font(.caption).foregroundStyle(.secondary)
          Picker("Batch inputs / edit target", selection: $model.scope) {
            ForEach([ApplyScope.all, .selected, .results], id: \.self) { Text($0.rawValue).tag($0) }
          }
        }
        if !recipeEditing {
        Text(model.workflow == .photo ? model.current?.name ?? "Choose a photo" : model.targetSummary).font(.caption)
          .foregroundStyle(.secondary)
        if !model.mixedFields.isEmpty && !(model.workflow == .batch && model.scope == .all) {
          Text("Mixed values: " + model.mixedFields.map(\.displayName).sorted().joined(separator: ", "))
            .font(.caption).foregroundStyle(.secondary)
          Text("Controls show the first target’s value. Changing a field sets that field for every labelled target; other fields stay distinct.").font(.caption).foregroundStyle(.secondary)
        }
        if model.workflow != .photo { overrideControls }
        }
      }
      #if os(iOS)
        if model.inspectorTask == .adjust || model.inspectorTask == .resize {
          if horizontalSizeClass == .compact, let asset = model.current {
            Section("Preview") {
              FramingSurface(model: model, asset: asset, interactive: false, maximum: 800).frame(
                height: 230
              ).accessibilityLabel("Processed photo preview")
            }
          }
        }
      #endif
      if model.inspectorTask == .adjust {
        Section("Adjust") {
          Menu("Quick Fix") {
            ForEach(QuickFix.allCases, id: \.self) { fix in
              Button(fix.rawValue) { model.quickFix(fix) }
            }
          }.disabled(model.targets.isEmpty)
          adjustment("Exposure", field(\.adjustments.exposure, [.adjustments_exposure]), -2...2, neutral: 0, mixed: model.mixedFields.contains(.adjustments_exposure))
          adjustment("Brightness", field(\.adjustments.brightness, [.adjustments_brightness]), -0.5...0.5, neutral: 0, mixed: model.mixedFields.contains(.adjustments_brightness))
          adjustment("Contrast", field(\.adjustments.contrast, [.adjustments_contrast]), 0.5...1.5, neutral: 1, mixed: model.mixedFields.contains(.adjustments_contrast))
          adjustment("Saturation", field(\.adjustments.saturation, [.adjustments_saturation]), 0...2, neutral: 1, mixed: model.mixedFields.contains(.adjustments_saturation))
          adjustment("Warmth", field(\.adjustments.warmth, [.adjustments_warmth]), -1...1, neutral: 0, mixed: model.mixedFields.contains(.adjustments_warmth))
          adjustment("Highlights", field(\.adjustments.highlights, [.adjustments_highlights]), 0...1, neutral: 1, mixed: model.mixedFields.contains(.adjustments_highlights))
          adjustment("Shadows", field(\.adjustments.shadows, [.adjustments_shadows]), 0...1, neutral: 0, mixed: model.mixedFields.contains(.adjustments_shadows))
          Button("Reset adjustments") {
            var value = model.controlConfiguration; value.adjustments = PhotoAdjustments()
            model.applyChange(ConfigurationPatch(values: value, fields: Set(ConfigurationField.allCases.filter { $0.category == .adjustments })))
          }
        }
      }
      if model.inspectorTask == .creative {
        Section("Creative & Privacy") {
          Button("Projects & Relink…") { open(.projects) }
          Button("Conceal workspace", systemImage: "eye.slash") { model.concealed = true }
          Toggle("Skip duplicate imports", isOn: $model.skipDuplicates)
          Toggle("Private Editing Mode", isOn: $model.privateEditing)
          Text(
            "Private mode disables the app’s memory thumbnail cache. Saved originals and recovery data remain on disk; this is not secure deletion or an encrypted vault."
          ).font(.caption).foregroundStyle(.secondary)
          Button("Make a Collage…") { open(.collage) }.disabled(model.assets.isEmpty)
          Button("Annotations & Privacy…") { open(.overlays) }.disabled(
            model.current == nil)
          Text("Opaque covers and cropping provide stronger concealment than blur or pixelation.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if model.inspectorTask == .resize {
        Section("Resize & Canvas") {
          Menu("Choose a size preset") {
            ForEach([512, 1024, 2048, 1080], id: \.self) { edge in
              Button("\(edge) × \(edge)") {
                var c = config.wrappedValue
                c.width = edge
                c.height = edge
                model.applyChange(ConfigurationPatch(values: c, fields: [.width, .height]))
              }
            }
            Button("1080 × 1350") { setSize(1080, 1350) }
            Button("1920 × 1080") { setSize(1920, 1080) }
            Button("3840 × 2160") { setSize(3840, 2160) }
          }
          LabeledContent("Width (px)") {
            TextField("Width", value: field(\.width, [.width]), format: .number).labelsHidden()
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Height (px)") {
            TextField("Height", value: field(\.height, [.height]), format: .number).labelsHidden()
              .multilineTextAlignment(.trailing)
          }
          Picker("How the photo fits", selection: field(\.crop.mode, [.crop_mode])) {
            ForEach(CropMode.allCases, id: \.self) { Text(cropLabel($0)).tag($0) }
          }
          if field(\.crop.mode, [.crop_mode]).wrappedValue == .preserveAspectRatio {
            Picker("Resize by", selection: field(\.resizeBasis, [.resizeBasis])) {
              ForEach(ResizeBasis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            if field(\.resizeBasis, [.resizeBasis]).wrappedValue == .percentage {
              TextField("Percentage", value: field(\.percentage, [.percentage]), format: .number)
            }
          }
          Toggle("Prevent upscaling", isOn: field(\.preventUpscaling, [.preventUpscaling]))
          if field(\.crop.mode, [.crop_mode]).wrappedValue == .canvas || field(\.crop.mode, [.crop_mode]).wrappedValue == .fit {
            ColorPicker("Background", selection: colour(field(\.background, [.background])), supportsOpacity: true)
            if field(\.crop.mode, [.crop_mode]).wrappedValue == .canvas {
              AnchorPicker(anchor: field(\.canvasAlignment, [.canvasAlignment]))
            }
          }
          if field(\.crop.mode, [.crop_mode]).wrappedValue == .stretch {
            Text("Stretch changes the image's aspect ratio.").font(.caption).foregroundStyle(
              .secondary)
          }
        }
        Section("Convert") {
          Picker("Output format", selection: field(\.format, [.format])) {
            ForEach(ImageProcessor.outputFormats, id: \.self) {
              Text($0.rawValue.uppercased()).tag($0)
            }
          }
          Button("Advanced export settings") { model.inspectorTask = .output }
        }
      }
      if model.inspectorTask == .resize || model.inspectorTask == .adjust {
        Section("Framing") {
          Menu("Aspect ratio") {
            Button("Square") { applyAspect(1) }
            Button("4:3") { applyAspect(4.0 / 3) }
            Button("3:2") { applyAspect(1.5) }
            Button("16:9") { applyAspect(16.0 / 9) }
            Button("4:5") { applyAspect(0.8) }
          }
          if !recipeEditing {
          HStack {
            Button("Smart Auto-frame") { model.autoFrame(.smart) }
            Button("Keep Subjects") { model.autoFrame(.keepSubjects) }
          }.disabled(model.analysing || model.targets.isEmpty)
          Text("Uses on-device Vision. Manual framing is preserved; review flagged proposals.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Refine selected image", systemImage: "crop") { open(.framing) }.disabled(
            model.current == nil)
          }
        }
        Section("Rotate & Flip") {
          HStack {
            Button {
              field(\.quarterTurns, [.quarterTurns]).wrappedValue -= 1
            } label: {
              Image(systemName: "rotate.left")
            }.accessibilityLabel("Rotate counterclockwise")
            Button {
              field(\.quarterTurns, [.quarterTurns]).wrappedValue += 1
            } label: {
              Image(systemName: "rotate.right")
            }.accessibilityLabel("Rotate clockwise")
            Button("180°") { field(\.quarterTurns, [.quarterTurns]).wrappedValue += 2 }
          }
          Toggle("Flip horizontally", isOn: field(\.flipHorizontal, [.flipHorizontal]))
          Toggle("Flip vertically", isOn: field(\.flipVertical, [.flipVertical]))
          LabeledContent(
            "Straighten", value: field(\.straighten, [.straighten]).wrappedValue,
            format: .number.precision(.fractionLength(1)))
          Slider(value: field(\.straighten, [.straighten]), in: -20...20, onEditingChanged: editGesture)
            .accessibilityLabel("Straighten angle")
        }
      }
      if model.inspectorTask == .resize || model.inspectorTask == .adjust {
        Section {
          DisclosureGroup("Borders, corners & shadow") {
            Toggle("Photo shadow", isOn: field(\.canvasStyle, [.canvasStyle]).shadow)
            adjustment("Border", field(\.canvasStyle, [.canvasStyle]).border, 0...0.2, neutral: 0)
            ColorPicker("Border colour", selection: colour(field(\.canvasStyle, [.canvasStyle]).borderColour))
            adjustment("Rounded corners", field(\.canvasStyle, [.canvasStyle]).cornerRadius, 0...0.5, neutral: 0)
          }
        }
      }
      if model.inspectorTask == .output {
        Section("Watermark") {
          Toggle("Add watermark", isOn: field(\.watermark.enabled, [.watermark_enabled]))
          if field(\.watermark.enabled, [.watermark_enabled]).wrappedValue {
            Picker("Content", selection: field(\.watermark.kind, [.watermark_kind])) {
              ForEach(WatermarkKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented)
            if field(\.watermark.kind, [.watermark_kind]).wrappedValue == .text {
              TextField("Watermark text", text: field(\.watermark.text, [.watermark_text]))
              Picker("Font", selection: field(\.watermark.fontName, [.watermark_fontName])) {
                Text("Helvetica Neue").tag("HelveticaNeue-Medium")
                Text("Avenir Next").tag("AvenirNext-Medium")
                Text("Times New Roman").tag("TimesNewRomanPSMT")
                Text("Menlo").tag("Menlo-Regular")
              }
              ColorPicker(
                "Colour", selection: colour(field(\.watermark.colour, [.watermark_colour])), supportsOpacity: true)
            } else {
              Button("Import watermark image…") { watermarkImport = true }
              if let url = field(\.watermark.imageURL, [.watermark_imageURL]).wrappedValue {
                Text(url.lastPathComponent).font(.caption).lineLimit(1)
              }
            }
            LabeledContent(
              "Relative width", value: field(\.watermark.relativeWidth, [.watermark_relativeWidth]).wrappedValue, format: .percent
            )
            Slider(
              value: field(\.watermark.relativeWidth, [.watermark_relativeWidth]), in: 0.02...0.8, onEditingChanged: editGesture
            ).accessibilityLabel("Watermark relative width")
            LabeledContent(
              "Opacity", value: field(\.watermark.opacity, [.watermark_opacity]).wrappedValue, format: .percent)
            Slider(value: field(\.watermark.opacity, [.watermark_opacity]), in: 0...1, onEditingChanged: editGesture)
              .accessibilityLabel("Watermark opacity")
            AnchorPicker(anchor: field(\.watermark.anchor, [.watermark_anchor]))
            LabeledContent(
              "Rotation", value: field(\.watermark.rotation, [.watermark_rotation]).wrappedValue, format: .number)
            Slider(value: field(\.watermark.rotation, [.watermark_rotation]), in: -180...180, onEditingChanged: editGesture)
              .accessibilityLabel("Watermark rotation")
            LabeledContent("Margin", value: field(\.watermark.margin, [.watermark_margin]).wrappedValue, format: .percent)
            Slider(value: field(\.watermark.margin, [.watermark_margin]), in: 0...0.2, onEditingChanged: editGesture)
              .accessibilityLabel("Watermark margin")
            TextField(
              "Horizontal offset (fraction)", value: field(\.watermark.offsetX, [.watermark_offsetX]), format: .number)
            TextField(
              "Vertical offset (fraction)", value: field(\.watermark.offsetY, [.watermark_offsetY]), format: .number)
            Toggle("Tile watermark", isOn: field(\.watermark.tiled, [.watermark_tiled]))
            Button("Save watermark preset") { model.saveWatermarkPreset() }
            if !model.watermarkPresets.isEmpty {
              Menu("Watermark presets") {
                ForEach(Array(model.watermarkPresets.enumerated()), id: \.offset) { index, w in
                  Button(w.kind == .text ? w.text : "Image watermark \(index + 1)") {
                    var value = model.controlConfiguration; value.watermark = w
                    model.applyChange(ConfigurationPatch(values: value, fields: Set(ConfigurationField.allCases.filter { $0.category == .watermark })))
                  }
                }
              }
            }
          }
        }
        Section("Format & Compression") {
          Picker("Format", selection: field(\.format, [.format])) {
            ForEach(ImageProcessor.outputFormats, id: \.self) {
              Text($0.rawValue.uppercased()).tag($0)
            }
          }
          if field(\.format, [.format]).wrappedValue.supportsQuality {
            Menu("Quality preset") {
              Button("Maximum Quality") { field(\.quality, [.quality]).wrappedValue = 0.98 }
              Button("Balanced") { field(\.quality, [.quality]).wrappedValue = 0.85 }
              Button("Smallest Practical") { field(\.quality, [.quality]).wrappedValue = 0.55 }
            }
            LabeledContent("Quality", value: field(\.quality, [.quality]).wrappedValue, format: .percent)
            Slider(value: field(\.quality, [.quality]), in: 0.1...1, onEditingChanged: editGesture)
              .accessibilityLabel("Output quality")
            Toggle(
              "Target file size",
              isOn: Binding(
                get: { field(\.targetBytes, [.targetBytes]).wrappedValue != nil },
                set: { field(\.targetBytes, [.targetBytes]).wrappedValue = $0 ? 500 * 1024 : nil }))
            if field(\.targetBytes, [.targetBytes]).wrappedValue != nil {
              LabeledContent("Maximum KB") {
                TextField(
                  "KB",
                  value: Binding(
                    get: { (field(\.targetBytes, [.targetBytes]).wrappedValue ?? 512000) / 1024 },
                    set: {
                      if $0 > 0 && $0 < 1_000_000 {
                        field(\.targetBytes, [.targetBytes]).wrappedValue = $0 * 1024
                      } else {
                        model.issues.append("Target size must be between 1 and 999,999 KB.")
                      }
                    }), format: .number
                ).labelsHidden()
              }
              LabeledContent(
                "Minimum quality", value: field(\.minimumQuality, [.minimumQuality]).wrappedValue, format: .percent)
              Slider(
                value: field(\.minimumQuality, [.minimumQuality]), in: 0.1...max(0.1, field(\.quality, [.quality]).wrappedValue),
                onEditingChanged: editGesture)
              Text("Unreachable targets fail clearly. Reduce dimensions if needed.").font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          if !field(\.format, [.format]).wrappedValue.preservesAlpha {
            Text("Transparency is flattened onto the chosen background, or white when transparent.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Picker("Colour", selection: field(\.colourPolicy, [.colourPolicy])) {
            Text("Convert to sRGB").tag(ColourPolicy.sRGB)
            Text("Preserve RGB profile").tag(ColourPolicy.preserve)
          }
          if field(\.privacyExport, [.privacyExport]).wrappedValue || !field(\.masks, [.masks]).wrappedValue.isEmpty {
            Text(
              "Privacy exports remove source metadata and embedded original thumbnails."
            ).font(.caption).foregroundStyle(.secondary)
          }
          Picker("Metadata", selection: field(\.metadata, [.metadata])) {
            Text("Remove supported metadata").tag(MetadataPolicy.remove)
            Text("Preserve supported metadata").tag(MetadataPolicy.preserve)
            Text("Remove location information").tag(MetadataPolicy.removeLocation)
          }.disabled(field(\.privacyExport, [.privacyExport]).wrappedValue || !field(\.masks, [.masks]).wrappedValue.isEmpty)
        }
        if !recipeEditing {
        Section("Export Plan") { ExportPlanView(model: model) }
        Section {
          DisclosureGroup(model.workflow == .batch ? "Naming & multiple export profiles" : "Output naming") {
            TextField("Naming template", text: $model.namingTemplate)
            Text("Tokens: {name}, {suffix}, {id}. Existing files receive numbered names.").font(
              .caption
            ).foregroundStyle(.secondary)
            Button("Save export settings as preset…") { savePreset = true }
            Text("Photo-specific privacy masks and annotations are not copied into new export presets. Use Copy Chosen Edits when you intend to transfer them.").font(.caption).foregroundStyle(.secondary)
            if model.workflow == .batch { ForEach(model.profiles) { profile in
              Toggle(
                profile.name,
                isOn: Binding(
                  get: { model.exportProfiles.contains(profile.id) },
                  set: {
                    if $0 {
                      model.exportProfiles.insert(profile.id)
                    } else {
                      model.exportProfiles.remove(profile.id)
                    }
                  }))
            }
            }
            Text(
              model.workflow == .batch
                ? "No checked profiles exports current settings. Multiple checked profiles create separate folders; individual framing remains applied."
                : "Editor exports one rendition using the current photo’s edits."
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
        }
      }
      if !recipeEditing && model.workflow == .photo {
        Section("Advanced photo settings") { overrideControls }
      }
    }.formStyle(.grouped).disabled(model.running)
      .fileImporter(isPresented: $watermarkImport, allowedContentTypes: ImageProcessor.importTypes)
    { result in
      switch result {
      case .success(let url): Task { await model.importWatermark(url) }
      case .failure(let error): model.issues.append(error.localizedDescription)
      }
    }
      .alert("Save preset", isPresented: $savePreset) {
        TextField("Preset name", text: $presetName)
        Button("Save") {
          model.saveProfile(name: presetName)
          presetName = ""
        }
        Button("Cancel", role: .cancel) {}
      }
  }
  @ViewBuilder var overrideControls: some View {
        if let asset = model.current {
          let fields = model.edits.overrides[asset.id]?.patch?.fields ?? []
          DisclosureGroup(fields.isEmpty ? "Using batch defaults" : "Photo overrides (\(Set(fields.map(\.category)).count) groups)") {
            Text(fields.isEmpty ? "This photo follows the shared batch settings." :
              "Overrides: " + Set(fields.map { $0.category.rawValue }).sorted().joined(separator: ", "))
              .font(.caption).foregroundStyle(.secondary)
            Menu("Reset Active Photo’s Overrides") {
              ForEach(EditCategory.allCases, id: \.self) { category in
                Button(category.rawValue + " → Inherit Batch") { model.resetCategories([category], ids: [asset.id]) }
              }
            }.disabled(fields.isEmpty)
          }
        }
  }
  func adjustment(
    _ title: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, neutral: Double,
    mixed: Bool = false
  ) -> some View {
    AdjustmentControl(title: title, value: binding, range: range, neutral: neutral,
      mixed: mixed, interaction: editGesture)
  }
  func setSize(_ w: Int, _ h: Int) {
    var c = config.wrappedValue
    c.width = w
    c.height = h
    model.applyChange(ConfigurationPatch(values: c, fields: [.width, .height]))
  }
  func applyAspect(_ ratio: Double) {
    var c = config.wrappedValue
    c.height = max(1, Int(Double(c.width) / ratio))
    c.crop.mode = .fill
    c.crop.aspectRatio = ratio
    model.applyChange(ConfigurationPatch(values: c, fields: [.height, .crop_mode, .crop_aspectRatio]))
  }
  func editGesture(_ started: Bool) { started ? model.beginInteraction() : model.endInteraction() }
  func colour(_ binding: Binding<RGBAColour>) -> Binding<Color> {
    Binding(
      get: {
        let c = binding.wrappedValue
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
      },
      set: { value in
        let c = value.resolve(in: environment)
        binding.wrappedValue = RGBAColour(
          Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity))
      })
  }
  func cropLabel(_ mode: CropMode) -> String {
    switch mode {
    case .fit: "Fit"
    case .fill: "Fill"
    case .stretch: "Stretch"
    case .canvas: "Canvas"
    case .manualCrop: "Manual Crop"
    case .preserveAspectRatio: "Preserve Aspect Ratio"
    }
  }
}
struct AnchorPicker: View {
  @Binding var anchor: WatermarkAnchor
  var body: some View {
    LabeledContent("Position") {
      LazyVGrid(
        columns: [GridItem(.fixed(44)), GridItem(.fixed(44)), GridItem(.fixed(44))], spacing: 8
      ) {
        ForEach(WatermarkAnchor.allCases, id: \.self) { position in
          Button {
            anchor = position
          } label: {
            Circle().fill(anchor == position ? Color.accentColor : Color.secondary.opacity(0.25))
              .frame(width: 12, height: 12).frame(width: 44, height: 44)
          }.buttonStyle(.plain).accessibilityLabel(
            [
              "Top left", "Top centre", "Top right", "Middle left", "Centre", "Middle right",
              "Bottom left", "Bottom centre", "Bottom right",
            ][position.rawValue]
          ).accessibilityAddTraits(anchor == position ? .isSelected : [])
        }
      }.padding(5).background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

/// Numeric entry and dragging share the same scoped field binding. Neither copies a photo's
/// complete configuration into the other selected photos.
private struct AdjustmentControl: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let neutral: Double
  let mixed: Bool
  let interaction: (Bool) -> Void

  private var boundedValue: Binding<Double> {
    Binding(get: { value }, set: { candidate in
      guard candidate.isFinite else { return }
      value = min(range.upperBound, max(range.lowerBound, candidate))
    })
  }
  @Environment(\.dynamicTypeSize) private var typeSize
  var titleLabel: some View {
    HStack {
      Text(title)
      if mixed {
        Text("Mixed").font(.caption).foregroundStyle(.secondary)
          .accessibilityLabel("Different values in the selected photos")
      }
    }
  }
  var valueField: some View {
    TextField(title, value: boundedValue, format: .number.precision(.fractionLength(2)))
      .labelsHidden().multilineTextAlignment(.trailing).monospacedDigit()
      .accessibilityLabel("\(title) value")
      .help("Enter a value from \(range.lowerBound) to \(range.upperBound).")
  }
  var resetButton: some View {
    Button { boundedValue.wrappedValue = neutral } label: {
      Image(systemName: "arrow.counterclockwise")
    }.buttonStyle(.borderless).comfortableHitTarget()
      .disabled(!mixed && value == neutral)
      .accessibilityLabel("Reset \(title)")
      .help("Reset \(title) to its neutral value for the labelled targets.")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if typeSize.isAccessibilitySize {
        titleLabel
        HStack {
          valueField.textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
          resetButton
        }
      } else {
        HStack {
          titleLabel
          Spacer()
          valueField.frame(width: 64)
          resetButton
        }
      }
      Slider(value: boundedValue, in: range, onEditingChanged: interaction)
        .labelsHidden().frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityValue(mixed ? "Mixed values; representative \(value)" : "\(value), neutral \(neutral)")
    }
  }
}
