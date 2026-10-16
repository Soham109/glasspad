# Glasspad product review (15 Oct 2026)

Read-only review. Sources: README, docs/SPEC.md, docs/UX-REVIEW.md, docs/SPEC-requests.md, a skim of Apps/iOS and Packages. Nothing in the code was changed.

## Competitor snapshot

Verified by web search this session (vendor listings only, no hands-on testing):
- Remote Mouse, Mobile Mouse, Unified Remote: mouse, keyboard, media, presentation tools, many per-app remotes (Unified Remote claims 90+), file manager and Wake on LAN (Unified Remote), cross-device clipboard (Remote Mouse). Windows and Linux hosts too.
- Newer iPhone trackpad apps: TouchLink (free trackpad and keyboard, paid launcher, updated 29 Jun 2026), Control My Mac (released 30 Jun 2026), Tracepad (Bluetooth or USB, updated Jan 2026), PhonePad, El Trackpad (USB, 2020). All need a Mac companion app.

Not verified (from memory, no source fetched): current prices and gating of Remote Mouse and Mobile Mouse, Stream Deck Mobile details, Jump Desktop specifics, and whether Apple has added any iPhone-as-trackpad feature in macOS 26 / iOS 26. Apple's Universal Control and Sidebar are iPad-to-Mac only as far as I know. Check before quoting any of this publicly.

Where Glasspad already wins: haptic clicks, real Spaces and Mission Control gestures, mirrored macOS trackpad settings, encrypted QR pairing, mirrored Dock, front-app-aware Actions, macro recording, Shortcuts, free and open source, no account.

Where it loses: install friction (Xcode, cable, 7-day renewal, no App Store), Mac only, same Wi-Fi only, no file transfer, no screen view, nothing on the Lock Screen or Control Center beyond the existing widgets and Live Activity.

## Ranked proposals (impact / effort, best first)

Impact 1-5. Effort S/M/L. "Breaks?" = risk to existing behaviour.

