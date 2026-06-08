import SwiftUI

#Preview("Idle") {
    let mlx = MLXBackend()
    ModelSetupView(mlx: mlx)
}

#Preview("Downloading") {
    let mlx = MLXBackend()
    mlx.loadState = .downloading(0.42)
    return ModelSetupView(mlx: mlx)
}

#Preview("Loading") {
    let mlx = MLXBackend()
    mlx.loadState = .loading
    return ModelSetupView(mlx: mlx)
}

#Preview("Failed") {
    let mlx = MLXBackend()
    mlx.loadState = .failed("Network connection lost. Please check your internet connection and try again.")
    return ModelSetupView(mlx: mlx)
}

struct ModelSetupView: View {
    let mlx: MLXBackend

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("On-Device AI")
                    .font(.title2.bold())
                Text("Sage needs to download a language model (~700 MB). It runs entirely on your device — no internet needed after download.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            switch mlx.loadState {
            case .idle:
                Button("Download Model") {
                    Task { await mlx.prepare() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .downloading(let progress):
                VStack(spacing: 10) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
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
}
