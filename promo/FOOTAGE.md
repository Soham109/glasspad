# Stock footage (film v4)

Every live action shot in the v4 film is a stock clip from Mixkit, used under the
**Mixkit Stock Video Free License** (checked on each clip's page; clips under Mixkit's
"Restricted License", which forbids commercial and advertising use, were rejected).

> Items under the Mixkit Stock Video Free License can be used in your commercial and
> non-commercial projects, for free. You're permitted to download, copy, modify, distribute,
> publicly perform and broadcast the Items. [...] Attribution is not required.
> (https://mixkit.co/license/#videoFree, limits in the User Terms: https://mixkit.co/terms/)

The User Terms forbid reselling the clips as they are, using them to build a competing stock
service, and bulk downloading by script. The film modifies every clip (the real app is
composited onto its green screens, the hands are keyed onto drawn sets, all of it graded and
cut), and `scripts/fetch-footage.sh` fetches only the seven clips below, one at a time.

No clip shows a person endorsing anything, and nobody in them is named or quoted. The one
visible brand mark is the "MacBook Pro" lettering on a laptop in the Clipboard shot, which
the framing crops out.

| Name in the film | Mixkit clip | Used for | File (as fetched) |
|---|---|---|---|
| desk-topdown | [Smartphone with a green screen on a desk setup](https://mixkit.co/free-stock-video/smartphone-with-a-green-screen-on-a-desk-setup-100069/) | Actions: the morning desk, top down | 3840x2160, 23.976 fps |
| focus-laptop | [A young woman typing on a laptop computer on the...](https://mixkit.co/free-stock-video/a-young-woman-typing-on-a-laptop-computer-on-the-100057/) | Layouts: writing at the laptop | 3840x2160, 23.976 fps |
| edit-suite | [A young gamer in front of a PC monitor with a green screen and an RGB PC rig](https://mixkit.co/free-stock-video/a-young-gamer-in-front-of-a-pc-monitor-with-51602/) | Final Cut: the edit suite | 3840x2160, 23.976 fps |
| hands-phone | [Hands using a cellphone with tracking point on a green screen](https://mixkit.co/free-stock-video/hands-using-a-cellphone-with-tracking-point-on-a-green-28300/) | Present: the presenter's hands on Next | 1920x1080, 59.94 fps (largest size offered) |
| couch-phone | [A young woman relaxing on the couch with mobile phone](https://mixkit.co/free-stock-video/a-young-woman-relaxing-on-the-couch-with-mobile-phone-100059/) | Remote: the couch | 3840x2160, 23.976 fps |
| handoff | [Copying from a cell phone to the computer](https://mixkit.co/free-stock-video/copying-from-a-cell-phone-to-the-computer-42630/) | Clipboard | 3840x2160, 23.976 fps |
| two-screens | [Man working on computer with chroma green background](https://mixkit.co/free-stock-video/man-working-on-computer-with-chroma-green-background-44737/) | Displays: a monitor and a laptop | 3840x2160, 23.976 fps |

Exact download URLs and SHA-256 checksums are in `scripts/fetch-footage.sh`.

## Pipeline

```bash
scripts/fetch-footage.sh                                   # public/footage/src/*.mp4 (not committed)
~/Library/Caches/glasspad-film-venv/bin/python -I scripts/v4/footage.py   # tracks and keyed layers
```

`scripts/v4/footage.py` (OpenCV, NumPy) finds each green screen in every frame, fits its four
corners (the four longest sides of the outline, intersected, so rounded corners and fingers
over an edge do not pull them in), smooths the track over time, and writes:

- `src/v4/tracks/<name>.json` (committed): the corners per frame.
- `public/footage/<name>/fg.mov` (not committed): ProRes 4444 with alpha, cropped around the
  screen: everything that is not green (hands, bezels, fingers) over the screen. Tracking
  markers on the screen are removed; spill is removed only at the key's edges.

In the film (`src/v4/footage/Footage.tsx`) the real app is pinned to the corners with a CSS
`matrix3d` homography, matched to the shot (exposure, a soft sheen), and the keyed layer goes
on top, so the person's own fingers pass over the app.

The venv: `python3 -m venv ~/Library/Caches/glasspad-film-venv && ~/Library/Caches/glasspad-film-venv/bin/pip install opencv-python-headless numpy`.
