import SwiftUI

#Preview("Idle") {
    let model = AppModel()
    if let mlx = model.mlxBackend {
        ModelSetupView(mlx: mlx)
            .environment(model)
            .environment(model.settings)
    }
}

struct ModelSetupView: View {
    let mlx: MLXBackend
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private var theme: CloeTheme { settings.visualTheme }

    var body: some View {
        ZStack {
            CloeStage(theme: theme)

            VStack(spacing: 28) {
                Spacer()

                CloeOrb(theme: theme, state: setupOrbState, size: 120)
                Text("Cloe")
                    .font(CloeTypography.hero)
                    .foregroundStyle(CloePalette.ink)
                Text("Private AI, entirely on your device.")
                    .font(CloeTypography.caption)
                    .foregroundStyle(CloePalette.inkMuted)
                    .multilineTextAlignment(.center)

                setupControls
                    .padding(.horizontal, 24)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .tint(theme.primary)
    }

    private var setupOrbState: CloeOrbState {
        switch mlx.loadState {
        case .downloading, .loading: .thinking
        default: .idle
        }
    }

    @ViewBuilder
    private var setupControls: some View {
        switch mlx.loadState {
        case .idle:
            VStack(spacing: 16) {
                modelPicker
                Button("Download \(settings.selectedMLXModel.name)") {
                    Task { await mlx.prepare() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .downloading(let progress):
            VStack(spacing: 10) {
                ProgressView(value: progress)
                Text("Downloading — \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading model…").font(.caption).foregroundStyle(.secondary)
            }

        case .ready:
            EmptyView()

        case .failed(let msg):
            VStack(spacing: 12) {
                Text(msg).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Retry") { Task { await mlx.prepare() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var modelPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(MLXModelCatalog.all.enumerated()), id: \.element.id) { index, option in
                Button {
                    guard option.isCompatible else { return }
                    model.switchMLXModel(to: option)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.name).fontWeight(.medium)
                            Text(option.sizeLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.selectedMLXModelID == option.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.isCompatible)
                .opacity(option.isCompatible ? 1 : 0.45)
                if index < MLXModelCatalog.all.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(CloePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
