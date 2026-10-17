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

The pair key in the code becomes that phone's stored key on both sides (Keychain, `AfterFirstUnlockThisDeviceOnly`). It is not replaced after pairing.

## 3. Handshake (TCP)

```
phone -> Mac   hello   {phoneID, phoneName, macID, nonce_p (16 bytes), v: 1}      not encrypted
Mac   -> phone hello   {nonce_m (16 bytes), udpPort}                              not encrypted
                       or a reject {reason}
both           sessionKey = HKDF-SHA256(ikm: pairKey, salt: nonce_p || nonce_m,
                                        info: "glasspad v1 session", 32 bytes)
phone -> Mac   seal("glasspad confirm v1")    proves the phone holds the key
Mac   -> phone seal("glasspad confirm v1")    proves the Mac holds the key
```

- The Mac looks up the stored key for `phoneID`. If there is none and a code is armed, it tries the code's key, and saves the phone only after the phone's proof checks out. A known phone that scanned a new code is checked against both keys.
- Before accepting, the Mac asks the Keychain again, so a phone forgotten during the handshake is refused.
- The phone accepts the session only after the Mac's proof checks out.
- Handshake messages are limited to 8 KB, at most 8 handshakes run at once, and each must finish within 5 seconds.

Because both nonces go into the key, every connection has its own key, and a recorded handshake cannot be replayed.

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
- There is no forward secrecy: every session key comes from the pair key, so someone who later gets the pair key and recorded the traffic can decrypt it. A key exchange during pairing (planned, see the threat model) would fix this and the reuse of the code as the long-term key.
