# Security

Glasspad controls your Mac from another device, so security matters here.

## How it is protected

- Pairing uses a QR code that carries a random 32-byte secret, shown on the Mac and scanned by the phone. It is stored in the Keychain on both devices.
- Each connection derives a new session key from that secret and two random values (HKDF-SHA256, a standard key derivation method).
- Messages are encrypted and authenticated with ChaCha20-Poly1305. Wrong key or altered data is dropped silently and counted.
- Replay protection: TCP counters must increase, and UDP uses a sliding window that rejects duplicates.
- The only unencrypted message is the first hello, which holds no secret.
- Unpaired devices cannot send input. A paired phone can be revoked from the Mac menu.

The full design is in [docs/SPEC.md](docs/SPEC.md), section 3.

## What to keep in mind

- Anyone who sees your QR code can pair. Do not share a screenshot of it. Revoke the phone in the menu if you do.
- The Mac app needs Accessibility permission, which lets it send input.
- The app has not had an independent security audit.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"). Include steps to reproduce and the versions involved. You will get a reply, and a fix will be credited to you unless you prefer otherwise.

## Supported versions

Only the latest commit on `main` until a first release is tagged.
