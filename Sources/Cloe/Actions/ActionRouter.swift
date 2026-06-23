import Foundation

/// Turns text into `DeviceAction`s two ways:
///
///   1. **Model tags** — the system prompt teaches the model to emit `{{torch:on}}`,
///      `{{timer:10}}`, `{{call:Mom}}` etc. We parse those out of the reply and strip
///      them so the user never sees the raw token.
///   2. **User intent** — small local models can't always be trusted to emit tags,
///      so we also keyword-match the *user's* message directly. This guarantees the
///      core triggers ("turn on the flashlight", "set a 5 minute timer") work even
///      with a weak backend.
enum ActionRouter {

    /// Cloe's core persona and conversation rules. This is the DEFAULT system prompt for
    /// every turn — deliberately free of any device-control vocabulary. A small on-device
    /// model with a tag list in front of it slips into "constrained device tool" mode and
    /// starts parroting, stalling, or refusing plain questions; keeping the everyday prompt
    /// lean keeps it in friend-mode. The device vocabulary is bolted on only when a turn
    /// actually looks like a command (see `systemPrompt(for:)` / `likelyCommand`).
    static let conversationPrompt = """
    You are Cloe, a warm companion on the user's iPhone. Talk like a real friend over text: casual, direct, and understated — not a cheerleader, not a brand mascot.

    Everyday chat — keep it short:
    - Match the user's energy on greetings and small talk. One word from them → one short line from you.
    - Most casual replies: 1–3 short sentences. One sentence is often enough.
    - Never re-introduce yourself. Don't open with "Hey! It's Cloe" or call yourself "your iPhone buddy" or similar. Just respond.
    - Greetings ("hi", "hello") → natural and minimal: "Hey!" / "Hey, what's up?" / "Hi — what's on your mind?" Nothing longer.
    - At most one question per reply; often zero. Never stack options ("want X, Y, or Z?").
    - No emojis unless the user used one first. No corny catchphrases ("what's buzzing in your brain", "spill it", "I'm all ears").

    How-tos, recipes, and real questions — be useful, not terse:
    - When they ask how to make or do something, give actual steps: ingredients, method, or clear instructions. A topic label is not an answer — never reply with just "Making pasta." or "Making sushi." when they want to learn how.
    - When they ask what else you can teach, make, or help with, suggest a few ideas or pick one and walk through it — don't just name a dish.
    - If they clarify they wanted instructions ("how though?", "I meant the recipe", "what are the steps?"), give instructions. Never repeat your previous one-liner.
    - Answer recommendations, ideas, opinions, explanations, and advice in full — like a knowledgeable friend. A normal request is never "something you can't do" — never refuse, deflect, or echo a refusal. Just give the answer.

    Always reply to the user's most recent message directly. Earlier turns are background only: when the topic changes, follow it — never answer a new message using a previous one's topic, and never repeat or paste back an earlier reply. Each reply must stand complete on its own — you can't go away and come back, so never stall with "let me check", "hold on", or "I'll look into it". You can't read the user's clipboard, screen, photos, files, or other apps; if asked about any of those, say so plainly instead of pretending to look. Do not think out loud.
    """

