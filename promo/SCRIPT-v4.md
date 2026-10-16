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
  One bar = 1.6552 s. Re-cut on its own bar grid for the longer film (MUSIC.md).
- Length: 63.5 bars of picture plus the score's ring out: 107.7 s.
- Scenes, music segments and voice placements live in `src/v4/edit.json`, read by the picture
  and by the mix, so they cannot drift apart.

| # | Scene | Use case | Film bars | Seconds | Track bars | Feel |
|---|---|---|---|---|---|---|
| 0 | Open | What Glasspad is | 0 to 4 | 0.0 to 6.6 | 0 to 4 | Quiet, curious |
| 1 | Morning desk | Buttons follow the app in front | 4 to 10 | 6.6 to 16.6 | 4 to 10 | Easy start |
| 2 | Pinned | Split Screen, Do Not Disturb | 10 to 16 | 16.6 to 26.5 | 10 to 16 | Confident |
| 3 | Focus | Layouts: a clock beside Actions | 16 to 21 | 26.5 to 34.8 | 20 to 25 | Lift |
| 4 | Edit suite | Final Cut buttons | 21 to 26 | 34.8 to 43.0 | 25 to 30 | Drive |
| 5 | Stage | Present: slides, timer, laser | 26 to 32 | 43.0 to 53.0 | 30 to 36 | Peak |
| 6 | Couch | Remote | 32 to 40 | 53.0 to 66.2 | 52 to 60 | Breakdown, warm |
| 7 | Handoff | Clipboard: phone to Mac | 40 to 44 | 66.2 to 72.8 | 60 to 64 | Build |
| 8 | Two screens | Displays: a window to the other display | 44 to 48 | 72.8 to 79.5 | 64 to 68 | Build |
| 9 | Everything else | Keyboard, Media, Dock, macros, Trackpad | 48 to 56 | 79.5 to 92.7 | 68 to 76 | Full |
| 10 | Private | No account, no cloud | 56 to 60 | 92.7 to 99.3 | 92 to 96 | Settles |
| 11 | End card | Free and open source | 60 to 63.5 | 99.3 to 107.7 | 96 to 99.5, stop | Stop |

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
3. As a message banner slides in on the display, the dot lands on Do Not Disturb: the banner
   goes and the menu bar shows the moon.

### 3. Focus (bars 16 to 21). Layouts.
Purpose: the phone's screen splits into two tools.

1. Over the shoulder, real footage: a person typing on a laptop (laptop screen composited:
   a document in a quiet editor).
2. Cut to the phone flat on the desk, top down, close: Actions alone. The dot drags a line in
   from the left edge and the StandBy clock opens beside Actions (the app's own frames for
   each place of the line, captured with -GPLayoutDragDemo, then the finished layout).
3. Back to her, closer, still writing: the tool sits beside her, out of the way.

### 4. Edit suite (bars 21 to 26). Final Cut buttons.
Purpose: a pro app gets its own buttons.

1. Real footage: a dark room, someone at a monitor (monitor composited: a Final Cut style
   timeline, drawn, no logos).
2. Macro on the phone: Final Cut buttons (real capture). The dot taps Blade.
3. Rack focus to the monitor: the clip under the playhead splits in two.

### 5. Stage (bars 26 to 32). Present.
Purpose: slides, timer and laser from the phone.

1. Wide: a dark hall from the seats, heads in silhouette, the deck's title slide on the screen.
2. The presenter's point of view: real hands (keyed from a green screen clip) hold the phone in
   Present; the finger lands on Next as the voice says "slides": the slide behind changes and
   the timer starts, as the app starts it on the first Next.
3. Back to the screen, pushing in: the laser point walks along the horizon of the photograph.
(A real meeting room clip was tried and dropped: a head crosses the screen it would need.)

### 6. Couch (bars 32 to 40). Remote.
Purpose: a TV remote for whatever the Mac is playing.

1. Real footage: a person relaxing on a couch with a phone (green screen phone, tracked):
   the Remote is composited on it, following the phone as she moves.
2. Cut to the TV (drawn, in a dim room): a film plays. A swipe on the phone (dot trail) skips
   it forward: the picture jumps, a small skip mark shows.
3. Search: letters typed on the phone appear in the player's search field on the TV.

### 7. Handoff (bars 40 to 44). Clipboard.
Purpose: phone clipboard to Mac.

1. Real footage: a hand holds a phone over a laptop keyboard; Clipboard on the phone, with a
   line of text copied on the phone (the simulator's pasteboard, so Paste is live).
2. Tap Paste: the text lifts off the phone toward the laptop, and lands in a note on the Mac.
(Text, not a photo: the simulator's pasteboard takes text only, and the film shows what the
app really did.)

### 8. Two screens (bars 44 to 48). Displays.
Purpose: move a window to the other display from the phone.

1. Real footage: an office desk with a monitor and a laptop (both composited).
2. Close on the phone: Displays, the Mac's two displays drawn as they sit. The dot drags
   Safari from the Studio Display onto the MacBook (real recording: the app's own move, sent
   by the demo Mac at the drop).
3. Back in the room: the window leaves the monitor and lands on the laptop. The camera pans
   with it, right to left.

### 9. Everything else (bars 48 to 56). Keyboard, Media, Dock, macros, Trackpad.
Purpose: the rest of the app, quickly, then home.

1. The mode menu (real recording). Then each word lands on its screen: Keyboard (the phone
   turns sideways), Media, Dock, and the Actions Library where a macro is recorded and pinned
   (macros live in Actions now).
2. Slow down on the last two bars: the phone lies flat as a trackpad (the v3 recording), three
   fingers swipe, the Mac's Space follows the fingers. A ring on each tap shows the haptic.

### 10. Private (bars 56 to 60). No account. No cloud.
Purpose: trust.

1. An account, shown and crossed out; a cloud, shown and crossed out. Then the Mac and the
   phone, one line between them with touches crossing it, a lock, and an outline that closes
   around both with the Wi-Fi mark.

### 11. End (bars 60 to 63.5).
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
