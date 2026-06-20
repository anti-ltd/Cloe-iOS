import SwiftUI

#Preview("Idle") {
    let model = AppModel()
    if let mlx = model.mlxBackend {
        ModelSetupView(mlx: mlx)
            .environment(model)
            .environment(model.settings)
    }
}

#Preview("Downloading") {
    let model = AppModel()
    if let mlx = model.mlxBackend {
        mlx.loadState = .downloading(0.42)
        return AnyView(ModelSetupView(mlx: mlx)
            .environment(model)
            .environment(model.settings))
    }
    return AnyView(EmptyView())
}

#Preview("Failed") {
    let model = AppModel()
    if let mlx = model.mlxBackend {
        mlx.loadState = .failed("Key model.embed_tokens.weight not found in LlamaModelInner.Embedding")
        return AnyView(ModelSetupView(mlx: mlx)
            .environment(model)
            .environment(model.settings))
    }
    return AnyView(EmptyView())
}

struct ModelSetupView: View {
    let mlx: MLXBackend
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("On-Device AI")
                    .font(.title2.bold())
                Text("Cloe runs a language model entirely on your device — no internet needed after the initial download.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Model picker — visible whenever a download isn't actively in progress
            switch mlx.loadState {
            case .downloading, .loading:
                EmptyView()
            default:
                modelPicker
            }

            // State-specific controls
            switch mlx.loadState {
            case .idle:
                Button("Download \(settings.selectedMLXModel.name)") {
                    Task { await mlx.prepare() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .downloading(let progress):
                VStack(spacing: 10) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("Downloading \(settings.selectedMLXModel.name) — \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading model…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .ready:
                EmptyView()

            case .failed(let msg):
                VStack(spacing: 12) {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await mlx.prepare() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(32)
    }

    // MARK: - Model picker

    private var modelPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(MLXModelCatalog.all.enumerated()), id: \.element.id) { index, option in
                Button {
                    guard option.isCompatible else { return }
                    model.switchMLXModel(to: option)
                } label: {
                    modelRow(option)
                }
                .buttonStyle(.plain)
                .disabled(!option.isCompatible)
                .opacity(option.isCompatible ? 1 : 0.45)

                if index < MLXModelCatalog.all.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func modelRow(_ option: MLXModelOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .fontWeight(.medium)
                    Text(option.tag)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                HStack(spacing: 4) {
                    Text(option.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !option.isCompatible {
                        Text("· A17+ required")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if settings.selectedMLXModelID == option.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else if !option.isCompatible {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
