import SwiftUI

#Preview {
    SettingsView()
        .environment({
            let s = AppSettings()
            return s
        }())
        .environment(AppModel())
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if settings.canChooseMLX {
                    mlxSection
                }

                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var mlxSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.preferMLX },
                set: { model.switchBackend(preferMLX: $0) }
            )) {
                Label("Use Local MLX Model", systemImage: "cpu")
            }
            .disabled(model.isGenerating)
        } header: {
            Text("AI Backend")
        } footer: {
            Text(settings.preferMLX
                 ? "Running Llama 3.2 1B on-device — fully private, no internet required after the initial ~700 MB download."
                 : "Using Apple Intelligence (Foundation Models) — fast, on-device, and always available on iOS 26+.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
