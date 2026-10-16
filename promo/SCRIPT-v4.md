# Glasspad film v4: script and shot list

The v3 film sold one idea, the trackpad. Glasspad is now a set of controls for your Mac that
lives on your iPhone, and the film has to show what that means in a day: a desk in the
morning, an afternoon of focus, an edit suite, a stage, a couch, a second display. Each scene
is one person, one place, one thing Glasspad does for them.

What carries over from v3, because it worked:

- **The dot.** One dot under the finger. It is the app icon, the touch on the glass, the
  pointer on the Mac. Every transition between scenes is the dot moving: a touch becomes a
  pointer, a tap becomes a window, a skip becomes the next scene.
- **Timing discipline.** Everything sits on the music's bar grid. Hits land on downbeats;
  scene changes land on phrase starts; the fourth bar of a phrase is where things breathe.
- **Rules.** No dashes anywhere. No invented numbers (no speeds, counts, percentages). Nothing
  said that the picture already says. Product name spoken twice: the open and the end.

New rules for v4:

- **Real people, real places.** Every use case opens on a person in a real room (licensed stock
  footage, see FOOTAGE.md). The app is composited onto their phone, monitor or laptop through
  the footage's own green screen, under their own fingers.
- **The real app.** Every phone screen is a capture of the iOS app in the simulator
  (scripts/v4/capture.sh). The Mac side is drawn, true to macOS: real menu bar, real Dock and
  app icons, SF Pro, SF Symbols.
- **On-screen text earns its place or goes.** The only text over picture is the feature name,
  small, in the corner, for the length of its scene, plus the end card. No slogans, no captions
  repeating the voice.
- **No still frame holds.** Every shot has a motivated move: a push toward what is about to
  change, a rack focus to where the result lands, a track along the desk following an object.
  Nothing floats for its own sake.
- **Voice.** Natural, unhurried: 140 to 155 words a minute inside a line, a breath between
  lines. Lines are cut to fit scenes, never sped up to fit.

## Timing

- Music: "Uplifting Electronic Indie" by WinnieTheMoog (CC BY 4.0), the v3 score, 145 BPM.
  One bar = 1.6552 s. Re-cut on its own bar grid for a longer film (MUSIC.md).
- Length: 67.5 bars of picture plus the score's ring out, about 114 s.
- Track sections used: intro (track bars 0 to 4), verse (4 to 20), lift (20 to 36),
  breakdown (52 to 60), build (60 to 68), lift again (68 to 76), last verse (92 to 96),
  stop (96 to 99.5).

| # | Scene | Use case | Film bars | Track bars | Feel |
|---|---|---|---|---|---|
| 0 | Open | What Glasspad is | 0 to 4 | 0 to 4 | Quiet, curious |
| 1 | Morning desk | Buttons follow the app in front | 4 to 12 | 4 to 12 | Easy start |
| 2 | Pinned | Everyday Mac controls, one tap | 12 to 20 | 12 to 20 | Confident |
| 3 | Focus | Layouts: two tools at once | 20 to 26 | 20 to 26 | Lift |
| 4 | Edit suite | Pro app buttons (Final Cut) | 26 to 31 | 26 to 31 | Drive |
| 5 | Stage | Present: slides, timer, laser | 31 to 36 | 31 to 36 | Peak |
| 6 | Couch | Remote | 36 to 44 | 52 to 60 | Breakdown, warm |
| 7 | Handoff | Clipboard: phone to Mac | 44 to 48 | 60 to 64 | Build |
| 8 | Two screens | Send a window to the other display | 48 to 52 | 64 to 68 | Build |
| 9 | Everything else | Keyboard, Media, Dock, Macros, Trackpad | 52 to 60 | 68 to 76 | Full |
| 10 | Private | No account, no cloud | 60 to 64 | 92 to 96 | Settles |
| 11 | End card | Free and open source | 64 to 67.5 | 96 to 99.5 | Stop |

## Voice

Sarah (ElevenLabs eleven_v4), as v3. Measured words a minute are in `src/v4/vo-measured.json`.

```
OPEN        Glasspad puts your Mac's controls on your iPhone.
ACTIONS     In the morning, it follows you from app to app.
            Open Safari, and the buttons change to match.
PINNED      The things you do every day stay pinned.
            Split Screen. Do Not Disturb.
LAYOUTS     Split the phone itself, and keep two tools open at once.
EDIT        In Final Cut, the edits you make most sit under your thumb.
PRESENT     On stage, it moves your slides, keeps time, and points for you.
REMOTE      On the couch, it becomes a remote.
            Swipe to skip. Type to search.
CLIPBOARD   Copy on your phone. Paste on your Mac.
DISPLAYS    Send a window to the other display, without reaching for it.
MORE        Keyboard, media, your Dock and macros are a tap away.
            And under it all, a trackpad you can feel.
PRIVATE     No account. No cloud. It all stays on your Wi-Fi.
END         Glasspad. Free and open source.
```

Why each line is worded the way it is:

- OPEN says the whole product in one plain sentence, so every scene after it is an example,
  not a new idea. "Controls" not "control surface": no jargon.
- ACTIONS names the morning (the setting) and the behaviour (follows you). The second line
  is the proof the picture shows: one app click, the buttons re-lay themselves.
- PINNED names two real buttons; the picture shows both working. Spoken names match the
  button labels exactly.
- LAYOUTS: "split the phone itself" is the surprise; the picture shows a divider dragged.
- EDIT: "sit under your thumb" is the feeling; the picture is the Blade button cutting a clip.
- PRESENT: three verbs, three things on screen (next slide, timer, laser), in that order.
- REMOTE: the couch line is a reveal; the two short sentences each get one gesture.
- CLIPBOARD and DISPLAYS: one sentence each; the picture does the work.
- MORE: a fast list over fast cuts, then the slow half line returns to where Glasspad began.
- PRIVATE and END: as v3, tightened.

