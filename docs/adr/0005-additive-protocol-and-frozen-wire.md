# 0005. Protocol changes are additive, and released messages are frozen in tests

- **Status:** Accepted
- **Date:** 2026-10-16 (commits `c4e8c9f`, `bf87af2`)
- **Code:** `ControlMessage.unknown`, `DeckAction.unsupported`, `LenientDecoding.swift`, `WireGoldenTests`, `WireGolden_*.swift`

## Context

- The phone and the Mac update separately. A person may update the Mac and not the phone for days, or the other way round.
- Each build must ignore what it does not know without ending the session, and must keep data it cannot use.
- A Deck button made by a newer build could be lost when an older build saved the Deck.

## Decision

Every protocol change is additive:

| Rule | How |
| --- | --- |
| New message types are ignored by older builds | An unknown `"t"` decodes as `ControlMessage.unknown` and the session stays up |
| New fields are optional | Older builds ignore them; newer builds accept their absence |
| Nothing is renamed or removed | Old names keep decoding |
| Data from a newer build survives a save | `DeckAction.unsupported` keeps the raw JSON and writes it back unchanged. The Mac never runs it. |

`WireGoldenTests` holds every message exactly as a released build wrote it. Each test run checks that the message still reads, and is written back the same. After each release, the wire is frozen again ([releasing](../releasing.md#after-the-release)).

## Consequences

| Good | Cost |
| --- | --- |
| Any phone works with any Mac from the same era | Old shapes stay in the decoder for good |
| A breaking change fails a test before it ships | Each release adds a frozen file |

## Alternatives considered

- **A version number check that refuses old peers:** forces both devices to update together, which the 7-day install makes painful.
