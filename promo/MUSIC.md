# Music and sound

## Score

| | |
| --- | --- |
| Title | Brand New World |
| Artist | Kai Engel |
| Source | https://commons.wikimedia.org/wiki/File:Kai_Engel_-_01_-_Brand_New_World.ogg |
| File | https://upload.wikimedia.org/wikipedia/commons/3/34/Kai_Engel_-_01_-_Brand_New_World.ogg |
| SHA-1 | 2377a4368d4b22c41e5e72e82e38dcc268071ece |
| Licence | Creative Commons Attribution 4.0 (CC BY 4.0), https://creativecommons.org/licenses/by/4.0 |
| Attribution required | Yes |

Credit line, used on both end cards and in the README:

> Music: "Brand New World" by Kai Engel, CC BY 4.0

The track is edited (shortened and re-ordered on its own bar grid) and mixed under the voice.
CC BY 4.0 allows this, including in promotional use, with the credit above. Changes made:
cut and re-sequenced, faded in and out, level-ducked under the narration.

Why not ElevenLabs music: the account is on the free plan, and the music API answered
`402 paid_plan_required`.

Getting the file again (it is not committed):

```bash
mkdir -p voice/work/music
curl -L -A "GlasspadPromoFilm/1.0 (https://github.com/Soham109/glasspad)" \
  -o voice/work/music/kai-engel-brand-new-world.ogg \
  https://upload.wikimedia.org/wikipedia/commons/3/34/Kai_Engel_-_01_-_Brand_New_World.ogg
```

## The edit

120 BPM. Bar k starts at 4.0033 + 1.99988 k seconds (fitted to 243 beats, 16 ms residual).
Each 8 s phrase is four bars; every phrase starts on the same chord, so phrase to phrase splices
are harmonically safe. Splices are 12 ms equal-power crossfades, 6 ms before the downbeat.

| Film time | Track bars | What it is |
| --- | --- | --- |
| 0 to 8 s | 36 to 39 | the quiet phrase before a return: the hook |
| 8 to 56 s | 8 to 31 | first full entry on the title, lift at 40 s for the modes |
| 56 to 68 s | 40 to 45 | the full return, under Media |
| 68 to 74.8 s | 78 to 81 | the track's own cadence; the final chord lands with the URLs at 72 s |

Teaser: bars 38 to 39, 8 to 11, 40 to 43, 76 to 80. All in `src/v2/edit.json`.

## Sound design

Every UI sound (taps, the haptic knock, whooshes on camera moves, the riser and impact on the
title, ticks for the display frames) is synthesized in `scripts/film/mix.py`. No samples, so
nothing else to license.

## Mix

`scripts/film/mix.py`: voice lines levelled to the same loudness, music ducked about 8.5 dB
under the voice (voice sits 9 to 15 dB above the bed), master to -14 LUFS integrated with a
true-peak limiter. Measured on the final MP4s: -14.0 LUFS, true peak -1.2 to -1.5 dBTP.
