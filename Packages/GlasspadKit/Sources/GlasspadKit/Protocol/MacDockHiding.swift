import Foundation

/// The one "Hide Mac Dock" choice both apps show, over the two switches `MacDockState` carries
/// (the wire format stays as it is). Always is the manual switch; While Connected is the other.
public enum MacDockHiding: String, CaseIterable, Sendable {
    case never, whileConnected, always

    public init(_ state: MacDockState?) {
        guard let state else { self = .never; return }
        self = state.hidden ? .always : state.hideWhileConnected ? .whileConnected : .never
    }

    /// The two switches for this choice, sent as one change.
    public var state: MacDockState {
        MacDockState(hidden: self == .always, hideWhileConnected: self == .whileConnected)
    }

    public var title: String {
        switch self {
        case .never: "Never"
        case .whileConnected: "While Connected"
        case .always: "Always"
        }
    }

    /// Under the choice, on both apps.
    public static let footer = "While Connected hides it only while your iPhone is connected. Never, or quitting Glasspad, brings it back."
}
