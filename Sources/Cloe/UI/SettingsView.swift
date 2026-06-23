import SwiftUI
import AVFoundation
import UIKit

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
    @Environment(\.openURL) private var openURL
    @State private var showChangelog = false

    private var theme: CloeTheme { settings.visualTheme }

    var body: some View {
        CloeSheetChrome(title: "Settings", dismiss: { dismiss() }) {
            List {
                appearanceSection
                if settings.canChooseMLX { backendSection }
                if model.mlxBackend != nil { modelSection }
                voiceSection
                actionsSection
                commuteSection
                quickAccessSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
        .tint(theme.primary)
        .sheet(isPresented: $showChangelog) {
            ChangelogView().environment(settings)
        }
    }

    private var appearanceSection: some View {
        Section {
            ForEach(CloeTheme.allCases) { item in
                Button { settings.visualTheme = item } label: {
                    HStack(spacing: 14) {
                        CloeOrb(theme: item, state: .idle, size: 32, halo: false)
                        Text(item.label).foregroundStyle(.primary)
                        Spacer()
                        if settings.visualTheme == item {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(item.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Tints the orb and accents across the app.")
        }
    }

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
                 ? "Running a local model on-device — fully private after download."
                 : "Using Apple Intelligence — on-device on iOS 26+.")
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
                    mlxModelRow(option)
                }
                .buttonStyle(.plain)
                .disabled(!option.isCompatible || model.isGenerating)
                .opacity(option.isCompatible ? 1 : 0.45)
            }
        } header: {
            Text("Local Model")
        }
    }

    @ViewBuilder
    private func mlxModelRow(_ option: MLXModelOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .foregroundStyle(option.isCompatible ? .primary : .secondary)
                    Text(option.tag)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(option.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if settings.selectedMLXModelID == option.id {
                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(theme.primary)
            } else if !option.isCompatible {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var voiceSection: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.autoSpeak }, set: { settings.autoSpeak = $0 })) {
                Label("Speak Replies Aloud", systemImage: "speaker.wave.2.fill")
            }
            Toggle(isOn: Binding(
                get: { model.speech.useNeuralVoice },
                set: { model.speech.useNeuralVoice = $0 }
            )) {
                Label("Natural Voice (Beta)", systemImage: "sparkles")
            }
            if model.speech.useNeuralVoice {
                neuralVoiceControls
            } else {
                Picker(selection: Binding(
                    get: { model.speech.voiceIdentifier },
                    set: { model.speech.voiceIdentifier = $0 }
                )) {
                    Text("Automatic (Best)").tag("")
                    ForEach(installedVoices, id: \.identifier) { voice in
                        Text(voiceLabel(voice)).tag(voice.identifier)
                    }
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                if model.speech.needsBetterVoice { naturalVoiceNudge }
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
                Button { model.speech.speak("Hello, I'm Cloe. This is how I sound.") } label: {
                    Label("Preview Voice", systemImage: "play.circle").font(.subheadline)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Dictation Pause") {
                    Text("\(settings.dictationSilence, specifier: "%.1f")s")
                        .foregroundStyle(.secondary).monospacedDigit()
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
        }
    }

    @ViewBuilder
    private var neuralVoiceControls: some View {
        Picker(selection: Binding(
            get: { model.speech.neuralVoiceID },
            set: { model.speech.neuralVoiceID = $0 }
        )) {
            ForEach(KokoroVoiceCatalog.all) { voice in
                Text(voice.displayLabel).tag(voice.id)
            }
        } label: {
            Label("Neural Voice", systemImage: "waveform.badge.magnifyingglass")
        }
        if let status = neuralStatus {
            HStack(spacing: 8) {
                if case .downloading = model.speech.kokoro.state { ProgressView() }
                else if case .preparing = model.speech.kokoro.state { ProgressView() }
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var neuralStatus: String? {
        switch model.speech.kokoro.state {
        case .ready: nil
        case .idle: "Downloads on first use (~90 MB, one time)."
        case .downloading(let p): "Downloading voice… \(Int(p * 100))%"
        case .preparing: "Preparing voice…"
        case .failed(let msg): "Couldn't load: \(msg)"
        case .unavailable: "Voice data missing."
        }
    }

    private var naturalVoiceNudge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Cloe is using a basic voice", systemImage: "exclamationmark.bubble")
                .font(.subheadline.weight(.semibold))
            Text("Download a Premium or Enhanced voice under Settings → Accessibility → Spoken Content → Voices.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Get a Natural Voice", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var installedVoices: [AVSpeechSynthesisVoice] { SpeechService.installedVoices() }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        case .default: quality = "Compact"
        @unknown default: quality = ""
        }
        return "\(voice.name) · \(voice.language) · \(quality)"
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
        }
    }

    private var commuteSection: some View {
        Section {
            TextField("Home address", text: Binding(
                get: { settings.homeAddress }, set: { settings.homeAddress = $0 }
            ), axis: .vertical)
            .textContentType(.fullStreetAddress).autocorrectionDisabled()
            TextField("Work address", text: Binding(
                get: { settings.workAddress }, set: { settings.workAddress = $0 }
            ), axis: .vertical)
            .textContentType(.fullStreetAddress).autocorrectionDisabled()
        } header: {
            Text("Commute")
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
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            Button { showChangelog = true } label: {
                Label("What's New", systemImage: "sparkles")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
