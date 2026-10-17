# 0003. Read now playing through a helper loaded by /usr/bin/perl

- **Status:** Accepted
- **Date:** 2026-10-15 (commit `390dccf`)
- **Code:** `Apps/Mac/Helpers/NowPlayingHelper.m`, `NowPlayingAdapter`, `MediaMode`, `scripts/build-mac.sh`

## Context

- Media, Remote and the Now Playing StandBy screen show what the Mac is playing, from any player.
- Only MediaRemote, a private macOS framework, knows that for every player.
- Since macOS 15.4, MediaRemote answers only Apple's own processes (bundle IDs starting with `com.apple.`). Glasspad's own calls come back empty.

## Decision

Build a small library, `GlasspadNowPlaying.dylib`, into the app, and run it inside `/usr/bin/perl`, which is an Apple process:

```
/usr/bin/perl -e <loader> /path/to/GlasspadNowPlaying.dylib
```

The helper prints one JSON object per line and reads commands (`send`, `seek`, `shuffle`, `repeat`, `refresh`) from its input. It quits when Glasspad quits.

Sources, best first:

| # | Source | When |
| --- | --- | --- |
| 1 | The perl helper | macOS 15.4 and later |
| 2 | MediaRemote in Glasspad's own process | Before macOS 15.4 |
| 3 | AppleScript to Spotify and Music | Needs the optional Automation permission |

The approach comes from [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause). The helper is a smaller, independent reimplementation that keeps the same output format.

## Consequences

| Good | Cost |
| --- | --- |
| Works for every player, with no extra permission | Depends on `/usr/bin/perl` staying on macOS and loading libraries |
| One helper for every source of media | A separate process to start, watch and restart (`NowPlayingAdapter`) |

## Alternatives considered

- **AppleScript only:** covers Spotify and Music, not browsers, and asks for Automation.
- **MediaRemote in process only:** returns nothing on macOS 15.4 and later.
