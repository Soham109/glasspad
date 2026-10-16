# Live check

Some features can only be seen working on a real Mac and a real iPhone. The tests use a pretend Mac, so they cannot show that Control Center really switched Do Not Disturb or that a display really changed size. The live check covers that, in one sitting: a guided run on the Mac, then a short list to try on the iPhone.

## On the Mac

```bash
scripts/live-check.sh --install
```

- `--install` builds this checkout and installs it to /Applications first (`scripts/install-mac.sh`). Leave it out when the installed Glasspad is already current.
- `--include-disruptive` adds Lock Screen, Sleep Display, Sleep Mac, Empty Trash and Eject All. They are left out unless you ask, and each one can still be skipped. Empty Trash deletes what is in the Trash for good.

The script quits Glasspad (the iPhone disconnects), opens the installed app with `--live-check`, and waits. Glasspad then shows only the Live Check window in the top right corner: no menu bar item, and it does not listen for the phone. When you press Done it quits, the script starts Glasspad as usual again and prints where the report is.

It runs in the installed app because that copy has the Accessibility and Screen & System Audio Recording permissions. Without Accessibility the window tells you so before you start.

### How a step goes

1. The window says what the step will do. Press **Run** (or Return), or **Skip**.
2. Glasspad runs the feature through the same code the iPhone's buttons reach (`DeckMode.perform` for Actions and Remote controls, `ModeRouter.handle` for everything else), then reads back what it can: Dark Mode, Night Shift, the Keep Awake assertion, window frames, display sizes and arrangement, volume, mute, brightness, the Dock's settings, the files it saved.
3. When only you can see it (did Notification Center open, did the screen turn warmer), it asks **Yes** or **No**, with a note field. A step the Mac already knows failed is not asked about.
4. Whatever the answer, it puts back everything that differs from before the step, checks each one, and says what it put back. Anything it could not put back is listed at the top of the report and in the window at the end.

Window tests use two TextEdit windows Glasspad opens itself ("Glasspad Live Check 1" and "2"). It brings one forward and checks that it really is the front window before every move, so your own windows are never touched. They close at the end, and TextEdit quits if the check opened it.

Stopping, or closing the window, puts back the current step first. The report is written after every step, so a stopped check still leaves one.

### Report

`~/Library/Logs/Glasspad/live-check-<date>.md` (a second run the same day adds `-2`, and so on): the Mac, macOS and Glasspad version, then a table per group with Pass, Fail or Skipped, what was read back, what was put back, and your note.

### What it covers

| Group | Steps | Put back |
| --- | --- | --- |
| Mac | Dark Mode, Do Not Disturb, Keep Awake, Notification Center | Appearance, Do Not Disturb (switched again), the assertion released, Notification Center closed |
| Windows | Left Half, Right Half, Top Half, Bottom Half, Fill, Center, Split Screen, Next Display | The test windows' frames |
| Displays | Window List, Move a Window (right half, dragged, to the other display), Looks Like and Going Back (the 15 second revert), Mirroring and Revert, Main Display, Arrange | Size, mirroring, main display and arrangement |
| Screenshots and Recording | Whole screen and front window screenshots (and the copy sent to the phone), a 3 second screen recording | The files go to the Trash |
| Sound | Volume (button and Media slider), Mute, Mute Microphone | Volume, mute, microphone mute and level |
| Brightness and Night Shift | Brightness (button and Displays slider), Night Shift | Brightness, Night Shift |
| Media | Play or Pause, Next and Previous Track | Playing or paused as before |
| Remote | Music, Spotify, TV, QuickTime Player, IINA, VLC, Infuse (each one installed): the Remote's keys for that player, worked out the way the phone does | Full screen and subtitles are pressed twice; playing or paused as before |
| Dock | Hide Mac Dock | The Dock's own settings |
| Shortcuts | A shortcut that does not exist, and the message the phone would show | Nothing to put back |
| Lock, Sleep and Disks | Lock Screen, Sleep Display, Sleep Mac, Empty Trash, Eject All (only with `--include-disruptive`) | Nothing: unlock or wake the Mac yourself |

Steps that cannot run on this Mac are offered as Skip with the reason: Next Display, Mirroring, Main Display and Arrange need a second display, and Remote steps need the player installed. For Media and Remote, start something playing first; the window says so.

### How long each step waits

Nothing moves on until you press Run, Skip, Yes or No; those wait as long as you like. Within a step:

| Step | Waits |
| --- | --- |
| Opening the test windows (first window step) | Up to 5 s for TextEdit, then up to 1.5 s for a window to come forward before each move |
| Dark Mode, Night Shift, Notification Center | 1 s before reading back |
| Do Not Disturb | Up to 2.4 s for Control Center, then 0.8 s |
| Window positions, Split Screen, Next Display | 0.6 s after the move |
| Window List, Move a Window | 1.2 s for window names, then 0.6 s after each move |
| Looks Like and Going Back | 2.5 s, then a countdown to 18 s (macOS gets 15 s to go back, plus 3 s) |
| Mirroring and Revert | 3 s mirrored, 3 s after Revert |
| Main Display, Arrange | 3 s |
| Screenshots | 0.5 s |
| Screen Recording | Records for 3 s, then 2.5 s to save |
| Volume, Brightness | 0.3 s (volume) or 0.4 s (brightness) after the button and after the slider |
| Play or Pause, Next and Previous Track | 2 s after each press |
| Remote | 1.5 s to see what plays, then 2 s after each key (up to 8 keys) |
| Hide Mac Dock | 2 s for the Dock to restart |
| Missing Shortcut | Until `shortcuts run` gives up |
| Putting back | 2 s after each display change, 1.5 s after resuming playback, 0.8 s after closing Notification Center |

Reading what plays takes up to 1.5 s each time, and 1.2 s more the first time.

## On the iPhone

These need the phone itself. Pair or connect as usual, then go through the list and note anything that is off.

- [ ] **Pairing.** Show a new code on the Mac and scan it from the setup screen. The camera finds the code and locks on at once, without hunting, in bright and dim light.
- [ ] **Haptics.** Click, drag and two finger scroll on the trackpad. The taps feel exactly as before: same strength, same timing, no extra ones.
- [ ] **Remote with Netflix.** Play something on netflix.com in Safari on the Mac, then use the Remote: play and pause, back and forward, full screen, subtitles, and Skip Intro when it shows.
- [ ] **Remote with YouTube.** The same on youtube.com in Safari: play and pause, back and forward 10 seconds, previous and next video, full screen, subtitles.
- [ ] **Layouts.** Open a layout with two or three panes and drag a divider. It follows your finger, and the layout opens the same way next time.
- [ ] **StandBy while charging.** Open a StandBy screen with the phone on its charger and leave it. The screen stays on. Unplug it: the screen locks on its usual Auto-Lock, unless you turned on keeping it on without power.
- [ ] **Website logos.** Add a Website action (for example apple.com and github.com). The site's logo shows on the button, sharp, and stays after you reopen the app.
- [ ] **Photo theme.** Choose the Photo theme and pick a photo. It fills the background behind the controls, and the controls stay easy to read.
- [ ] **Switching themes.** Switch between a few themes, light and dark. Each change is smooth, with no flash and no stutter.
