import Foundation

/// A ready-made starting point, like a document template. Picking one makes a new layout the
/// person can then change and name.
public struct LayoutTemplate: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var panes: [String]
    public var direction: SplitDirection
    public var split: Double
    public var innerSplit: Double

    public init(id: String, name: String, panes: [String], direction: SplitDirection = .automatic,
                split: Double = 0.5, innerSplit: Double = 0.5) {
        self.id = id
        self.name = name
        self.panes = panes
        self.direction = direction
        self.split = split
        self.innerSplit = innerSplit
    }

    /// A new layout from this template.
    public func makeLayout(named name: String? = nil) -> ScreenLayout {
        ScreenLayout(name: name ?? self.name, panes: panes, direction: direction, split: split, innerSplit: innerSplit)
    }

    /// The built-in templates, most useful first. Mode names match `AppMode` on the phone; the
    /// app hides any template whose modes this build does not have.
    public static let builtIn: [LayoutTemplate] = [
        LayoutTemplate(id: "trackpad-actions", name: "Trackpad and Actions", panes: ["trackpad", "actions"], split: 0.6),
        LayoutTemplate(id: "trackpad-keys", name: "Trackpad and Keyboard", panes: ["trackpad", "keys"], direction: .stacked, split: 0.5),
        LayoutTemplate(id: "trackpad-media", name: "Trackpad and Media", panes: ["trackpad", "media"], split: 0.6),
        LayoutTemplate(id: "trackpad-dock", name: "Trackpad and Dock", panes: ["trackpad", "dock"], split: 0.6),
        LayoutTemplate(id: "media-actions", name: "Media and Actions", panes: ["media", "actions"]),
        LayoutTemplate(id: "desk", name: "Desk", panes: ["trackpad", "media", "actions"], split: 0.5),
        LayoutTemplate(id: "presenter", name: "Presenter", panes: ["present", "trackpad"], split: 0.5),
        LayoutTemplate(id: "couch", name: "Couch", panes: ["remote", "media"], split: 0.5),
        LayoutTemplate(id: "remote-trackpad", name: "Remote and Trackpad", panes: ["remote", "trackpad"], split: 0.5),
    ]
}
