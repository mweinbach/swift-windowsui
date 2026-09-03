import Foundation
import WinSwiftUI

struct WorkbenchRoot: View {
    @ObservedObject var model: WorkbenchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("gpu-workbench-mark", bundle: .module)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("GPU Workbench bundled mark")
                VStack(alignment: .leading, spacing: 4) {
                    Text("GPU Workbench").font(.title)
                    Text("Renderer requested: Direct3D 11. Actual backend requires diagnostics.")
                        .font(.caption)
                }
            }
            SessionCounterCard(parentRevision: model.parentRevision)
            Button("Rebuild parent") { model.rebuildParent() }
                .accessibilityIdentifier("workbench.rebuild")
            TabView(selection: $model.selectedPage) {
                dashboard
                    .tabItem { Text("Dashboard") }
                    .tag(0)
                settings
                    .tabItem { Text("Settings") }
                    .tag(1)
            }
            HStack {
                Button("Show dashboard") { model.selectedPage = 0 }
                    .accessibilityIdentifier("workbench.dashboard")
                Button("Show settings") { model.selectedPage = 1 }
                    .accessibilityIdentifier("workbench.settings")
            }
            Text(model.status).accessibilityIdentifier("workbench.status")
            if let error = model.errorMessage {
                Text(error).foregroundStyle(Color.red)
                    .accessibilityIdentifier("workbench.error")
            }
        }
        .padding(24)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current draft: \(model.displayName)")
                .accessibilityIdentifier("workbench.draftSummary")
            if model.showSavedProfileDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved profile details").font(.headline)
                    Text("Saved profile: \(model.savedPreferences.displayName)")
                        .accessibilityIdentifier("workbench.savedSummary")
                }
                .accessibilityIdentifier("workbench.savedDetails")
            }
            Text("Edit a profile in Settings, save it, and restart to verify persistence.")
        }
        .padding(16)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Display name", text: $model.displayName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("workbench.displayName")
            Toggle("Show saved profile details", isOn: $model.showSavedProfileDetails)
                .accessibilityIdentifier("workbench.showSavedDetails")
            HStack {
                Button("Save settings") { model.save() }
                    .accessibilityIdentifier("workbench.save")
                Button("Reload saved settings") { model.reload() }
                    .accessibilityIdentifier("workbench.reload")
            }
            Text("Reload replaces the draft only after a valid saved file is read.")
                .font(.caption)
        }
        .padding(16)
    }
}

private struct SessionCounterCard: View {
    let parentRevision: Int
    @State private var count = 0

    var body: some View {
        HStack(spacing: 16) {
            Text("Local count: \(count)")
                .accessibilityIdentifier("workbench.localCount")
            Button("Increment local counter") { count += 1 }
                .accessibilityIdentifier("workbench.increment")
            Text("Parent rebuilds: \(parentRevision)")
        }
    }
}
