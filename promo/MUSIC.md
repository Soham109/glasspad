# Music and sound

## Score

| | |
| --- | --- |
| Title | Uplifting Electronic Indie |
| Artist | WinnieTheMoog |
| Source | https://commons.wikimedia.org/wiki/File:Uplifting_Electronic_Indie_by_WinnieTheMoog.ogg |
| File | https://upload.wikimedia.org/wikipedia/commons/a/ac/Uplifting_Electronic_Indie_by_WinnieTheMoog.ogg |
| SHA-1 | 050949e57c99bccd5b8772c0e2f28df954245e41 |
| Licence | Creative Commons Attribution 4.0 (CC BY 4.0), https://creativecommons.org/licenses/by/4.0 |
| Attribution required | Yes (checked in the file's Commons metadata) |

Credit line, used on both end cards and in the README:

> Music: "Uplifting Electronic Indie" by WinnieTheMoog, CC BY 4.0

CC BY 4.0 allows editing and promotional use with that credit. Changes made: cut and
re-sequenced on the bar grid, a short synthesized room tail after the final stop, level-ducked
under the narration.

Why this track: the brief asked for something more upbeat with a clear pulse. It is 145 BPM
with a drum pulse throughout (fitted grid residual 1.5 ms over 329 beats), and it has a
stop-start intro, a lift, a breakdown and a hard stop ending, which give the edit its hits.
Rejected on the way: two Commons tracks labelled as made with AI, and stock-sounding
"corporate" cues.

Why not ElevenLabs music: the account is on the free plan, and the music API answered
`402 paid_plan_required`.

Getting the file again (it is not committed):

```bash
mkdir -p voice/work/music
curl -L -A "GlasspadPromoFilm/1.0 (https://github.com/Soham109/glasspad)" \
  -o voice/work/music/winnie-uplifting-electronic-indie.ogg \
  https://upload.wikimedia.org/wikipedia/commons/a/ac/Uplifting_Electronic_Indie_by_WinnieTheMoog.ogg
```

## The edit

145 BPM. Bar k starts at 0.4310 + 1.6552 k seconds. Phrase starts share one chord, so phrase
to phrase splices are harmonically safe. Splices are 12 ms equal-power crossfades, 6 ms before
the downbeat. All in `src/v2/edit.json` ("audio"), built by `scripts/film/build_edit.py`.

| Film time | Track bars | Hit |
| --- | --- | --- |
| 0 to 6.6 s | 0 to 3 | stop-start intro under the hook |
| 6.6 s | 4 | the groove enters on the title |
| 33.1 s | 20 | the lift, on "Tap the top for everything else" |
| 49.7 s | 56 to 59 | drop to the breakdown as the cover opens into privacy |
| 56.3 s | 96 | the return, on the end card |
| 61.2 s | 99 | the hard stop, on the URLs; a synthesized tail rings out |

Teaser: bars 2 to 7, 20 to 23, 58 to 59, 96 to 99.

## Sound design

Every UI sound (taps, the haptic knock, whooshes on camera moves, the riser and impacts on the
hits, ticks for the display frames) is synthesized in `scripts/film/mix.py`. No samples, so
nothing else to license.

## Voice

eleven_v4, voice Sarah. v4 ignores the `speed` setting (measured 4.96 s at 1.0 vs 4.88 s at
1.2), and multilingual v2, which honours it, measured more robotic (uniform 0.23 s pauses,
narrower pitch range, more repeated sentence shapes). So the v4 takes are tightened by
`scripts/film/tighten_voice.py`: long internal pauses shortened, then a 12% pitch-preserving
tempo lift (median pitch unchanged within the tracker's noise).

## Mix

`scripts/film/mix.py`: voice lines levelled to one loudness, music ducked about 8.5 dB under
the voice, master to -14 LUFS integrated with a true-peak limiter.

## Film v4 (the longer cut)

Same track, same licence and credit line (shown on the v4 end card). It fits the longer cut:
its verse, lift, breakdown and build give each group of use cases its own energy.

| Film bars | Film time | Track bars | Section | Scenes |
| --- | --- | --- | --- | --- |
| 0 to 16 | 0 to 26.5 s | 0 to 16 | intro, verse | Open, Actions, Pinned |
| 16 to 32 | 26.5 to 53.0 s | 20 to 36 | lift | Layouts, Final Cut, Present |
| 32 to 48 | 53.0 to 79.5 s | 52 to 68 | breakdown, build | Remote, Clipboard, Displays |
| 48 to 56 | 79.5 to 92.7 s | 68 to 76 | lift again | Modes, Trackpad |
| 56 to 63.5 | 92.7 to 105.1 s | 92 to 99.5 | last verse, hard stop | Private, end card |

Splices are 12 ms equal power, 6 ms before the downbeat, between phrase starts (which share a
chord). All in `src/v4/edit.json`; the mix is `scripts/v4/mix.py`.

Mix (measured by the script with ffmpeg ebur128, numbers from the current draft):

- Voice lines each levelled to the same loudness; the voice alone reads about -15 LUFS in
  the master.
- The bed is side chained to the voice (150 ms look ahead, 120 ms attack, 450 ms release):
  about -27 LUFS under speech and about -18 LUFS in the breaths, so the music rises between
  lines and every word sits about 12 LU above the music.
- Master: -16 LUFS integrated, true peak -1.2 dBTP (4x oversampled limiter), loudness range
  about 5 LU. The no voice version: -17 LUFS, the bed never ducks.
- Sound design (taps, a knock for the haptic and the blade, a few soft whooshes, key ticks,
  one generic chime for the message banner) is synthesized in the script, no samples.

Voice for v4: ElevenLabs eleven_v4, Sarah, one take per line (`scripts/v4/voice.py`, seeds in
`src/v4/vo-lines.json`). Lines the voice read faster than 155 words a minute were eased to
about 150 with a pitch preserving tempo change (never more than 12% slower); the measured
pace of every line is in `src/v4/vo-measured.json`.
