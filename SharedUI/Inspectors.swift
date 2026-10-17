import FramepebbleCore
import SwiftUI

enum EditorDestination { case framing, collage, overlays, projects }

/// Presentation metadata for the existing field-specific adjustment controls.
/// Choosing a parameter never changes its value or the operation's scope.
enum AdjustmentParameter: String, CaseIterable {
  case exposure = "Exposure", brightness = "Brightness", contrast = "Contrast"
  case highlights = "Highlights", shadows = "Shadows", saturation = "Saturation", warmth = "Warmth"
  case vibrance = "Vibrance", tint = "Tint"
  static let light: [Self] = [.exposure, .brightness, .contrast, .highlights, .shadows]
  static let colour: [Self] = [.saturation, .vibrance, .warmth, .tint]
  var keyPath: WritableKeyPath<ProcessingConfiguration, Double> {
    switch self {
    case .exposure: \.adjustments.exposure
    case .brightness: \.adjustments.brightness
    case .contrast: \.adjustments.contrast
    case .highlights: \.adjustments.highlights
    case .shadows: \.adjustments.shadows
    case .vibrance: \.adjustments.vibrance
    case .tint: \.adjustments.tint
    case .saturation: \.adjustments.saturation
    case .warmth: \.adjustments.warmth
    }
  }
  var field: ConfigurationField {
    switch self {
    case .exposure: .adjustments_exposure
    case .brightness: .adjustments_brightness
    case .contrast: .adjustments_contrast
    case .highlights: .adjustments_highlights
    case .shadows: .adjustments_shadows
    case .vibrance: .adjustments_vibrance
    case .tint: .adjustments_tint
    case .saturation: .adjustments_saturation
    case .warmth: .adjustments_warmth
    }
  }
  var range: ClosedRange<Double> {
    switch self {
    case .exposure: -2...2
    case .brightness: -0.5...0.5
    case .contrast: 0.5...1.5
    case .highlights, .shadows: 0...1
    case .vibrance, .tint: -1...1
    case .saturation: 0...2
    case .warmth: -1...1
    }
  }
  var neutral: Double { self == .contrast || self == .highlights || self == .saturation ? 1 : 0 }
}

