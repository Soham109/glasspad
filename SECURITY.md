# Security

## Report a vulnerability

Please do not open a public issue.

- On GitHub: the Security tab, then **Report a vulnerability**.
- Or email **hello@sohamaggarwal.com**.

Include the steps to reproduce and the Glasspad, iOS and macOS versions. You will get a reply, and the fix will credit you unless you prefer otherwise.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.2.x | Yes |
| 0.1.x and earlier | No |

Fixes go to `main` and the next release.

## How Glasspad is protected

Glasspad controls your Mac from another device, so security matters here.

- **Pairing:** the Mac shows a QR code holding a random 32-byte secret, valid for 5 minutes. Both devices keep the secret in the Keychain, and the iPhone never sends it anywhere.
- **Encryption:** each connection makes a new session key from that secret (HKDF-SHA256, a standard way to derive keys). Every message is encrypted and checked with ChaCha20-Poly1305. Altered or replayed messages are dropped.
- **Only paired phones** can send input. Forget a phone on the Mac in Settings > iPhone.
- **Shell command buttons** can only be made on the Mac, in `~/Library/Application Support/Glasspad/deck.json`, and run only after you turn on "Allow shell command buttons" in Settings > Advanced. The phone can never add or change one.
- **No account and no server.** The iPhone and Mac talk only over your Wi-Fi. A Website button asks only that website for its name and logo.

The full design is in [docs/SPEC.md](docs/SPEC.md), section 3.

## Keep in mind

- Anyone who sees a live pairing code can pair while it is valid. Do not share a screenshot or the link.
- The Mac app needs Accessibility permission to send input. Automation permission, for Spotify and Music, is optional.
- Some features use parts of macOS that Apple does not document. Each has a fallback.
- Glasspad has not had an independent security audit.
