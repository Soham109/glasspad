# Security

Glasspad controls your Mac from another device, so security matters here.

## How it is protected

- Pairing uses a code shown on the Mac: a QR code drawn as moving dots, carrying a random 32-byte secret. The phone scans it, or you send the same link with Copy Link or Share. The secret is stored in the Keychain on both devices, and on the iPhone it never leaves that device.
- A code is valid for 5 minutes. After that its secret is no longer accepted and the Mac shows Code Expired.
- Each connection derives a new session key from that secret and two random values (HKDF-SHA256, a standard key derivation method). Both sides prove they hold the key before the Mac saves a new phone.
- Messages are encrypted and authenticated with ChaCha20-Poly1305. Wrong key or altered data is dropped silently and counted.
- Replay protection: TCP counters must increase, and UDP uses a sliding window that rejects duplicates.
- The only unencrypted messages are the two opening hellos (or the Mac's refusal), which hold no secret.
- Unpaired devices cannot send input. A paired phone can be removed on the Mac with Forget… in Settings > iPhone.
- The phone can edit Actions, but it can never add or change a shell command button. Those are made on the Mac, in `~/Library/Application Support/Glasspad/deck.json`, and run only after you turn on "Allow shell command buttons" in the Mac's Settings > Advanced.
- A button made by a newer Glasspad that this Mac cannot read is never run.

The full design is in [docs/SPEC.md](docs/SPEC.md), section 3.

## What leaves your Wi-Fi

- Nothing between the iPhone and the Mac. There is no account and no server.
- When you add a Website button, the iPhone asks that website for its name and logo. It asks only the site itself, never a logo service.
- The installer downloads the source from GitHub and XcodeGen from its GitHub release, checked against its published checksum.

## What to keep in mind

- Anyone who sees a live code can pair while it is valid. Do not share a screenshot or the link. Forget the phone on the Mac if you did.
- The Mac app needs Accessibility permission, which lets it send input. Spotify and Music control asks for Automation permission, which is optional.
- Some features use parts of macOS that Apple does not document (gestures, now playing, Night Shift, Do Not Disturb). Each has a fallback, and none needs more permissions than the ones above.
- The app has not had an independent security audit.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"). Include steps to reproduce and the versions involved. You will get a reply, and a fix will be credited to you unless you prefer otherwise.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.0 | Yes |
| Earlier test builds | No |

Fixes go to the latest release and to `main`.
