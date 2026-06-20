import Foundation

struct Message: Identifiable, Codable {
    var id = UUID()
    let role: Role
    var content: String
    /// Device actions Cloe fired while producing this message (torch, haptics, …).
    /// Rendered as small chips under the bubble.
    var actions: [DeviceAction] = []

    enum Role: String, Codable {
        case user, assistant
    }
}
