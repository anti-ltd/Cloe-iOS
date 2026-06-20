import SwiftUI

#Preview {
    let model = AppModel()
    return SettingsView()
        .environment(model.settings)
        .environment(model)
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showChangelog = false

    var body: some View {
        NavigationStack {
            List {
                if settings.canChooseMLX {
                    backendSection
                }

                // Model picker — shown whenever MLX is the active backend
                if model.mlxBackend != nil {
                    modelSection
                }

                voiceSection
                actionsSection
                commuteSection
                quickAccessSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showChangelog) { ChangelogView() }
        }
    }

    // MARK: - Sections

    private var backendSection: some View {
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
                 ? "Running a local model on-device — fully private, no internet required after download."
                 : "Using Apple Intelligence (Foundation Models) — fast, on-device, and always available on iOS 26+.")
        }
    }

    private var modelSection: some View {
        Section {
            ForEach(MLXModelCatalog.all) { option in
                Button {
                    guard option.isCompatible, !model.isGenerating else { return }
                    model.switchMLXModel(to: option)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(option.name)
                                    .foregroundStyle(option.isCompatible ? .primary : .secondary)
                                Text(option.tag)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Text(option.sizeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                if !option.isCompatible {
                                    Text("· A17+ required")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        if settings.selectedMLXModelID == option.id {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        } else if !option.isCompatible {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.isCompatible || model.isGenerating)
                .opacity(option.isCompatible ? 1 : 0.45)
            }
        } header: {
            Text("Local Model")
        } footer: {
            Text("Your conversation is kept when you switch models. A new model starts a download if needed.")
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.autoSpeak },
                set: { settings.autoSpeak = $0 }
            )) {
                Label("Speak Replies Aloud", systemImage: "speaker.wave.2.fill")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(model.speech.rate) },
                        set: { model.speech.rate = Float($0) }
                    ), in: 0.0...1.0)
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                }
                Button {
                    model.speech.speak("Hello, I'm Cloe. This is how I sound.")
                } label: {
                    Label("Preview Voice", systemImage: "play.circle")
                        .font(.subheadline)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Dictation Pause") {
                    Text("\(settings.dictationSilence, specifier: "%.1f")s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { settings.dictationSilence },
                        set: { settings.dictationSilence = $0 }
                    ), in: 0.4...2.0, step: 0.1)
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Tap the speaker on any reply to hear it. Enable auto-speak to read every reply. Dictation pause sets how long to wait after you stop talking before sending.")
        }
    }

    private var actionsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.enableDeviceActions },
                set: { settings.enableDeviceActions = $0 }
            )) {
                Label("Device Triggers", systemImage: "flashlight.on.fill")
            }
        } header: {
            Text("Device Control")
        } footer: {
            Text("Let Cloe control the flashlight, haptics, and screen brightness. Try: “turn on the flashlight” or “set brightness to max”.")
        }
    }

    private var commuteSection: some View {
        Section {
            TextField("Home address", text: Binding(
                get: { settings.homeAddress },
                set: { settings.homeAddress = $0 }
            ), axis: .vertical)
            .textContentType(.fullStreetAddress)
            .autocorrectionDisabled()

            TextField("Work address", text: Binding(
                get: { settings.workAddress },
                set: { settings.workAddress = $0 }
            ), axis: .vertical)
            .textContentType(.fullStreetAddress)
            .autocorrectionDisabled()
        } header: {
            Text("Commute")
        } footer: {
            Text("Used when you ask things like “I need to be at work for 8am, what time do I need to leave?”. Cloe checks your contact card first, then these. Leave blank to use only your “My Card” addresses.")
        }
    }

    private var quickAccessSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.liveActivityEnabled },
                set: { on in
                    settings.liveActivityEnabled = on
                    if on { CloeLiveActivityController.start() }
                    else { CloeLiveActivityController.end() }
                }
            )) {
                Label("Lock Screen Quick Access", systemImage: "lock.iphone")
            }
            .disabled(!CloeLiveActivityController.isSupported)
        } header: {
            Text("Quick Access")
        } footer: {
            Text(CloeLiveActivityController.isSupported
                 ? "Pin Cloe to your Lock Screen — tap to open, or tap the mic to talk hands-free. Works on any iPhone, with or without a Dynamic Island. iOS may dismiss it after a few hours; flip this back on to bring it back."
                 : "Turn on Live Activities for Cloe in the Settings app to use Lock Screen quick access.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            Button {
                showChangelog = true
            } label: {
                Label("What's New", systemImage: "sparkles")
            }
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
