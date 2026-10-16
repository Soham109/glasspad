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
