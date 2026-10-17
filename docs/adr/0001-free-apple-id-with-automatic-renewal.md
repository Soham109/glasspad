# 0001. Install with a free Apple ID; the Mac renews the iPhone app

- **Status:** Accepted
- **Date:** 2026-10-15 (commit `ff46d4e`)
- **Code:** `install.sh`, `scripts/install-phone.sh`, `scripts/setup-autorefresh.sh`, `scripts/refresh-phone.sh`, `ProvisionExpiry`

## Context

- Glasspad must stay free for everyone: no paid services and no paid Apple Developer Program.
- Without the paid program there is no App Store and no TestFlight. The only way onto an iPhone is to build it with Xcode and a free Apple ID.
- Apps signed with a free Apple ID stop opening after 7 days, when their provisioning profile expires.

## Decision

Each person builds both apps from source on their own Mac with their own free Apple ID, through one command (`install.sh`). The Mac then renews the iPhone app by itself:

| Step | Rule |
| --- | --- |
| When | A LaunchAgent runs `scripts/refresh-phone.sh` every hour and at login |
| From | Day 5 of the 7 |
| What | The exact revision installed last, never a newer one |
| If the app is in use | Wait, unless the phone has been idle 30 minutes or under a day is left |
| If the phone is away | Retry next hour; a notice from day 6 |
| Where it shows | Mac Settings > iPhone, iPhone Settings > About |

## Consequences

| Good | Cost |
| --- | --- |
| Free for everyone, no account with us, the code you run is the code you can read | Install needs Xcode, a cable the first time, and Developer Mode |
| Nothing to publish: no binaries, no review | The phone must be on the Mac's Wi-Fi or cable once every few days |
| Renewal never ships an unfinished change | People update by running the installer again |

## Alternatives considered

- **App Store or TestFlight:** need the paid program.
- **Prebuilt, signed downloads:** an iPhone app cannot be shared that way without the paid program.
- **Renew on day 6 or 7:** too little room when the phone is away for a day.
