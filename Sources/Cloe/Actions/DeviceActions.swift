import AVFoundation
import Contacts
import EventKit
import MessageUI
import SwiftUI
import UIKit

#if canImport(AlarmKit)
import AlarmKit
#endif

/// A physical thing Cloe can do to the device, decoded from either a model tag
/// (e.g. `{{torch:on}}`) or a plain-language user request ("turn on the flashlight").
enum DeviceAction: Equatable, Codable {
    enum TorchMode: String, Codable { case on, off, toggle }
    enum Haptic: String, Codable { case success, warning, error, light, medium, heavy }
    enum Brightness: String, Codable { case max, min, up, down }

    case torch(TorchMode)
    case haptic(Haptic)
    case brightness(Brightness)
    case timer(minutes: Int, label: String?)
    case alarm(at: Date, label: String?)
    case reminder(title: String, due: Date?)
    case calendarEvent(title: String, date: Date?)
    case directions(destination: String)
    case call(contact: String)
    case text(contact: String, body: String?)
    // Cross-app integrations.
    case clingNote(text: String)             // pin a note in the Cling app
    case clingParking(label: String)         // pin where you parked in Cling
    case clipboardAdd(text: String)          // add to Clink's clipboard manager
    case scratchpadAdd(text: String)         // save to Clink's scratchpad

    /// Actions that leave the app (Maps, Phone, Cling) or present a sheet (Messages),
    /// or that benefit from natural-language date parsing of the *whole* message
    /// (reminders, events). These run once the reply is finished rather than
    /// mid-stream, so Cloe gets to acknowledge before the screen changes.
    var runsAtTurnEnd: Bool {
        switch self {
        case .call, .directions, .text, .reminder, .calendarEvent,
             .clingNote, .clingParking:
            return true
        default:
            return false
        }
    }

    /// Short user-facing label shown in the chat as a "triggered" chip.
    var label: String {
        switch self {
        case .torch(.on):     return "Flashlight on"
        case .torch(.off):    return "Flashlight off"
        case .torch(.toggle): return "Flashlight toggled"
        case .haptic:         return "Haptic"
        case .brightness(.max):  return "Brightness max"
        case .brightness(.min):  return "Brightness min"
        case .brightness(.up):   return "Brightness up"
        case .brightness(.down): return "Brightness down"
        case .timer(let m, let label):
            return label.map { "\($0) · \(m) min" } ?? "\(m) min timer"
        case .alarm(let date, let label):
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            return label.map { "\($0) · \(f.string(from: date))" } ?? "Alarm \(f.string(from: date))"
        case .reminder(let t, _):       return "Reminder: \(t)"
        case .calendarEvent(let t, _):  return "Event: \(t)"
        case .directions(let d):        return "Directions: \(d)"
        case .call(let c):              return "Call \(c)"
        case .text(let c, _):           return "Text \(c)"
        case .clingNote:                return "Pinned in Cling"
        case .clingParking(let l):      return l.isEmpty ? "Parking pinned" : "Parked: \(l)"
        case .clipboardAdd:             return "Saved to Clink clipboard"
        case .scratchpadAdd:            return "Saved to scratchpad"
        }
    }

    var systemImage: String {
        switch self {
        case .torch(.off):    return "flashlight.off.fill"
        case .torch:          return "flashlight.on.fill"
        case .haptic:         return "waveform"
        case .brightness(.min), .brightness(.down): return "sun.min.fill"
        case .brightness:     return "sun.max.fill"
        case .timer:          return "timer"
        case .alarm:          return "alarm.fill"
        case .reminder:       return "checklist"
        case .calendarEvent:  return "calendar.badge.plus"
        case .directions:     return "arrow.triangle.turn.up.right.diamond.fill"
        case .call:           return "phone.fill"
        case .text:           return "message.fill"
        case .clingNote:      return "pin.fill"
        case .clingParking:   return "parkingsign.circle.fill"
        case .clipboardAdd:   return "doc.on.clipboard.fill"
        case .scratchpadAdd:  return "note.text"
        }
    }
}

/// The result of running a `DeviceAction`.
enum DeviceActionOutcome: Equatable {
    /// Ran successfully — show a chip.
    case applied
    /// Hardware or permission unavailable — show nothing.
    case unavailable
    /// The view layer must present a Messages compose sheet to finish the action.
    case compose(ComposeRequest)
}

