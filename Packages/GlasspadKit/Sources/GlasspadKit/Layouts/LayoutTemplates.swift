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
    /// app hides any template whose modes this build does not have. The first four are also
    /// the layouts a new install starts with (`LayoutLibrary.starter`).
    public static let builtIn: [LayoutTemplate] = [
        LayoutTemplate(id: "desk", name: "Desk", panes: ["trackpad", "actions"], split: 0.6),
        LayoutTemplate(id: "type", name: "Type", panes: ["trackpad", "keys"], split: 0.5),
        LayoutTemplate(id: "listen", name: "Listen", panes: ["trackpad", "media"], split: 0.6),
        LayoutTemplate(id: "couch", name: "Couch", panes: ["remote", "trackpad"], split: 0.6),
        LayoutTemplate(id: "trackpad-dock", name: "Trackpad and Dock", panes: ["trackpad", "dock"], split: 0.6),
        LayoutTemplate(id: "media-actions", name: "Media and Actions", panes: ["media", "actions"]),
        LayoutTemplate(id: "studio", name: "Studio", panes: ["trackpad", "media", "actions"], split: 0.5),
        LayoutTemplate(id: "presenter", name: "Presenter", panes: ["present", "trackpad"], split: 0.5),
        LayoutTemplate(id: "standby", name: "StandBy", panes: ["clock", "nowPlaying"]),
        LayoutTemplate(id: "clock-trackpad", name: "Clock and Trackpad", panes: ["clock", "trackpad"], split: 0.4),
    ]

    /// The layouts a new install starts with.
    public static let starterIDs = ["desk", "type", "listen", "couch"]
}
