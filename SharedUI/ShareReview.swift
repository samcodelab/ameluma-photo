import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#else
  import UIKit
  import Photos
#endif
/// Every external handoff in this view uses already validated final outputs, never source URLs.
struct ShareReview: View {
  let urls: [URL]
  var summary = ""
  var analyzer: any SensitiveImageAnalyzing = AppleSensitiveAnalyzer()
  @State private var capability: SensitiveAnalysisAvailability = .unavailable(
    "Checking capability…")
  @State private var checkBeforeSharing = false
  @State private var checked = false
  @State private var checking = false
  @State private var flagged: Set<URL> = []
  @State private var checkTask: Task<Void, Never>?
  @State private var checkProgress = 0
  private let checkProcessor = ImageProcessor()
  @State private var session = ShareReviewSession(outputs: [])
  @State private var status = ""
  @State private var choosingFolder = false
  @State private var copying = false
  @State private var copyTask: Task<Void, Never>?
  @State private var copiedURLs: [URL] = []
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        if !summary.isEmpty { Section("This export") { Text(summary).font(.caption) } }
        Section {
          Text("Review before sharing").font(.headline)
          Text(
            "Review the final images and exclude anything you do not want to share. An optional on-device check can flag sensitive content when the system allows it. Unflagged images are not guaranteed safe."
          ).font(.caption)
        }
        Section("Optional sensitive-content check") {
          if case .unavailable(let reason) = capability {
            Text(reason).font(.caption).foregroundStyle(.secondary)
          }
          Toggle("Check before sharing", isOn: $checkBeforeSharing).disabled(
            !capability.canAnalyze || checking)
          if checkBeforeSharing {
            Button("Check final images") { scanOutputs() }.disabled(checking)
            if checking {
              ProgressView(value: Double(checkProgress), total: Double(max(1, urls.count)))
              Button("Cancel check") { checkTask?.cancel() }
            }
            if !checked {
              Button("Continue with manual review") {
                checkTask?.cancel()
                checkBeforeSharing = false
              }
            }
          }
          if !status.isEmpty { Text(status).font(.caption) }
          if !flagged.isEmpty {
            Label(
              "Some photos may be private (\(flagged.count))", systemImage: "exclamationmark.shield"
            ).foregroundStyle(.orange)
          }
        }
        ForEach(urls, id: \.self) { url in
          HStack {
            OutputThumbnail(url: url, revealed: session.revealed.contains(url))
            VStack(alignment: .leading) {
              if flagged.contains(url) {
                Label("May contain sensitive content", systemImage: "exclamationmark.shield").font(
                  .caption)
              }
              Button(session.revealed.contains(url) ? "Conceal preview" : "Show final image") {
                if !session.revealed.insert(url).inserted { session.revealed.remove(url) }
              }
              Toggle(
                "Include",
                isOn: Binding(
                  get: { session.included.contains(url) }, set: { session.include(url, $0) }))
            }
          }
        }
        Section {
          Button("Approve selected images") { session.approve() }.disabled(
            session.included.isEmpty || checking || (checkBeforeSharing && !checked))
          if !session.approvedOutputs.isEmpty && !checking && (!checkBeforeSharing || checked) {
            let chosen = session.approvedOutputs
            Button("Export Reviewed Files…", systemImage: "folder") { choosingFolder = true }.disabled(copying)
            if copying {
              ProgressView("Publishing reviewed files…")
              Button("Cancel File Export") { copyTask?.cancel() }
            }
            ShareLink(items: chosen) {
              Label("Share reviewed outputs", systemImage: "square.and.arrow.up")
            }
            #if os(iOS)
              Button("Save reviewed images to Photos") {
                Task {
                  do {
                    let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    guard permission == .authorized || permission == .limited else {
                      status = "Photo additions permission is required."
                      return
                    }
                    for url in chosen { try await PhotoLibraryExporter.save(url) }
                    status = "Saved \(chosen.count) reviewed images."
                  } catch { status = error.localizedDescription }
                }
              }
            #endif
            if !status.isEmpty { Text(status) }
            if let first = chosen.first {
              Button("Copy processed image") { copy(first) }
              #if os(macOS)
                Button("Reveal in Finder") {
                  NSWorkspace.shared.activateFileViewerSelecting(chosen)
                }
              #endif
            }
          }
        }
      }.navigationTitle("Prepare to Share").compactNavigationTitle().toolbar {
        Button("Done") { dismiss() }
      }.onAppear { session = ShareReviewSession(outputs: urls) }
        .task { capability = await analyzer.availability() }
        .onChange(of: checkBeforeSharing) { _, _ in
          checked = false
          session.revokeApproval()
        }
        .onDisappear { checkTask?.cancel(); copyTask?.cancel() }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
          switch result {
          case .success(let folder): copyReviewed(to: folder)
          case .failure(let error): status = "Destination selection failed: " + error.localizedDescription
          }
        }
    }.frame(minWidth: 320, minHeight: 440)
  }
  func copyReviewed(to folder: URL) {
    let approved = session.approvedOutputs
    guard !copying, !approved.isEmpty else { return }
    copying = true; copiedURLs = []
    copyTask = Task {
      let access = folder.startAccessingSecurityScopedResource()
      defer { if access { folder.stopAccessingSecurityScopedResource() }; copying = false }
      do {
        for url in approved {
          try Task.checkCancellation()
          let output = try await checkProcessor.copyValidatedOutput(url, to: folder)
          copiedURLs.append(output)
          status = "Exported \(copiedURLs.count) of \(approved.count) reviewed files. Existing files and originals are unchanged."
        }
      } catch is CancellationError {
        status = "Export cancelled. \(copiedURLs.count) completed files remain in your selected folder."
      } catch {
        status = "Export stopped after \(copiedURLs.count) completed files: " + error.localizedDescription
      }
    }
  }
  func scanOutputs() {
    guard !checking else { return }
    checking = true
    checked = false
    checkProgress = 0
    flagged = []
    session.revokeApproval()
    checkTask = Task {
      defer { checking = false }
      let availability = await analyzer.availability()
      capability = availability
      guard availability.canAnalyze else { return }
      var failed = false
      for url in urls {
        if Task.isCancelled { return }
        do {
          let image = try await checkProcessor.analysisThumbnail(
            url, configuration: ProcessingConfiguration(), maximum: 1200)
          let sensitive = try await analyzer.analyze(image)
          try Task.checkCancellation()
          if sensitive {
            flagged.insert(url)
            session.revealed.remove(url)
          }
        } catch is CancellationError { return } catch { failed = true }
        checkProgress += 1
      }
      checked = !failed
      status =
        failed
        ? "Some files could not be checked. Retry or continue with manual review."
        : "Check complete. Review flagged photos before approving."
    }
  }
  func copy(_ url: URL) {
    #if os(macOS)
      guard let image = NSImage(contentsOf: url) else {
        status = "The processed image could not be copied."
        return
      }
      NSPasteboard.general.clearContents()
      if !NSPasteboard.general.writeObjects([image]) {
        status = "The clipboard rejected the processed image."
      } else {
        status = "Processed image copied."
      }
    #else
      do {
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else {
          status = "The processed image could not be decoded."
          return
        }
        UIPasteboard.general.image = image
        status = "Processed image copied."
      } catch { status = error.localizedDescription }
    #endif
  }
}
struct OutputThumbnail: View {
  let url: URL
  let revealed: Bool
  @State private var image: CGImage?
  var body: some View {
    Group {
      if let image, revealed {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        Image(systemName: "eye.slash").font(.title)
      }
    }.frame(width: 120, height: 100).background(
      .secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8)
    ).task { image = try? await ImageProcessor().thumbnail(url, maximum: 300) }.accessibilityLabel(
      revealed ? "Final processed preview" : "Preview concealed")
  }
}

struct ReviewedOutputs: Identifiable {
  let id = UUID()
  let urls: [URL]
}
