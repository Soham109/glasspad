import AppKit

/// Copy Link for the pairing code. The link holds a secret that works until pairing ends, so
/// it goes on the pasteboard marked the way clipboard history apps and password managers agree
/// on (nspasteboard.org):
///
/// - `org.nspasteboard.ConcealedType`: private, do not show or keep it.
/// - `org.nspasteboard.TransientType`: short-lived, do not record it at all.
///
/// When pairing ends (paired, expired, cancelled or refused) the link is cleared again, unless
/// something else was copied since. It still reaches the iPhone through Universal Clipboard,
/// which is how Paste the Link Instead works on the phone.
@MainActor
public final class PairingLinkPasteboard {
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    public static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    /// The pasteboard's change count right after our copy; nil when nothing of ours is there.
    private var ourChange: Int?

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func copy(_ url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
        pasteboard.setData(Data(), forType: Self.concealedType)
        pasteboard.setData(Data(), forType: Self.transientType)
        ourChange = pasteboard.changeCount
    }

    /// Pairing ended: take the link off the pasteboard if it is still the last thing copied.
    public func clear() {
        guard let change = ourChange else { return }
        ourChange = nil
        guard pasteboard.changeCount == change else { return }
        pasteboard.clearContents()
    }
}
