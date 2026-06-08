import Foundation

@Observable
final class AppSettings {
    /// Persisted user preference to use the local MLX model instead of Foundation Models.
    /// Only honoured when `canChooseMLX` is true.
    var preferMLX: Bool {
        didSet { UserDefaults.standard.set(preferMLX, forKey: "preferMLX") }
    }

    /// `true` when the device is iOS 26+ with an A17 Pro chip or newer,
    /// meaning the user can pick between Foundation Models and MLX.
    var canChooseMLX: Bool {
        if #available(iOS 26.0, *) {
            return DeviceCapability.isA17OrNewer
        }
        return false
    }

    init() {
        preferMLX = UserDefaults.standard.bool(forKey: "preferMLX")
    }
}
