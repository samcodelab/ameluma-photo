import FramepebbleCore
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main struct FramepebbleIOSApp: App { var body: some Scene { WindowGroup { MobileWorkspace() } } }
struct MobileWorkspace: View {
  @State private var model = Workspace(startInLibrary: true)
  #if DEBUG
    @State private var home = !CommandLine.arguments.contains("-FramepebbleReviewGallery")
  #else
    @State private var home = true
  #endif
  @State private var showInspector = true
  @State private var detailWidth: CGFloat = 0
  @State private var pendingTaskImport = false
  @State private var activity = "Resize or Convert"
  @State private var reviewedURLs: [URL] = []
  @State private var reviewPayload: ReviewedOutputs?
  @State private var photos: [PhotosPickerItem] = []
  @State private var importFiles = false
  @State private var importFolder = false
  @State private var exportFolder = false
  @State private var retry = false
  @State private var settingsSheet = false
  @State private var editAfterExport = false
  @State private var nextEditor: EditorDestination?
  @State private var exportSheet = false
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.scenePhase) private var phase
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular {
        NavigationSplitView {
          LibrarySidebar(model: model).disabled(model.overlayEditor)
        } detail: {
          GeometryReader { geometry in
            Group {
              if model.overlayEditor {
                VStack(spacing: 0) {
                  PhotoDocumentTabs(model: model).padding(12).disabled(true)
          PhotoEditorTools(model: model).padding(.horizontal, 16).disabled(true)
                  OverlayEditor(model: model, embedded: true)
                }.privacyCurtain(model: model)
              } else {
                HStack(spacing: 0) {
                  collection.frame(maxWidth: .infinity)
                  if !model.browsingLibrary && showInspector && geometry.size.width >= 760 && (model.workflow == .photo || model.workflow == .batch) {
                    Divider()
                    if model.precision {
                      ScrollView { PrecisionEditor(model: model, showsPreview: model.workflow != .photo) }.frame(width: 340)
                    } else {
                      SettingsEditor(model: model, focused: model.workflow == .photo).frame(width: 340)
                    }
                  }
                }
              }
            }.onAppear { detailWidth = geometry.size.width }
              .onChange(of: geometry.size.width) { _, width in detailWidth = width }
          }.navigationTitle(model.workspaceTitle).toolbar {
            if !model.overlayEditor {
              Menu {
                importActions
              } label: {
                Label("Import", systemImage: "plus")
              }
              Button("Projects", systemImage: "folder") { model.projectsView = true }
              if !model.browsingLibrary && model.workflow != .collages && model.workflow != .gif {
              Button {
                if detailWidth >= 760 { showInspector.toggle() } else { settingsSheet = true }
              } label: {
                Image(systemName: "sidebar.right")
              }.accessibilityLabel(
                detailWidth < 760
                  ? "Editing settings"
                  : showInspector ? "Hide editing controls" : "Show editing controls")
              Button("Export") { exportSheet = true }.disabled(
                model.targets.isEmpty || model.running)
              }
            }
          }
        }
      } else {
        NavigationStack {
          Group { if home { homeScreen } else { collection } }.navigationTitle(
            home ? "Ameluma Photo" : model.workspaceTitle
          ).navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .topBarLeading) {
              if !home {
                Button("Home", systemImage: "house") { home = true }
              }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
              if home {
                Button("Help & Privacy", systemImage: "questionmark.circle") {
                  model.helpPresented = true
                }
              }
              if !home {
                Menu {
                  importActions
                } label: {
                  Image(systemName: "plus")
                }
                if !model.browsingLibrary && model.workflow != .collages && model.workflow != .gif {
                Button {
                  settingsSheet = true
                } label: {
                  Image(systemName: "slider.horizontal.3")
                }.accessibilityLabel("Editing settings")
                Button {
                  exportSheet = true
                } label: {
                  Image(systemName: "square.and.arrow.up")
                }.accessibilityLabel("Export " + model.actionLabel).disabled(model.targets.isEmpty)
                }
              }
            }
          }
        }
      }
    }.tint(.blue)
      .sheet(
        isPresented: $model.sensitiveReviewPresented,
        onDismiss: model.finishPrivacyReviewPresentation
      ) { SensitiveReviewView(model: model).privacyCurtain(model: model) }
      .sheet(isPresented: $model.helpPresented) {
        HelpPrivacyView(storageDirectory: model.directory.deletingLastPathComponent())
          .privacyCurtain(model: model)
      }
      .fullScreenCover(
        isPresented: Binding(
          get: {
            model.overlayEditor
              && !(UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular)
          }, set: { model.overlayEditor = $0 }), onDismiss: model.finishOverlayPresentation
      ) {
        VStack(spacing: 0) {
          PhotoDocumentTabs(model: model).padding(.horizontal).disabled(true)
          OverlayEditor(model: model)
        }.privacyCurtain(model: model)
      }
      .sheet(isPresented: $model.collageEditor) {
        CollageEditor(model: model).privacyCurtain(model: model)
      }
      .sheet(isPresented: Binding(get: { model.copySourceID != nil }, set: { if !$0 { model.copySourceID = nil } })) {
        CopyEditsChooser(model: model)
      }
      .sheet(isPresented: $model.projectsView) {
        ProjectsView(model: model).privacyCurtain(model: model)
      }
      .sheet(item: $model.sharingSession) { session in
        ShareReview(urls: session.outputs, summary: session.summary, analyzer: model.sensitiveAnalyzer).privacyCurtain(
          model: model)
      }
      .task {
        if UIDevice.current.userInterfaceIdiom == .phone { model.tileSize = 110 }
        await model.start()
      }
      .sheet(item: $reviewPayload) { payload in
        ShareReview(urls: payload.urls, analyzer: model.sensitiveAnalyzer).privacyCurtain(
          model: model)
      }
      .overlay {
        if model.concealed {
          Color(.systemBackground).ignoresSafeArea().overlay(
            Button("Reveal workspace", systemImage: "eye") { model.concealed = false }.buttonStyle(
              .borderedProminent))
        }
      }
      .sheet(
        isPresented: $settingsSheet,
        onDismiss: {
          guard let destination = nextEditor else { return }
          nextEditor = nil
          switch destination {
          case .framing: model.precision = true
          case .collage: model.collageEditor = true
          case .overlays: if let asset = model.current { model.openOverlayEditor(for: asset) }
          case .projects: model.projectsView = true
          }
        }
      ) {
        NavigationStack {
          SettingsEditor(
            model: model, focused: true,
            openEditor: { destination in
              nextEditor = destination
              settingsSheet = false
            }
          ).privacyCurtain(model: model).navigationTitle(activity).toolbar {
            Button("Done") { settingsSheet = false }
          }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
      }
      .sheet(
        isPresented: $exportSheet,
        onDismiss: {
          if editAfterExport {
            editAfterExport = false
            settingsSheet = true
          }
          if !reviewedURLs.isEmpty {
            reviewPayload = ReviewedOutputs(urls: reviewedURLs)
            reviewedURLs = []
          }
        }
      ) {
        NavigationStack {
          exportControls.navigationTitle("Export").toolbar {
            Button("Done") { exportSheet = false }
          }
        }
      }
      .fullScreenCover(
        isPresented: Binding(
          get: {
            model.precision
              && !(UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
                && showInspector && detailWidth >= 760)
          }, set: { model.precision = $0 })
      ) {
        NavigationStack {
          ScrollView { PrecisionEditor(model: model, showsHeader: false) }.privacyCurtain(
            model: model
          ).navigationTitle("Refine Framing").navigationBarTitleDisplayMode(.inline).toolbar {
            Button("Done") { model.precision = false }
          }
        }
      }
      .fileImporter(
        isPresented: $importFiles, allowedContentTypes: ImageProcessor.importTypes,
        allowsMultipleSelection: true, onCompletion: importResult
      )
      .fileImporter(
        isPresented: $importFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true,
        onCompletion: importResult
      )
      .fileImporter(isPresented: $exportFolder, allowedContentTypes: [.folder]) { result in
        switch result {
        case .success(let url): model.export(to: url, retry: retry)
        case .failure(let error): model.issues.append(error.localizedDescription)
        }
      }
      .onChange(of: photos) { _, items in
        guard !items.isEmpty else { return }
        beginPhotoImport(items)
      }
      .onChange(of: phase) { _, value in
        if value == .inactive && model.privateEditing { model.concealed = true }
        if value == .background {
          if model.privateEditing { model.concealed = true }
          model.sensitivityTask?.cancel()
          model.cancelImport()
          model.gifExportTask?.cancel()
          model.collageTask?.cancel()
          model.task?.cancel()
          model.analysisTask?.cancel()
          model.indexingTask?.cancel()
          Task {
            let token = UIApplication.shared.beginBackgroundTask(withName: "Preserve local edits")
            await model.flush()
            if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
          }
        } else if value == .active {
          model.startIndexing()
        }
      }
  }
  var homeScreen: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          PebbleMark(size: 48)
          VStack(alignment: .leading) {
            Text("Your photos. Your way.").font(.title2.weight(.semibold))
            Text("What would you like to do?").foregroundStyle(.secondary)
          }
        }.padding(.vertical)
        Button {
          model.showLibrary(.all, clearSearch: true)
          home = false
        } label: {
          Label("Workspace · \(model.workspaceAssets.count) photos", systemImage: "photo.on.rectangle.angled")
            .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
        ForEach(
          [
            "Batch Edit", "Editor", "Convert", "Censor", "Create GIF", "Collages",
          ], id: \.self
        ) { name in
          Button {
            activity = name
            home = false
            pendingTaskImport = model.workspaceAssets.isEmpty
            launchTask()
          } label: {
            HStack {
              Image(systemName: taskSymbol(name)).font(.title3).foregroundStyle(.blue).frame(
                width: 30)
              VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline).foregroundStyle(.primary)
                Text(taskDescription(name)).font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption)
            }.multilineTextAlignment(.leading).padding(16).frame(
              maxWidth: .infinity, alignment: .leading
            ).background(
              Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
          }.buttonStyle(.plain)
        }
        Button("Projects & Clear Photos", systemImage: "folder") { model.projectsView = true }
        if !model.workspaceAssets.isEmpty {
          Text("Recent workspace").font(.headline)
          Button(
            "Continue editing \(model.workspaceAssets.count) \(model.workspaceAssets.count == 1 ? "photo" : "photos")"
          ) { home = false }
          Text("Your current workspace is saved on this device.").font(.caption).foregroundStyle(
            .secondary)
        }
        Text("Live Photos export as still images. All edits preserve your originals.").font(
          .caption
        ).foregroundStyle(.secondary)
      }.padding(20)
    }.background(Color(.systemGroupedBackground))
  }
  func taskSymbol(_ name: String) -> String {
    switch name {
    case "Editor", "Perfect a Photo": "slider.horizontal.3"
    case "Collages", "Make a Collage": "rectangle.split.2x2"
    case "Create GIF": "photo.stack"
    case "Convert": "arrow.triangle.2.circlepath"
    case "Censor", "Privacy": "eye.slash"
    case "Prepare to Share": "square.and.arrow.up"
    default: "arrow.up.left.and.arrow.down.right"
    }
  }
  func taskDescription(_ name: String) -> String {
    switch name {
    case "Editor", "Perfect a Photo": "Edit one photo, then export or share it"
    case "Collages", "Make a Collage": "Choose sources and edit your composition"
    case "Create GIF": "Turn photos into an animation with captions"
    case "Convert": "Change format while keeping source dimensions"
    case "Censor", "Privacy": "Cover details you want to keep private"
    case "Prepare to Share": "Review and save your finished photos"
    default: "Select photos, apply shared edits and export a batch"
    }
  }
  func finishTaskImport() {
    if pendingTaskImport && !model.workspaceAssets.isEmpty {
      pendingTaskImport = false
      if !model.precision && !model.overlayEditor && !model.collageEditor && !settingsSheet {
        launchTask()
      }
    }
  }
  func launchTask() {
    if activity == "Batch Edit" { model.selectPhotos(for: .batch); return }
    if activity == "Editor" { model.selectPhotos(for: .edit); return }
    if activity == "Collages" { model.selectPhotos(for: .collage); return }
    if activity == "Convert" { model.selectPhotos(for: .convert); return }
    if activity == "Censor" { model.selectPhotos(for: .censor); return }
    let workflow: StudioWorkflow = activity == "Editor" ? .photo : activity == "Collages" ? .collages : activity == "Create GIF" ? .gif : .batch
    model.switchWorkflow(workflow)
    guard !model.workspaceAssets.isEmpty else { return }
    if activity == "Create GIF" { return }
    if activity == "Batch Edit" || activity == "Editor" || activity == "Collages" {
      model.inspectorTask = .resize
      return
    }
    model.inspectorTask =
      activity == "Editor" || activity == "Perfect a Photo" ? .adjust : activity == "Prepare to Share" ? .output : .resize
    if activity == "Editor" || activity == "Perfect a Photo" || activity == "Privacy" {
      model.scope = .individual
    } else {
      model.scope = .all
    }
    if activity == "Make a Collage" {
      if model.scope == .individual { model.scope = .all }
      model.collageEditor = true
    } else if activity == "Privacy" {
      model.showHideSomething()
    } else if activity == "Prepare to Share" {
      exportSheet = true
    } else if UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
      && detailWidth >= 760
    {
      showInspector = true
      model.precision = false
    } else {
      settingsSheet = true
    }
  }
  var collection: some View {
    Group {
      if model.browsingLibrary { libraryCollection }
      else if model.workflow == .photo && !model.workspaceAssets.isEmpty { PhotoEditorWorkspace(model: model, openSettings: {
        if UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular && detailWidth >= 760 { showInspector = true }
        else { settingsSheet = true }
      }) }
      else if model.workflow == .gif { GIFEditor(model: model, importAction: { importFiles = true }) }
      else if model.workflow == .collages && !model.workspaceAssets.isEmpty { CollageEditor(model: model, embedded: true) }
      else { libraryCollection }
    }
  }
  var libraryCollection: some View {
    VStack(spacing: 0) {
      if model.workspaceAssets.isEmpty && model.gifSelectionContext == nil {
        VStack(spacing: 16) {
          PebbleMark(size: 48)
          Text(model.browsingLibrary ? "Your photo workspace" : activity).font(.title2.weight(.semibold))
          Text("Add some photos to start editing, creating or converting.").font(.subheadline).foregroundStyle(
            .secondary)
          PhotosPicker(selection: $photos, matching: .images, preferredItemEncoding: .compatible) {
            Label("Add Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
          }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isImporting)
          Button {
            importFiles = true
          } label: {
            Label("Browse Files", systemImage: "folder").frame(maxWidth: .infinity)
          }.buttonStyle(.bordered).controlSize(.large)
        }.padding(24)
      }
      if !model.workspaceAssets.isEmpty || model.gifSelectionContext != nil { ImageCollection(model: model, importAction: { importFiles = true }) } else { Spacer(minLength: 12) }
      if !model.browsingLibrary && model.workflow == .batch && model.current != nil {
        HStack {
          Button(model.conversionInputIDs != nil ? "Format & Export" : "Batch Settings", systemImage: "slider.horizontal.3") {
            if model.conversionInputIDs != nil { exportSheet = true }
            else { model.inspectorTask = .resize; settingsSheet = true }
          }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding(.horizontal)
      }
      if !model.browsingLibrary && model.current != nil && model.conversionInputIDs == nil {
        if typeSize.isAccessibilitySize {
          Menu("Photo actions") {
            Button("Rotate clockwise", systemImage: "rotate.right") { rotateCurrent() }
            Button("Refine framing", systemImage: "crop") { model.precision = true }
          }.padding(.vertical, 8)
        } else {
          HStack {
            Button("Rotate", systemImage: "rotate.right") { rotateCurrent() }.comfortableHitTarget()
            Button("Refine", systemImage: "crop") { model.precision = true }.comfortableHitTarget()
            Spacer()
          }.padding(.horizontal).padding(.vertical, 4)
        }
      }
      if model.isImporting || model.running || model.analysing || !model.issues.isEmpty
        || !model.results.isEmpty || !model.collageOutputs.isEmpty
      {
        ExportStatus(model: model).padding(.horizontal)
      }
    }.dropDestination(for: URL.self) { urls, _ in
      Task { await model.importURLs(urls) }
      return true
    }
  }
  func rotateCurrent() {
    if let asset = model.current {
      var configuration = model.configuration(for: asset)
      configuration.quarterTurns += 1
      model.setImageConfiguration(configuration, for: asset.id)
    }
  }
  @ViewBuilder var importActions: some View {
    PhotosPicker(
      "Select Photos", selection: $photos, matching: .images, preferredItemEncoding: .compatible
    ).disabled(model.isImporting)
    Button("Import Files") { importFiles = true }
    Button("Privacy Review…") { model.sensitiveReviewPresented = true }
    Button("Import Folder") { importFolder = true }
  }
  func beginPhotoImport(_ items: [PhotosPickerItem]) {
    guard !model.isImporting, !model.clearingWorkspace else {
      photos = []
      return
    }
    model.importing = true
    model.importCompleted = 0
    model.importSkipped = 0
    model.importFailed = 0
    model.importDiscovered = items.count
    model.importBytes = 0
    model.importSize = 0
    model.importTask = Task {
      var stillOnly = false
      for (position, item) in items.enumerated() {
        if Task.isCancelled { break }
        model.importMessage = "Loading photo \(position + 1) of \(items.count)…"
        do {
          stillOnly =
            stillOnly || item.supportedContentTypes.contains(where: { $0.conforms(to: .livePhoto) })
          if let data = try await item.loadTransferable(type: Data.self) {
            try Task.checkCancellation()
            await model.importData(data, name: "Photo-\(UUID().uuidString.prefix(6)).jpg")
          } else {
            model.importFailed += 1
            model.issues.append("A selected photo could not be loaded.")
          }
        } catch is CancellationError { break } catch {
          model.importFailed += 1
          model.issues.append(error.localizedDescription)
        }
      }
      let cancelled = Task.isCancelled
      model.importing = false
      model.importTask = nil
      photos = []
      model.status =
        cancelled
        ? "Import cancelled. Completed photos are retained."
        : "Imported \(model.importCompleted) photos."
      if stillOnly {
        model.status += " Live Photos were imported as still images; motion is not retained."
      }
      model.persist()
      model.startIndexing()
      if !cancelled { finishTaskImport() }
    }
  }
  var exportControls: some View {
    ScrollView {
      VStack(spacing: 18) {
        Image(systemName: model.running ? "gearshape.2" : "square.and.arrow.up").font(
          .system(size: 42)
        ).foregroundStyle(.blue).padding(.top, 30)
        Text(model.running ? "Processing photos…" : "\(model.targets.count) photos to export").font(
          .title2.weight(.semibold))
        Text("Edits are applied to new copies. Your originals stay unchanged.").font(.subheadline)
          .foregroundStyle(.secondary)
        if model.workflow == .batch && model.conversionInputIDs == nil {
          Picker("Batch inputs", selection: $model.scope) {
            ForEach([ApplyScope.all, .selected, .results], id: \.self) { Text($0.rawValue).tag($0) }
          }
        }
        if model.conversionInputIDs != nil {
          Picker("Format", selection: Binding(get: { model.controlConfiguration.format }, set: { model.updateField(\.format, value: $0, fields: [.format]) })) {
            ForEach(ImageProcessor.outputFormats, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
          }
        }
        ExportPlanView(model: model)
        Text(
          "Individual edits are included. Active export profiles may produce additional sizes and formats."
        ).font(.caption).foregroundStyle(.secondary)
        Text(
          "\(ExportPlanView(model: model).sizeSummary(model.controlConfiguration)) · \(model.controlConfiguration.format.rawValue.uppercased())"
        ).font(.subheadline).foregroundStyle(.secondary)
        Button("Change size or format", systemImage: "slider.horizontal.3") {
          exportSheet = false
          model.inspectorTask = model.conversionInputIDs != nil ? .output : .resize
          editAfterExport = true
        }
        Button {
          prepareShare()
        } label: {
          Label("Review & Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).controlSize(.large).disabled(
          model.running || model.targets.isEmpty)
        Toggle("Review before saving to Photos", isOn: $model.requirePrivacyReview)
        Button {
          retry = false
          exportFolder = true
        } label: {
          Label("Save to Files", systemImage: "folder").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(
          model.running || model.targets.isEmpty)
        Button {
          savePhotos()
        } label: {
          Label("Save to Photos", systemImage: "photo").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).controlSize(.large).disabled(
          model.running || model.targets.isEmpty)
        if !model.pendingExports.isEmpty {
          Button("Retry unfinished exports to Files") {
            retry = true
            exportFolder = true
          }.disabled(model.running)
        }
        ExportStatus(model: model)
      }.padding(24)
    }
  }
  func importResult(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      Task {
        await model.importURLs(urls)
        finishTaskImport()
      }
    case .failure(let error): model.issues.append(error.localizedDescription)
    }
  }
  func prepareShare() {
    let directory = model.directory.deletingLastPathComponent().appendingPathComponent("Exports")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      model.export(to: directory) { urls in
        reviewedURLs = urls
        exportSheet = false
      }
    } catch { model.issues.append(error.localizedDescription) }
  }
  func savePhotos() {
    Task {
      let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
      guard permission == .authorized || permission == .limited else {
        model.status = "Allow photo additions in Settings to save processed images."
        return
      }
      let directory = model.directory.deletingLastPathComponent().appendingPathComponent("Exports")
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      } catch {
        model.issues.append(error.localizedDescription)
        return
      }
      model.export(to: directory) { urls in
        if model.requirePrivacyReview {
          reviewedURLs = urls
          exportSheet = false
          return
        }
        var count = 0
        for url in urls {
          if Task.isCancelled { break }
          do {
            try await PhotoLibraryExporter.save(url)
            count += 1
          } catch {
            model.issues.append(
              "Photos save failed: \(error.localizedDescription). The processed file remains available to share."
            )
          }
        }
        model.status = "Saved \(count) images to Photos. Completed files remain available below."
      }
    }
  }
}
