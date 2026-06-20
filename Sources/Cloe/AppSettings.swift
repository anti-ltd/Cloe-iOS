import Foundation

@Observable
final class AppSettings {
    /// Persisted user preference to use the local MLX model instead of Foundation Models.
    /// Only honoured when `canChooseMLX` is true.
    var preferMLX: Bool {
        didSet { UserDefaults.standard.set(preferMLX, forKey: "preferMLX") }
    }

    /// ID of the currently selected MLX model (matches `MLXModelOption.id`).
    var selectedMLXModelID: String {
        didSet { UserDefaults.standard.set(selectedMLXModelID, forKey: "selectedMLXModelID") }
    }

    /// Read each assistant reply aloud automatically when it finishes streaming.
    var autoSpeak: Bool {
        didSet { UserDefaults.standard.set(autoSpeak, forKey: "autoSpeak") }
    }

    /// Allow Cloe to control the device (flashlight, haptics, brightness) via action tags.
    var enableDeviceActions: Bool {
        didSet { UserDefaults.standard.set(enableDeviceActions, forKey: "enableDeviceActions") }
    }

    /// Pin a Lock Screen Live Activity for quick access to Cloe from anywhere.
    var liveActivityEnabled: Bool {
        didSet { UserDefaults.standard.set(liveActivityEnabled, forKey: "liveActivityEnabled") }
    }

    /// Home address used to resolve "home" in commute questions ("what time do I need
    /// to leave to get home by 6?"). Falls back to the Contacts "My Card" home address.
    var homeAddress: String {
        didSet { UserDefaults.standard.set(homeAddress, forKey: "homeAddress") }
    }

    /// Work address used to resolve "work" / "the office" in commute questions.
    /// Falls back to the Contacts "My Card" work address.
    var workAddress: String {
        didSet { UserDefaults.standard.set(workAddress, forKey: "workAddress") }
    }

    /// Quiet gap (seconds) after the last dictated speech before voice input auto-stops
    /// and the transcript auto-sends. Lower = snappier, higher = tolerates longer pauses.
    var dictationSilence: Double {
        didSet { UserDefaults.standard.set(dictationSilence, forKey: "dictationSilence") }
    }

    /// Resolved model option from the catalog, falling back to the default if the saved ID is stale.
    var selectedMLXModel: MLXModelOption {
        MLXModelCatalog.all.first { $0.id == selectedMLXModelID } ?? MLXModelCatalog.defaultModel
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
        selectedMLXModelID = UserDefaults.standard.string(forKey: "selectedMLXModelID")
            ?? MLXModelCatalog.defaultModel.id
        autoSpeak = UserDefaults.standard.bool(forKey: "autoSpeak")
        // Default ON — device control is the headline feature.
        enableDeviceActions = UserDefaults.standard.object(forKey: "enableDeviceActions") as? Bool ?? true
        liveActivityEnabled = UserDefaults.standard.bool(forKey: "liveActivityEnabled")
        homeAddress = UserDefaults.standard.string(forKey: "homeAddress") ?? ""
        workAddress = UserDefaults.standard.string(forKey: "workAddress") ?? ""
        dictationSilence = UserDefaults.standard.object(forKey: "dictationSilence") as? Double ?? 0.8
    }
}
