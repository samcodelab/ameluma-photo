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

struct DemoWorkspaceMenu: View {
    @Bindable var owner: Workspace
    var body: some View {
        if let demo = owner.demoWorkspace {
            Menu {
                Text("Demo Workspace · generated sample photos")
                Text("Edits are saved separately from your workspace.")
                Divider()
                Button("Return to Your Workspace", systemImage: "arrow.uturn.backward") {
                    Task { await owner.returnFromDemoWorkspace() }
                }.disabled(!demo.canSwitchDemoWorkspace)
                if !demo.canSwitchDemoWorkspace {
                    Text("Finish or cancel the current edit or operation before returning.")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Demo").font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }.accessibilityLabel("Demo Workspace and return options")
              .help("Generated sample photos · your workspace is kept separately")
        }
    }
}
