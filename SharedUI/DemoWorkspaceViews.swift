import SwiftUI

struct DemoWorkspaceButton: View {
    @Bindable var model: Workspace
    var body: some View {
        if !model.isDemoWorkspace {
            Button(model.switchingDemo ? "Opening Demo Workspace…" : "Open Demo Workspace", systemImage: "photo.on.rectangle") {
                Task { await model.openDemoWorkspace() }
            }.disabled(!model.canSwitchDemoWorkspace)
              .accessibilityIdentifier("workspace.openDemo")
              .help("Try the generated sample photos in a separate editing workspace")
        }
    }
}

private struct WorkspaceOwnerKey: EnvironmentKey {
    static let defaultValue: Workspace? = nil
}
extension EnvironmentValues {
    var workspaceOwner: Workspace? {
        get { self[WorkspaceOwnerKey.self] }
        set { self[WorkspaceOwnerKey.self] = newValue }
    }
}

/// Workspace switching belongs to the gallery, never the photo's editing toolbar.
struct WorkspaceSwitcherButton: View {
    @Bindable var model: Workspace
    var body: some View {
        Button { model.presentWorkspaceSwitcher() } label: {
            HStack(spacing: 5) {
                Text(model.isDemoWorkspace ? "Demo Workspace" : model.projectName).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.headline)
        }.buttonStyle(.plain).accessibilityLabel("Switch workspace")
          .accessibilityValue(model.isDemoWorkspace ? "Demo Workspace" : model.projectName)
          .accessibilityIdentifier("workspace.switcher")
          .disabled(!model.canSwitchDemoWorkspace || model.gifSelectionContext != nil)
    }
}
