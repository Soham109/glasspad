import Foundation
import CryptoKit

/// Protocol 2 key agreement (docs/SPEC.md section 3).
///
/// Every protocol 2 connection runs an X25519 exchange: each side makes a fresh key pair and
/// sends the public half in its hello. The shared secret is mixed with the stored pair key, so
///
/// - the session key needs both the pair key and that connection's private keys (someone who
///   later learns the pair key still cannot read a recorded session), and
/// - on a connection that asks for it (`rekey`), both sides also derive a new pair key and keep
///   it in place of the old one. A phone pairing from a code always asks, so the key in the code
///   (and in a copied link or a screenshot of it) is never the phone's long-term key.
///
/// ```
/// ikm         = X25519(phone, mac) || pairKey
/// salt        = nonce_p || nonce_m
/// sessionKey  = HKDF-SHA256(ikm, salt, "glasspad v2 session" || rekey (1 byte) || pub_p || pub_m)
/// newPairKey  = HKDF-SHA256(ikm, salt, "glasspad v2 pair" || pub_p || pub_m)     (only when rekey)
/// ```
///
/// Both public keys and the rekey flag are in the info, so changing either unencrypted hello
/// makes the two sides derive different keys and the key confirmation fails.
public enum KeyAgreement {
    static let sessionInfo = Data("glasspad v2 session".utf8)
    static let pairInfo = Data("glasspad v2 pair".utf8)
    public static let publicKeyLength = 32

    public struct Keys: Equatable, Sendable {
        /// Seals and opens this connection's messages.
        public let sessionKey: Data
        /// The pair key both sides keep from now on; nil when the connection did not rekey.
        public let newPairKey: Data?
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The other side's public key is not 32 bytes, or is a value that gives no secret.
        case badPublicKey
    }

    /// A fresh key pair for one connection. Never stored.
    public static func makeKeyPair() -> Curve25519.KeyAgreement.PrivateKey { Curve25519.KeyAgreement.PrivateKey() }

    /// The keys for one connection. Both sides call this with the same values (their own
    /// private key and the other side's public key) and get the same result.
    public static func derive(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicKey: Data, pairKey: Data,
                              phoneNonce: Data, macNonce: Data, phonePublicKey: Data, macPublicKey: Data,
                              rekey: Bool) throws -> Keys {
        guard peerPublicKey.count == publicKeyLength,
              let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: peer)
        else { throw Failure.badPublicKey }
        let secret = shared.withUnsafeBytes { Data($0) }
        // A small-order public key gives an all-zero secret: refuse it rather than fall back to
        // the pair key alone.
        guard secret.contains(where: { $0 != 0 }) else { throw Failure.badPublicKey }
        var ikm = secret
        ikm.append(pairKey)
        var salt = phoneNonce
        salt.append(macNonce)
        var info = sessionInfo
        info.append(rekey ? 1 : 0)
        info.append(phonePublicKey)
        info.append(macPublicKey)
        let session = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: info,
                                             outputByteCount: 32)
        var newPair: Data?
        if rekey {
            var pInfo = pairInfo
            pInfo.append(phonePublicKey)
            pInfo.append(macPublicKey)
            newPair = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: pInfo,
                                             outputByteCount: 32).withUnsafeBytes { Data($0) }
        }
        return Keys(sessionKey: session.withUnsafeBytes { Data($0) }, newPairKey: newPair)
    }
}
