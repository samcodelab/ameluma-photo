import FramepebbleCore
import SwiftUI

/// The timeline is shared by batch settings and individual photo edits.
struct EditingHistoryView: View {
  @Bindable var model: Workspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
        Text("Choose a step to restore batch and photo edits.")
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Section {
          Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
            .disabled(!model.canUndo || model.running || model.analysing || model.overlayEditor)
          Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
            .disabled(!model.canRedo || model.running || model.analysing || model.overlayEditor)
        }
        Section("Edit steps") {
          ForEach(Array(model.history.steps.enumerated()), id: \.element.id) { index, step in
            Button { model.moveEditingHistory(to: step.id) } label: {
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: step.isCurrent ? "checkmark.circle.fill" : step.isRedo ? "arrow.uturn.forward.circle" : "circle")
                  .foregroundStyle(step.isCurrent ? Color.accentColor : Color.secondary)
                Text("\(index + 1). " + step.title).frame(maxWidth: .infinity, alignment: .leading)
                if step.isCurrent { Text("Current").font(.caption).foregroundStyle(.secondary) }
              }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
              .foregroundStyle(step.isRedo ? Color.secondary : Color.primary)
              .accessibilityValue(step.isCurrent ? "Current state" : step.isRedo ? "Available to redo" : "Previous state")
              .disabled(model.running || model.analysing || model.overlayEditor)
          }
        }
        Section {
        Text("Grey steps can be redone until you make a new edit. This timeline is shared across photos and batch settings. Current session · up to 80 Undo steps. Saved edits survive reopening; Undo history starts again when a project opens. Imports, export files, collages and automations are outside this photo-edit timeline.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }.navigationTitle("Undo History").compactNavigationTitle().toolbar {
        Button("Done") { dismiss() }
      }
    }.background(.background)
    #if os(macOS)
      .frame(minWidth: 480, idealWidth: 620, minHeight: 440, idealHeight: 620)
    #endif
  }
}
