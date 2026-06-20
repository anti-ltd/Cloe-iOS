import Contacts
import CoreLocation
import Foundation
import MapKit

/// Answers "what time do I need to leave?" deterministically.
///
/// The flow: parse the target arrival time and the destination out of the user's
/// words, resolve the destination to a coordinate (named *work* / *home* come from
/// the Contacts "My Card" first, then Cloe's Settings; anything else is geocoded),
/// get the current location, ask MapKit for a traffic-aware ETA, and subtract it
/// from the arrival time.
///
/// This **short-circuits the model** the same way `ClinkStore.retrievalReply` does:
/// a leave time has to be exact, and a small on-device model is unreliable at both
/// the arithmetic and at resisting the urge to invent a plausible-sounding wrong
/// number. So we compute it ourselves and hand back finished prose.
@MainActor
enum CommutePlanner {

    /// A place the user wants to reach.
    enum Place {
        case work
        case home
        case named(String)   // geocoder query, e.g. "the airport"

        var spoken: String {
            switch self {
            case .work:           return "work"
            case .home:           return "home"
            case .named(let q):   return q
            }
        }
    }

    /// The outcome of a commute question: the prose to show, plus the computed leave
    /// time when we produced a real ETA (so a follow-up "set an alarm" has a time to
    /// use). `leave` is nil for clarifying / error replies — nothing to set.
    struct Plan {
        let reply: String
        let leave: Date?
        let destination: String

        static func message(_ text: String, destination: String = "") -> Plan {
            Plan(reply: text, leave: nil, destination: destination)
        }
    }

    /// Cheap sync gate + full async answer. Returns `nil` when the message isn't a
    /// "when should I leave" question, so the caller falls through to the model.
    static func plan(for text: String, settings: AppSettings) async -> Plan? {
        guard isLeaveQuestion(text) else { return nil }

        // Target arrival time — without one there's nothing to subtract from.
        guard let arrival = arrivalTime(in: text) else {
            return .message("When do you need to be there? Give me the time and I'll work out when you should leave.")
        }
        // Destination.
        guard let place = destination(in: text) else {
            return .message("Where are you headed? Tell me the place and I'll work out your leave time.")
        }

        let mode = travelMode(in: text)

        // Current location — needed for the ETA regardless of how the place resolves.
        guard let origin = await LocationProvider().current() else {
            return .message("I need location access to estimate the trip — turn it on for Cloe in Settings, then ask again.")
        }
        // Destination → a map item.
        guard let destItem = await resolve(place, near: origin, settings: settings) else {
            return .message(unresolved(place), destination: place.spoken)
        }

        // Traffic-aware ETA for the target arrival.
        if let travel = await travelTime(from: origin, to: destItem, mode: mode, arriving: arrival) {
            let (text, leave) = phrase(arrival: arrival, travel: travel, mode: mode, place: place, fallback: false)
            return Plan(reply: text, leave: leave > Date() ? leave : nil, destination: place.spoken)
        }
        // Transit frequently has no ETA in MapKit — fall back to driving so the user
        // still gets a number, and say that's what happened.
        if mode != .automobile,
           let drive = await travelTime(from: origin, to: destItem, mode: .automobile, arriving: arrival) {
            let (text, leave) = phrase(arrival: arrival, travel: drive, mode: .automobile, place: place, fallback: true)
            return Plan(reply: text, leave: leave > Date() ? leave : nil, destination: place.spoken)
        }
        return .message("I couldn't work out a route to \(place.spoken) right now — give it another go in a moment.", destination: place.spoken)
    }

    // MARK: - Detection

    /// Does this message ask when to leave? Cheap, runs on every turn before any await.
    static func isLeaveQuestion(_ text: String) -> Bool {
        let t = text.lowercased()
        // Direct phrasings that are unambiguous on their own.
        let direct = ["need to leave", "should i leave", "time to leave", "when to leave",
                      "do i leave", "have to leave", "gotta leave", "when do i leave",
                      "leave the house by", "set off"]
        if direct.contains(where: t.contains) { return true }
        // Otherwise require both a "leave / head out" verb and a timing question, so
        // "leave me alone" or "I left work early" don't trip it.
        let mentionsLeave = t.contains("leave") || t.contains("head out") || t.contains("set out")
        let asksTime = t.contains("what time") || t.contains("when") || t.contains("how early")
        return mentionsLeave && asksTime
    }

    // MARK: - Parsing

