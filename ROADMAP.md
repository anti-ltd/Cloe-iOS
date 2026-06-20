# Cloe Roadmap

> **Cloe** is a fully on-device, **agentic** iOS assistant. It runs Apple's Foundation
> Models on capable hardware and downloaded MLX models (SmolLM / Qwen / Gemma / Llama)
> everywhere else — and it doesn't just *chat*, it **plans, calls tools, reads the
> results, and acts** across multiple steps. Fully offline, no account, no cloud.
>
> **Positioning:** the on-device agent for the iPhones and regions Apple's new Siri abandons.

---

## North star — what "blows Siri away" actually means

Don't compete on world-knowledge or cloud breadth — that's a losing, off-thesis fight. Win on
four things Siri structurally cannot match on the hardware/regions we target, and make each one
a *demonstrable* demo, not a bullet point:

1. **A real on-device agent loop.** Multi-step: read calendar → find contact → draft a text →
   ask to confirm → done. Siri's agentic version is cloud-assisted and device/region-gated; ours
   runs the loop locally. **This is the whole product.** Everything else feeds it.
2. **Works with the network off.** The headline demo is the full multi-step flow **in airplane
   mode**, on an **iPhone 13**. No competitor that phones home can do this.
3. **Transparent.** Tool calls render inline as the agent works ("📅 checking your calendar…
   → found 3 events"). The user sees the reasoning. Siri is an opaque black box; trust is a feature.
4. **Private + no-account + EU-available + runs on ~600M excluded phones.** The durable moat (below).

**The three marquee demos** to be able to show end-to-end, offline, on a non-AI phone:
- *"What's my next meeting, and text Sarah I'll be 10 minutes late."* → calendar-read +
  contact-lookup + compose-text (confirm). Three tools, one sentence, no network.
- *"Set a 12-minute timer and turn the flashlight on."* → two tools in one turn.
- *"Remind me to call mom when I get home."* → location-based reminder.

If those three work offline on an iPhone 13, Cloe wins its niche. Build toward them.

---

## The gap we fill

Apple's redesigned LLM Siri (unveiled WWDC 2026, iOS 27) is real and compelling — on-screen
awareness, personal-context search, broad cross-app App Intents actions, multi-turn memory, a
dedicated app, and a Gemini/ChatGPT cloud fallback. But it leaves three durable gaps:

1. **Hardware exclusion (~600M iPhones).** Apple Intelligence requires A17 Pro / 8 GB RAM.
   iPhone 14 and earlier, the non-Pro 15, and the SE run modern iOS but **cannot run Apple
   Intelligence at all.** Cloe's MLX backend runs there. The largest, most durable gap.
2. **EU delay (~450M users).** The new agentic Siri is delayed indefinitely in the EU under the
   DMA. (Base Apple Intelligence shipped to the EU in April 2025; the *new Siri* has not.)
3. **Offline / private / no-account.** Cloe runs all inference on-device, zero data leaving the
   phone, no sign-in, works in airplane mode.

### Honest framing (do not overclaim)

- The new Siri **is** in developer beta now; it is not yet public/GA. The gap is "not yet
  generally available + region/device-gated," not "doesn't exist."
- Cloe's *default* backend on A17+ devices is Apple's own Foundation Models. The defensible wedge
  is therefore **older/excluded hardware + EU + offline privacy + an agent that runs locally** —
  not a blanket "Apple Intelligence is unavailable" claim, which the default path contradicts on
  A17 EU phones.
- Avoid amateur legal framing. Apple's EU block is a feature-interoperability (DMA) decision, not
  a GDPR data-transfer problem. Lean on "runs on your old phone, offline, no account."
- **The agent loop is only as good as the local model.** Sub-2B quantized models plan unreliably.
  Be honest that the full agentic experience is gated to the larger MLX models and Foundation
  Models; weaker phones get a graceful, more deterministic subset. (See "Honest constraints.")

### Use the beta

iOS 27 developer beta ships the new Siri now. Install it and benchmark Cloe against the real
thing — App Intents surface, voice loop, personal-context behavior, *multi-step tool execution* —
instead of guessing parity.

---

## Hard ceiling — never build these

iOS forbids these to third-party apps. Pursuing them wastes time.

| Capability | Why impossible |
| --- | --- |
| Be the system default assistant; intercept "Hey Siri" / the hotword | Apple reserves the assistant role and hotword. No API. |
| Always-on background wake word that wakes the phone from lock | No background always-listening API. Listening is foreground / active-audio-session only. |
| Read or act on other apps' on-screen content (true on-screen awareness) | Forbidden. Cloe sees only its own UI. Siri does this via opted-in App Intents annotations. |
| Semantic search inside Messages / Mail bodies | No third-party read API. (Calendar, Reminders, Contacts, Photos **are** accessible with permission.) |
| Send SMS / place a call silently | `MFMessageComposeViewController` + `tel:` require the user to tap Send / Call. **This is why side-effecting tools need a confirm gate — it's an OS constraint, not a choice.** |
| Toggle Low Power, Focus, Airplane, Wi-Fi, cellular, system volume | Read-only or no API. (Brightness and torch are allowed.) |
| Route to Apple's 20B model or Private Cloud Compute | Third parties get only the ~3B on-device AFM. |
| Worldwide side-button summon | `com.apple.developer.side-button-access` is iOS 26.2, Japan-only. |

**Workaround for "screen awareness":** let the user share / paste a **screenshot into Cloe**
(PhotosPicker + a share extension) and reason over it. Allowed, and approximates the value. A
natural future *tool* in the registry (`describe_screenshot`).

---

## Shipped since last roadmap (was Tier 1, now done)

The original Tier-1 parity items are **built** (verify against device; some not yet device-tested):

- **✅ App Intents + "Ask Cloe" / "Talk to Cloe" shortcuts** (`Intents/CloeIntents.swift`).
  Siri phrases, Shortcuts, Spotlight, Action Button. `AppModel` registers itself via
  `AppDependencyManager` so intents drive the live model (`pendingQuickAction`).
- **✅ Action Button + Control Center + Home/Lock-Screen widgets + Live Activity quick access**
  (`CloeWidgets/*`, `Shared/CloeControlIntent.swift`, `CloeIntentBridge.swift`, `CloeDeepLink.swift`,
  `LiveActivity/CloeLiveActivity.swift`). Deep-link routing (`cloe://voice`) lands in `AppModel`.
- **✅ Conversation persistence + history** (`ConversationStore.swift`, `Conversation`,
  `UI/HistoryView.swift`). The old data-loss bug is fixed — model/thread switches no longer wipe
  messages; history is replayed.

What this means for the agentic push: **the assistant *surface* and *plumbing* exist.** The
missing piece is the *brain* — the loop that turns a request into planned, executed, observed
actions. That's the rest of this document.

---

## Tier 0 — The agentic core (the spine; everything hangs off it)

> This is the rewrite of the product's center. Today Cloe has **two disconnected, non-agentic
> action systems** and they must converge into one.

### The problem to fix

1. **`ActionRouter` `{{tag}}` regex** (`Actions/ActionRouter.swift`) is **fire-and-forget**: the
   model emits `{{torch:on}}`, we run it, the model *guesses* the confirmation sentence and **never
   learns whether the action succeeded.** `DeviceActions.perform` even returns a `Bool` we throw
   away on the model's behalf. No observation → not an agent.
2. **App Intents** are a parallel path with no LLM in the loop.
3. **`AIBackend`** (`AI/AIBackend.swift`) exposes only `streamResponse / resetContext / prewarm` —
   **no tool surface at all.** FM relies on its `LanguageModelSession` memory (and currently
   *ignores* the `history` param); MLX is stateless and replays the full chat each call. Any tool
   loop has to accommodate both shapes.

### The fix: one Tool Registry + one agent loop

#### A. `CloeTool` — declare each capability **once**

A protocol/struct capturing everything a capability needs to be model-callable, intent-callable,
and confirm-gated:

```
protocol CloeTool {
    static var name: String { get }                 // "create_event"
    static var description: String { get }           // for the model + Shortcuts
    associatedtype Arguments: Codable & Generable    // typed params
    static var sideEffecting: Bool { get }           // → needs a confirm gate
    static var availability: ToolAvailability { get } // iOS ver / permission / backend tier
    func execute(_ args: Arguments) async throws -> ToolResult  // text the model reads back
}
```

`ToolResult` is **structured text the model consumes on the next turn** ("3 events today: …").
That return value closing the loop is the single most important change in this whole roadmap.

#### B. Adapters — surface the same registry four ways

| Surface | Mechanism | Reliability |
| --- | --- | --- |
| **Foundation Models** | Wrap each `CloeTool` as an FM `Tool` (`Tool` protocol + `@Generable` args + `call`), feed via `LanguageModelSession(tools:, instructions:)`. FM runs the loop **natively** — calls, observes, continues. | **High** (iOS 26+, A17). Ship first. |
| **MLX** | Inject the tool spec (JSON) into the system prompt; parse `<tool_call>{…}</tool_call>` from the stream (`ToolCallProcessor`); execute; append a `<tool_response>` turn; **re-run `generate`.** MLX already rebuilds the full chat each call, so the loop is natural: detect → stop → execute → append result → regenerate. | **Model-gated.** Reliable only on Qwen3-4B / Llama-3.2-3B class. Smaller models fall back to (D). |
| **App Intents / Shortcuts** | Optionally expose high-value tools (`set_timer`, `create_event`) as discrete `AppIntent`s too, so Siri/Shortcuts run them with **no LLM** — same `execute` underneath. | **High**, deterministic. |
| **Keyword fallback** | `ActionRouter.intents(fromUserText:)` survives as a deterministic safety net for the core device triggers when the model is too weak to tool-call. | **High**, narrow. |

#### C. `AgentRunner` — the loop, lifted out of `AppModel.sendMessage`

A new orchestrator sits between `AppModel` and the backends and owns the turn cycle:

```
plan → (tool call?) → confirm-if-side-effecting → execute → observe result
     → feed back → repeat (bounded: maxSteps ≈ 5) → final answer
```

- Extend `AIBackend` with a tool-aware turn that streams **`AgentEvent`s** (`.token`, `.toolCall`,
  `.toolResult`, `.final`) instead of bare text, OR keep `streamResponse` and let `AgentRunner`
  drive the backend turn-by-turn. Prefer the event stream — it's what the transparent-UI demo needs.
- **Bound the loop** (`maxSteps`) so a confused small model can't spin. Surface a step counter.

#### D. Confirmation gates (OS-required *and* good agent UX)

- **Read-only tools** (`next_meeting`, `find_contact`, `battery_level`, `whats_the_time`) execute
  immediately, no gate.
- **Side-effecting tools** (`send_text`, `create_event`, `set_alarm`, `open_directions`) return a
  **proposed action**; the UI renders a confirm card; `execute` runs only on tap. For texts/calls
  this is *mandatory* (the OS requires the user tap Send/Call anyway — lean into it as UX).

#### E. Transparent tool UI

Render each tool call inline as a chip in the chat ("📅 Checking your calendar…" → "Found 3
events"). Reuse the existing `Message.actions` chip machinery (`MessageBubble`) generalized from
`DeviceAction` to any tool. This *is* North-star #3 — build it with the loop, not after.

**Effort:** `L` for the registry + FM adapter + loop + 3 starter tools. `+M` for the MLX adapter.
**Ship order:** FM tool-calling first (reliable), MLX tool-calling as a capability-gated follow-on.
**Migration:** keep `{{tag}}` working until the registry covers torch/haptic/brightness, then make
those three the *first* registered tools and retire the bespoke tag parser (keep keyword fallback).

---

## Tier 1 — Fill the registry (the tools that make it *do things*)

Each is now "a `CloeTool` + permission + confirm policy," not a bespoke subsystem. Order by
value/effort. The first three are the marquee-demo tools — build those first.

#### 1. Calendar & Reminders tools — `M` — **marquee**
- `next_meeting` / `events_today` (read): `EKEventStore` date-predicate query. Read-only, no gate.
- `create_event` (write): `requestWriteOnlyAccessToEvents()` (no prompt after grant). Confirm gate;
  optional `EKEventEditViewController` for the confirm.
- `create_reminder` (incl. **location-based** — "when I get home"): EventKit reminders, full access.
- Info.plist: `NSCalendarsWriteOnlyAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`.

#### 2. Contacts + call/text tools — `M` — **marquee**
- `find_contact` (read): `CNContactStore` name match. Read-only.
- `send_text` (side-effecting): `MFMessageComposeViewController` — OS forces the user to tap Send,
  so the confirm gate is free. `call_contact`: `tel:` URL (user taps Call).
- Info.plist: `NSContactsUsageDescription`.

#### 3. Timers & alarms — `S–M` — **marquee** (the simplest multi-tool demo)
- `set_timer` / `set_alarm`: **AlarmKit** (iOS 26, WWDC25) — breaks through silent/Focus, shows on
  Lock Screen / Dynamic Island. **Gate behind iOS 26**; won't ship on the MLX / pre-A17 offline path
  → provide a degraded local-notification timer there so the demo still runs on older phones.
- Info.plist: `NSAlarmKitUsageDescription`.

#### 4. Device-control tools (migrate existing) — `S`
- Re-home torch / haptic / brightness from `DeviceActions` into the registry as the **first three
  tools** (read result back: "flashlight's on" only when `perform` returned `true` — closes the
  no-observation bug). Keyword fallback stays.

#### 5. Directions & maps — `S`
- `open_directions`: `MKMapItem.openMaps` / `maps://`. Side-effecting (leaves app) → confirm.

#### 6. On-device personal-context tools — `S–M` structured, `+L` embeddings
- **Phase 1 (ship first):** the read tools above already cover the marquee personal-context demos
  ("next meeting", "X's number") with **no embeddings**.
- **Phase 2 (optional):** `search_photos` over Photos *metadata* (`PHAsset` date/location) via an
  on-device embedding index (`NLContextualEmbedding` or a small MLX embed model).
- **Honest scope:** Messages and Mail are off-limits. Frame as "searches what you grant" — which is
  the privacy story anyway.
- Info.plist: `NSPhotoLibraryUsageDescription` (Phase 2).

> **Architecture cost (don't underestimate):** `DeviceActions.perform`'s synchronous `Bool`
> contract becomes async + permission-aware; several tools present UI or leave the app. This is
> absorbed by the `CloeTool.execute(...) async throws` contract — design it async from day one.

---

## Tier 2 — Experiential edge

#### 7. Continuous hands-free voice loop with barge-in — `M–L` — strongest experiential edge
A true voice-first agent is Cloe's best differentiator on non-AI hardware and in the EU. The pieces
exist (STT auto-submit, TTS) but aren't chained and fight over the audio session.

- **Build:** STT auto-submit → agent loop → TTS → auto-reopen mic, with barge-in (speak to interrupt
  TTS). Spoken confirmation for side-effecting tools ("Want me to send that?") closes the loop hands-free.
- **Required fixes (current code will not work as-is):**
  - **Single shared, persistent `.playAndRecord` session.** Today `SpeechService.configureSession()`
    sets `.playback` while speaking and `VoiceInput.cleanupAudio()` calls `setActive(false)` on stop —
    they fight over the category.
  - **Echo cancellation.** `VoiceInput` uses mode `.measurement`, which disables AEC — the synth's
    output leaks into the mic and is transcribed as user speech (constant false barge-ins). Use mode
    `.voiceChat`, or `AVAudioSession.setPrefersEchoCancelledInput(true)` (iOS 18.2+).
  - Detect speech energy → `synth.stopSpeaking(at: .immediate)`; re-arm STT on
    `AVSpeechSynthesizerDelegate.didFinish`.

#### 8. Multilingual STT/TTS + localized system prompt — `S` — clean beat (new Siri is English-first)
The MLX models (Qwen3 / Gemma3) are already multilingual; only the voice I/O layer is locale-locked.

- **Build:** a language picker wiring `SFSpeechRecognizer(locale:)`, `AVSpeechSynthesisVoice(language:)`,
  and a localized `ActionRouter.systemPrompt` (String Catalog). Tool descriptions localize too.
- **Caveats:** build the STT locale list from `SFSpeechRecognizer.supportedLocales()` and **gate each
  on `supportsOnDeviceRecognition`** (Cloe sets `requiresOnDeviceRecognition = true`, so unsupported
  locales break the offline promise). Build the TTS list from `AVSpeechSynthesisVoice.speechVoices()`;
  enhanced voices need a Settings download. A localized prompt only helps if the model handles that language.

#### 9. In-app "Hey Cloe" wake word (+ CarPlay, gated) — `L`
- **Wake word (feasible, foreground / audio-session only):** use **`SpeechAnalyzer` / `SpeechTranscriber`**
  (iOS 26, no session time limit, built for long-form continuous on-device transcription) — *not*
  `SFSpeechRecognizer` continuous (legacy, ~1-min cap). Cloe uses `SFSpeechRecognizer` today, so migrate.
  Be explicit: cannot wake from lock / background.
- **CarPlay (gated, uncertain):** Apple-granted entitlement. iOS 26.4 opened a third-party voice-assistant
  CarPlay path (ChatGPT/Gemini use it), but **no wake word in CarPlay, and the app may not control vehicle
  systems or iPhone settings** (kills the device-action tools there). Apply as a separate bet or drop it.

---

## Tier 3 — Positioning & polish

#### 10. Offline / older-device / no-account positioning baked in — `S`
- **Already true (no code change):** zero network at inference — no analytics/telemetry/crash SDKs
  anywhere; the only network use is the MLX model download at setup.
- **Required, currently missing:** a `PrivacyInfo.xcprivacy` privacy manifest + an accurate App Store
  privacy label (declare zero data collection). No privacy manifest or entitlements file today.
- **Badge:** scope to "inference runs on-device / offline" — not an absolute "no data leaves device"
  (App Review rejects unverifiable absolutes; the model download would contradict it).
- **Onboarding / store copy:** target older/excluded devices + EU + offline + no-account + *on-device agent*.

#### 11. RAM-aware model auto-recommend — `S` — mostly already built
- `ModelSetupView` already greys out / locks A17-only models. **Real work:** add a RAM check to
  `DeviceCapability` (today only `isA17OrNewer`, a chip-ID check — no memory check) via
  `ProcessInfo.processInfo.physicalMemory` / `os_proc_available_memory()`, and auto-select the largest
  catalog model that fits on first launch. Tie this to the agent: **only recommend a tool-call-capable
  model (≥3–4B) when RAM allows**, so the agentic loop is enabled only where it'll actually work.

---

## Honest constraints & risks (read before building Tier 0)

- **Small-model planning is the #1 risk.** Sub-2B quantized models hallucinate tool calls, loop, and
  botch JSON args. Mitigation: gate the MLX agent loop to ≥3–4B; bound `maxSteps`; validate tool args
  against the schema and reject/repair malformed calls; always keep the deterministic keyword fallback.
- **FM vs MLX are different animals.** FM has native, reliable tool-calling but a fixed ~3B model and
  ignores our `history` (session-stateful). MLX is stateless, replays history, and tool-calls only via
  prompt-injected `<tool_call>` parsing. The `AgentRunner` must abstract both; don't assume parity.
- **Confirm gates are non-negotiable for texts/calls** (OS requirement) — design the UI around them
  rather than fighting them.
- **Latency.** Each agent step is a full generation. Multi-step loops on a small model on an old phone
  can be slow — stream tool chips immediately so it *feels* responsive, and cap steps.
- **Permissions cascade.** Each tool adds an Info.plist key + a runtime grant flow. Batch the asks
  sensibly; never block chat on a permission the user declined — degrade the tool, keep the conversation.

---

## Suggested sequence

1. **Tier 0** — Tool Registry + FM adapter + `AgentRunner` loop + transparent tool UI, with
   torch/haptic/brightness migrated as the first three tools (proves the loop end-to-end on shipped
   capabilities, no new permissions).
2. **Tier 1 #1–3** (calendar, contacts, timers) — the three marquee-demo tools. Now the loop *does things*.
3. **Tier 0 MLX adapter** — bring the loop to non-AI phones (capability-gated to ≥3–4B).
4. **Tier 1 #4–6** — device-tool cleanup, directions, personal-context Phase 1.
5. **Tier 2 #7** (voice loop) — the headline experiential differentiator, now agent-aware.
6. **Tier 2 #8** (multilingual) + **Tier 3 #10–11** (positioning, RAM/agent gating) — small, ship alongside.
7. **Tier 2 #9** (wake word / CarPlay) + personal-context Phase 2 (embeddings) — larger bets, last.

---

## Current state (reference)

- **Backends:** Foundation Models (iOS 26+, A17 Pro) and MLX (downloaded quantized models — SmolLM 135M
  → Qwen3 4B), behind the `AIBackend` protocol. Fully offline after download. **No tool surface yet.**
- **Actions:** torch, haptic, brightness — via model `{{tag}}` emission **and** keyword fallback
  (`ActionRouter` / `DeviceActions`). **Fire-and-forget; no result feedback to the model** (the gap
  Tier 0 closes).
- **Assistant surface (shipped):** App Intents ("Ask Cloe" / "Talk to Cloe"), Shortcuts, Spotlight,
  Action Button, Control Center + Home/Lock-Screen widgets, Live Activity quick access, deep links.
- **Persistence (shipped):** on-device conversation store + history; model/thread switches no longer wipe.
- **Voice:** on-device STT (`SFSpeechRecognizer`, hands-free auto-submit on silence) and TTS
  (`AVSpeechSynthesizer`, autoSpeak). Not yet chained into a continuous loop.
- **Settings flags:** `preferMLX`, `selectedMLXModelID`, `autoSpeak`, `enableDeviceActions`,
  `liveActivityEnabled`, `dictationSilence`.
- **Status:** builds; **not yet device-verified** (post-rename).

_New `.swift` files require `xcodegen generate` before they compile (the app builds CloeKit into the
same module). Confirm against the iOS 27 developer beta for real-Siri parity — especially multi-step
tool execution._
