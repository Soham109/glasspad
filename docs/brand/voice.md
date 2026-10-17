# Glasspad voice

How Glasspad sounds, and the names it uses, in the apps, on the website, in the README, the changelog and release notes. Approved taglines and descriptions by length live in [copy.md](copy.md).

## Tone

- Calm and plain, like Apple's own help pages. Say what happens, not how great it is.
- Lead with the point. One idea per sentence. Short beats complete.
- Talk to the person: "your Mac", "your iPhone". Not "the user".
- Never claim more than the code does. If a feature has a limit, say the limit.
- No hype words: no "seamless", "powerful", "magic", "blazing", "effortless".

## Length

- A button or menu item: one to three words.
- A footer, hint or empty state: one sentence, two at most.
- An error: what happened, then what to do. Two short sentences.
- A website section: a heading and one or two sentences. Lists over paragraphs.
- If a sentence needs "and" twice, split it or cut it.

## Rules

- US spelling and usage: color, center, canceled, gray, favorite, movie (not film), cellular (not mobile data).
- No em dashes or en dashes. Use a period, a comma, a colon or "to" ("1 to 3").
- Title Case for UI names, buttons, menu items, screen titles and Settings rows, as Apple does: Pair Your iPhone, Show Code as Text, Keep Screen On. Sentence case for everything else, including hints and notices.
- Write a UI name exactly as it appears on screen, and only bold it in docs when it is the thing to click.
- Paths in Settings use a space, a greater-than sign and a space: System Settings > Privacy & Security > Accessibility. The website may render the sign as ›. Use "&" only where Apple's own label does (Privacy & Security, Desktop & Dock, Move & Resize).
- Modifier keys are capitalized: Command, Option, Control, Shift, Fn. Shortcuts may use symbols: ⌘C.
- Hyphenate finger counts used as adjectives: two-finger scroll, three-finger swipe.
- Prefer full words over contractions in the apps ("cannot", "did not"). Pick one per surface and keep it.
- Numbers: digits for counts and times (5 minutes, 7 days, 39 themes). Dates in the US form: October 17, 2026.
- Say "iPhone" and "Mac", not "phone", "device" or "computer", unless the sentence is about other products too.
- No time estimates ("takes about a minute"). Describe what happens.

## Canonical names

Use these spellings everywhere. The left column is the name on screen.

### Modes

| Name | What it is | Not |
| --- | --- | --- |
| Trackpad | The trackpad mode | trackpad screen, touchpad |
| Keyboard | Typing mode (stored as `keys`) | Keys |
| Media | What is playing, volume, sound output, brightness | Music, Now Playing (that is a StandBy screen) |
| Dock | The Mac's Dock on the iPhone | Apps (its old name) |
| Actions | Buttons for the app in front, then Pinned | Deck, Buttons |
| Pinned | The person's own buttons, inside Actions (stored as `deck`) | Deck, My Buttons, Favorites |
| Macros | Recorded steps, inside Actions or as its own mode | |
| Remote | The couch remote for movies and music | Media remote, TV remote |
| Present | The slide remote with timer and laser | Presenter, Presentation mode |
| Clipboard | Send to Mac and Get from Mac | |
| Displays | Every display and window | Display mode, Screens |
| Arrange | The Split Screen sheet that shows where windows go | |

Counting: Glasspad has 11 modes (the list above, without Arrange). Five show in the mode menu by default: Trackpad, Keyboard, Media, Dock and Actions. Present, Remote and Displays open full screen from the mode menu. Clipboard opens from Keyboard's shortcut row or a Pinned button.

### StandBy screens and layouts

- StandBy screens: Clock, Now Playing, Calendar. They show in layouts.
- Layouts: up to three modes on one screen. Templates: Desk, Type, Listen, Couch, Trackpad and Dock, Media and Actions, Studio, Presenter, StandBy, Clock and Trackpad. "Presenter" is the layout; "Present" is the mode.

### Parts of the app

- mode button (the control at the top of the screen; not "pill")
- mode menu
- Library (where every app, Mac control, macro, shortcut and website is added from)
- Mac controls (Do Not Disturb, Night Shift, Keep Awake, Split Screen and the rest)
- app set (a list of macros for some apps, in the Mac's Macros settings; not "profile")
- Live Activity, Lock Screen, Control Center, StandBy (Apple's names)
- Live Check (the Mac's self-test window)

### Mac app

- Glasspad in the menu bar; the menu bar window
- Pair Your iPhone…, Show Code as Text, Copy Link, Forget iPhone, Hide Mac Dock
- Glasspad Settings: General, iPhone, Trackpad, Macros, Advanced, About

### Themes

39 themes in six groups: Classic, Glass, Color, Grain, Tinted, Photo. Write "39 themes", never a rounded number.

### Platforms and requirements

- macOS 14 or later, iOS 18 or later, Xcode 26 or later. Write them in that form.
- Apple's names: Apple Account (Apple's current name for an Apple ID; the installer and site still say "free Apple ID", so change them together), Accessibility, Automation, Local Network, Developer Mode, Wake for network access, Personal Team.
- Third-party names as their makers write them: Stream Deck, Stream Deck Mobile, Remote Mouse, Mobile Mouse, YouTube, Prime Video, Disney+, QuickTime Player, IINA, VLC, Spotify.

### Product facts that must match everywhere

- Version: 0.3.0
- Free, MIT, no account, no ads, no in-app purchases
- Starter buttons for 74 apps, written as "more than 70 apps" or "70+ apps"
- Remote follows 11 players
- Up to 8 buttons per app in Actions; no limit on Pinned
- A free install stops opening after 7 days; the Mac renews it once it is 5 days old
- Pairing code valid for 5 minutes; display changes revert after 15 seconds
