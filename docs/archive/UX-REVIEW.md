> **Archived.** Kept for history, not maintained, and may not match the current code. See [the archive index](README.md).

# UX review: first-time user walkthrough

iPhone 18 Pro simulator, against a stand-in Mac running the kit's `GlasspadServer` with fake
data. Paper and Graphite, portrait and landscape, default and accessibility text sizes.
Status: [x] fixed in this pass, [ ] left.

## Confusing

- [x] Settings had two places for haptics. "Feel" held strength and a "Haptic Types" page,
  while a separate "Haptics by kind" section further down held three more strength sliders.
  Its footer said scrolling and Spaces stay silent, yet Haptic Types offered switches named
  "Scroll and pinch steps" and "Spaces and Mission Control", which no longer exist as
  trackpad haptics (those cues are now confirmations). One Haptics page now holds both, with
  honest names.
- [x] Settings was one very long page (11 sections). Pointer and scrolling tuning moved to a
  "Pointer and Scrolling" page under Trackpad, next to what comes from the Mac.
- [x] After the first launch the pill fades in 2 s and nothing says it exists. A one-time
  hint under the pill now says "Tap for modes. Hold for Settings."
- [x] Trackpad while the Mac cannot be found said only "Looking for your Mac", with no hint
  what to check. The other modes said more. Same guidance everywhere now.
- [x] Actions offline showed a header "No App", which reads as broken. It now says "Not
  connected" and why.
- [x] The "Choose" sheet for the front app said "Nothing shows for Safari" while the screen
  showed two Safari buttons (it read the list before the Mac's data arrived).
- [x] Onboarding said "choose Pair"; the Mac menu says "Pair Your iPhone". Copy now matches.
- [x] Settings pages for Apps and Actions had segmented size pickers and a "Fine Tune"
  slider with no label saying what they change.
- [ ] Accessibility being off on the Mac is invisible on the phone: touches simply do
  nothing. Needs a protocol message from the Mac (kit and Mac app change), not a phone-only fix.

## Owner feedback: Actions has too much, Apps is really the Dock

- [x] Actions showed far too much by default. A new setup started with Safari, Downloads,
  a "Mac" folder of 20 controls and a tile for every macro. New setups now start with six
  essentials (Screenshot, Lock Screen, Mute, Dark Mode, Mission Control, Show Desktop);
  everything else is in the + Library. Macros are no longer all pinned on a new setup.
- [x] Existing Pinned grids are never trimmed on their own. Over 12 tiles, Actions offers
  "Tidy Up" once (with "Keep Mine"), and edit mode has "Reset to Defaults". Both confirm first.
- [x] The front app's section shows 6 buttons by default instead of 8; the rest are in that
  app's list (Edit > Choose), up to 8.
- [x] Sideways, Actions is a split view: the front app on the left half, Pinned on the right,
  each sizing its tiles to its half.
- [x] Adding an app that is not in the Dock was hidden behind Library search. Apps is now the
  first Library group, with "All Apps on Your Mac": every installed app, searchable, one tap
  to pin.
- [x] "Apps" mode is renamed "Dock" (symbol `dock.rectangle`) and mirrors the Mac's Dock only:
  no search, no Recent row. The saved identifier is unchanged, so settings still load.

## Ugly or inconsistent

- [x] Keyboard mode: three rows of three different shapes (wide capsules, round chips, and
  tall stretched ovals for esc, tab and the arrows). Rebuilt as one family of flat keycaps,
  like the system keyboard, with the modifier name under each symbol.
- [x] Keyboard landscape: the shortcut row was cut off by the system keyboard. Now fits.
- [x] Present: Previous was a glass lozenge and Next a flat rounded rectangle, and only Next
  had a word. Both are now the same flat shape and both are labelled.
- [x] Mode menu: Clipboard, Present, Lock Rotation and Settings were bare text with no
  button shape, and mixed filled and outlined icons. Now each sits on a tile like the modes.
- [x] Clipboard button "Get Mac clipboard" was the only sentence-case button.
- [x] Media showed a greyed AirPlay icon that does nothing when the Mac reports no outputs.

## Broken or hard to use

- [x] Tap targets under 44 pt: tip close buttons (28), Present timer buttons (42), Edit and
  Done in Actions (34 tall), mode menu tool rows (40).
- [x] Large text sizes: mode menu words hyphenated mid-word ("Clip-board", "Set-tings");
  keyboard esc and tab vanished; onboarding title and body truncated with "...". The menu
  and keys now cap at a size that fits, and onboarding text wraps fully.
- [x] Pairing without a camera: once the keyboard came up the "No camera here" card shrank
  to a thumbnail with clipped text. It now collapses to one line.
- [x] Onboarding scan page left a large blank hole where the invisible Start button sat.
- [x] Keyboard mode kept the system keyboard up while showing "Looking for your Mac",
  covering the message and swallowing typing.
