import AppKit
import FramepebbleCore
import SwiftUI

@MainActor final class FramepebbleDelegate: NSObject, NSApplicationDelegate {
  var workspace: Workspace?
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let workspace else { return .terminateNow }
    Task {
      await Automations.shared.stop()
      await workspace.stopWork()
      let previousIssues = workspace.issues.count
      await workspace.flush()
      let saved = workspace.issues.count == previousIssues
      if !saved && !workspace.isReviewSession { Automations.shared.start() }
      sender.reply(toApplicationShouldTerminate: saved)
    }
    return .terminateLater
  }
}

@main struct FramepebbleMacApp: App {
  @NSApplicationDelegateAdaptor(FramepebbleDelegate.self) private var delegate
  @State private var personalWorkspace = Workspace(startInLibrary: true)
  private var model: Workspace { personalWorkspace.demoWorkspace ?? personalWorkspace }
  var body: some Scene {
    Window("Ameluma Photo", id: "studio") {
      if NSClassFromString("XCTestCase") != nil {
        Text("Automated tests are running.").padding(40)
      } else {
        MacWorkspace(model: model)
          .toolbar { ToolbarItem(placement: .principal) { DemoWorkspaceMenu(owner: personalWorkspace) } }
          .onChange(of: model.isDemoWorkspace) { _, _ in delegate.workspace = model }
          .task {
          await model.start()
          delegate.workspace = model
          if !model.isReviewSession { Automations.shared.start() }
        }
      }
    }.defaultLaunchBehavior(.presented).defaultSize(width: 1280, height: 820).windowResizability(.contentMinSize)
      .commands {
        CommandGroup(replacing: .undoRedo) {
          Button(model.undoActionTitle) {
            model.undoActiveWorkspace()
          }
          .keyboardShortcut("z").disabled(
            !model.canUndoActiveWorkspace)
          Button(model.redoActionTitle) {
            model.redoActiveWorkspace()
          }
          .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(
            !model.canRedoActiveWorkspace)
        }
        CommandGroup(after: .undoRedo) {
          Button("Undo History…") { model.historyPresented = true }
            .disabled(model.overlayEditor || (!model.browsingLibrary && model.workflow != .batch && model.workflow != .photo))
        }
        CommandGroup(replacing: .newItem) {
          Button("New Project") { Task { await model.newProject() } }.keyboardShortcut("n")
          Button("Close Project") { Task { await model.closeProject() } }.keyboardShortcut(
            "w", modifiers: [.command, .shift])
          Button("Projects & Clear Photos…") { model.projectsView = true }
          Button("Import Images…") { MacWorkspace(model: model).importImages() }.keyboardShortcut(
            "o")
          Button("Export " + model.actionLabel + "…") { MacWorkspace(model: model).exportImages() }.keyboardShortcut(
            "e"
          ).disabled(model.targets.isEmpty || model.running)
        }
        CommandGroup(before: .saveItem) {
          if model.workflow == .photo && !model.browsingLibrary && !model.editorTabs.isEmpty {
            Button("Close Photo Tab") {
              if let id = model.current?.id { model.closeEditorTab(id) }
            }.keyboardShortcut("w").disabled(model.overlayEditor)
          } else if model.workflow == .collages && !model.browsingLibrary && model.activeCollageID != nil {
            Button("Close Collage Tab") {if let id=model.activeCollageID {model.closeCollageTab(id)}}
              .keyboardShortcut("w").disabled(model.running || model.collageGenerating)
          }
        }
        CommandGroup(replacing: .help) {
          Button("Ameluma Photo Help & Privacy") { model.helpPresented = true }
        }
        CommandMenu("Photo") {
          Button("Rotate Clockwise") {
            if let asset = model.current {
              var c = model.configuration(for: asset)
              c.quarterTurns += 1
              model.setImageConfiguration(c, for: asset.id)
            }
          }.keyboardShortcut("r").disabled(model.current == nil)
          Button("Conceal Workspace") { model.concealed = true }.keyboardShortcut(
            "h", modifiers: [.command, .shift])
          Button("Privacy Review") { model.showLibrary(.privacyReview, clearSearch: true) }.disabled(model.workspaceAssets.isEmpty)
          Button("Make a Collage…") { model.switchWorkflow(.collages) }.disabled(
            model.workspaceAssets.isEmpty || model.running)
        }
      }
    MenuBarExtra("Ameluma Photo", systemImage: "photo.badge.arrow.down") {
      FramepebbleStatusMenu(model: personalWorkspace)
    }
  }
}
struct MacWorkspace: View {
  @Bindable var model: Workspace
  @State private var showAutomations = false
  @State private var batchInspector = true
  @State private var photoInspector = false
  private var showInspector: Bool {
    get { model.workflow == .photo ? photoInspector : batchInspector }
    nonmutating set { if model.workflow == .photo { photoInspector = newValue } else { batchInspector = newValue } }
  }
  @State private var inspectorWidth: CGFloat = EditorPanelLayout.inspectorWidth
  @State private var sidebarPreference: Bool?
  @State private var exportPresented = false
  @State private var resizeStart: CGFloat?
  var body: some View {
    GeometryReader { geometry in
    let sidebarVisible = EditorPanelLayout.navigationVisible(width: geometry.size.width, editing: !model.browsingLibrary || model.overlayEditor, preference: sidebarPreference)
    let fittedInspectorWidth = EditorPanelLayout.fittedInspectorWidth(requested: inspectorWidth, available: geometry.size.width - (sidebarVisible ? 221 : 0) - (model.workflow == .photo ? 49 : 0))
    HStack(spacing: 0) {
      if sidebarVisible {
      LibrarySidebar(model: model, openAutomations: { showAutomations = true }).disabled(model.overlayEditor).frame(width: 220)
      Divider()
      }
      if model.overlayEditor {
        OverlayEditor(model: model, embedded: true)
      } else if model.browsingLibrary {
        VStack(spacing: 0) {
          ImageCollection(model: model, importAction: importImages)
          if model.isImporting { ImportProgressView(model: model) }
          ExportStatus(model: model).padding(.horizontal, 16).padding(.bottom, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.workflow == .automations {
        AutomationDashboard(automations: Automations.shared, embedded: true)
      } else if model.workflow == .gif {
        GIFEditor(model: model, importAction: importImages)
      } else if model.workflow == .collages {
        CollageEditor(model: model, embedded: true)
      } else {
        Group {
          if model.workflow == .photo { PhotoEditorWorkspace(model: model, openSettings: { showInspector = true }, showsToolbox: false, showsQuickControls: !showInspector) }
          else { ImageCollection(model: model, importAction: importImages) }
        }.safeAreaInset(
          edge: .bottom, spacing: 0
        ) {
          if model.isImporting { ImportProgressView(model: model) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        if showInspector {
          Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 5).contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 0).onChanged { value in
                if resizeStart == nil { resizeStart = fittedInspectorWidth }
                inspectorWidth = min(420, max(280, (resizeStart ?? 300) - value.translation.width))
              }.onEnded { _ in resizeStart = nil }
            )
            .accessibilityLabel("Resize inspector")
          VStack(spacing: 0) {
            if model.workflow == .batch {
              InspectorToolPicker(model: model).padding(10)
              Divider()
            }
            if model.precision {
              ScrollView { PrecisionEditor(model: model, showsPreview: model.workflow != .photo).padding(12) }
            } else {
              SettingsEditor(model: model, focused: model.workflow == .photo, showsContext: model.workflow == .photo, compactPanel: true)
            }
            Divider()
            VStack(spacing: 8) {
              if !model.pendingExports.isEmpty {
                Button("Retry unfinished exports…") { exportImages(retry: true) }.disabled(
                  model.running)
              }
              ExportStatus(model: model)
            }.padding(14)
          }.frame(width: fittedInspectorWidth)
        }
        if model.workflow == .photo {
          Divider()
          PhotoEditorTools(model: model, openSettings: { if model.inspectorTask != .adjust || model.precision { showInspector = true } }, vertical: true)
            .frame(width: 48).padding(.vertical, 8).background(.bar)
        }
      }
    }
    }.frame(minWidth: showInspector && (model.workflow == .photo || model.workflow == .batch) ? 1040 : 740, minHeight: 600)
      .background(Color(nsColor: .windowBackgroundColor)).disabled(model.clearingWorkspace)
      .toolbar {
        ToolbarItemGroup {
          Button {
            sidebarPreference = !EditorPanelLayout.navigationVisible(width: NSApp.keyWindow?.contentView?.bounds.width ?? 1280, editing: !model.browsingLibrary || model.overlayEditor, preference: sidebarPreference)
          } label: { Image(systemName: "sidebar.left") }
            .help("Show or hide navigation").accessibilityLabel("Toggle navigation sidebar")
          if model.browsingLibrary && !model.overlayEditor {
            Button(action: importImages) { Label("Import", systemImage: "plus") }.keyboardShortcut("o")
            Button("Projects", systemImage: "folder") { model.projectsView = true }
          }
          if !model.browsingLibrary && !model.overlayEditor && (model.workflow == .photo || model.workflow == .batch) {
            Button(action: importImages) { Label("Import", systemImage: "plus") }.keyboardShortcut(
              "o")
            Button("Share " + model.actionLabel, systemImage: "square.and.arrow.up") { prepareShare() }.disabled(
              model.targets.isEmpty || model.running)
            Button { exportPresented = true } label: { Label("Export " + model.actionLabel, systemImage: "square.and.arrow.down") }
              .keyboardShortcut("e").disabled(model.targets.isEmpty || model.running)
            Menu {
              Button("Rotate " + model.actionLabel, systemImage: "rotate.right") { model.rotateTargets() }.disabled(model.targets.isEmpty)
              Button("Auto-frame " + model.actionLabel, systemImage: "sparkles") { model.autoFrame(.smart) }.disabled(model.analysing || model.targets.isEmpty)
              Divider()
              Button("Automations", systemImage: "folder.badge.gearshape") {
                showAutomations = true
              }
              Button("Privacy Review", systemImage: "checkmark.shield") {
                model.sensitiveReviewPresented = true
              }
              Button("Projects", systemImage: "folder") { model.projectsView = true }
              Button("Conceal workspace", systemImage: "eye.slash") { model.concealed = true }
            } label: {
              Label("More", systemImage: "ellipsis.circle")
            }
            Button {
              showInspector.toggle()
            } label: {
              Image(systemName: "sidebar.right")
            }.accessibilityLabel(showInspector ? "Hide editing controls" : "Show editing controls")
          }
        }
      }
      .sheet(isPresented: $exportPresented) {
        NavigationStack {
          VStack(spacing: 0) {
            SettingsEditor(model: model, focused: true, task: .output)
            Divider()
            if model.running {
              VStack(alignment: .leading, spacing: 8) {
                Text(model.status).font(.caption)
                ProgressView(value: Double(model.completed), total: Double(max(1, model.total)))
                Button("Cancel export") { model.task?.cancel() }
              }.padding([.horizontal, .top])
            } else if let output = model.latestExport {
              ExportCompletionView(model: model, output: output).padding([.horizontal, .top])
            } else if model.status != "Your photos. Your way." {
              StatusNotice(model: model).padding([.horizontal, .top])
            }
            HStack {
              Button("Cancel") { exportPresented = false }.keyboardShortcut(.cancelAction)
              Spacer()
              Button("Save " + model.actionLabel + "…") { exportImages() }
                .buttonStyle(.borderedProminent).disabled(model.running || model.targets.isEmpty)
            }.padding()
          }.navigationTitle("Export").toolbar { Button("Done") { exportPresented = false } }
        }.frame(width: 480, height: 640).privacyCurtain(model: model)
      }
      .onDrop(of: BrowserDropImporter.acceptedTypes, isTargeted: nil) { providers in
        BrowserDropImporter.start(providers, model: model)
      }
      .sheet(
        isPresented: $model.sensitiveReviewPresented,
        onDismiss: model.finishPrivacyReviewPresentation
      ) { SensitiveReviewView(model: model).privacyCurtain(model: model) }
      .sheet(isPresented: $model.helpPresented) {
        HelpPrivacyView(storageDirectory: model.directory.deletingLastPathComponent())
          .privacyCurtain(model: model)
      }
      .sheet(isPresented: $showAutomations) {
        AutomationDashboard(automations: Automations.shared).privacyCurtain(model: model)
      }
      .sheet(isPresented: $model.collageEditor) {
        CollageEditor(model: model).privacyCurtain(model: model)
      }
      .sheet(isPresented: Binding(get: { model.copySourceID != nil }, set: { if !$0 { model.copySourceID = nil } })) {
        CopyEditsChooser(model: model)
      }
      .sheet(isPresented: Binding(get: { model.relinkSourceID != nil }, set: { if !$0 { model.relinkSourceID = nil } })) {
        if let id = model.relinkSourceID { SourceRecoveryView(model: model, sourceID: id).privacyCurtain(model: model) }
      }
      .sheet(item: $model.filterBatchRequest) { FilterBatchSheet(model: model, request: $0) }
      .sheet(isPresented: $model.projectsView) {
        ProjectsView(model: model).privacyCurtain(model: model)
      }
      .sheet(item: $model.sharingSession) { session in
        ShareReview(urls: session.outputs, summary: session.summary, analyzer: model.sensitiveAnalyzer).privacyCurtain(
          model: model)
      }
      .overlay {
        if model.concealed {
          Color(nsColor: .windowBackgroundColor).overlay(
            Button("Reveal workspace", systemImage: "eye") { model.concealed = false }.buttonStyle(
              .borderedProminent))
        }
      }

      .onChange(of: model.inspectorTask) { _, task in if task == .filters { showInspector = true } }
      .onChange(of: model.precision) { _, enabled in if enabled { showInspector = true } }

  }
  func prepareShare() {
    let directory = model.directory.deletingLastPathComponent().appendingPathComponent("Exports")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      model.export(to: directory) { urls in model.beginSharing(urls) }
    } catch { model.issues.append(error.localizedDescription) }
  }
  func importImages() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = ImageProcessor.importTypes
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.begin { response in
      guard response == .OK else { return }
      let urls = panel.urls
      Task { await model.importURLs(urls) }
    }
  }
  func exportImages() { exportImages(retry: false) }
  func exportImages(retry: Bool, targetIDs: Set<UUID>? = nil) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Export here"
    panel.message = targetIDs == nil ? model.exportPlanSummary : "This photo → 1 file · current edits"
    panel.title = targetIDs == nil ? "Export " + model.actionLabel : "Export This Photo"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      model.export(to: url, retry: retry, targetIDs: targetIDs)
    }
  }
}

private struct FramepebbleStatusMenu: View {
  @Bindable var model: Workspace
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Button("Open Ameluma Photo") {
      openWindow(id: "studio")
      NSApplication.shared.activate()
    }
    Divider()
    Text("Monitoring requires Ameluma Photo to remain open.")
    Text("\(Automations.shared.recipes.filter(\.enabled).count) workflows enabled")
    ForEach(Automations.shared.recipes) { recipe in
      Button("\(recipe.enabled ? "Pause" : "Resume") \(recipe.name)") {
        Automations.shared.toggle(recipe.id)
      }
    }
    Divider()
    Button("Help & Privacy") {
      openWindow(id: "studio")
      NSApplication.shared.activate()
      model.helpPresented = true
    }
    Button("Quit Ameluma Photo") { NSApplication.shared.terminate(nil) }
  }
}
