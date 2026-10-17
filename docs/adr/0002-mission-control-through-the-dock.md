# 0002. Mission Control, App Exposé and Show Desktop buttons ask the Dock

- **Status:** Accepted
- **Date:** 2026-10-16 (commits `d62b294`, `47dfe0e`, `5a51b78`)
- **Code:** `DeckMode` (`DockView`, `showDockView`), `LiveDeckEnvironment`

## Context

- Actions buttons, the Remote and Siri ("Open Mission Control") can open Mission Control, App Exposé and Show Desktop.
- These were started by running Mission Control's own program. On macOS 27, macOS kills that program when it is started directly, so the buttons stopped working.
- There is no public API for these views.

## Decision

Ask the Dock, the way the Dock's own keys and gestures do: `CoreDockSendNotification` with `com.apple.expose.awake`, `com.apple.expose.front.awake` or `com.apple.showdesktop.awake`. The function is private, loaded at run time with `dlsym`, and checked before use.

If it is missing, fall back to Mission Control's program started through Launch Services, never directly.

Siri's Mission Control waits for the Mac's answer and never sends a second try, because a second one would close it again.

## Consequences

| Good | Cost |
| --- | --- |
| Works on macOS 27 and earlier, the same way the keyboard key does | Relies on a private function that Apple could remove |
| No extra permission | The fallback must stay tested (`DeckModeTests`) |

## Alternatives considered

- **Keyboard shortcuts (Control plus Up Arrow):** depend on the person's shortcut settings, which may be off.
- **Run the program directly:** killed by macOS 27.
