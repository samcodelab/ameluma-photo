import AppKit
import FramepebbleCore
import ImageIO
import Observation
import SwiftUI

actor AutomationScanner {
  let processor = ImageProcessor()
  var trackers: [UUID: FileStabilityTracker] = [:]
  var digestCache: [URL: (SourceFingerprint, String)] = [:]
  func existing(_ recipe: AutomationRecipe, input: URL) throws -> [URL] {
    try processorFiles(input, recursive: recipe.recursive)
  }
  func candidates(_ recipe: AutomationRecipe, input: URL) throws -> [URL] {
    let files = try processorFiles(input, recursive: recipe.recursive)
    var tracker = trackers[recipe.id] ?? FileStabilityTracker()
    var stable: [URL] = []
    for url in files {
      try Task.checkCancellation()
      if tracker.stable(url, fingerprint: try SourceFingerprint.read(url)) { stable.append(url) }
    }
    trackers[recipe.id] = tracker
    return stable
  }
  private func processorFiles(_ root: URL, recursive: Bool) throws -> [URL] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    let files: [URL]
    if recursive {
      guard
        let walker = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: Array(keys),
          options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { throw ProcessingError.destination }
      files = walker.allObjects.compactMap { $0 as? URL }
    } else {
      files = try FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
    }
    return try files.filter { url in
      let r = try url.resourceValues(forKeys: keys)
      return r.isRegularFile == true && r.isSymbolicLink != true
        && ImageProcessor.importTypes.contains {
          url.pathExtension.lowercased() == $0.preferredFilenameExtension
            || $0.identifier == "public.jpeg"
              && ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        }
    }
  }
  func digest(_ url: URL) throws -> String {
    let fingerprint = try SourceFingerprint.read(url)
    if let cached = digestCache[url], cached.0 == fingerprint { return cached.1 }
    let value = try ContentDigest.read(url)
    if digestCache.count >= 16384 { digestCache.removeAll() }
    digestCache[url] = (fingerprint, value)
    return value
  }
}
@MainActor @Observable final class Automations {
  static let shared = Automations()
  var recipes: [AutomationRecipe] = []
  var message = "Monitoring runs while Ameluma Photo is open."
  var task: Task<Void, Never>?
  private var stopping = false
  var busy = false
  private(set) var editingRecipeIDs: Set<UUID> = []
  var approvalTask: Task<Void, Never>?
  private var events: FolderEvents?
  let processor = ImageProcessor()
  let scanner = AutomationScanner()
  let analyzer = VisionAnalyzer()
  let root: URL
  var ledger: URL { root.appendingPathComponent("Automations.json") }
  init(root: URL? = nil) {
    #if DEBUG
    let arguments = CommandLine.arguments
    let reviewPosition = arguments.firstIndex(of: "-FramepebbleReviewRoot")
    let reviewRoot = reviewPosition.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]).appendingPathComponent("Automations", isDirectory: true) : nil }
    #else
    let reviewRoot: URL? = nil
    #endif
    self.root =
      root ?? reviewRoot
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Framepebble/Automations", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: ledger.path) {
        let data = try Data(contentsOf: ledger)
        if let legacy = try? JSONDecoder().decode([AutomationRecipe].self, from: data) {
          recipes = legacy
        } else {
          let value = try JSONDecoder().decode(AutomationLedger.self, from: data)
          guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }
          recipes = value.recipes
        }
      }
    } catch { message = "Automation recovery failed: \(error.localizedDescription)" }
  }
  func start() {
    guard task == nil else { return }
    stopping = false
    refreshEvents()
    task = Task {
      while !Task.isCancelled {
        await reconcile()
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }
  func refreshEvents() {
    events = FolderEvents(
      folders: recipes.filter { $0.enabled && !editingRecipeIDs.contains($0.id) }.compactMap { try? resolve($0.inputBookmark) }
    ) { [weak self] in await self?.reconcile() }
  }
  func stop() async {
    stopping = true
    task?.cancel()
    task = nil
    events = nil
    while busy { try? await Task.sleep(for: .milliseconds(100)) }
    save()
  }
  func save() {
    do {
      try JSONEncoder().encode(AutomationLedger(recipes: recipes)).write(
        to: ledger, options: .atomic)
    } catch { message = "Could not save automation state: \(error.localizedDescription)" }
  }
  func beginEditing(_ id: UUID) {
    editingRecipeIDs.insert(id)
    refreshEvents()
  }
  func cancelEditing(_ id: UUID) {
    editingRecipeIDs.remove(id)
    refreshEvents()
  }
  /// Commit all editable properties together, retaining jobs/counters that may have finished meanwhile.
  @discardableResult func commitEditedRecipe(_ draft: AutomationRecipe) -> Bool {
    guard let i = recipes.firstIndex(where: { $0.id == draft.id }) else { message = "This automation is no longer available."; return false }
    var value = draft
    let current = recipes[i]
    value.history = current.history; value.pending = current.pending; value.failures = current.failures
    value.completed = current.completed; value.lastActivity = current.lastActivity; value.error = current.error
    value.enabled = false
    var updated = recipes; updated[i] = value
    do {
      try JSONEncoder().encode(AutomationLedger(recipes: updated)).write(to: ledger, options: .atomic)
      recipes = updated
      editingRecipeIDs.remove(draft.id)
      refreshEvents()
      message = "Saved automation. Monitoring is paused; choose Enable when ready."
      return true
    } catch { message = "Could not save automation: " + error.localizedDescription; return false }
  }
  func resolve(_ data: Data?) throws -> URL {
    guard let data else { throw ProcessingError.destination }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
      bookmarkDataIsStale: &stale)
    guard !stale else { throw CocoaError(.fileReadNoPermission) }
    return url
  }
  func choose(_ id: UUID, input: Bool) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    guard panel.runModal() == .OK, let url = panel.url,
      let i = recipes.firstIndex(where: { $0.id == id })
    else { return }
    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
      if input {
        recipes[i].inputBookmark = data
        recipes[i].inputLabel = url.lastPathComponent
      } else {
        recipes[i].outputBookmark = data
        recipes[i].outputLabel = url.lastPathComponent
      }
      recipes[i].enabled = false
      refreshEvents()
      save()
    } catch { message = error.localizedDescription }
  }
  func validate(_ recipe: AutomationRecipe) throws -> (URL, URL) {
    if !recipe.resizeEnabled
      && (recipe.configuration.crop.framing == .smart
        || recipe.configuration.crop.framing == .keepSubjects)
    {
      throw NSError(
        domain: "Framepebble", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Enable Resize / Canvas to use Smart or Keep Subjects framing."
        ])
    }
    let input = try resolve(recipe.inputBookmark)
    let output = try resolve(recipe.outputBookmark)
    guard !AutomationSafety.overlaps(input, output) else {
      throw NSError(
        domain: "Framepebble", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Input and output folders must not overlap."])
    }
    for other in recipes where other.id != recipe.id {
      if let otherInput = try? resolve(other.inputBookmark),
        AutomationSafety.overlaps(output, otherInput)
      {
        throw NSError(
          domain: "Framepebble", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Output overlaps another automation input; this could create a loop."
          ])
      }
      if let otherOutput = try? resolve(other.outputBookmark),
        AutomationSafety.overlaps(input, otherOutput)
      {
        throw NSError(
          domain: "Framepebble", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Input overlaps another automation output."])
      }
    }
    return (input, output)
  }
  func toggle(_ id: UUID) {
    guard let i = recipes.firstIndex(where: { $0.id == id }) else { return }
    if recipes[i].enabled {
      recipes[i].enabled = false
      refreshEvents()
      save()
      return
    }
    Task {
      do {
        _ = try validate(recipes[i])
        if !recipes[i].processExisting && recipes[i].lastActivity == nil {
          let input = try resolve(recipes[i].inputBookmark)
          let access = input.startAccessingSecurityScopedResource()
          defer { if access { input.stopAccessingSecurityScopedResource() } }
          for file in try await scanner.existing(recipes[i], input: input) {
            recipes[i].history.insert(try await scanner.digest(file))
          }
          recipes[i].lastActivity = Date()
        }
        recipes[i].enabled = true
        recipes[i].error = nil
        refreshEvents()
        save()
      } catch {
        recipes[i].error = error.localizedDescription
        save()
      }
    }
  }
  func reconcile(force: UUID? = nil) async {
    guard !busy, !stopping else { return }
    busy = true
    defer { busy = false }
    for recipe in recipes where (recipe.enabled || recipe.id == force) && !editingRecipeIDs.contains(recipe.id) {
      guard let i = recipes.firstIndex(where: { $0.id == recipe.id }) else { continue }
      do {
        let (input, output) = try validate(recipe)
        let a = input.startAccessingSecurityScopedResource()
        let b = output.startAccessingSecurityScopedResource()
        defer {
          if a { input.stopAccessingSecurityScopedResource() }
          if b { output.stopAccessingSecurityScopedResource() }
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: output.path, isDirectory: &directory),
          directory.boolValue
        else { throw ProcessingError.destination }
        for file in try await scanner.candidates(recipe, input: input) {
          guard !stopping else { break }
          try Task.checkCancellation()
          guard !editingRecipeIDs.contains(recipe.id), recipes.contains(where: { $0.id == recipe.id && ($0.enabled || $0.id == force) })
          else { break }
          let digest = try await scanner.digest(file)
          guard !recipes[i].history.contains(digest),
            !recipes[i].pending.contains(where: { $0.digest == digest }),
            !recipes[i].failures.contains(where: { $0.digest == digest })
          else { continue }
          let before = try SourceFingerprint.read(file)
          let source: SourceAsset
          do { source = try await processor.importSnapshot(file, to: root) } catch {
            var job = AutomationJob(
              source: SourceAsset(url: file), digest: digest, configuration: recipe.configuration)
            job.error = error.localizedDescription
            recipes[i].failures.append(job)
            save()
            continue
          }
          let after = try SourceFingerprint.read(file)
          guard before == after, try await scanner.digest(source.url) == digest else {
            try? FileManager.default.removeItem(at: source.url)
            continue
          }
          let sourceImage = CGImageSourceCreateWithURL(source.url as CFURL, nil)
          let sourceType = sourceImage.flatMap { CGImageSourceGetType($0) } as String?
          let sourceFormat = OutputFormat.allCases.first { $0.typeIdentifier == sourceType }
          let config: ProcessingConfiguration
          do { config = try recipe.processingConfiguration(sourceFormat: sourceFormat) } catch {
            var failed = AutomationJob(
              source: source, digest: digest, configuration: recipe.configuration)
            failed.error = error.localizedDescription
            recipes[i].failures.append(failed)
            save()
            continue
          }
          recipes[i].lastActivity = Date()
          var job = AutomationJob(source: source, digest: digest, configuration: config)
          do {
            if recipe.configuration.crop.framing == .smart
              || recipe.configuration.crop.framing == .keepSubjects
            {
              let image = try await processor.analysisThumbnail(
                source.url, configuration: job.configuration, maximum: 900)
              let proposal = try await analyzer.frame(
                image, ratio: Double(job.configuration.width) / Double(job.configuration.height),
                mode: job.configuration.crop.framing)
              job.configuration.crop = job.configuration.crop.adoptingGeometry(proposal.crop)
              if proposal.needsReview {
                recipes[i].pending.append(job)
                save()
                continue
              }
            }
            if recipe.mode == .review || recipe.privacyReview {
              recipes[i].pending.append(job)
            } else {
              _ = try await processor.export(
                source, configuration: job.configuration, to: output, profile: recipe.profile)
              recipes[i].history.insert(digest)
              recipes[i].completed += 1
              try? FileManager.default.removeItem(at: source.url)
            }
          } catch {
            job.error = error.localizedDescription
            recipes[i].failures.append(job)
          }
          recipes[i].lastActivity = Date()
          save()
        }
        recipes[i].error = nil
      } catch { recipes[i].error = error.localizedDescription }
      save()
    }
  }
  func approve(_ recipeID: UUID, job: AutomationJob) {
    approvalTask = Task {
      guard !busy, let i = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
      busy = true
      defer { busy = false }
      do {
        let (input, output) = try validate(recipes[i])
        let inputAccess = input.startAccessingSecurityScopedResource()
        let scoped = output.startAccessingSecurityScopedResource()
        defer {
          if scoped { output.stopAccessingSecurityScopedResource() }
          if inputAccess { input.stopAccessingSecurityScopedResource() }
        }
        _ = try await processor.export(
          job.source, configuration: job.configuration, to: output, profile: recipes[i].profile)
        recipes[i].pending.removeAll { $0.id == job.id }
        recipes[i].failures.removeAll { $0.id == job.id }
        recipes[i].history.insert(job.digest)
        recipes[i].completed += 1
        try? FileManager.default.removeItem(at: job.source.url)
        save()
      } catch { message = error.localizedDescription }
    }
  }
  func test(_ id: UUID) async -> CGImage? {
    guard let recipe = recipes.first(where: { $0.id == id }) else { return nil }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = ImageProcessor.importTypes
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)
      let type = source.flatMap { CGImageSourceGetType($0) } as String?
      var c = try recipe.processingConfiguration(
        sourceFormat: OutputFormat.allCases.first { $0.typeIdentifier == type })
      if c.crop.framing == .smart || c.crop.framing == .keepSubjects {
        let image = try await processor.analysisThumbnail(url, configuration: c, maximum: 900)
        let proposal = try await analyzer.frame(
          image, ratio: Double(c.width) / Double(c.height), mode: c.crop.framing)
        c.crop = c.crop.adoptingGeometry(proposal.crop)
      }
      return try await processor.render(url, configuration: c, previewMaximum: 1000)
    } catch {
      message = error.localizedDescription
      return nil
    }
  }
}
struct AutomationDashboard: View {
  @Bindable var automations: Automations
  var embedded = false
  @State private var editing: UUID?
  @State private var preview: CGImage?
  @State private var deleting: UUID?
  @State private var dashboardSection = "Workflows"
  @State private var selectedRecipe: UUID?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("Automation view", selection: $dashboardSection) {
            Text("Workflows").tag("Workflows")
            Text("Pending Reviews").tag("Pending Reviews")
            Text("Failed Jobs").tag("Failed Jobs")
          }.pickerStyle(.segmented)
          Text(automations.message).font(.caption)
          Button("New Automation") {
            let recipe = AutomationRecipe()
            automations.recipes.append(recipe); selectedRecipe = recipe.id
            automations.save()
          }
        }
        Section("Workflows") {
          ForEach(automations.recipes.filter { dashboardSection == "Workflows" || (dashboardSection == "Pending Reviews" ? !$0.pending.isEmpty : !$0.failures.isEmpty) }) { recipe in
            Button { selectedRecipe = recipe.id; preview = nil } label: {
              HStack {
                Label(recipe.name, systemImage: recipe.enabled ? "circle.fill" : "pause.circle")
                Spacer()
                Text("\(recipe.pending.count) pending · \(recipe.failures.count) failed").font(.caption).foregroundStyle(.secondary)
                if selectedRecipe == recipe.id { Image(systemName: "checkmark") }
              }
            }.buttonStyle(.plain)
          }
        }
        ForEach(automations.recipes.filter { $0.id == selectedRecipe }) { recipe in
          recipeDetail(recipe)
        }
        if let preview {
          Section("Test preview — nothing written to destination") {
            Image(decorative: preview, scale: 1).resizable().scaledToFit().frame(maxHeight: 320)
          }
        }
      }.onAppear { if selectedRecipe == nil { selectedRecipe = automations.recipes.first?.id } }
        .buttonStyle(.bordered).navigationTitle("Automations").toolbar {
        if !embedded { Button("Done") { dismiss() } }
      }.sheet(
        item: Binding(get: { editing.map { RecipeSelection(id: $0) } }, set: { editing = $0?.id })
      ) { selection in AutomationEditor(automations: automations, id: selection.id) }.alert(
        "Delete automation?",
        isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
      ) {
        Button("Delete", role: .destructive) {
          automations.recipes.removeAll { $0.id == deleting }
          automations.refreshEvents()
          automations.save()
          deleting = nil
        }
        Button("Cancel", role: .cancel) { deleting = nil }
      } message: {
        Text("Monitoring stops. Original and exported images remain unchanged.")
      }
    }
    .frame(minWidth: 600, minHeight: 600)
  }
  private func recipeDetail(_ recipe: AutomationRecipe) -> some View {
          Section(recipe.name) {
            Label(
              recipe.error != nil ? "Needs attention" : recipe.enabled ? "Monitoring" : "Paused",
              systemImage: recipe.enabled ? "circle.fill" : "pause.circle")
            Text("Input: \(recipe.inputLabel) → Output: \(recipe.outputLabel)")
            Text(recipe.mode == .automatic ? "Publication: Automatic" : "Publication: Review Before Export").font(.caption.weight(.semibold))
            Text(
              "\(recipe.completed) completed · \(recipe.pending.count) pending · \(recipe.failures.count) failed"
            ).font(.caption)
            if let date = recipe.lastActivity {
              Text("Last activity: \(date.formatted())").font(.caption).foregroundStyle(.secondary)
            }
            if let error = recipe.error { Text(error).foregroundStyle(.orange) }
            HStack {
              Button(recipe.enabled ? "Pause" : "Enable") { automations.toggle(recipe.id) }
              Button("Edit") { editing = recipe.id }
              Button("Process Eligible Photos") { Task { await automations.reconcile(force: recipe.id) } }
              Button("Test Preview") { Task { preview = await automations.test(recipe.id) } }
            }.disabled(automations.busy)
            HStack {
              Button("Duplicate") {
                var copy = recipe
                copy.id = UUID()
                copy.name += " Copy"
                copy.enabled = false
                copy.history = []
                copy.pending = []
                copy.failures = []
                copy.completed = 0
                automations.recipes.append(copy)
                automations.save()
              }
              Button("Delete", role: .destructive) { deleting = recipe.id }.disabled(
                automations.busy)
            }
            ForEach(dashboardSection == "Pending Reviews" ? recipe.pending : dashboardSection == "Failed Jobs" ? recipe.failures : recipe.pending + recipe.failures) { job in
              DisclosureGroup((job.error == nil ? "Pending review · " : "Failed · ") + job.source.name) {
                AutomationReviewPreview(automations: automations, job: job)
                Button(job.error == nil ? "Approve export" : "Retry export") {
                  automations.approve(recipe.id, job: job)
                }
                Button("Exclude from workflow") {
                  if let i = automations.recipes.firstIndex(where: { $0.id == recipe.id }) {
                    automations.recipes[i].history.insert(job.digest)
                    automations.recipes[i].pending.removeAll { $0.id == job.id }
                    automations.recipes[i].failures.removeAll { $0.id == job.id }
                    automations.save()
                  }
                }
              }.disabled(automations.busy)
            }
          }
  }

}
struct RecipeSelection: Identifiable { let id: UUID }
struct AutomationEditor: View {
  @Bindable var automations: Automations
  let id: UUID
  @State private var workspace = Workspace(
    directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Framepebble/RecipeEditing", isDirectory: true))
  @Environment(\.dismiss) private var dismiss
  @State private var draft: AutomationRecipe
  @State private var saveError: String?
  private let wasEnabled: Bool
  init(automations: Automations, id: UUID) {
    self.automations = automations; self.id = id
    let saved = automations.recipes.first { $0.id == id } ?? AutomationRecipe()
    _draft = State(initialValue: saved); wasEnabled = saved.enabled
  }
  var recipe: Binding<AutomationRecipe> { Binding(get: { draft }, set: { draft = $0 }) }
  func chooseFolder(input: Bool) {
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
      if input { draft.inputBookmark = bookmark; draft.inputLabel = url.lastPathComponent }
      else { draft.outputBookmark = bookmark; draft.outputLabel = url.lastPathComponent }
    } catch { saveError = error.localizedDescription }
  }
  var body: some View {
    NavigationStack {
      VStack {
        Form {
          TextField("Name", text: recipe.name)
          Button("Input: \(recipe.inputLabel.wrappedValue)") { chooseFolder(input: true) }
          Button("Output: \(recipe.outputLabel.wrappedValue)") {
            chooseFolder(input: false)
          }
          Toggle("Include subfolders", isOn: recipe.recursive)
          Toggle("Process existing images", isOn: recipe.processExisting)
          Picker("Mode", selection: recipe.mode) {
            ForEach(AutomationMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          Toggle("Require manual privacy review", isOn: recipe.privacyReview)
          Toggle("Resize / Canvas", isOn: recipe.resizeEnabled)
          Toggle("Convert format", isOn: recipe.convertEnabled)
          Toggle("Compression", isOn: recipe.compressionEnabled)
          Toggle("Watermark", isOn: recipe.watermarkEnabled)
          Toggle("Metadata action", isOn: recipe.metadataEnabled)
          Picker(
            "Automatic framing",
            selection: Binding(
              get: { workspace.settings.crop.framing },
              set: { workspace.settings.crop.framing = $0 })
          ) {
            Text("Centre").tag(FramingMode.centre)
            Text("Smart").tag(FramingMode.smart)
            Text("Keep Subjects").tag(FramingMode.keepSubjects)
          }
          TextField("Naming template", text: recipe.profile.namingTemplate)
          Text(
            "Changes are not saved until Save. Monitoring is suspended while editing. Save keeps it paused; Cancel restores the saved recipe and its previous monitoring state. Review-required jobs still need approval."
          ).font(.caption)
          if let saveError { Text(saveError).foregroundStyle(.orange) }
        }.formStyle(.grouped).frame(minHeight: 200, idealHeight: 300, maxHeight: 350)
        SettingsEditor(model: workspace, recipeEditing: true)
      }.navigationTitle("Automation Recipe").toolbar {
        Button(wasEnabled ? "Cancel & Resume" : "Cancel") { automations.cancelEditing(id); dismiss() }
        Button("Save & Keep Paused") {
          draft.configuration = workspace.settings
          if automations.commitEditedRecipe(draft) { dismiss() }
          else { saveError = automations.message }
        }
      }.onAppear {
        workspace.settings = draft.configuration
        automations.beginEditing(id)
      }.onDisappear { automations.cancelEditing(id); workspace.persistenceTask?.cancel() }
        .interactiveDismissDisabled()
    }.frame(minWidth: 560, minHeight: 600)
  }
}

struct AutomationReviewPreview: View {
  let automations: Automations
  let job: AutomationJob
  @State private var revealed = false
  @State private var image: CGImage?
  @State private var error: String?
  var body: some View {
    VStack {
      if revealed, let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 280)
      } else {
        Image(systemName: "eye.slash").font(.title).frame(height: 100)
      }
      Button(revealed ? "Conceal preview" : "Show processed preview") { revealed.toggle() }
      if let error { Text(error).font(.caption).foregroundStyle(.orange) }
    }
    .task {
      do {
        image = try await automations.processor.render(
          job.source.url, configuration: job.configuration, previewMaximum: 600)
      } catch { self.error = error.localizedDescription }
    }
  }
}