| # | What | Why a user cares | Viability | Impact | Effort | Breaks? |
|---|---|---|---|---|---|---|
| 1 | Accessibility-off warning on the phone (already a known open item in UX-REVIEW) | The most common first-run failure is a pointer that silently does nothing, and it recurs after every reinstall or auto-renew | VIABLE. `AXIsProcessTrusted` is public; needs one new Mac to phone control message | 5 | S | Low. Additive message, old phones ignore it. Confirm the decoder tolerates unknown cases |
| 2 | "Copy pairing link" in Mac popover (SPEC-requests item 3, not marked done) | Pairing without a camera (and demos, and Mac to second iPhone) | VIABLE. Pasteboard only | 3 | S | None |
| 3 | In-app first-run checklist on the phone: Local Network permission, Mac found, Accessibility on, test move | iOS Local Network prompt denial looks identical to "Mac not found". A guided check removes most support questions | VIABLE. Public APIs. Detecting denial is awkward (no direct query; infer from Bonjour failure). Treat the detection as RISKY, the checklist as VIABLE | 4 | M | Low |
| 4 | Pairing and connection diagnostics screen ("why can't I connect") showing RTT, Wi-Fi vs other network, Mac asleep, client isolation hint | Hotel, office and guest Wi-Fi block device to device traffic; users blame the app | VIABLE. Reuse existing RTT and discovery state | 3 | S | None |
| 5 | Control Center control and Lock Screen / Action Button shortcut that opens straight to Trackpad | Table stakes for a remote: speed to first touch. Widgets and App Intents already exist | VIABLE on iOS 18+ via `ControlWidget` and the existing `OpenTrackpadIntent` | 3 | S | None |
| 6 | Wake Mac button wired to the UI (kit has `WakeOnLAN` and `KnownMacsStore`; SPEC-requests says phone should offer it) | Unified Remote has it; matters for "Mac asleep across the room" | VIABLE but RISKY: broadcast needs the multicast entitlement, which free Apple ID sideloading likely cannot get (unverified). Unicast to a known IP may suffice. Mac must have Wake for network access on | 3 | M | Low |
| 7 | Signed, notarized Mac app plus a Mac-side DMG (roadmap item) | Removes Gatekeeper and Accessibility-reset pain on the Mac half | VIABLE (needs paid Apple Developer account for the Mac side, 99 USD per year) | 4 | M | Medium. Changes the app's signing identity, so Accessibility and Automation grants reset once |
| 8 | TestFlight or paid-account install path documented as the "no 7-day renewal" option | The 7-day limit and Xcode requirement are the biggest adoption wall | VIABLE for TestFlight (needs paid account; free Apple ID cannot). AltStore or SideStore style install is RISKY (third party, policy changes; unverified for iOS 26). Alternative-marketplace distribution is region limited | 5 | M | None to code |
| 9 | Shareable macro and Pinned deck files (roadmap) plus a starter pack gallery | Community content is the moat against paid competitors; exports of `deck.json` and macros as files, imported via Files or AirDrop | VIABLE. Security note: imported macros run keystrokes and shell-like actions, so import must show a preview and never auto-run | 4 | M | Low. New file format; version it |
| 10 | Typing quality: Mac to phone text sync is not needed, but add key repeat for held arrows/backspace, Fn row, and a persistent modifier lock | Keyboard mode currently has Esc, Tab, arrows and a shortcut row. Heavy users hit missing keys fast | VIABLE. CGEvent keys already used | 3 | S | Low |
| 11 | Edge and corner hot zones on the pad (e.g. right edge two-finger scroll strip, corner right-click) | Competitors offer one-finger scroll; helps one-handed use | VIABLE (phone-side gesture recogniser only) | 2 | S | Medium. Must be off by default so tap and drag behaviour stays |
| 12 | Three-finger drag, tap-to-drag lock, and corner secondary click parity checks against the Mac's accessibility trackpad options | Mirroring settings is the headline feature; gaps here break the promise | VIABLE. `dragLock` haptic exists, so part is built; verify the rest | 3 | M | Medium (gesture engine) |
| 13 | iPad support (roadmap) | Larger pad, Split View with Actions | VIABLE (SwiftUI app; layouts need work) | 3 | L | Low |
| 14 | Mac screen peek: low frame rate thumbnail of the Mac screen for the Laser pointer and for "where is my pointer" | Competitors with remote desktop (Jump) do this; for Glasspad it would help Present | RISKY. Needs Screen Recording permission, adds a heavy stream, and breaks the "nothing heavy, minimal" principle | 3 | L | Medium (new permission, battery, thermal) |
| 15 | File drop: send a photo or file from the phone to the Mac Downloads | Unified Remote and Remote Mouse offer file transfer; Continuity AirDrop already covers this well | VIABLE but low differentiation (AirDrop exists) | 2 | M | Low |
| 16 | Universal Control style cursor hand-off, or Sidecar-like extended display | Apple only does this iPad to Mac | NOT VIABLE for iPhone: no public API, and private Continuity paths are signed and entitled | 1 | L | n/a |
| 17 | Real pressure Force Touch | Phone has no pressure sensor; current half-second hold is the right workaround. SPEC-requests notes a private pressure event (type 34) for the Mac side | RISKY (private event type, may break per macOS release); the phone cannot supply pressure anyway | 1 | M | High |
| 18 | Windows or Linux host | Competitors' main reach | VIABLE technically but a different product; dilutes the macOS-feel pitch. Do not do | 2 | L | High (protocol and gestures) |
| 19 | Over-the-internet use | Competitors with cloud relays offer it | RISKY: breaks the "nothing leaves your network" privacy claim; if ever done, relay must only see ciphertext, which the current ChaCha20 session design permits | 2 | L | High |
| 20 | App Store release | Biggest reach lever | NOT VIABLE as is: Mac side needs Accessibility, private gestures and event taps, which the Mac App Store sandbox forbids. iPhone app alone might pass review, but is useless without the Mac helper | 5 | L | High |

## Missing table stakes, summarised
- Wake Mac in the UI (row 6), Control Center / Action Button entry (row 5), key repeat and Fn row (row 10), one-finger scroll option (row 11), accessible install path (rows 7, 8).
- Competitors' bigger libraries of per-app remotes: Glasspad's answer is the front-app Actions plus shareable packs (row 9). Do not copy their breadth.

## Onboarding and first-run gaps
- Install needs Xcode, cable, Developer Mode, trust step, and 7-day renewal. The installer helps, but there is no in-app explanation of any of it (rows 3, 8).
- Silent failure when Accessibility is off, after every reinstall (row 1).
- Local Network permission denial looks like "Mac not found" (rows 3, 4).
- No sample or demo mode visible to someone who has not paired yet. There is a `DemoData` and `DemoScript` in the app, so offering a "Try without a Mac" screen is a small step. Worth checking whether it is reachable outside screenshot builds (unverified).
- Latency claim "numbers will be published once measured" in the FAQ is an open promise; publish measured numbers on real hardware before launch.

## Differentiators to double down on
1. Feel: haptics, same acceleration curve, taps never nudge. Publish a short side by side video and the measured latency.
2. Real Mac gestures (Spaces, Mission Control) that remote apps cannot do. Keep the native vs fallback indicator honest.
3. Front-app aware Actions and macro recording, wrapped with Shortcuts and Siri via the existing intents.
4. Privacy and open source: no account, no servers, encrypted pairing. Say it on the first screen.
5. Dock mirror: unique among the apps found; keep it simple.

## Suggested order
Rows 1, 2, 4, 5 first (small, low risk, fix first-run). Then 3, 9, 10, 7. Decide on 8 as a business question (paid account) before building anything.