struct SettingsEditor: View {
  @Bindable var model: Workspace
  var focused = false
  var recipeEditing = false
  var task: InspectorTask? = nil
  var showsContext = true
  var showsPreview = false
  var compactPanel = false
  var focusedAdjustment = false
  var adjustmentDetails: (() -> Void)? = nil
  var dismissAdjustment: (() -> Void)? = nil
  var horizontalAdjustment = false
  var activeTask: InspectorTask { task ?? model.inspectorTask }
  var openEditor: ((EditorDestination) -> Void)? = nil
  @State private var looksPresented = false
  @State private var watermarkImport = false
  @State private var watermarkDesignTargets: [UUID]?
  @State private var savePreset = false
  @State private var presetName = ""
  @State private var parameter: AdjustmentParameter = .exposure
  @State private var lightExpanded = true
  @State private var colourExpanded = false
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
    case .projects: model.presentWorkspaceSwitcher()
    }
  }
  var config: Binding<ProcessingConfiguration> {
    Binding(get: { model.controlConfiguration }, set: { model.controlConfiguration = $0 })
  }
  func field<T>(_ key: WritableKeyPath<ProcessingConfiguration, T>, _ fields: Set<ConfigurationField>) -> Binding<T> {
    Binding(get: { model.controlConfiguration[keyPath: key] }, set: { model.updateField(key, value: $0, fields: fields) })
  }
  var body: some View {
    Group {
      if activeTask == .filters { PhotoLooksPicker(model: model, scrollable: true).padding(12) }
      else if focusedAdjustment && activeTask == .adjust && !typeSize.isAccessibilitySize {
        focusedAdjustmentControls.padding(.horizontal, 12).padding(.bottom, 8)
      } else if compactPanel && (activeTask == .adjust || activeTask == .watermark || activeTask == .resize) {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            if showsContext && !recipeEditing {
              if model.workflow == .photo { InspectorHeading(title: activeTask.rawValue, subtitle: "This photo"); overrideControls }
              else { OperationContextHeader(model: model, allowsChangingInputs: task == nil) }
              Divider()
            }
            if model.workflow == .batch && !model.mixedFields.isEmpty {
              DisclosureGroup("Mixed values") {
                Text(model.mixedFields.map(\.displayName).sorted().joined(separator: ", ")).font(.caption)
                Text("Each change affects only that property on the operation photos.").font(.caption).foregroundStyle(.secondary)
              }
            }
            if activeTask == .adjust {
              if model.workflow == .batch && !showsContext { InspectorHeading(title: "Adjust") }
              adjustmentControls; canvasAppearanceControls
            }
            else if activeTask == .watermark { watermarkControls }
            else { compactResizeControls }
          }.padding(12)
        }
      } else {
        #if os(macOS)
        propertyForm.formStyle(.grouped)
        #else
        propertyForm
        #endif
      }
    }
    .disabled(model.running)
      .fileImporter(isPresented: $watermarkImport, allowedContentTypes: ImageProcessor.importTypes)
    { result in
      switch result {
      case .success(let url): Task { await model.importWatermark(url) }
      case .failure(let error): if !error.isUserCancellation { model.issues.append(error.localizedDescription) }
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
  var quickFixMenu: some View {
    Menu("Auto Corrections", systemImage: "chevron.down") {
      ForEach([QuickFix.lighting, .colour, .straighten], id: \.self) { fix in Button(fix.rawValue) { model.quickFix(fix) } }
    }.disabled(model.targets.isEmpty || model.quickFixRunning)
  }
  @ViewBuilder var quickFixProgress: some View {
    if model.quickFixRunning {
      ProgressView("Analysing photos…", value: Double(model.quickFixCompleted), total: Double(max(1, model.quickFixTotal)))
      Button("Cancel Corrections") { model.quickFixTask?.cancel() }
    }
  }
  func parameterControl(_ parameter: AdjustmentParameter) -> some View {
    adjustment(parameter.rawValue, field(parameter.keyPath, [parameter.field]), parameter.range,
      neutral: parameter.neutral, mixed: model.mixedFields.contains(parameter.field))
  }
  var focusedAdjustmentControls: some View {
    let layout = horizontalAdjustment ? AnyLayout(HStackLayout(alignment: .center, spacing: 8)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
    return VStack(alignment: .leading, spacing: 0) {
    layout {
      AdjustmentControl(title: parameter.rawValue, value: field(parameter.keyPath, [parameter.field]),
        range: parameter.range, neutral: parameter.neutral, mixed: model.mixedFields.contains(parameter.field),
        interaction: editGesture, parameterSelection: $parameter, interactionAvailable: { !model.interactionInProgress }, targetIDs: model.targets.map(\.id))
      HStack {
        Toggle(isOn: Binding(get: { model.controlConfiguration.autoEnhance?.enabled == true }, set: { model.setAutoEnhance($0) })) {
          Label("Auto", systemImage: "wand.and.stars")
        }.toggleStyle(.button).disabled(model.quickFixRunning)
          .comfortableHitTarget().accessibilityLabel("Auto Enhance")
          .accessibilityValue(model.controlConfiguration.autoEnhance?.enabled == true ? "On" : "Off")
          .help("Toggle automatic enhancement; other edits stay unchanged")
        Spacer()
        if let adjustmentDetails {
          Button(action: adjustmentDetails) {
            if horizontalAdjustment { Image(systemName: "list.bullet") }
            else { Label("All Adjustments", systemImage: "list.bullet") }
          }
            .comfortableHitTarget().foregroundStyle(.primary).accessibilityLabel("All Adjustments")
        }
        if let dismissAdjustment {
          Button(action: dismissAdjustment) { Image(systemName: "xmark") }
            .comfortableHitTarget().foregroundStyle(.primary).accessibilityLabel("Hide adjustment controls")
        }
      }.fixedSize(horizontal: true, vertical: false)
    }
      quickFixProgress
    }
  }
  @ViewBuilder var adjustmentControls: some View {
    Button("Open Filters", systemImage: "camera.filters") { model.choosePhotoInspector(.filters) }
    Toggle("Auto Enhance", isOn: Binding(get: { model.controlConfiguration.autoEnhance?.enabled == true }, set: { model.setAutoEnhance($0) })).disabled(model.quickFixRunning)
    quickFixMenu
    quickFixProgress
    DisclosureGroup("Light", isExpanded: $lightExpanded) {
      VStack(spacing: 8) { ForEach(AdjustmentParameter.light, id: \.self) { parameterControl($0) } }.padding(.top, 6)
    }
    DisclosureGroup("Colour", isExpanded: $colourExpanded) {
      VStack(spacing: 8) { ForEach(AdjustmentParameter.colour, id: \.self) { parameterControl($0) } }.padding(.top, 6)
    }
    ColourMixControls(model: model)
    Button("Reset Light & Colour") {
      var value = model.controlConfiguration; value.adjustments = PhotoAdjustments()
      model.applyChange(ConfigurationPatch(values: value, fields: Set(ConfigurationField.allCases.filter { $0.rawValue.hasPrefix("adjustments.") })))
    }
  }
  var propertyForm: some View {
    Form {
      if showsContext && !recipeEditing {
        Section {
          OperationContextHeader(model: model, allowsChangingInputs: task == nil)
          if model.workflow == .photo { overrideControls }
          else if !model.mixedFields.isEmpty {
            DisclosureGroup("Mixed values") {
              Text(model.mixedFields.map(\.displayName).sorted().joined(separator: ", ")).font(.caption)
              Text("Controls show the first photo. Each change affects only that property on the labelled photos.").font(.caption)
            }
          }
        }
      }
      if recipeEditing { Section { InspectorToolPicker(model: model, recipeEditing: true) } }
      if model.workflow == .batch, model.conversionInputIDs != nil, activeTask == .output || activeTask == .resize {
        Section("Size") {
          LabeledContent("Dimensions", value: model.conversionResizingEnabled ? "Custom resize" : "Source dimensions")
          Toggle("Also Resize", isOn: $model.conversionResizingEnabled)
            .onChange(of: model.conversionResizingEnabled) { _, enabled in if enabled { model.inspectorTask = .resize }; model.persist() }
          Text("Existing crops and visual edits are retained.").font(.caption).foregroundStyle(.secondary)
        }
      }
      #if os(iOS)
      if showsPreview, let asset = model.current {
        Section { FramingSurface(model: model, asset: asset, interactive: false, maximum: 800).frame(height: 150) }
      }
      #endif
      if activeTask == .adjust {
        Section {
          adjustmentControls
        } header: {
          if showsContext || recipeEditing { Text("Adjust") }
        }
      }
      if activeTask == .creative {
        Section("Photo Tools") {
          Button("Make a Collage…") { open(.collage) }.disabled(model.workspaceAssets.isEmpty)
          Button("Annotations & Privacy…") { open(.overlays) }.disabled(model.current == nil)
          Button("Back to Workspace") { model.showLibrary() }
          Text("Opaque covers and cropping provide stronger concealment than blur or pixelation.").font(.caption).foregroundStyle(.secondary)
        }
      }
      if activeTask == .output {
        if model.conversionInputIDs == nil {
          Section { DisclosureGroup("Resize & Canvas") { resizeControls } }
        } else if model.conversionResizingEnabled {
          Section("Resize & Canvas") { resizeControls }
        }
      }
      if activeTask == .resize && (model.conversionInputIDs == nil || model.conversionResizingEnabled || recipeEditing) {
        Section("Resize & Canvas") { resizeControls }
        Section("Convert") {
          Picker(model.mixedFields.contains(.format) ? "Output format · Mixed" : "Output format", selection: field(\.format, [.format])) {
            ForEach(ImageProcessor.outputFormats, id: \.self) {
              Text($0.rawValue.uppercased()).tag($0)
            }
          }
          Button("Advanced export settings") { model.inspectorTask = .output }
        }
      }
      if activeTask == .resize {
        Section("Framing") { framingControls }
        Section("Rotate & Flip") { rotationControls }
      }
      if activeTask == .resize || activeTask == .adjust {
        Section {
          canvasAppearanceControls
        }
      }
      if activeTask == .watermark { Section { watermarkControls } }
      if activeTask == .output {
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
            LabeledContent("Quality", value: field(\.quality, [.quality]).wrappedValue, format: .percent.precision(.fractionLength(0)))
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
                "Minimum quality", value: field(\.minimumQuality, [.minimumQuality]).wrappedValue, format: .percent.precision(.fractionLength(0)))
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
            Text("Remove metadata").tag(MetadataPolicy.remove)
            Text("Keep supported metadata").tag(MetadataPolicy.preserve)
            Text("Remove location").tag(MetadataPolicy.removeLocation)
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

    }
    #if os(macOS)
    .formStyle(.columns).padding(12)
    #else
    .formStyle(.grouped)
    #endif
  }
  var canvasAppearanceControls: some View {
          DisclosureGroup("Borders, corners & shadow") {
            Toggle("Photo shadow", isOn: field(\.canvasStyle, [.canvasStyle]).shadow)
            adjustment("Border", field(\.canvasStyle, [.canvasStyle]).border, 0...0.2, neutral: 0)
            ColorPicker("Border colour", selection: colour(field(\.canvasStyle, [.canvasStyle]).borderColour))
            adjustment("Rounded corners", field(\.canvasStyle, [.canvasStyle]).cornerRadius, 0...0.5, neutral: 0)
          }
  }
  @ViewBuilder var watermarkControls: some View {
    Button("Watermark Designs…", systemImage: "square.stack.3d.up") {
      watermarkDesignTargets = model.targets.map(\.id)
    }
    .sheet(isPresented: Binding(get: { watermarkDesignTargets != nil }, set: { if !$0 { watermarkDesignTargets = nil } })) {
      WatermarkDesignsView(model: model, targetIDs: watermarkDesignTargets ?? [])
    }

    if !model.controlConfiguration.watermark.enabled {
      Button("Add Watermark", systemImage: "plus") {
        field(\.watermark.enabled, [.watermark_enabled]).wrappedValue = true
      }.comfortableHitTarget()
    } else {
      HStack {
        Text("Watermark").font(.headline)
        Spacer()
        Button(role: .destructive) {
          field(\.watermark.enabled, [.watermark_enabled]).wrappedValue = false
        } label: { Label("Remove", systemImage: "trash") }
          .comfortableHitTarget().accessibilityLabel("Remove Watermark")
          .accessibilityHint("Undo restores the watermark and its settings.")
      }
      Picker("Content", selection: field(\.watermark.kind, [.watermark_kind])) {
        ForEach(WatermarkKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
      }.pickerStyle(.segmented)
      if model.controlConfiguration.watermark.kind == .text {
        TextField("Watermark text", text: field(\.watermark.text, [.watermark_text]))
          .textFieldStyle(.roundedBorder).accessibilityLabel("Watermark text")
        LabeledContent("Font") {
          Picker("Font", selection: field(\.watermark.fontName, [.watermark_fontName])) {
            Text("Helvetica Neue").tag("HelveticaNeue-Medium")
            Text("Avenir Next").tag("AvenirNext-Medium")
            Text("Times New Roman").tag("TimesNewRomanPSMT")
            Text("Menlo").tag("Menlo-Regular")
          }.labelsHidden()
        }
        ColorPicker("Colour", selection: colour(field(\.watermark.colour, [.watermark_colour])), supportsOpacity: true)
      } else {
        Button("Import watermark image…") { watermarkImport = true }
        if let url = model.controlConfiguration.watermark.imageURL { Text(url.lastPathComponent).font(.caption).lineLimit(1) }
      }
      InspectorSlider(title: "Size", value: field(\.watermark.relativeWidth, [.watermark_relativeWidth]), range: 0.02...0.8, percentage: true, interaction: editGesture)
      InspectorSlider(title: "Opacity", value: field(\.watermark.opacity, [.watermark_opacity]), range: 0...1, percentage: true, interaction: editGesture)
      DisclosureGroup("Placement & pattern") {
        VStack(alignment: .leading, spacing: 10) {
          Text("Drag on the photo to position. Use handles to resize or rotate.").font(.caption).foregroundStyle(.secondary)
          AnchorPicker(anchor: field(\.watermark.anchor, [.watermark_anchor]))
          InspectorSlider(title: "Rotation", value: field(\.watermark.rotation, [.watermark_rotation]), range: -180...180, interaction: editGesture)
          InspectorSlider(title: "Margin", value: field(\.watermark.margin, [.watermark_margin]), range: 0...0.2, percentage: true, interaction: editGesture)
          TextField("Horizontal offset", value: field(\.watermark.offsetX, [.watermark_offsetX]), format: .percent.precision(.fractionLength(0)))
          TextField("Vertical offset", value: field(\.watermark.offsetY, [.watermark_offsetY]), format: .percent.precision(.fractionLength(0)))
          Toggle("Tile watermark", isOn: field(\.watermark.tiled, [.watermark_tiled]))
        }.padding(.top, 8)
      }
      DisclosureGroup("Presets") {
        Button("Save watermark preset") { model.saveWatermarkPreset() }
        ForEach(Array(model.watermarkPresets.enumerated()), id: \.offset) { index, w in
          Button(w.kind == .text ? w.text : "Image watermark \(index + 1)") {
            var value = model.controlConfiguration; value.watermark = w
            model.applyChange(ConfigurationPatch(values: value, fields: Set(ConfigurationField.allCases.filter { $0.category == .watermark })))
          }
        }
      }
    }
  }
  @ViewBuilder var framingControls: some View {
          Menu("Aspect ratio") {
            Button("Square") { applyAspect(1) }
            Button("4:3") { applyAspect(4.0 / 3) }
            Button("3:2") { applyAspect(1.5) }
            Button("16:9") { applyAspect(16.0 / 9) }
            Button("4:5") { applyAspect(0.8) }
          }
          if !recipeEditing {
          VStack(alignment: .leading, spacing: 8) {
            Button("Smart Auto-frame") { model.autoFrame(.smart) }
            Button("Keep Subjects") { model.autoFrame(.keepSubjects) }
          }.disabled(model.analysing || model.targets.isEmpty)
          Text("Uses on-device Vision. Manual framing is preserved; review flagged proposals.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Refine selected image", systemImage: "crop") { open(.framing) }.disabled(
            model.current == nil)
          }
  }
  @ViewBuilder var rotationControls: some View {
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
            "Straighten (°)", value: field(\.straighten, [.straighten]).wrappedValue,
            format: .number.precision(.fractionLength(1)))
          Slider(value: field(\.straighten, [.straighten]), in: -20...20, onEditingChanged: editGesture)
            .accessibilityLabel("Straighten angle")
  }
  var compactResizeControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.conversionInputIDs != nil && !recipeEditing {
        Toggle("Also Resize", isOn: $model.conversionResizingEnabled)
          .onChange(of: model.conversionResizingEnabled) { _, _ in model.persist() }
        Text("Existing crops and visual edits are retained.").font(.caption).foregroundStyle(.secondary)
      }
      if model.conversionInputIDs == nil || model.conversionResizingEnabled || recipeEditing {
        InspectorHeading(title: "Resize & Canvas")
        resizeControls
        Button("Fit for Sharing") { model.quickFix(.sharing) }.disabled(model.quickFixRunning)
        Divider()
        DisclosureGroup("Framing") { framingControls.padding(.top, 8) }
        DisclosureGroup("Rotate & Flip") { rotationControls.padding(.top, 8) }
        canvasAppearanceControls
      }
      Divider()
      Picker("Format", selection: field(\.format, [.format])) {
        ForEach(ImageProcessor.outputFormats, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
      }
      Button("Export settings…") { model.inspectorTask = .output }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .pickerStyle(.menu)
  }
  @ViewBuilder var resizeControls: some View {
          Menu("Choose a size preset") {
            ForEach([512, 1024, 2048, 1080], id: \.self) { edge in
              Button("\(edge) × \(edge) · Fit") {
                var c = config.wrappedValue
                c.width = edge
                c.height = edge; c.crop.mode = .fit; c.nativeOutputSizing = false
                model.applyChange(ConfigurationPatch(values: c, fields: [.width, .height, .crop_mode, .nativeOutputSizing]))
              }
            }
            Button("1080 × 1350 · Fit") { setSize(1080, 1350) }
            Button("1920 × 1080 · Fit") { setSize(1920, 1080) }
            Button("3840 × 2160 · Fit") { setSize(3840, 2160) }
          }
          Picker(model.mixedFields.contains(.crop_mode) ? "Fit mode · Mixed" : "Sizing", selection: field(\.crop.mode, [.crop_mode])) {
            ForEach(CropMode.allCases, id: \.self) { Text(cropLabel($0)).tag($0) }
          }
          Text(model.mixedFields.contains(.crop_mode) ? "These photos use different sizing modes. Changing Sizing replaces only that property." : sizingConsequence(config.wrappedValue.crop.mode)).font(.caption).foregroundStyle(.secondary)
          if config.wrappedValue.crop.mode == .preserveAspectRatio {
            Picker("Resize by", selection: field(\.resizeBasis, [.resizeBasis])) {
              ForEach(ResizeBasis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            if config.wrappedValue.resizeBasis == .percentage {
              LabeledContent("Scale (%)") {
                TextField("Percentage", value: field(\.percentage, [.percentage]), format: .number)
                  .labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90)
              }
              if config.wrappedValue.percentage == 100 {
                Text("Original dimensions · no padding").font(.caption).foregroundStyle(.secondary)
              }
            } else {
              LabeledContent(config.wrappedValue.resizeBasis == .height ? "Height (px)" : "Width / edge (px)") {
                if config.wrappedValue.resizeBasis == .height {
                  TextField("Height", value: field(\.height, [.height]), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90)
                } else {
                  TextField("Width", value: field(\.width, [.width]), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90)
                }
              }
            }
          } else {
            LabeledContent(model.mixedFields.contains(.width) ? "Width · Mixed (px)" : "Width (px)") {
              TextField("Width", value: field(\.width, [.width]), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90)
            }
            LabeledContent(model.mixedFields.contains(.height) ? "Height · Mixed (px)" : "Height (px)") {
              TextField("Height", value: field(\.height, [.height]), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90)
            }
          }
          Toggle("Prevent upscaling", isOn: field(\.preventUpscaling, [.preventUpscaling]))
          if field(\.crop.mode, [.crop_mode]).wrappedValue == .canvas || field(\.crop.mode, [.crop_mode]).wrappedValue == .fit {
            ColorPicker("Background", selection: colour(field(\.background, [.background])), supportsOpacity: true)
            if field(\.crop.mode, [.crop_mode]).wrappedValue == .canvas {
              AnchorPicker(anchor: field(\.canvasAlignment, [.canvasAlignment]))
            }
          }
  }
  @ViewBuilder var overrideControls: some View {
        if let asset = model.current {
          let fields = model.edits.overrides[asset.id]?.patch?.fields ?? []
          DisclosureGroup(fields.isEmpty ? "Uses batch settings" : "\(fields.count) photo-specific \(fields.count == 1 ? "edit" : "edits")") {
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
      mixed: mixed, interaction: editGesture, interactionAvailable: { !model.interactionInProgress }, targetIDs: model.targets.map(\.id))
  }
  func setSize(_ w: Int, _ h: Int) {
    var c = config.wrappedValue
    c.width = w
    c.height = h; c.crop.mode = .fit; c.nativeOutputSizing = false
    model.applyChange(ConfigurationPatch(values: c, fields: [.width, .height, .crop_mode, .nativeOutputSizing]))
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
  func sizingConsequence(_ mode: CropMode) -> String {
    switch mode {
    case .fit: "Fits the complete photo inside the output; unused space uses the background colour."
    case .fill: "Crops to match the output proportions; framing controls choose the visible area."
    case .canvas: "Fits the complete photo on the canvas; Position controls its placement."
    case .stretch: "Changes the photo’s proportions to match the output dimensions."
    case .manualCrop: "Uses manual framing to crop the photo to the output dimensions."
    case .preserveAspectRatio: "Resizes proportionally without adding canvas padding."
    }
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
  var cellSize: CGFloat {
    #if os(macOS)
    24
    #else
    44
    #endif
  }
  var body: some View {
    LabeledContent("Position") {
      LazyVGrid(
        columns: [GridItem(.fixed(cellSize)), GridItem(.fixed(cellSize)), GridItem(.fixed(cellSize))], spacing: 4
      ) {
        ForEach(WatermarkAnchor.allCases, id: \.self) { position in
          Button {
            anchor = position
          } label: {
            Circle().fill(anchor == position ? Color.accentColor : Color.secondary.opacity(0.25))
              .frame(width: 10, height: 10).frame(width: cellSize, height: cellSize)
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
/// Display units only: persisted Core Image parameters retain their established meaning.
struct AdjustmentDisplayScale {
  var multiplier: Double = 1
  var offset: Double = 0
  var unit = ""
  var step: Double = 0.01
  func display(_ value: Double) -> Double { value * multiplier + offset }
  func stored(_ value: Double) -> Double { (value - offset) / multiplier }
  static func forTitle(_ title: String) -> Self {
    switch title {
    case "Exposure": return Self(unit: "EV")
    case "Brightness": return Self(multiplier: 200, step: 1)
    case "Contrast": return Self(multiplier: 200, offset: -200, step: 1)
    case "Saturation": return Self(multiplier: 100, offset: -100, step: 1)
    case "Highlights": return Self(multiplier: 100, offset: -100, step: 1)
    case "Shadows", "Warmth", "Tint", "Vibrance": return Self(multiplier: 100, step: 1)
    default: return Self(step: title.contains("(°)") || title.contains("(%)") ? 1 : 0.01)
    }
  }
}

struct AdjustmentControl: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let neutral: Double
  let mixed: Bool
  let interaction: (Bool) -> Void
  var parameterSelection: Binding<AdjustmentParameter>? = nil
  var interactionAvailable: () -> Bool = { false }
  var targetIDs: [UUID] = []
  @FocusState private var valueFocused: Bool
  @State private var ownsNumericInteraction = false
  @State private var ownsSliderInteraction = false
  func finishNumericInteraction() {
    if ownsNumericInteraction { ownsNumericInteraction = false; interaction(false) }
  }

  private var boundedValue: Binding<Double> {
    Binding(get: { value }, set: { candidate in
      guard candidate.isFinite else { return }
      value = min(range.upperBound, max(range.lowerBound, candidate))
    })
  }
  @Environment(\.dynamicTypeSize) private var typeSize
  var titleLabel: some View {
    HStack {
      if let parameterSelection {
        Menu {
          ForEach(AdjustmentParameter.allCases, id: \.self) { parameter in
            Button { parameterSelection.wrappedValue = parameter } label: {
              if parameter == parameterSelection.wrappedValue { Label(parameter.rawValue, systemImage: "checkmark") }
              else { Text(parameter.rawValue) }
            }
          }
        } label: {
          HStack(spacing: 4) {
            Text(parameterSelection.wrappedValue.rawValue).font(.subheadline).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2)
          }.fixedSize(horizontal: true, vertical: false)
        }.menuIndicator(.hidden).accessibilityLabel("Adjustment: " + parameterSelection.wrappedValue.rawValue)
          .accessibilityIdentifier("editor.adjustmentParameter")
      } else { Text(title) }
      if mixed {
        Text("Mixed").font(.caption).foregroundStyle(.secondary)
          .accessibilityLabel("Different values in the selected photos")
      }
    }
  }
  var displayScale: AdjustmentDisplayScale { .forTitle(title) }
  var displayRange: ClosedRange<Double> { displayScale.display(range.lowerBound)...displayScale.display(range.upperBound) }
  var displayValue: Binding<Double> {
    Binding(get: { displayScale.display(value) }, set: { boundedValue.wrappedValue = displayScale.stored($0) })
  }
  var valueField: some View {
    HStack(spacing: 2) {
    TextField(title, value: displayValue, format: .number.precision(.fractionLength(0...2)))
      .labelsHidden().multilineTextAlignment(.trailing).monospacedDigit().textFieldStyle(.roundedBorder)
      .modifier(SignedNumericEntry())
      .focused($valueFocused)
      .onSubmit { valueFocused = false }
      .onChange(of: valueFocused) { _, focused in
        if focused && interactionAvailable() { ownsNumericInteraction = true; interaction(true) }
        else if !focused { finishNumericInteraction() }
      }
      .onChange(of: title) { _, _ in valueFocused = false; finishNumericInteraction() }
      .onChange(of: targetIDs) { _, _ in valueFocused = false; finishNumericInteraction() }
      .onDisappear { finishNumericInteraction(); if ownsSliderInteraction { ownsSliderInteraction = false; interaction(false) } }
      .accessibilityLabel("\(title) value")
      .help("Enter a value from \(displayRange.lowerBound) to \(displayRange.upperBound) \(displayScale.unit).")
    if !displayScale.unit.isEmpty { Text(displayScale.unit).font(.caption).foregroundStyle(.secondary) }
    }
  }
  var resetButton: some View {
    Button { valueFocused = false; finishNumericInteraction(); boundedValue.wrappedValue = neutral } label: {
      Image(systemName: "arrow.counterclockwise")
    }.buttonStyle(.borderless).comfortableHitTarget().foregroundStyle(.primary)
      .disabled(!mixed && value == neutral)
      .accessibilityLabel("Reset \(title)")
      .help("Reset \(title) to its neutral value for the labelled targets.")
  }
  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      VStack(alignment: .leading, spacing: 2) {
        if typeSize.isAccessibilitySize {
          titleLabel
          valueField.textFieldStyle(.roundedBorder)
        } else {
          HStack { titleLabel; Spacer(); valueField.frame(width: 64) }
        }
        Slider(value: displayValue, in: displayRange, step: displayScale.step, onEditingChanged: { editing in
          if editing {
            valueFocused = false; finishNumericInteraction()
            if interactionAvailable() { ownsSliderInteraction = true; interaction(true) }
          } else if ownsSliderInteraction { ownsSliderInteraction = false; interaction(false) }
        })
          .labelsHidden().frame(maxWidth: .infinity)
          .accessibilityLabel(title)
          .accessibilityValue(mixed ? "Mixed values; representative \(displayScale.display(value))" : "\(displayScale.display(value)) \(displayScale.unit), neutral \(displayScale.display(neutral))")
      }
      resetButton
    }.accessibilityElement(children: .contain)
  }
}

/// Candidate tiles and the canvas use the shared versioned renderer.
struct PhotoLooksPicker: View {
  @Bindable var model: Workspace
  var scrollable = false
  var compact = false
  var replacesToolbox = false
  @Environment(\.horizontalSizeClass) private var sizeClass
  var tileWidth: CGFloat { sizeClass == .compact ? 76 : 112 }
  @FocusState private var focusedPreset: String?
  @FocusState private var comparisonFocused: Bool
  @FocusState private var intensityFocused: Bool
  @State private var ownsIntensityInteraction = false
  @State private var ownsIntensitySlider = false
  func finishIntensityEntry() {
    if ownsIntensityInteraction { ownsIntensityInteraction = false; model.endInteraction() }
  }
  @State private var hoveredPreset: String?
  @State private var unsupportedSource = false
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var collection: FilterCollection = .essentials
  @State private var previews: [String: CGImage] = [:]
  @State private var previewConfigurations: [String: ProcessingConfiguration] = [:]
  @State private var previewBase: PreviewInput?
  @State private var browserContentHeight: CGFloat = 520
  @State private var failure: String?
  @State private var generation = 0
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var scenePhase
  #if os(macOS)
  @Environment(\.controlActiveState) private var activeState
  #endif
  var sample: SourceAsset? { model.exportPreviewAsset }
  var current: FilterEdit? { model.controlConfiguration.filterEdit }
  var selected: CreativePreset? { current.flatMap { e in e.presetID.flatMap { FilterCatalog.preset($0,version:e.recipeVersion) } } }
  var hasCreativeFilter: Bool {
    model.targets.contains { source in
      let configuration = model.configuration(for: source)
      return configuration.filterEdit?.presetID != nil || configuration.look != nil
    }
  }
  var mixedFilters: Bool {
    let edits=model.targets.map { model.configuration(for:$0).filterEdit }
    guard let first=edits.first else { return false }
    return edits.dropFirst().contains { $0?.presetID != first?.presetID || $0?.recipeVersion != first?.recipeVersion || $0?.intensity != first?.intensity }
  }
  var candidates: [CreativePreset] { FilterCatalog.presets.filter { $0.collection == collection } }
  struct PreviewInput: Equatable {
    var source: SourceAsset?; var configuration: ProcessingConfiguration
    var collection: FilterCollection; var generation: Int; var privateMode: Bool; var maximum: Int
  }
  var input: PreviewInput { PreviewInput(source:sample,configuration:sample.map { model.configuration(for:$0) } ?? model.controlConfiguration,collection:collection,generation:generation,privateMode:model.privateEditing,maximum:compact && sizeClass == .compact ? 160 : 280) }
  var body: some View {
    VStack(alignment:.leading,spacing:compact ? 6 : 12) {
      if replacesToolbox && !compact {
        Button("Back to Tools", systemImage: "chevron.left") { model.choosePhotoInspector(.adjust) }
      }
      if scrollable {
        ScrollView { presetBrowser.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { browserContentHeight = $0 } }
          .frame(maxHeight: min(560, max(120, browserContentHeight)))
      } else { presetBrowser }
      if let legacy=model.controlConfiguration.look { Text("Saved legacy filter: " + legacy.title).font(.caption) }
      if let selected {
        if !compact { Text(selected.name).font(.headline); Text(selected.description).font(.caption).foregroundStyle(.secondary) }
      } else if current?.presetID != nil { Text("Filter unavailable. Select Original to recover.").foregroundStyle(.orange) }
      if mixedFilters { Text("Mixed filters or intensity. Changes affect only creative filter properties.").font(.caption).foregroundStyle(.secondary) }
      if current?.presetID != nil { intensityControls }
      if compact {
        HStack {
          Toggle("Auto Enhance",isOn:Binding(get:{model.controlConfiguration.autoEnhance?.enabled == true},set:{model.setAutoEnhance($0)})).font(.caption).disabled(model.quickFixRunning)
          Spacer()
          if hasCreativeFilter { Button("Remove Filter") { intensityFocused = false; finishIntensityEntry(); model.selectCreativeFilter(nil) }.font(.caption) }
        }
      } else if hasCreativeFilter { Button("Remove Filter") { intensityFocused = false; finishIntensityEntry(); model.selectCreativeFilter(nil) } }
      if model.quickFixRunning { ProgressView("Analysing…"); Button("Cancel") { model.quickFixTask?.cancel() } }
      if let failure {
        Text(failure).font(.caption).foregroundStyle(.secondary)
        HStack { Button("Retry") { generation+=1 }; if let sample { Button("Locate Source…") { model.relinkSourceID=sample.id } } }
      }
    }.frame(maxHeight: scrollable ? .infinity : nil, alignment: .top)
      .disabled(model.running || model.overlayEditor || model.targets.isEmpty)
      .task(id:input) {
        let request=input
        var base = request
        base.configuration.filterEdit = nil; base.configuration.look = nil
        // An intensity change changes only the selected tile. Keep the other valid
        // candidates visible while the latest selected preview is prepared.
        if previewBase != base { previews=[:]; previewConfigurations=[:]; previewBase=base }
        failure=nil; unsupportedSource=false
        guard let asset=request.source else { return }
        do {
          try await model.processor.validateCreativeSource(asset.url)
          for preset in [CreativePreset?.none]+FilterCatalog.presets.filter({$0.collection == request.collection}).map(Optional.some) {
            try Task.checkCancellation()
            var c=request.configuration; c.look=nil
            c.filterEdit=FilterEdit(presetID:preset?.id,intensity:preset?.id == c.filterEdit?.presetID ? c.filterEdit?.intensity ?? 0.7 : 0.7,grainSeed:c.filterEdit?.grainSeed ?? Workspace.filterSeed(asset.id))
            let key = preset?.id ?? "original"
            if previewConfigurations[key] == c, previews[key] != nil { continue }
            let maximum=request.maximum
            let image=try await FilterPreviewService.shared.preview(asset,configuration:c,maximum:maximum,privateMode:request.privateMode)
            try Task.checkCancellation()
            guard input == request else { return }
            previews[key]=image; previewConfigurations[key]=c
          }
        } catch is CancellationError {} catch { if input == request { failure=error.localizedDescription; if case CreativeFilterError.hdr = error { unsupportedSource=true } } }
      }
      .onAppear { if let selected { collection=selected.collection } }
      .onChange(of:current?.presetID) { _,_ in AccessibilityNotification.Announcement(selected?.name ?? "Original").post() }
      .onDisappear { finishIntensityEntry(); if ownsIntensitySlider { ownsIntensitySlider = false; model.endInteraction() }; previews=[:]; previewConfigurations=[:]; previewBase=nil; model.filterComparisonActive=false }
      .onChange(of: sample?.id) { _, _ in intensityFocused=false; finishIntensityEntry(); model.filterComparisonActive=false }
      .onChange(of: model.targets.map(\.id)) { _, _ in intensityFocused=false; finishIntensityEntry() }
      .onChange(of: comparisonFocused) { _, focused in if !focused { model.filterComparisonActive=false } }
      .onChange(of:scenePhase) { _,phase in if phase != .active { model.filterComparisonActive=false; Task { await FilterPreviewService.shared.clearMemory() } } }
      #if os(macOS)
      .onChange(of:activeState) { _,state in if state == .inactive { model.filterComparisonActive=false } }
      #endif
  }
  var intensityControls: some View {
      (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
        Text("Intensity").font(.caption)
        Slider(value:Binding(get:{current?.intensity ?? 0.7},set:{model.setFilterIntensity($0)}),in:0...1,onEditingChanged: { editing in
          if editing {
            intensityFocused = false; finishIntensityEntry()
            if !model.interactionInProgress { ownsIntensitySlider = true; model.beginInteraction() }
          } else if ownsIntensitySlider { ownsIntensitySlider = false; model.endInteraction() }
        })
          .accessibilityLabel("Filter intensity")
        TextField("Intensity percent",value:Binding(get:{(current?.intensity ?? 0.7)*100},set:{model.setFilterIntensity($0/100)}),format:.number.precision(.fractionLength(0)))
          .frame(width:typeSize.isAccessibilitySize ? 110 : 52).multilineTextAlignment(.trailing).monospacedDigit().textFieldStyle(.roundedBorder)
          .modifier(SignedNumericEntry())
          .focused($intensityFocused)
          .onSubmit { intensityFocused = false }
          .onChange(of: intensityFocused) { _, focused in
            if focused && !model.interactionInProgress { ownsIntensityInteraction = true; model.beginInteraction() }
            else if !focused { finishIntensityEntry() }
          }
          .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in model.setFilterIntensity((current?.intensity ?? 0.7)+(press.modifiers.contains(.shift) ? 0.10 : 0.01)); return .handled }
          .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in model.setFilterIntensity((current?.intensity ?? 0.7)-(press.modifiers.contains(.shift) ? 0.10 : 0.01)); return .handled }
        Text("%").font(.caption)
      }.disabled(current?.presetID == nil)
  }
  var presetBrowser: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !compact {
        HStack(alignment:.top) {
          tile(nil,width:112)
          VStack(alignment:.leading,spacing:8) {
            Text("Corrections").font(.caption).foregroundStyle(.secondary)
            Toggle("Auto Enhance",isOn:Binding(get:{model.controlConfiguration.autoEnhance?.enabled == true},set:{model.setAutoEnhance($0)})).disabled(model.quickFixRunning)
            Button("Recalculate Enhance") { model.setAutoEnhance(true,recalculate:true) }.font(.caption).disabled(model.quickFixRunning)
          }
        }
      }
      HStack {
        Picker("Collection",selection:$collection) { ForEach(FilterCollection.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
        Spacer(minLength:0)
        compare
      }
      if compact {
        HStack(alignment: .top, spacing: 8) {
          if replacesToolbox {
            Button { model.choosePhotoInspector(.adjust) } label: {
              VStack(spacing: 6) { Image(systemName: "chevron.left"); Text("Tools").font(.caption) }
                .frame(width: 52, height: tileWidth * 0.75)
            }.comfortableHitTarget().accessibilityLabel("Back to editing tools")
          }
          ScrollView(.horizontal) { HStack(alignment:.top,spacing:8) { tile(nil,width:tileWidth); ForEach(candidates) { tile($0,width:tileWidth) } }.padding(2) }.scrollIndicators(.hidden)
        }
      } else {
        LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
          ForEach(candidates) { preset in tile(preset,width:nil) }
        }
      }
    }
  }
  var compare: some View {
    Button(model.filterComparisonActive ? "Before Filter" : "Compare Filter") {}.font(.caption).foregroundStyle(.primary)
      .focused($comparisonFocused)
      .onKeyPress(.space) { model.filterComparisonActive.toggle(); return .handled }
      .onKeyPress(.return) { model.filterComparisonActive.toggle(); return .handled }
      .accessibilityAction { model.filterComparisonActive.toggle() }
      .help("Hold to compare without filters and Auto Enhance. Keyboard or VoiceOver: activate to toggle.")
      .accessibilityLabel("Compare filters and Auto Enhance")
      .accessibilityValue(model.filterComparisonActive ? "Before" : "Edited")
      .onLongPressGesture(minimumDuration:0,pressing:{model.filterComparisonActive=$0},perform:{})
      .accessibilityHint("Temporarily bypass Auto Enhance and creative filter; other edits stay")
      .accessibilityAction(named:Text(model.filterComparisonActive ? "Show filtered photo" : "Show without filters and Auto Enhance")) { model.filterComparisonActive.toggle() }
  }
  func tile(_ preset: CreativePreset?,width: CGFloat?) -> some View {
    let chosen=current?.presetID == preset?.id && model.controlConfiguration.look == nil
    return Button { intensityFocused = false; finishIntensityEntry(); model.selectCreativeFilter(preset?.id) } label: {
      VStack(alignment:.leading,spacing:4) {
        ZStack(alignment:.topTrailing) {
          Color.secondary.opacity(0.08)
          if let image=previews[preset?.id ?? "original"] { Image(decorative:image,scale:1).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity) }
          else { Image(systemName:failure == nil ? "photo" : "exclamationmark.triangle").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
          if chosen { Image(systemName:"checkmark.circle.fill").foregroundStyle(.white,Color.accentColor).padding(4) }
          if let sample { SensitivePreviewCover(model:model,ids:[sample.id]) }
        }.aspectRatio(4/3,contentMode:.fit).clipped()
          .overlay(Rectangle().strokeBorder(chosen ? Color.accentColor : Color.secondary.opacity(hoveredPreset == (preset?.id ?? "original") ? 0.7 : 0.2),lineWidth:chosen || contrast == .increased ? 2 : 1))
        Text(preset?.name ?? "Original").font(.caption).foregroundStyle(.primary).lineLimit(2)
      }.frame(width:width)
    }.buttonStyle(.plain).disabled(preset != nil && unsupportedSource)
      .focused($focusedPreset,equals:preset?.id ?? "original")
      .onHover { hoveredPreset = $0 ? preset?.id ?? "original" : nil }
      .onKeyPress(keys:[.leftArrow,.rightArrow,.upArrow,.downArrow,.return,.space],phases:.down) { press in
        if press.key == .return || press.key == .space { model.selectCreativeFilter(preset?.id); return .handled }
        let ids=["original"]+candidates.map(\.id)
        let index=ids.firstIndex(of:preset?.id ?? "original") ?? 0
        let step=(press.key == .leftArrow || press.key == .rightArrow || compact) ? 1 : 2
        let delta=(press.key == .leftArrow || press.key == .upArrow) ? -step : step
        focusedPreset=ids[min(ids.count-1,max(0,index+delta))];return .handled
      }
      .help(preset?.description ?? "Remove only the creative filter")
      .accessibilityLabel((preset?.name ?? "Original") + ", " + (preset?.collection.rawValue ?? "No creative filter") + ". " + (preset?.description ?? "Preserve corrections and all other edits"))
      .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// Signed decimal edits need punctuation as well as digits; decimalPad omits minus.
private struct SignedNumericEntry: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
    content.keyboardType(.numbersAndPunctuation).submitLabel(.done)
    #else
    content
    #endif
  }
}
