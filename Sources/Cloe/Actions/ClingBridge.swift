import CoreLocation
import UIKit

/// Builds and opens `cling://create/…` deep links into the sibling **Cling** pin
/// app. Cling parses these via its `ClingCreateRequest` API; opening the URL
/// foregrounds Cling and fires a Live Activity. `open` (not `canOpenURL`) means no
/// `LSApplicationQueriesSchemes` entry is needed; it returns false if Cling isn't
/// installed.
enum ClingBridge {
    private static let scheme = "cling"
    private static let host = "create"

    /// Create a Cling note pin.
    @MainActor
    static func note(_ text: String, sourceURL: URL? = nil) async -> Bool {
        var items = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "from", value: "cloe")
        ]
        if let sourceURL { items.append(URLQueryItem(name: "sourceURL", value: sourceURL.absoluteString)) }
        return await open(path: "/note", items: items)
    }

    /// Create a Cling parking pin at a coordinate, with an optional spot label
    /// (e.g. "45a") as the note.
    @MainActor
    static func parking(coordinate: CLLocationCoordinate2D, note: String?) async -> Bool {
        var items = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(coordinate.longitude)),
            URLQueryItem(name: "from", value: "cloe")
        ]
        if let note, !note.isEmpty { items.append(URLQueryItem(name: "note", value: note)) }
        return await open(path: "/parking", items: items)
    }

    @MainActor
    private static func open(path: String, items: [URLQueryItem]) async -> Bool {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = items
        guard let url = components.url else { return false }
        return await UIApplication.shared.open(url)
    }
}
