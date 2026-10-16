# Glasspad 0.1.0

A control surface for your Mac, on your iPhone. A small menu bar app on the Mac and an app on the iPhone, on the same Wi-Fi. Free, private and open source.

## Highlights

- **Trackpad:** move, click, scroll, pinch and swipe between Spaces, with a tap you can feel on every click. Follows your Mac's own trackpad settings.
- **Keyboard:** type or dictate, with modifier keys, shortcuts, arrows and F1 to F12.
- **Media:** what is playing in Spotify, Music or a browser, with artwork, scrubbing, sound output, volume and screen brightness.
- **Dock:** your Mac's Dock. Tap to open, hold to hide or quit, and hide the Mac's own Dock.
- **Actions:** buttons that follow the app in front, for more than 70 apps.
- **Pinned:** your own buttons, including Do Not Disturb, Night Shift, Keep Awake, Split Screen, window tiling, screenshots, apps and websites with their real logos. Folders keep them tidy; the Library finds anything.
- **Macros and Shortcuts:** record steps on your Mac once and replay them with a tap, or run any shortcut.
- **Remote:** a touch pad like the Siri Remote. Its keys follow the player, and Search types on the Mac.
- **Present:** Next and Back, a timer, and a laser you steer with one finger.
- **Clipboard:** text and images, both ways.
- **Displays:** every display and its windows. Move a window to another display or tile it, and set brightness, resolution and Night Shift.
- **Layouts:** up to three modes on one screen.
- **StandBy:** a clock beside Now Playing or your calendar while the iPhone charges, in dim red at night.
- **Themes:** 28 themes in four groups: Classic, Glass, Color, and Photo.
- **Private:** paired by QR code, encrypted, no account.

The full list is in the [changelog](https://github.com/Soham109/glasspad/blob/main/CHANGELOG.md).

## Install

Paste this into Terminal on your Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/Soham109/glasspad/main/install.sh | bash
```

What it does, in order:

- Checks for Xcode and finishes its one-time setup (opens the App Store if Xcode is missing).
- Downloads XcodeGen, the tool that makes the Xcode project, and checks it against its published checksum.
- Downloads the Glasspad source to `~/Projects/glasspad`.
- Finds your Apple Development certificate (asks you to sign in to Xcode if there is none).
- Builds the Mac app, installs it in Applications and opens the Accessibility page in System Settings.
- Builds the iPhone app and installs it, waiting while you turn on Developer Mode and trust the app.
- Sets up automatic renewal, so your Mac renews the iPhone app before it expires.

It waits for you wherever Apple needs a click, and it is safe to run again: finished steps are skipped. Then click Glasspad in the menu bar, choose **Pair Your iPhone…** and scan the code.

## Requirements

- A Mac on macOS 14 or later, with Xcode (free on the App Store).
- An iPhone on iOS 18 or later, and a cable for the first install.
- A free Apple ID.
- With a free Apple ID, apps you install yourself stop opening after 7 days. Your Mac renews Glasspad over Wi-Fi when the install is 5 days old.

## Known limitations

- Glasspad is not on the App Store. You build it on your Mac with Xcode.
- Renewal needs the Mac awake and the iPhone reachable within those 7 days. If it lapses, run the installer again.
- Both devices should be on the same Wi-Fi. When the iPhone cannot find the Mac there, it tries a direct Wi-Fi link between the two, which is less steady.
- One iPhone controls the Mac at a time.
- The Mac app needs Accessibility permission. Spotify and Music control asks for Automation permission, which is optional.
- Some features use parts of macOS that Apple does not document: native gestures, now playing, Night Shift and Do Not Disturb (pressed in Control Center). A macOS update can break them. Gestures then fall back to keyboard shortcuts, and Do Not Disturb to a shortcut you already have.
- Apart from installing, the only request that leaves your Wi-Fi is a new Website button asking its site for the site's name and logo.
- There has been no independent security audit.

## Verified on real hardware

To be filled in after the live checks.

## Links

- Website: https://glasspad.sohamaggarwal.com
- Guide: https://glasspad.sohamaggarwal.com/guide
- Bugs and ideas: https://github.com/Soham109/glasspad/issues