    /// Target arrival time from the user's words. A bare time ("8am") resolves to
    /// today; if that's already past, we mean the next day.
    private static func arrivalTime(in text: String) -> Date? {
        guard var date = ActionRouter.firstDate(in: text) else { return nil }
        if date < Date() {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    /// Driving by default; switch when the user names a different mode.
    private static func travelMode(in text: String) -> MKDirectionsTransportType {
        let t = text.lowercased()
        if t.contains("walk") || t.contains("on foot") { return .walking }
        if t.contains("transit") || t.contains("bus") || t.contains("train")
            || t.contains("subway") || t.contains("metro") || t.contains("tube") { return .transit }
        return .automobile
    }

    /// The destination from the user's words: named *work* / *home*, or a free-text
    /// place pulled from after a preposition.
    private static func destination(in text: String) -> Place? {
        let t = text.lowercased()
        if t.contains("the office") || t.contains(" office") || t.hasPrefix("office")
            || t.contains(" work") || t.hasPrefix("work") || t.contains("my job") {
            return .work
        }
        if t.contains(" home") || t.hasPrefix("home") || t.contains("the house") {
            return .home
        }
        if let q = namedPlace(in: text) { return .named(q) }
        return nil
    }

    /// Pull a place phrase that sits between a preposition and the time, e.g.
    /// "be at the airport for 6am" → "the airport".
    private static func namedPlace(in text: String) -> String? {
        let boundary = #"(?: (?:for|by|at|before|around)\b|$)"#
        let leads = [#"\bbe at "#, #"\bget to "#, #"\breach "#, #"\bto "#, #"\bat "#]
        for lead in leads {
            if let q = firstCapture(lead + #"(.+?)"# + boundary, in: text) {
                let cleaned = q.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    // MARK: - Resolution

    /// Resolve a `Place` to a map item. Named work/home read the Contacts My Card
    /// first, then the Settings fallback; everything else is geocoded directly.
    private static func resolve(_ place: Place, near origin: CLLocationCoordinate2D, settings: AppSettings) async -> MKMapItem? {
        switch place {
        case .work:
            guard let address = await meCardAddress(label: CNLabelWork) ?? nonEmpty(settings.workAddress) else { return nil }
            return await geocode(address, near: origin)
        case .home:
            guard let address = await meCardAddress(label: CNLabelHome) ?? nonEmpty(settings.homeAddress) else { return nil }
            return await geocode(address, near: origin)
        case .named(let query):
            return await geocode(query, near: origin)
        }
    }

    /// The postal address with the given label (work/home) from the user's "My Card",
    /// formatted as a single mailing-address string. `nonisolated` so the Contacts
    /// query runs off the main actor and its access callback never inherits MainActor
    /// isolation (the Swift 6 `dispatch_assert_queue` trap).
    nonisolated private static func meCardAddress(label: String) async -> String? {
        guard await contactsAccess() else { return nil }
        let store = CNContactStore()
        let keys: [any CNKeyDescriptor] = [CNContactPostalAddressesKey as CNKeyDescriptor]
        guard let me = try? store.unifiedMeContactWithKeys(toFetch: keys) else { return nil }
        // Prefer the requested label; fall back to any address the card has.
        let match = me.postalAddresses.first { ($0.label ?? "") == label } ?? me.postalAddresses.first
        guard let value = match?.value else { return nil }
        let formatted = CNPostalAddressFormatter.string(from: value, style: .mailingAddress)
        return nonEmpty(formatted)
    }

    /// Geocode an address or place name to a map item, biased to the current area.
    private static func geocode(_ query: String, near origin: CLLocationCoordinate2D) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems.first
    }

    /// Traffic-aware travel time for the requested mode, arriving by `arriving`.
    private static func travelTime(from origin: CLLocationCoordinate2D, to destination: MKMapItem, mode: MKDirectionsTransportType, arriving: Date) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = destination
        request.transportType = mode
        request.arrivalDate = arriving
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return eta.expectedTravelTime
    }

    // MARK: - Phrasing

    private static func phrase(arrival: Date, travel: TimeInterval, mode: MKDirectionsTransportType, place: Place, fallback: Bool) -> (text: String, leave: Date) {
        let leave = arrival.addingTimeInterval(-travel)
        let minutes = max(1, Int((travel / 60).rounded()))

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let leaveStr = formatter.string(from: leave)
        let arriveStr = formatter.string(from: arrival)

        let emoji: String
        let trip: String
        switch mode {
        case .walking: emoji = "🚶"; trip = "\(minutes)-minute walk"
        case .transit: emoji = "🚆"; trip = "\(minutes)-minute trip"
        default:       emoji = "🚗"; trip = "\(minutes)-minute drive"
        }
        let lead = fallback ? "I couldn't get transit times, but " : ""
        let dest = place.spoken

        // Leave time already gone (with a minute of slack) — tell them to move; no
        // alarm nudge (an alarm in the past is pointless).
        if leave < Date().addingTimeInterval(-60) {
            let head = lead.isEmpty ? "T" : "\(lead)t"
            return ("\(emoji) \(head)o reach \(dest) by \(arriveStr) it's about a \(trip), so you'd have needed to leave by \(leaveStr) — that's already passed, so head out as soon as you can.", leave)
        }
        let head = lead.isEmpty ? "It's" : "\(lead)it's"
        // Trailing nudge advertises the follow-up: the user can just reply "set an alarm".
        return ("\(emoji) \(head) about a \(trip) to \(dest) right now, so to be there by \(arriveStr) you'll want to leave by \(leaveStr). Want an alarm for then?", leave)
    }

    private static func unresolved(_ place: Place) -> String {
        switch place {
        case .work:
            return "I don't have your work address yet. Add it in Settings ▸ Commute, or set a work address on your contact card, and I'll work out your leave time."
        case .home:
            return "I don't have your home address yet. Add it in Settings ▸ Commute, or set a home address on your contact card, and I'll work out your leave time."
        case .named(let query):
            return "I couldn't find “\(query)” on the map — try a more specific name or a full address."
        }
    }

    // MARK: - Helpers

    // `nonisolated` because `meCardAddress` (also nonisolated) calls it; otherwise the
    // enum's @MainActor isolation would make this an illegal cross-actor sync call.
    nonisolated private static func nonEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Contacts authorization, mirrored from `DeviceActions` so this file stays
    /// self-contained. `nonisolated` to keep the access callback off the main actor.
    nonisolated private static func contactsAccess() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                CNContactStore().requestAccess(for: .contacts) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
