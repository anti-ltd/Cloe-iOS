import Foundation

enum DeviceCapability {
    /// `true` on A17 Pro (iPhone 15 Pro/Max) and newer physical devices,
    /// or simulators targeting those models.
    ///
    /// iPhone16,x maps to A17 Pro; iPhone17,x and above map to A18+.
    static var isA17OrNewer: Bool {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let id = String(cString: machine)

        // Apple Silicon / Intel simulator: inspect the simulated model identifier.
        let modelId: String
        if id == "arm64" || id.hasPrefix("x86") {
            modelId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        } else {
            modelId = id
        }

        return iPhoneMajorVersion(modelId) >= 16 // iPhone16,x = A17 Pro+
    }

    private static func iPhoneMajorVersion(_ id: String) -> Int {
        guard id.hasPrefix("iPhone") else { return 0 }
        let digits = id.dropFirst("iPhone".count)
        guard let major = digits.split(separator: ",").first.flatMap({ Int($0) }) else { return 0 }
        return major
    }
}
