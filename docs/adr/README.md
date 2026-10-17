# Architecture decision records

An ADR (architecture decision record) is a short note of **why** a decision was made, so nobody has to rediscover it. Each one is a page: the problem, the choice, and what it costs.

| # | Decision | Status | Date |
| --- | --- | --- | --- |
| [0001](0001-free-apple-id-with-automatic-renewal.md) | Install with a free Apple ID; the Mac renews the iPhone app | Accepted | 2026-10-15 |
| [0002](0002-mission-control-through-the-dock.md) | Mission Control, App Exposé and Show Desktop buttons ask the Dock | Accepted | 2026-10-16 |
| [0003](0003-now-playing-through-perl.md) | Read now playing through a helper loaded by `/usr/bin/perl` | Accepted | 2026-10-15 |
| [0004](0004-main-thread-never-blocks.md) | Code on the main thread never blocks, checked in every test run | Accepted | 2026-10-16 |
| [0005](0005-additive-protocol-and-frozen-wire.md) | Protocol changes are additive, and released messages are frozen in tests | Accepted | 2026-10-16 |

## Writing a new one

1. Copy [template.md](template.md) to `NNNN-short-title.md`, with the next number.
2. Fill it in. Keep it to one screen.
3. Add a row above, in the same pull request as the change it explains.

An ADR is never edited to say something new. To change a decision, write a new ADR and set the old one's status to `Superseded by NNNN`.
