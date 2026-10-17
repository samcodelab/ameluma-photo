import SwiftUI

/// Pinned outside the photo scroll view, including when the Mac inspector is hidden.
struct ImportProgressView: View {
  @Bindable var model: Workspace
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(model.importMessage).font(.callout).lineLimit(1)
        Spacer()
        if model.hasHiddenWorkspaceFilters {
          Button("Show arriving images") {
            model.showAllWorkspacePhotos()
          }
        }
        Button("Cancel import") { model.cancelImport() }
      }
      if model.importSize > 0 {
        ProgressView(value: Double(model.importBytes), total: Double(model.importSize))
          .accessibilityLabel("Current file copy")
        Text(
          "\(ByteCountFormatter.string(fromByteCount: model.importBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: model.importSize, countStyle: .file)) · \(model.importCompleted) imported · \(model.importSkipped) skipped · \(model.importFailed) failed"
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        HStack {
          ProgressView().controlSize(.small)
          Text(
            "\(model.importCompleted) imported · \(model.importSkipped) skipped · \(model.importFailed) failed. You can edit completed images now."
          ).font(.caption).foregroundStyle(.secondary)
        }
      }
    }.padding(12).background(.regularMaterial)
  }
}