/// Executes `DeviceAction`s against real hardware and system frameworks. Main-actor
/// isolated because most of this touches UIKit / UI-presenting frameworks; the
/// slower Contacts query hops off-main via `nonisolated` helpers.
@MainActor
final class DeviceActions {
    private let notification = UINotificationFeedbackGenerator()
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)

    /// Cached torch device. Looking this up the first time spins up the camera
    /// subsystem (slow, ~100ms+), so we grab it once off the main thread at launch
    /// and reuse it — every later flashlight command is then instant.
    private var torchDevice: AVCaptureDevice?

    /// Reused across reminder/event writes so we don't re-prompt every time.
    private let eventStore = EKEventStore()

    /// One-shot location fetch for "I parked here" → Cling parking pins.
    private let locationProvider = LocationProvider()

    init() {
        // Warm the hardware so the *first* command isn't the slow one: fetch the
        // torch device off-main, and pre-charge the Taptic engine.
        Task.detached(priority: .utility) {
            let device = AVCaptureDevice.default(for: .video)
            await MainActor.run { self.torchDevice = device }
        }
        prepareHaptics()
    }

    /// Pre-charge the Taptic engine so the next haptic fires with no warm-up lag.
    /// Cheap to call repeatedly; call again shortly before an action is likely.
    func prepareHaptics() {
        notification.prepare()
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
    }

    /// Run one action. Hardware-instant actions return synchronously-fast; the
    /// permission-gated / network-y ones (timer, calendar, contacts) suspend.
    func perform(_ action: DeviceAction) async -> DeviceActionOutcome {
        switch action {
        case .torch(let mode):       return setTorch(mode) ? .applied : .unavailable
        case .haptic(let kind):      fireHaptic(kind); return .applied
        case .brightness(let level): setBrightness(level); return .applied
        case .timer(let m, let label):        return await startTimer(minutes: m, label: label)
        case .alarm(let date, let label):     return await scheduleAlarm(at: date, label: label)
        case .reminder(let t, let due):       return await addReminder(title: t, due: due)
        case .calendarEvent(let t, let date): return await addEvent(title: t, date: date)
        case .directions(let dest):           return await openDirections(to: dest)
        case .call(let contact):              return await placeCall(to: contact)
        case .text(let contact, let body):    return await prepareText(to: contact, body: body)
        case .clingNote(let text):            return await ClingBridge.note(text) ? .applied : .unavailable
        case .clingParking(let label):        return await park(label: label)
        case .clipboardAdd(let text):         return ClinkStore.addClip(text) ? .applied : .unavailable
        case .scratchpadAdd(let text):        return ClinkStore.addNote(text) ? .applied : .unavailable
        }
    }

    // MARK: - Cling parking

    /// Capture the current location and pin it in Cling with the spot label as the
    /// note. Falls back to a plain Cling note pin if location is denied/unavailable.
    private func park(label: String) async -> DeviceActionOutcome {
        let note = label.isEmpty ? nil : label
        if let coordinate = await locationProvider.current() {
            return await ClingBridge.parking(coordinate: coordinate, note: note) ? .applied : .unavailable
        }
        let text = label.isEmpty ? "Parked here" : "Parked at \(label)"
        return await ClingBridge.note(text) ? .applied : .unavailable
    }

    // MARK: - Torch

    private func setTorch(_ mode: DeviceAction.TorchMode) -> Bool {
        // Use the warmed device; fall back to a live lookup if the warm-up Task
        // hasn't landed yet (and cache that result for next time).
        let device = torchDevice ?? AVCaptureDevice.default(for: .video)
        torchDevice = device
        guard let device, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let shouldBeOn: Bool
            switch mode {
            case .on:     shouldBeOn = true
            case .off:    shouldBeOn = false
            case .toggle: shouldBeOn = !device.isTorchActive
            }
            if shouldBeOn {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Haptics

    private func fireHaptic(_ kind: DeviceAction.Haptic) {
        switch kind {
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .error:   notification.notificationOccurred(.error)
        case .light:   impactLight.impactOccurred()
        case .medium:  impactMedium.impactOccurred()
        case .heavy:   impactHeavy.impactOccurred()
        }
        // Keep the engine warm for a likely follow-up.
        prepareHaptics()
    }

    // MARK: - Brightness

    private func setBrightness(_ level: DeviceAction.Brightness) {
        let current = UIScreen.main.brightness
        let target: CGFloat
        switch level {
        case .max:  target = 1.0
        case .min:  target = 0.0
        case .up:   target = min(1.0, current + 0.25)
        case .down: target = max(0.0, current - 0.25)
        }
        UIScreen.main.brightness = target
    }

    // MARK: - Timer (AlarmKit, iOS 26)

    /// Schedule a real countdown timer that rings through Silent / Focus and shows
    /// on the Lock Screen / Dynamic Island. AlarmKit only prompts inside the app.
    private func startTimer(minutes: Int, label: String?) async -> DeviceActionOutcome {
        guard minutes > 0 else { return .unavailable }
        #if canImport(AlarmKit)
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        guard AlarmManager.shared.authorizationState == .authorized else { return .unavailable }

        let title = (label?.isEmpty == false ? label! : "Timer")
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let presentation = AlarmPresentation(
            alert: .init(title: "\(title)", stopButton: stopButton),
            countdown: .init(title: "\(title)"),
            paused: .init(
                title: "Paused",
                resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill")
            )
        )
        let attributes = AlarmAttributes<CloeTimerMetadata>(
            presentation: presentation,
            metadata: CloeTimerMetadata(),
            tintColor: .pink
        )
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: TimeInterval(minutes * 60),
            attributes: attributes
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            return .applied
        } catch {
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    // MARK: - Alarm (AlarmKit, iOS 26)

    /// Schedule a real alarm at a fixed clock time (e.g. the commute leave time). Same
    /// AlarmKit surface as the timer — rings through Silent / Focus and shows on the
    /// Lock Screen — but `.alarm(schedule: .fixed(date))` instead of a countdown.
    private func scheduleAlarm(at date: Date, label: String?) async -> DeviceActionOutcome {
        guard date > Date() else { return .unavailable }
        #if canImport(AlarmKit)
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        guard AlarmManager.shared.authorizationState == .authorized else { return .unavailable }

        let title = (label?.isEmpty == false ? label! : "Alarm")
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        // A fixed alarm has no countdown / paused state — just the alert.
        let presentation = AlarmPresentation(alert: .init(title: "\(title)", stopButton: stopButton))
        let attributes = AlarmAttributes<CloeTimerMetadata>(
            presentation: presentation,
            metadata: CloeTimerMetadata(),
            tintColor: .pink
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            return .applied
        } catch {
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    // MARK: - Reminders & calendar (EventKit)

    private func addReminder(title: String, due: Date?) async -> DeviceActionOutcome {
        let granted = (try? await eventStore.requestFullAccessToReminders()) ?? false
        guard granted else { return .unavailable }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        do {
            try eventStore.save(reminder, commit: true)
            return .applied
        } catch {
            return .unavailable
        }
    }

    private func addEvent(title: String, date: Date?) async -> DeviceActionOutcome {
        // Write-only access is enough to add an event and never prompts again after grant.
        let granted = (try? await eventStore.requestWriteOnlyAccessToEvents()) ?? false
        guard granted else { return .unavailable }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        let start = date ?? Date(timeIntervalSinceNow: 3600)
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        guard event.calendar != nil else { return .unavailable }
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return .applied
        } catch {
            return .unavailable
        }
    }

    // MARK: - Directions (Maps)

    private func openDirections(to destination: String) async -> DeviceActionOutcome {
        let query = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        guard let url = URL(string: "maps://?daddr=\(query)&dirflg=d") else { return .unavailable }
        let ok = await UIApplication.shared.open(url)
        return ok ? .applied : .unavailable
    }

    // MARK: - Call & text (Contacts)

    private func placeCall(to contact: String) async -> DeviceActionOutcome {
        guard let match = await Self.lookupPhone(name: contact) else { return .unavailable }
        let digits = match.number.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return .unavailable }
        let ok = await UIApplication.shared.open(url)
        return ok ? .applied : .unavailable
    }

    private func prepareText(to contact: String, body: String?) async -> DeviceActionOutcome {
        guard MFMessageComposeViewController.canSendText() else { return .unavailable }

        var name = contact
        var messageBody = body
        var match = await Self.lookupPhone(name: name)

        // The model often drops the `name|message` pipe and lumps everything into the
        // contact, e.g. {{text:Claire McDermott hi}} → contact "Claire McDermott hi".
        // When we have no explicit body and the whole string doesn't resolve, peel
        // words off the end until the leading part matches a contact; the peeled tail
        // becomes the message body. Keep at least one word as the name.
        if match == nil, body?.isEmpty ?? true {
            let words = contact.split(separator: " ").map(String.init)
            var split = words.count - 1
            while split >= 1 {
                let candidate = words[0..<split].joined(separator: " ")
                if let m = await Self.lookupPhone(name: candidate) {
                    match = m
                    name = candidate
                    messageBody = words[split...].joined(separator: " ")
                    break
                }
                split -= 1
            }
        }

        return .compose(ComposeRequest(
            recipients: match.map { [$0.number] } ?? [],
            body: messageBody,
            contactDisplay: match?.display ?? name
        ))
    }

    /// Find the first contact matching `name` that has a phone number. Runs off the
    /// main actor (the Contacts query can be slow) and is `nonisolated` so its
    /// completion closure never inherits MainActor isolation — avoiding the Swift 6
    /// `dispatch_assert_queue` trap when a framework calls back on another thread.
    nonisolated private static func lookupPhone(name: String) async -> (display: String, number: String)? {
        guard await requestContactsAccess() else { return nil }
        let store = CNContactStore()
        // The formatter descriptor pulls in whatever name keys `.fullName` needs;
        // typed `[any CNKeyDescriptor]` so the String phone key and the descriptor
        // can sit in one array.
        let keys: [any CNKeyDescriptor] = [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else { return nil }
        for contact in contacts {
            if let number = contact.phoneNumbers.first?.value.stringValue {
                let display = CNContactFormatter.string(from: contact, style: .fullName) ?? name
                return (display, number)
            }
        }
        return nil
    }

    nonisolated private static func requestContactsAccess() async -> Bool {
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

#if canImport(AlarmKit)
/// AlarmKit metadata for Cloe's timers — none needed; the presentation carries the
/// label. Required to specialise `AlarmAttributes`.
struct CloeTimerMetadata: AlarmMetadata {
    init() {}
}
#endif