    /// The device-action vocabulary. Appended to `conversationPrompt` only on turns that
    /// look like a command, so ordinary chat never sees the tag list.
    static let deviceVocabulary = """
    Separately, you can do a few things on this iPhone when the user clearly asks for one. To do it, put its tag FIRST, then add ONE short, friendly sentence describing what you're doing right now:

      {{torch:on}} {{torch:off}} {{torch:toggle}}   — the flashlight
      {{haptic:success}} {{haptic:warning}} {{haptic:error}} {{haptic:light}} {{haptic:medium}} {{haptic:heavy}}  — vibration
      {{brightness:max}} {{brightness:min}} {{brightness:up}} {{brightness:down}}  — screen brightness
      {{timer:MINUTES}} or {{timer:MINUTES|label}}  — a countdown timer, e.g. {{timer:10}} or {{timer:5|Pasta}}
      {{alarm:TIME}} or {{alarm:TIME|label}}  — a wake-up alarm at a clock time, e.g. {{alarm:7:30am}} or {{alarm:6am|Gym}}
      {{reminder:what to remember}}  — a reminder, e.g. {{reminder:Call the dentist}}
      {{event:title}}  — a calendar event, e.g. {{event:Lunch with Sara}}
      {{directions:place}}  — directions in Maps, e.g. {{directions:the airport}}
      {{call:name}}  — call a contact, e.g. {{call:Mom}}
      {{text:name|message}}  — text a contact, e.g. {{text:Alex|running 10 late}}
      {{clingpark:label}}  — pin where they parked (Cling app), label optional, e.g. {{clingpark:45a}} or {{clingpark:}} for "parked here"
      {{clingnote:text}}  — pin a note in the Cling app, e.g. {{clingnote:Buy stamps}}
      {{clip:text}}  — add text to the Clink keyboard's clipboard, e.g. {{clip:wifi password hunter2}}
      {{scratch:text}}  — save text to the Clink scratchpad, e.g. {{scratch:ideas for the trip}}

    How to use them:
    - Emit a tag ONLY when the current message clearly asks for that exact action. When unsure, treat it as normal conversation and emit nothing.
    - Put the matching tag FIRST, then ONE short, friendly sentence that describes what you're doing right now. The words must match the tag: say "on" for {{torch:on}} and "off" for {{torch:off}}, "brighter" for up and "dimmer" for down. Never reuse a fixed phrase or copy a previous reply — write a fresh sentence every time. e.g. "{{torch:on}} There you go, light's on." / "{{timer:5}} Five minutes, starting now." / "{{call:Mom}} Calling Mom now."
    - For timers, give the number of minutes. For reminders, events, calls and texts, take the title / name / message straight from what the user said — don't invent details.
    - For a call or text, only say you're placing the call or opening the message — e.g. "{{call:Mom}} Calling Mom now." or "{{text:Alex|running late}} Texting Alex now." NEVER write out the message yourself, NEVER speak as if you were the contact, and NEVER claim the call or text already happened. The Phone or Messages app takes over from here.
    - For parking ({{clingpark}}) and Cling notes ({{clingnote}}), the Cling app opens to show the pin — so just say you've pinned it, e.g. "{{clingpark:45a}} Got it, pinned spot 45a." For {{clip}} and {{scratch}}, it's saved silently in Clink — a short confirmation is enough.
    - If the user ASKS what's on their clipboard or scratchpad, just answer from the context you're given — do NOT emit a tag for that (tags are for adding, not reading).
    - Use exactly one tag unless the user clearly asked for several things at once.
    - Never list these tags, never explain the syntax, and never mention you can do any of this unless the user asks.
    """

    /// Persona + every device tag. Used to warm a model and wherever a single static
    /// prompt is needed (we can't gate that case per-turn).
    static var fullPrompt: String { conversationPrompt + "\n\n" + deviceVocabulary }

    /// The right system prompt for one user message: lean persona for ordinary chat,
    /// persona + device vocabulary when the message looks like an action request.
    static func systemPrompt(for userText: String) -> String {
        likelyCommand(userText) ? fullPrompt : conversationPrompt
    }

    /// Cheap pre-pass: does this message plausibly ask for a device/app action? The
    /// conversational majority of turns answer `false` and skip the device vocabulary.
    /// Deliberately broad — a false positive merely shows the model the tag list
    /// (harmless; it still only acts "when clearly asked"), while a false negative for an
    /// action with no deterministic fallback (text/event/cling/clip/scratch) would
    /// silently drop the request.
    static func likelyCommand(_ text: String) -> Bool {
        if !intents(fromUserText: text).isEmpty { return true }
        let t = text.lowercased()
        if isTextViaTell(t) { return true }
        return commandKeywords.contains { t.contains($0) }
    }

