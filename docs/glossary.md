# Glossary

Words used in the code and the docs, in plain terms. Code names are in `code font`.

| Term | Meaning |
| --- | --- |
| <a id="accessibility"></a>**Accessibility permission** | The macOS permission that lets an app send input and move other apps' windows. The Mac app needs it. |
| <a id="adr"></a>**ADR** | Architecture decision record: a short note of why a decision was made. See [adr/](adr/README.md). |
| <a id="aead"></a>**AEAD** | Encryption that also proves the data was not changed. Glasspad uses ChaCha20-Poly1305. |
| <a id="awdl"></a>**AWDL, peer-to-peer Wi-Fi** | Apple's direct device-to-device Wi-Fi. It works without a shared network, but the radio hops channels several times a second, which shows up as latency spikes. The phone tries the shared Wi-Fi first and allows AWDL only after 3 seconds. |
| <a id="automation"></a>**Automation permission** | The macOS permission to send Apple Events to another app. Optional; used for Spotify and Music. |
| <a id="bonjour"></a>**Bonjour** | Apple's way to find services on the local network without typing an address. The Mac advertises `_glasspad._tcp`. |
| <a id="cgevent"></a>**CGEvent** | A macOS input event (mouse, scroll, key) that an app can create and post. |
| <a id="control-channel"></a>**Control channel** | The TCP connection that carries everything except touches. See `ControlMessage`. |
| <a id="deck"></a>**Deck** | The code name for Actions: buttons on the phone that run things on the Mac. Stored in `deck.json`. |
| <a id="developer-mode"></a>**Developer Mode** | An iPhone setting that allows apps you build yourself to run. |
| <a id="fallback"></a>**Fallback** | The public way to do something when a private macOS call is missing, for example a keyboard shortcut for Spaces. |
| <a id="frame"></a>**Frame (touch)** | One snapshot of every finger on the trackpad, sent over UDP. `TouchFrame`. |
| <a id="haptics"></a>**Haptics** | Taps you feel from the phone's vibration motor. Played on the phone by Core Haptics. |
| <a id="heartbeat"></a>**Heartbeat** | A tiny packet the phone sends every 20 ms while a trackpad shows, so the Wi-Fi radio does not doze and add delay. |
| <a id="hkdf"></a>**HKDF** | A standard way to turn one secret into fresh keys. Each connection derives its own session key from the pairing key. |
| <a id="layout"></a>**Layout** | One to three modes on one phone screen. `ScreenLayout`. |
| <a id="live-check"></a>**Live check** | A guided run on a real Mac that tries each feature and puts the Mac back. See [LIVE-CHECK.md](LIVE-CHECK.md). |
| <a id="main-actor"></a>**Main actor, main thread** | The one thread that draws the interface. Code there must never wait. See [ADR 0004](adr/0004-main-thread-never-blocks.md). |
| <a id="mediaremote"></a>**MediaRemote** | The private macOS framework that knows what is playing. |
| <a id="mode"></a>**Mode** | One screen on the phone: Trackpad, Keyboard, Media and so on. `AppMode` on the phone, `GlasspadMode` on the wire. |
| <a id="motion-scheduler"></a>**MotionScheduler** | The Mac part that releases pointer motion in step with the display's refresh, to smooth out Wi-Fi timing. |
| <a id="pairing-key"></a>**Pairing key** | A random 32-byte secret in the QR code. Both devices keep it in the Keychain. |
| <a id="pill"></a>**Pill** | The small control at the top of the phone screen. Tap for the mode menu, hold for Settings. |
| <a id="provisioning-profile"></a>**Provisioning profile** | Apple's permission for one app to run on one device. With a free Apple ID it lasts 7 days. |
| <a id="recognizer"></a>**Recognizer** | `GestureRecognizer`: turns finger frames into pointer, click, scroll and swipe events. |
| <a id="renewal"></a>**Renewal** | Reinstalling the phone app before its 7-day profile expires. The Mac does it hourly when due. |
| <a id="sealed"></a>**Sealed** | Encrypted and authenticated. Every message after the two Hellos is sealed. |
| <a id="session"></a>**Session** | One connection between a phone and a Mac, with its own key. |
| <a id="snapshot-harness"></a>**Snapshot harness** | Tests in `Apps/Mac/Tests` that draw Mac windows to PNG files. |
| <a id="standby"></a>**StandBy** | Clock, Now Playing and Calendar screens for a charging phone. |
| <a id="starter-library"></a>**Starter library** | The built-in buttons for more than 70 apps. `StarterLibrary`. |
| <a id="tool"></a>**Tool** | A mode that opens on top from the mode menu instead of the pill: Present, Remote, Displays, Clipboard. |
| <a id="touch-channel"></a>**Touch channel** | The UDP path that carries touch frames and heartbeats. |
| <a id="visual-check"></a>**Visual check** | Screenshots compared with a baseline to catch unwanted UI changes. See [testing](testing.md). |
| <a id="wire"></a>**Wire** | The messages the phone and the Mac send each other. See [SPEC.md](SPEC.md). |
| <a id="wire-golden"></a>**Wire golden** | Messages frozen as an older release wrote them, checked by `WireGoldenTests`. |
| <a id="xcodegen"></a>**XcodeGen** | A tool that makes the Xcode project from `project.yml`. |
