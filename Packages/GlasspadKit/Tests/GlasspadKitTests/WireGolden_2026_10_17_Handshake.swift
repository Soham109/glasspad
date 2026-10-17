// The handshake as of protocol 2 (17 October 2026), frozen. Never edit by hand: a change here
// means a phone or Mac from that version can no longer connect to this one. Protocol 1 lines
// are what 0.2.x phones and Macs send, and must keep working.
extension WireGolden {
    /// Phone -> Mac hellos: protocol 1 (0.2.x), protocol 2 asking for a new key, protocol 2
    /// with an agreed key.
    static let phoneHello_2026_10_17: [String] = [
        ##"{"macID":"0E3C9A1B-4D2F-4A55-9C21-7F8A6B3C9D11","nonce":"oaGhoaGhoaGhoaGhoaGhoQ==","phoneID":"5A1F6C2E-8B7D-4E3A-9F10-2C4B6D8E0A12","phoneName":"Soham's iPhone","t":"hello","v":1}"##,
        ##"{"kx":"B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9\/AsrhtHHw=","macID":"0E3C9A1B-4D2F-4A55-9C21-7F8A6B3C9D11","nonce":"oaGhoaGhoaGhoaGhoaGhoQ==","phoneID":"5A1F6C2E-8B7D-4E3A-9F10-2C4B6D8E0A12","phoneName":"Soham's iPhone","rekey":true,"t":"hello","v":2}"##,
        ##"{"kx":"B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9\/AsrhtHHw=","macID":"0E3C9A1B-4D2F-4A55-9C21-7F8A6B3C9D11","nonce":"oaGhoaGhoaGhoaGhoaGhoQ==","phoneID":"5A1F6C2E-8B7D-4E3A-9F10-2C4B6D8E0A12","phoneName":"Soham's iPhone","t":"hello","v":2}"##,
    ]

    /// Mac -> phone hellos: protocol 1, protocol 2 with a new key, protocol 2 without.
    static let macHello_2026_10_17: [String] = [
        ##"{"nonce":"srKysrKysrKysrKysrKysg==","t":"hello","udpPort":52100,"v":1}"##,
        ##"{"kx":"WGmv9FBUlzLLqu1eXfmzCm2jHLDldCutWtShp2jxpns=","nonce":"srKysrKysrKysrKysrKysg==","rekey":true,"t":"hello","udpPort":52100,"v":2}"##,
        ##"{"kx":"WGmv9FBUlzLLqu1eXfmzCm2jHLDldCutWtShp2jxpns=","nonce":"srKysrKysrKysrKysrKysg==","rekey":false,"t":"hello","udpPort":52100,"v":2}"##,
    ]

    static let reject_2026_10_17 = ##"{"reason":"Update Glasspad on this iPhone to use it with this Mac.","t":"reject"}"##
    static let keySaved_2026_10_17 = ##"{"t":"keySaved"}"##

    /// Known answers for `KeyAgreement.derive`. Phone private key bytes 1...32, Mac private key
    /// bytes 33...64, pair key 32 x 0x11, phone nonce 16 x 0xA1, Mac nonce 16 x 0xB2.
    enum KeyAgreement_2026_10_17 {
        static let phonePublic = "B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw="
        static let macPublic = "WGmv9FBUlzLLqu1eXfmzCm2jHLDldCutWtShp2jxpns="
        static let rekeySession = "9ff04168558e9bb8869912001fbed9a2d3d6793207a9d78a4e923f0eea3e2f1d"
        static let newPairKey = "f8f3461ecdc6b2b56518a44545b54fe83ab920f7cb557bcf537bd88610c05b11"
        static let plainSession = "81e9f55dd032a83c992dbf2ad40fbc87a7fa201635c2bf04921a88be4225772c"
        /// The phone's key confirmation (counter 0) sealed with `rekeySession`.
        static let sealedConfirm = "00000000000000004fb3c535af69f13330d1e3a584fa53815a2b5022401d664230c84425bce0673663ed62"
    }
}
