# Security

## Report a vulnerability

Please do not open a public issue.

- On GitHub: the Security tab, then **Report a vulnerability**.
- Or email **hello@sohamaggarwal.com**.

Include the steps to reproduce and the Glasspad, iOS and macOS versions. You will get a reply, and the fix will credit you unless you prefer otherwise.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.3.x | Yes |
| 0.2.x | No |
| 0.1.x and earlier | No |

Fixes go to `main` and the next release.

## How Glasspad is protected

Glasspad controls your Mac from another device, so security matters here.

- **Pairing:** the Mac shows a QR code holding a random 32-byte secret. It works once, for 5 minutes, and only after you click Allow on the Mac. On that first connection the phone and Mac agree a new key (X25519), so the code is useless afterwards.
- **Encryption:** each connection runs a fresh X25519 key exchange mixed with the pair key (HKDF-SHA256), so a key learned later cannot open a recorded session. Every message is encrypted and checked with ChaCha20-Poly1305. Altered or replayed messages are dropped.
- **Only paired phones** can send input. Forget a phone on the Mac in Settings > iPhone.
- **Shell command buttons** can only be made on the Mac, in `~/Library/Application Support/Glasspad/deck.json`, and run only after you turn on "Allow shell command buttons" in Settings > Advanced. The phone can never add or change one.
- **No account and no server.** The iPhone and Mac talk only over your Wi-Fi. A Website button asks only that website for its name and logo.
- **Clipboard:** Get from Mac never sends an item that a password manager marked private.
- **Album artwork:** when Media shows a song, the Mac may download its artwork from the music service.

Who could attack Glasspad and how it holds up: [docs/security/threat-model.md](docs/security/threat-model.md). The pairing and message format: [docs/security/protocol.md](docs/security/protocol.md). The full design is in [docs/SPEC.md](docs/SPEC.md), section 3.

## Keep in mind

- Pair only your own phone: a paired phone can type and click as you. Click Don't Allow for any phone you do not recognize. Phones paired by 0.2.x move to an agreed key the next time an updated phone connects to an updated Mac.
- The Mac app needs Accessibility permission to send input. Automation permission, for Spotify and Music, is optional.
- Some features use parts of macOS that Apple does not document. Each has a fallback.
- Glasspad has not had an independent security audit.