## Shot list

Camera language for the whole film: the person is always seen first, wide or over the
shoulder; then we move in to the phone; then the result lands somewhere else in the room and
focus racks to it. Screen direction: the phone is always to the right of the Mac it controls,
so anything sent from phone to Mac travels right to left, every time. Moves are eased
(springs for objects, slow in and long settle for the camera); fast moves get motion blur.

### 0. Open (bars 0 to 4). "Glasspad puts your Mac's controls on your iPhone."
Purpose: say what it is, and plant the dot.

1. Macro, black frame. A single soft point of light swells: a fingertip's contact on glass,
   very shallow depth of field. It is the dot.
2. Rack focus and pull back (continuous): the dot is on the screen of an iPhone standing
   sideways on a stand. The phone screen wakes to Actions (real capture) as the camera keeps
   pulling back, low and slow, past the phone to a desk at dawn: monitor in the centre,
   MacBook on the left, phone on the right. Light sweeps across the glass.
3. "Glasspad" wordmark sets small under the desk, leaves on bar 4.

### 1. Morning desk (bars 4 to 12). Actions follow the app in front.
Purpose: the buttons change with the app.

1. Top down, real footage: a desk with coffee and notebooks, a phone lying among them showing
   Actions (composited onto the footage's green screen). Slow push in.
2. Match cut on the phone's outline into the drawn desk, three quarter view. Mail is in front
   on the monitor; the phone shows Mail buttons.
3. Track right along the desk following the pointer: it clicks a Safari window. Mid move the
   focus racks from the monitor to the phone: the phone's buttons re-lay themselves to Safari
   (real recording, the Mac's front app switch is scripted in the app).

### 2. Pinned (bars 12 to 20). Split Screen. Do Not Disturb.
Purpose: everyday Mac controls, one tap away.

1. Low angle hero of the phone on its stand, Pinned in focus. The dot lands on Split Screen.
2. Whip to the monitor (motion blur): two windows spring to the left and right halves.
3. Push in on the phone: the dot lands on Do Not Disturb; the button lights.
4. Rack to the Mac: a notification banner that was sliding in folds away; the menu bar shows
   the Focus moon.

### 3. Focus (bars 20 to 26). Layouts.
Purpose: the phone's screen splits into two tools.

1. Over the shoulder, real footage: a person typing on a laptop (laptop screen composited:
   a document in a quiet editor).
2. Cut to the phone flat on the desk, top down, close: a layout with two panes (real
   capture). The dot grabs the divider and drags it; the panes resize (real recording of the
   app's own divider drag).

### 4. Edit suite (bars 26 to 31). Final Cut buttons.
Purpose: a pro app gets its own buttons.

1. Real footage: a dark room, someone at a monitor (monitor composited: a Final Cut style
   timeline, drawn, no logos).
2. Macro on the phone: Final Cut buttons (real capture). The dot taps Blade.
3. Rack focus to the monitor: the clip under the playhead splits in two.

### 5. Stage (bars 31 to 36). Present.
Purpose: slides, timer and laser from the phone.

1. Wide, real footage of a presenter keyed onto a drawn stage with a large screen.
2. Over the shoulder close: Present mode on the phone (real capture). Next: the slide on the
   big screen changes. The timer runs.
3. The dot is held on the touch pad: a laser point appears on the big screen and moves.

### 6. Couch (bars 36 to 44). Remote.
Purpose: a TV remote for whatever the Mac is playing.

1. Real footage: a person relaxing on a couch with a phone (green screen phone, tracked):
   the Remote is composited on it, following the phone as she moves.
2. Cut to the TV (drawn, in a dim room): a film plays. A swipe on the phone (dot trail) skips
   it forward: the picture jumps, a small skip mark shows.
3. Search: letters typed on the phone appear in the player's search field on the TV.

### 7. Handoff (bars 44 to 48). Clipboard.
Purpose: phone clipboard to Mac.

1. Real footage: a hand holds a phone over a laptop keyboard (both screens composited:
   Clipboard on the phone, a document on the laptop).
2. Tap Paste: the copied photo lifts off the phone, travels right to left, and lands in the
   Mac document.

### 8. Two screens (bars 48 to 52). Next Display.
Purpose: move a window to the other display from the phone.

1. Real footage: an office desk with a monitor and a laptop (both composited).
2. The dot taps Next Display on the phone (inset close, real capture); the window slides off
   the monitor and onto the laptop screen. The camera pans with it.

### 9. Everything else (bars 52 to 60). Keyboard, Media, Dock, Macros, Trackpad.
Purpose: the rest of the app, quickly, then home.

1. The mode menu opens (real recording). One bar each, cut on the beat with the dot carrying
   over: Keyboard, Media, Dock, Macros (real captures).
2. Slow down on the last two bars: the phone lies flat as a trackpad (the v3 recording), three
   fingers swipe, the Mac's Space follows the fingers. A ring on each tap shows the haptic.

### 10. Private (bars 60 to 64). No account. No cloud.
Purpose: trust.

1. Pull up and out: the phone and Mac become small inside a rounded outline (your Wi-Fi), one
   line between them with a lock that closes. As v3, simplified.

### 11. End (bars 64 to 67.5).
1. Everything folds into the dot; the dot glides once; the end card sets. The phone beside the
   wordmark cycles through its themes (Graphite, Paper, Mono) on the last three beats.

```
Glasspad
Free and open source.
github.com/Soham109/glasspad
Music: "Uplifting Electronic Indie" by WinnieTheMoog, CC BY 4.0
```

## What is a re-capture after the final merge

See the report and `scripts/v4/capture.sh`: every phone screen is re-made by one command.
