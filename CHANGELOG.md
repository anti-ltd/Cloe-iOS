# Changelog

All notable changes to Cloe are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

### Added
- **"What time do I need to leave?"** Ask Cloe when to set off and it works out a
  real answer from live traffic — *"I need to be at work for 8am, what time do I
  need to leave?"* It checks the drive (or walk/transit if you say so) to your
  destination and tells you the exact time to head out. Reply **"set an alarm"**
  (or just *"yes"*) and Cloe sets one for that leave time. *Work* and *home* come
  from your contact card or the new **Settings → Commute** addresses; anywhere
  else, just name the place.
- **Alarms.** Cloe can set a wake-up alarm at a clock time — *"set an alarm for
  6:45am"* — alongside the countdown timers it already does. Rings through Silent
  and Focus, just like the Clock app.
- **Home & Lock Screen widgets.** Add a Cloe widget to your Home Screen (tap to
  chat, or tap the mic to talk) or a Lock Screen widget for one-tap access — plus
  a **"Talk to Cloe" button for Control Center** and the Action Button. Unlike the
  Lock Screen Live Activity, these stay put.
- **Siri, Shortcuts & the Action Button.** Say *"Ask Cloe…"* or *"Talk to Cloe"*
  to Siri, drop Cloe into a Shortcut, find it in Spotlight, or bind it to the
  Action Button — Cloe opens and takes your question (or starts listening) right
  away. No setup, no account.
- **Lock Screen quick access.** A Live Activity pins Cloe to the Lock Screen so
  it's reachable from anywhere — tap the card to open the chat, or tap the mic to
  start talking hands-free. Works on any iPhone, with or without a Dynamic Island.
  The card shows live status: *Thinking…* while a reply generates, then the answer
  so you can glance at it without unlocking. Turn it on in **Settings → Quick
  Access**. (iOS may dismiss the activity after a few hours; flip it back on to
  re-pin it.)
- **Talk to Cloe.** On-device speech-to-text lets you speak instead of type.
  Hold the mic to talk, release to send — or just talk and pause, and Cloe sends
  it for you. Everything is transcribed on-device; nothing leaves the phone.
- **Spoken replies.** Tap the speaker on any reply to hear it, or enable
  **Speak Replies Aloud** to have every answer read out. Adjustable speaking rate.
- **Cloe gets things done.** Ask in plain language and Cloe acts on it:
  - *"set a 10 minute timer"* — a real countdown that rings through Silent and
    Focus and shows on the Lock Screen / Dynamic Island (via AlarmKit).
  - *"remind me to call the dentist tomorrow"* — adds a Reminder, with the
    due date pulled from your own words.
  - *"add lunch with Sara Friday at noon"* — drops an event on your calendar.
  - *"directions to the airport"* — opens the route in Maps.
  - *"call Mom"*, *"text Alex I'm running late"* — finds the contact and dials,
    or hands you a pre-filled message to send (Cloe never sends silently).
- **Works with Cling & Clink.** Cloe talks to its sibling apps:
  - *"I parked at 45a"* — drops a **Cling** parking pin at your current spot,
    labelled 45a, so you can navigate back (falls back to a note if location is
    off). *"Cling a note: pick up the dry cleaning"* pins a note.
  - *"Copy hunter2 to my clipboard"* / *"add this to my scratchpad: …"* — saves
    straight into the **Clink** keyboard's clipboard manager and scratchpad.
  - *"What's on my clipboard?"* / *"read my scratchpad"* — Cloe reads them back.
- **Device control.** Ask Cloe to control the flashlight, haptics, and screen
  brightness in plain language — *"turn on the flashlight"*, *"set brightness to
  max"*. On by default; everything above toggles under **Settings → Device
  Control**, and each capability asks permission the first time it's used.
- **Conversation history.** Past chats are saved on-device and listed in the
  history view. Switching models or starting a new chat no longer wipes what you
  said.
- **Two on-device backends.** Apple Intelligence (Foundation Models) on capable
  hardware, and downloadable MLX models (SmolLM, Qwen, Gemma, Llama) everywhere
  else — fully offline after the one-time download, no account.

### Changed
- The persona is now a warm, friendly assistant first and a device-controller
  second, so replies stay on-topic instead of fixating on device actions.

### Fixed
- Replies no longer parrot a previous turn back at you.
- The chain-of-thought from reasoning models (`<think>…</think>`) is hidden from
  the chat instead of leaking into the bubble.
