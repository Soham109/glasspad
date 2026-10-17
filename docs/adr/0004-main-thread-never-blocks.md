# 0004. Code on the main thread never blocks, checked in every test run

- **Status:** Accepted
- **Date:** 2026-10-16 (commits `902a254`, `0b03527`, `bf87af2`)
- **Code:** `scripts/check-main-thread.py`, `scripts/main-thread-allowlist.txt`, `AutomationProbe`

## Context

- The main thread draws the interface. If it waits, the app freezes.
- The Mac app froze at launch, and later its menu bar icon froze, because the Automation permission check (`AEDeterminePermissionToAutomateTarget`) ran on the main thread while Media polled Spotify or Music. That call can wait a long time.
- Swift's concurrency checks cannot tell a blocking call from a fast one.

## Decision

Code on the main thread never makes a call that can block:

| Not allowed on the main thread | Do this instead |
| --- | --- |
| `AEDeterminePermissionToAutomateTarget` | `AutomationProbe`, off the main thread with a real timeout |
| `Process.waitUntilExit()` | A termination handler, or a background queue |
| Semaphore or group `wait()` | `async`/`await`, or a callback |
| `Thread.sleep`, `sleep`, `usleep` | `Task.sleep`, `asyncAfter` |

`scripts/check-main-thread.py` runs in `scripts/test.sh`. It looks at every main-actor code path (types marked `@MainActor`, SwiftUI, AppKit and UIKit types, closures sent to the main queue) for those calls, directly or one call away. A reviewed exception goes in `scripts/main-thread-allowlist.txt` with the reason.

## Consequences

| Good | Cost |
| --- | --- |
| The freeze cannot come back unnoticed | The check reads source text, so it can miss a call hidden deeper than one level |
| Clear rule for reviewers | Some code needs a callback where a wait would be shorter |

## Alternatives considered

- **Code review only:** the same kind of freeze happened twice, at launch and later in the menu bar icon.
- **A run-time watchdog:** finds a freeze only after a person sees it.
