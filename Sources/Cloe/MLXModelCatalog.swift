import MLXLLM
import MLXLMCommon

/// A user-facing description of an MLX model the app can download and run.
struct MLXModelOption: Identifiable, Sendable {
    /// Stable key used for UserDefaults persistence.
    let id: String
    let name: String
    /// Short quality/speed label shown as a badge, e.g. "Balanced".
    let tag: String
    /// Approximate download size shown in the UI, e.g. "~900 MB".
    let sizeLabel: String
    let configuration: ModelConfiguration
    /// When `true` the model is greyed out on pre-A17 devices.
    let requiresA17: Bool

    var isCompatible: Bool {
        requiresA17 ? DeviceCapability.isA17OrNewer : true
    }
}

/// Curated list of models the app offers, ordered from smallest to largest.
enum MLXModelCatalog {
    static let all: [MLXModelOption] = [
        .init(id: "smollm_135m",   name: "SmolLM 135M",    tag: "Tiny",     sizeLabel: "~100 MB",
              configuration: LLMRegistry.smolLM_135M_4bit,    requiresA17: false),
        .init(id: "qwen3_0_6b",    name: "Qwen 3 0.6B",    tag: "Fast",     sizeLabel: "~350 MB",
              configuration: LLMRegistry.qwen3_0_6b_4bit,     requiresA17: false),
        .init(id: "gemma3_1b",     name: "Gemma 3 1B",     tag: "Capable",  sizeLabel: "~600 MB",
              configuration: LLMRegistry.gemma3_1B_qat_4bit,  requiresA17: false),
        .init(id: "qwen2_5_1_5b",  name: "Qwen 2.5 1.5B",  tag: "Capable",  sizeLabel: "~800 MB",
              configuration: LLMRegistry.qwen2_5_1_5b,        requiresA17: false),
        .init(id: "qwen3_1_7b",    name: "Qwen 3 1.7B",    tag: "Balanced", sizeLabel: "~900 MB",
              configuration: LLMRegistry.qwen3_1_7b_4bit,     requiresA17: false),
        .init(id: "llama3_2_3b",   name: "Llama 3.2 3B",   tag: "Powerful", sizeLabel: "~1.8 GB",
              configuration: LLMRegistry.llama3_2_3B_4bit,    requiresA17: true),
        .init(id: "qwen3_4b",      name: "Qwen 3 4B",       tag: "Powerful", sizeLabel: "~2.2 GB",
              configuration: LLMRegistry.qwen3_4b_4bit,       requiresA17: true),
    ]

    static var defaultModel: MLXModelOption { all.first { $0.id == "qwen3_1_7b" }! }
}
