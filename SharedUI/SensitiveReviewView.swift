import FramepebbleCore
import SwiftUI

struct SensitiveReviewView: View {
  @Bindable var model: Workspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section("Optional on-device check") {
          Text(
            "Find photos that may need privacy editing. Checks inspect originals. Automatic checks can miss content or flag ordinary photos; they do not locate areas to cover."
          ).font(.callout)
          if case .unavailable(let reason) = model.sensitivityAvailability {
            Text(reason).font(.caption).foregroundStyle(.secondary)
          }
          HStack {
            Button("Check all photos") {
              model.sensitivityStatus = ""
              model.scanSensitiveImages()
            }
            Button("Check selected") {
              model.sensitivityStatus = ""
              model.scanSensitiveImages(selectedOnly: true)
            }.disabled(model.selection.isEmpty)
          }.disabled(
            !model.sensitivityAvailability.canAnalyze || model.sensitivityTask != nil
              || model.workspaceAssets.isEmpty)
          if model.sensitivityTask != nil {
            ProgressView(
              value: Double(model.sensitivityCompleted),
              total: Double(max(1, model.sensitivityTotal)))
            Button("Cancel check") { model.sensitivityTask?.cancel() }
          }
          if !model.sensitivityStatus.isEmpty { Text(model.sensitivityStatus).font(.caption) }
          Button("Show flagged photos (\(model.sensitivity.flagged.count))") {
            model.library = .privacyReview
            model.query = ""
            dismiss()
          }
          Button("Clear temporary review flags") { model.clearSensitivityReview() }
          Text(
            "Flags and reveal choices stay in memory for this session and are not saved in projects."
          ).font(.caption).foregroundStyle(.secondary)
        }
        Section("Manual review and editing") {
          ForEach(model.workspaceAssets) { asset in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                FramingSurface(model: model, asset: asset, interactive: false, maximum: 240).frame(
                  width: 90, height: 90)
                VStack(alignment: .leading) {
                  Text(asset.name).lineLimit(1)
                  if model.sensitivity.findings[asset.id]?.sensitive == true {
                    Label("May contain sensitive content", systemImage: "exclamationmark.shield")
                      .font(.caption)
                  }
                  Toggle(
                    "Flag for privacy review",
                    isOn: Binding(
                      get: { model.sensitivity.manual.contains(asset.id) },
                      set: { model.sensitivity.mark(asset.id, forReview: $0) }))
                }
              }
              HStack {
                Button("Reveal & Edit with Privacy Tool", systemImage: "eye.slash") {
                  model.openPrivacyEditor(.overlays, asset: asset)
                }
                Button("Reveal & Crop", systemImage: "crop") {
                  model.openPrivacyEditor(.framing, asset: asset)
                }
              }.buttonStyle(.bordered)
            }.padding(.vertical, 4)
          }
        }
      }.navigationTitle("Privacy Review").compactNavigationTitle().toolbar {
        Button("Done") { dismiss() }
      }
      .task { model.sensitivityAvailability = await model.sensitiveAnalyzer.availability() }
    }
    #if os(macOS)
      .frame(minWidth: 560, minHeight: 500)
    #endif
  }
}
struct SensitivePreviewCover: View {
  @Bindable var model: Workspace
  let ids: Set<UUID>
  var body: some View {
    if ids.contains(where: { model.sensitivity.concealed($0) }) {
      Rectangle().fill(.background).overlay {
        GeometryReader { geometry in
          if geometry.size.width < 140 || geometry.size.height < 140 {
            Button {
              model.sensitivity.revealed.formUnion(ids)
            } label: {
              Label("Show", systemImage: "eye.slash").font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Show photo that may be private")
          } else {
            VStack(spacing: 8) {
              Image(systemName: "eye.slash").font(.title2)
              Text("This photo may be private").font(.caption).multilineTextAlignment(.center)
              if case .available(descriptiveInterventions: true) = model.sensitivityAvailability {
                Text(
                  "You don't have to view it. If it makes you uncomfortable, close this view and talk to someone you trust."
                ).font(.caption).multilineTextAlignment(.center)
              }
              Button("Show photo") { model.sensitivity.revealed.formUnion(ids) }.buttonStyle(
                .bordered)
            }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }.accessibilityElement(children: .contain)
    }
  }
}
