# Pairing and transport: design notes

How the iPhone and the Mac find each other, agree on keys, and protect what they send. This describes the code as it is in `Packages/GlasspadKit/Sources/GlasspadKit` (`Crypto/`, `Transport/`, `Protocol/ControlMessage.swift`). The risks that follow from it are in [threat-model.md](threat-model.md); the full product spec is [docs/SPEC.md](../SPEC.md), section 3.

## Terms

- **Pair key**: 32 random bytes from the system's secure random generator (`SecRandomCopyBytes`), one per phone and Mac pair.
- **Nonce**: a random value used once. Here, 16 random bytes picked by each side for each connection.
- **AEAD**: encryption that also detects tampering. Glasspad uses ChaCha20-Poly1305 from Apple's CryptoKit.
- **HKDF**: a standard way to turn one secret into a new key. Glasspad uses HKDF with SHA-256.

## 1. Discovery

The Mac listens on one TCP port (control messages) and one UDP port (touches), both picked by the system. It announces `_glasspad._tcp` over Bonjour with its name, plus a TXT record holding its Mac ID (a UUID) and the protocol version. Nothing secret is announced.

## 2. Pairing code

On the Mac, Pair Your iPhone makes a new pair key and shows:

```
glasspad://pair?v=1&id=<Mac ID>&name=<Mac name>&k=<pair key, base64url>
```

as a QR code, a link to copy, or a link to share. The key is armed on the Mac for 5 minutes (`PairingFlow.codeLifetime`) and for one phone; then it is dropped. The phone checks the version, the ID, and that the key is exactly 32 bytes. A link opened from outside the app asks the user before it is used.

The code's key opens the first connection only (see 3a). Both sides then keep the agreed key in the Keychain (`AfterFirstUnlockThisDeviceOnly`). The server checks the code's 5 minute end itself (`GlasspadServer.armPairing(key:expiresAt:)`), on the wall clock.

## 3. Handshake (TCP)

```
phone -> Mac   hello  {phoneID, phoneName, macID, nonce_p, kx_p, rekey?, v: 2}    not encrypted
Mac   -> phone hello  {nonce_m, udpPort, kx_m, rekey, v: 2}  or a reject {reason}  not encrypted
both           ikm        = X25519(phone, Mac) || pairKey
               salt       = nonce_p || nonce_m
               sessionKey = HKDF-SHA256(ikm, salt, "glasspad v2 session" || rekey || kx_p || kx_m)
               newPairKey = HKDF-SHA256(ikm, salt, "glasspad v2 pair" || kx_p || kx_m)   when rekey
phone -> Mac   seal("glasspad confirm v1")
Mac   -> phone seal("glasspad approval wait v2")    new phone only, while the Mac asks
Mac            saves newPairKey (keeps the old key until keySaved)
Mac   -> phone seal("glasspad confirm v1")          or seal("glasspad approval denied v2")
phone          saves newPairKey
phone -> Mac   seal({"t":"keySaved"})               the Mac drops the old key
```

- The Mac looks up the stored key for `phoneID`. If there is none and a code is armed, it tries the code's key, and saves the phone only after the phone's proof checks out and someone clicks Allow on the Mac (30 seconds, then it counts as Don't Allow). A known phone that scanned a new code is checked against both keys.
- Before accepting, the Mac asks the Keychain again, so a phone forgotten during the handshake is refused.
- The phone accepts the session only after the Mac's proof checks out.
- Handshake messages are limited to 8 KB, at most 8 handshakes run at once, and each must finish within 5 seconds.

Because both nonces and a fresh key exchange go into the key, every connection has its own key, and a recorded handshake cannot be replayed.

### 3a. Protocol 1 and old installs

- `kx` is a fresh X25519 key pair per connection; the private half is never stored. Every session key needs it, so a key learned later cannot open a recorded session (forward secrecy).
- Both public keys and the rekey flag are in the HKDF info: changing either unencrypted hello breaks the key confirmation.
- The phone asks for `rekey` while its key is a code's key. A new phone is always rekeyed.
- A Mac on protocol 2 accepts a protocol 1 hello only from a phone it stored with a code's key, and never to pair. An updated phone falls back to protocol 1 only when the Mac answers "unsupported version 2" and its own key is still a code's key.
- A forged "unsupported version" reply can keep a phone that has not moved yet on protocol 1 until the app restarts. That is the same security 0.2.x had, and it cannot be used to pair.
- Frozen in `WireGolden_2026_10_17_Handshake.swift`, with known answers for the key derivation.

Protocol 1, used by 0.2.x:

```
phone -> Mac   hello   {phoneID, phoneName, macID, nonce_p (16 bytes), v: 1}
Mac   -> phone hello   {nonce_m (16 bytes), udpPort}  or a reject {reason}
both           sessionKey = HKDF-SHA256(ikm: pairKey, salt: nonce_p || nonce_m,
                                        info: "glasspad v1 session", 32 bytes)
phone -> Mac   seal("glasspad confirm v1")
Mac   -> phone seal("glasspad confirm v1")
```

## 4. Encrypted messages

Every message after the handshake is sealed with the session key:

```
counter (8 bytes, big-endian) || ciphertext || tag (16 bytes)
nonce = direction label (4 bytes) || counter (8 bytes)
labels: "P2M\0" phone to Mac, TCP   "M2P\0" Mac to phone, TCP
        "P2MU"  phone to Mac, UDP   "M2PU"  Mac to phone, UDP
```

- Each direction and channel has its own label, so a message cannot be reflected back or moved between TCP and UDP, and no nonce is ever used twice with the same key.
- **TCP**: the counter must be higher than the last one accepted.
- **UDP** (touches and heartbeats): the receiver keeps the highest counter seen and a 64-bit map of the 64 below it; a repeat or anything older is dropped. The replay check runs before decryption, and the window moves only after a packet decrypts.
- A message that fails to decrypt is dropped and counted, never acted on. The Mac learns the phone's UDP address only from a packet that decrypts.

## 5. What is not protected

- The two hellos and a reject are readable by anyone on the network: the phone ID, phone name, Mac ID, both nonces, and the UDP port.
- The UDP port in the Mac's hello is not signed. Changing it only breaks touches for that connection.
- Protocol 1 sessions (a 0.2.x phone or Mac) have no forward secrecy: every session key comes from the pair key.