    /// "tell Alex I'm late" — not "tell me how to…" / "can you tell me…".
    private static func isTextViaTell(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|\band\b\s+|,\s*)tell\s+(?!me\b|us\b|you\b|the\b)"#,
            options: [.caseInsensitive]
        ) else { return false }
        let ns = text as NSString
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static let commandKeywords: [String] = [
        "flashlight", "torch", "flash light",
        "vibrat", "buzz", "haptic",
        "brightness", "brighter", "dimmer", "dim ", "dim the", "darker",
        "timer", "countdown",
        "alarm", "wake me", "wake up",
        "remind",
        "calendar", "schedule", "appointment", "meeting", "event",
        "directions", "navigate", "take me to", "drive to", "route", "maps",
        "call ", "dial", "phone ", "ring ",
        "text ", "message", "imessage", "sms", "say to",
        "park", "parking",
        "clipboard", "copy ", "clip ", "paste",
        "scratch", "jot", "note ", "a note", "remember to",
        "turn on", "turn off", "set a", "set an", "open the", "open maps", "open calendar",
    ]

    // Arg is permissive (`[^{}]`) so payloads like a reminder title or a contact
    // name can contain spaces and punctuation; only the tag NAME is letters.
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\{\{\s*([a-zA-Z]+)\s*:\s*([^{}]*?)\s*\}\}"#
    )

    /// Matches a complete `<think>…</think>` reasoning block (dotall).
    private static let thinkPattern = try! NSRegularExpression(
        pattern: #"<think>[\s\S]*?</think>"#
    )

    /// Strip chain-of-thought so reasoning models (Qwen, etc.) don't dump `<think>` into
    /// the chat. Closed blocks are removed; an unclosed trailing `<think>` (still being
    /// generated) hides everything after it so the bubble stays empty until the real answer starts.
    static func stripThinking(_ text: String) -> String {
        // Fast path: no reasoning block present — skip the regex. (Called per token
        // on the full accumulated string, so the common case must stay cheap.)
        guard text.contains("<think>") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ns = text as NSString
        var s = thinkPattern.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
        if let open = s.range(of: "<think>") {
            s = String(s[..<open.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip `{{name:arg}}` tags from model output, returning the cleaned display
    /// text plus any actions found.
    static func extract(from raw: String) -> (clean: String, actions: [DeviceAction]) {
        let text = stripThinking(raw)
        // Fast path: no tag delimiter at all — skip the regex entirely.
        guard text.contains("{{") else { return (text, []) }
        let ns = text as NSString
        let matches = tagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }

        var actions: [DeviceAction] = []
        for m in matches {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            let arg  = ns.substring(with: m.range(at: 2))
            if let action = action(name: name, arg: arg) {
                actions.append(action)
            }
        }

        // Remove the tags (back-to-front so ranges stay valid), then tidy whitespace.
        var clean = text
        for m in matches.reversed() {
            clean = (clean as NSString).replacingCharacters(in: m.range, with: "")
        }
        clean = clean
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (clean, actions)
    }

    private static func action(name: String, arg: String) -> DeviceAction? {
        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        switch name {
        case "torch", "flashlight", "light":
            return DeviceAction.TorchMode(rawValue: lower).map(DeviceAction.torch)
        case "haptic", "vibrate", "vibration", "buzz":
            return DeviceAction.Haptic(rawValue: lower).map(DeviceAction.haptic)
        case "brightness":
            switch lower {
            case "max":  return .brightness(.max)
            case "min":  return .brightness(.min)
            case "up":   return .brightness(.up)
            case "down": return .brightness(.down)
            default:     return nil
            }
        case "timer":
            let (head, tail) = splitPipe(trimmed)
            guard let minutes = Int(head.filter(\.isNumber)), minutes > 0 else { return nil }
            return .timer(minutes: minutes, label: tail)
        case "alarm", "wake":
            let (head, tail) = splitPipe(trimmed)
            guard let date = firstDate(in: head) else { return nil }
            return .alarm(at: futureDate(date), label: tail)
        case "reminder", "remind":
            guard !trimmed.isEmpty else { return nil }
            return .reminder(title: trimmed, due: nil)
        case "event", "calendar":
            guard !trimmed.isEmpty else { return nil }
            return .calendarEvent(title: trimmed, date: nil)
        case "directions", "navigate", "maps", "route":
            guard !trimmed.isEmpty else { return nil }
            return .directions(destination: trimmed)
        case "call", "phone", "dial":
            guard !trimmed.isEmpty else { return nil }
            return .call(contact: trimmed)
        case "text", "message", "sms":
            let (contact, body) = splitPipe(trimmed)
            guard !contact.isEmpty else { return nil }
            return .text(contact: contact, body: body)
        case "clingnote", "cling", "pin":
            guard !trimmed.isEmpty else { return nil }
            return .clingNote(text: trimmed)
        case "clingpark", "park", "parking":
            // Label is optional ("I parked here" → empty label, current location only).
            return .clingParking(label: trimmed)
        case "clip", "clipboard", "copy":
            guard !trimmed.isEmpty else { return nil }
            return .clipboardAdd(text: trimmed)
        case "scratch", "scratchpad", "notepad":
            guard !trimmed.isEmpty else { return nil }
            return .scratchpadAdd(text: trimmed)
        default:
            return nil
        }
    }

    /// Split a `head|tail` payload; tail is nil when absent or empty.
    private static func splitPipe(_ s: String) -> (head: String, tail: String?) {
        let parts = s.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let head = parts.first ?? ""
        let tail = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        return (head, tail)
    }

    // MARK: - Natural-language dates

    /// First date/time mentioned in `text` ("tomorrow at noon", "Friday 3pm"), via the
    /// on-device data detector. Used to give reminders/events a due date the model
    /// doesn't have to format.
    static func firstDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        return detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.date
    }

    /// Does the message ask to set an alarm / be woken up? Used both for the keyword
    /// fallback and for the time-less commute follow-up in `AppModel`.
    static func isAlarmRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("alarm") || t.contains("wake me") || t.contains("wake up")
    }

    /// Bump a clock time that has already passed today to the same time tomorrow, so
    /// "set an alarm for 6am" at 9am means tomorrow, not a moment in the past.
    static func futureDate(_ date: Date) -> Date {
        date < Date() ? (Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date) : date
    }

    /// Fill in a due/start date on reminders and events that don't have one yet,
    /// reading it from the user's own words.
    static func attachingDates(_ actions: [DeviceAction], userText: String) -> [DeviceAction] {
        guard actions.contains(where: {
            if case .reminder(_, nil) = $0 { return true }
            if case .calendarEvent(_, nil) = $0 { return true }
            return false
        }) else { return actions }

        let date = firstDate(in: userText)
        guard let date else { return actions }
        return actions.map { action in
            switch action {
            case .reminder(let title, nil):     return .reminder(title: title, due: date)
            case .calendarEvent(let title, nil): return .calendarEvent(title: title, date: date)
            default:                             return action
            }
        }
    }

    // MARK: - Plain-language fallback

    /// Keyword-match the user's raw message so core triggers fire regardless of model.
    static func intents(fromUserText text: String) -> [DeviceAction] {
        let t = text.lowercased()
        var actions: [DeviceAction] = []

        let mentionsTorch = t.contains("flashlight") || t.contains("torch")
        if mentionsTorch {
            if t.contains("off") {
                actions.append(.torch(.off))
            } else if t.contains("toggle") {
                actions.append(.torch(.toggle))
            } else if t.contains("on") || t.contains("turn") || t.contains("enable") || t.contains("light up") {
                actions.append(.torch(.on))
            } else {
                actions.append(.torch(.toggle))
            }
        }

        if t.contains("vibrate") || t.contains("buzz") || t.contains("haptic") {
            actions.append(.haptic(.medium))
        }

        if t.contains("brightness") || t.contains("brighter") || t.contains("dimmer") || t.contains("dim ") {
            if t.contains("max") || t.contains("full") || t.contains("brightest") {
                actions.append(.brightness(.max))
            } else if t.contains("min") || t.contains("lowest") || t.contains("darkest") {
                actions.append(.brightness(.min))
            } else if t.contains("dimmer") || t.contains("dim ") || t.contains("down") || t.contains("lower") {
                actions.append(.brightness(.down))
            } else if t.contains("brighter") || t.contains("up") || t.contains("raise") {
                actions.append(.brightness(.up))
            }
        }

        // Timer: "set a 5 minute timer", "timer for 90 seconds".
        if t.contains("timer") || (t.contains("countdown")) {
            if let minutes = durationMinutes(in: t) {
                actions.append(.timer(minutes: minutes, label: nil))
            }
        }

        // Alarm: "set an alarm for 7am", "wake me at 6:30". Needs a clock time in the
        // message; the time-less follow-up to a commute answer ("set an alarm") is
        // resolved against the stashed leave time in AppModel, not here.
        if isAlarmRequest(text), let date = firstDate(in: text) {
            actions.append(.alarm(at: futureDate(date), label: nil))
        }

        // Reminder: "remind me to <X>".
        if let range = text.range(of: "remind me to ", options: .caseInsensitive) {
            let title = cleaned(String(text[range.upperBound...]))
            if !title.isEmpty { actions.append(.reminder(title: title, due: nil)) }
        }

        // Directions: "directions to <X>", "navigate to <X>", "take me to <X>".
        for kw in ["directions to ", "navigate to ", "take me to ", "directions for "] {
            if let range = text.range(of: kw, options: .caseInsensitive) {
                let dest = cleaned(String(text[range.upperBound...]))
                if !dest.isEmpty { actions.append(.directions(destination: dest)); break }
            }
        }

        // Call: only when the message *starts* with "call <name>" — avoids
        // false positives like "call me crazy" mid-sentence.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = prefixArgument(trimmed, keyword: "call ") {
            actions.append(.call(contact: name))
        }

        // Text: "text <name>" / "message <name>", optionally "... saying <body>". Allowed
        // at the start or after an "and"/comma so it fires inside a multi-action request
        // ("...and text Claire"), while the word boundary avoids stray matches like
        // "context". A rough name|body split is fine — DeviceActions re-resolves the
        // contact against the address book; no body → an empty compose the user fills in.
        if let regex = try? NSRegularExpression(
            pattern: #"(?:^|\band\b\s+|,\s*)(?:text|message)\s+(.+)$"#,
            options: [.caseInsensitive]
        ) {
            let ns = text as NSString
            if let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                var contact = cleaned(ns.substring(with: m.range(at: 1)))
                var body: String?
                for delim in [" saying ", " that says ", " to say ", ": "] {
                    if let r = contact.range(of: delim, options: .caseInsensitive) {
                        body = cleaned(String(contact[r.upperBound...]))
                        contact = cleaned(String(contact[..<r.lowerBound]))
                        break
                    }
                }
                if !contact.isEmpty {
                    actions.append(.text(contact: contact, body: (body?.isEmpty ?? true) ? nil : body))
                }
            }
        }

        // Cling parking: "I parked at 45a", "parked in level 3", or bare "parked here".
        var parked = false
        for kw in ["parked at ", "parked in ", "parked on ", "parked near ", "parked by ", "parking spot "] {
            if let range = text.range(of: kw, options: .caseInsensitive) {
                actions.append(.clingParking(label: cleaned(String(text[range.upperBound...]))))
                parked = true
                break
            }
        }
        if !parked, t.contains("parked here") || t.contains("where i parked") || t.contains("save my parking") {
            actions.append(.clingParking(label: ""))
        }

        // Cling note: "cling a note: <x>", "pin a note <x>".
        for kw in ["cling a note:", "cling note:", "cling this:", "pin a note:", "cling a note ", "cling note "] {
            if let range = text.range(of: kw, options: .caseInsensitive) {
                let body = cleaned(String(text[range.upperBound...]))
                if !body.isEmpty { actions.append(.clingNote(text: body)); break }
            }
        }

        // Clink scratchpad / clipboard: explicit "<keyword>: <text>" so we only grab
        // a deliberate payload, never a stray mention.
        for kw in ["scratchpad:", "scratch this:", "note to scratchpad:", "add to scratchpad:"] {
            if let range = text.range(of: kw, options: .caseInsensitive) {
                let body = cleaned(String(text[range.upperBound...]))
                if !body.isEmpty { actions.append(.scratchpadAdd(text: body)); break }
            }
        }
        for kw in ["copy to clipboard:", "add to clipboard:", "clipboard:"] {
            if let range = text.range(of: kw, options: .caseInsensitive) {
                let body = cleaned(String(text[range.upperBound...]))
                if !body.isEmpty { actions.append(.clipboardAdd(text: body)); break }
            }
        }

        return actions
    }

    /// If `s` begins (case-insensitively) with `keyword`, return the cleaned remainder.
    private static func prefixArgument(_ s: String, keyword: String) -> String? {
        guard s.lowercased().hasPrefix(keyword) else { return nil }
        let arg = cleaned(String(s.dropFirst(keyword.count)))
        return arg.isEmpty ? nil : arg
    }

    /// Trim whitespace and a trailing "for me" / punctuation tail from an extracted argument.
    private static func cleaned(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" for me", " please", " for me please"] where out.lowercased().hasSuffix(suffix) {
            out = String(out.dropLast(suffix.count))
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
    }

    /// Spelled-out numbers accepted in spoken durations ("five minute timer").
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "ninety": 90,
    ]

    /// Parse a duration like "5 minutes", "90-second", "1 hour", or "five minute" into
    /// whole minutes. Accepts digits or a number word; tolerates a space or hyphen.
    private static func durationMinutes(in t: String) -> Int? {
        let unitPattern = #"(hours?|hrs?|minutes?|mins?|seconds?|secs?)"#
        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)

        func toMinutes(_ value: Int, unit: String) -> Int {
            if unit.hasPrefix("h") { return value * 60 }
            if unit.hasPrefix("s") { return max(1, Int((Double(value) / 60).rounded())) }
            return value
        }

        // Digits: "5 minutes", "90-second".
        if let regex = try? NSRegularExpression(pattern: #"(\d+)[\s-]*"# + unitPattern),
           let m = regex.firstMatch(in: t, range: full),
           let value = Int(ns.substring(with: m.range(at: 1))) {
            return toMinutes(value, unit: ns.substring(with: m.range(at: 2)))
        }

        // Number words: "five minute timer".
        let words = numberWords.keys.joined(separator: "|")
        if let regex = try? NSRegularExpression(pattern: "(" + words + #")[\s-]*"# + unitPattern),
           let m = regex.firstMatch(in: t, range: full),
           let value = numberWords[ns.substring(with: m.range(at: 1))] {
            return toMinutes(value, unit: ns.substring(with: m.range(at: 2)))
        }
        return nil
    }

    /// Merge model-tag actions with user-intent actions, de-duplicating while
    /// preserving order (tags win since they reflect the model's actual decision).
    static func merged(tagActions: [DeviceAction], userText: String) -> [DeviceAction] {
        var result = tagActions
        for action in intents(fromUserText: userText) where !result.contains(action) {
            result.append(action)
        }
        return result
    }
}
