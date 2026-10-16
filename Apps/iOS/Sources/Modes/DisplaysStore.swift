import Foundation
import GlasspadKit
import Observation

/// What the Mac says about its displays and windows, for every Displays screen and pane at
/// once. The Mac sends updates only while one of them shows (`watch`), at most four a second.
/// A command shows its result at once (`DisplaysState.applying`, the Mac's own math); the
/// Mac's next state confirms it or puts things back.
@MainActor
@Observable
final class DisplaysStore {
    static let shared = DisplaysStore()

    private(set) var state: DisplaysState?
    /// When the change waiting for Keep goes back by itself.
    private(set) var pendingDeadline: Date?
    /// Why the last command did not work, shown for a few seconds.
    private(set) var notice: String?
    /// Watching, connected, and the Mac has not answered for a while: it is too old for Displays.
    private(set) var macTooOld = false
    /// What the last Split Screen did, shown for a few seconds wherever it was started.
    private(set) var splitNotice: SplitNotice?

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var watchStarted: Date?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// The commands of the Split Screen in flight, and what to say once the last one worked.
    @ObservationIgnored private var splitAsked: (ids: [UUID], summary: String)?
    private var session: MacSession { .shared }

    // MARK: Watching

    /// A Displays screen or pane appeared (true) or went away (false).
    func watch(_ on: Bool) {
        let was = watchers > 0
        watchers = max(0, watchers + (on ? 1 : -1))
        let now = watchers > 0
        guard was != now else { return }
        #if DEBUG
        if session.isDemo {
            if now, state == nil { demo = DisplaysDemo(); state = demo?.state }
            return
        }
        #endif
        session.send(.displaysWatch(on: now))
        if now { expectAnswer() }
    }

    /// A new session: ask again if something is watching.
    func linkConnected() {
        guard watchers > 0 else { return }
        session.send(.displaysWatch(on: true))
        expectAnswer()
    }

    func reset() {
        state = nil
        splitAsked = nil
        pendingDeadline = nil
        notice = nil
        macTooOld = false
    }

    /// A Mac from before Displays never answers; after a few seconds, say so.
    private func expectAnswer() {
        let started = Date()
        watchStarted = started
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard self.watchStarted == started, self.watchers > 0, self.session.isConnected, self.state == nil else { return }
            self.macTooOld = true
        }
    }

    // MARK: From the Mac

    func receive(_ message: ModeMessage) {
        switch message {
        case .displaysState(let s):
            state = s
            macTooOld = false
            pendingDeadline = s.pending.map { Date().addingTimeInterval(TimeInterval($0.secondsLeft)) }
        case .displaysResult(let id, let ok, let message):
            if let asked = splitAsked, asked.ids.contains(id) {
                if !ok {
                    splitAsked = nil
                    Haptics.shared.play(.error)
                    showSplit(message ?? "Your Mac did not split the screen.", ok: false)
                } else if id == asked.ids.last {
                    splitAsked = nil
                    Haptics.shared.play(.detent)
                    showSplit(asked.summary, ok: true)
                }
                return
            }
            if ok {
                Haptics.shared.play(.detent)
            } else {
                Haptics.shared.play(.error)
                show(message ?? "Your Mac did not do that.")
            }
        default:
            break
        }
    }

    // MARK: Commands

    func run(_ command: WindowCommand, on window: MacWindow) {
        guard let state else { return }
        if command != .raise, !state.canArrangeWindows {
            Haptics.shared.play(.error)
            show("Allow Glasspad in Accessibility on your Mac to move windows.")
            return
        }
        self.state = state.applying(command, window: window.id)
        #if DEBUG
        if session.isDemo { return demoAnswer() }
        #endif
        session.send(.windowCommand(id: UUID(), windowID: window.id, command: command))
    }

    /// Split Screen as chosen in its sheet: shown at once, then confirmed by name ("Safari and
    /// Notes, side by side on Studio Display.") or with the Mac's reason it could not.
    func split(_ selection: SplitSelection) {
        guard let state, let steps = state.commands(for: selection), let summary = state.splitSummary(selection) else {
            Haptics.shared.play(.error)
            return showSplit("That window has closed.", ok: false)
        }
        guard state.canArrangeWindows else {
            Haptics.shared.play(.error)
            return showSplit("Allow Glasspad in Accessibility on your Mac to move windows.", ok: false)
        }
        var preview = state
        for step in steps { preview = preview.applying(step.command, window: step.window) }
        self.state = preview
        #if DEBUG
        if session.isDemo {
            demoAnswer()
            return showSplit(summary, ok: true)
        }
        #endif
        let ids = steps.map { _ in UUID() }
        splitAsked = (ids, summary)
        for (id, step) in zip(ids, steps) {
            session.send(.windowCommand(id: id, windowID: step.window, command: step.command))
        }
        // A dropped link never leaves it unanswered.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard self.splitAsked?.ids == ids else { return }
            self.splitAsked = nil
            self.showSplit("Your Mac did not answer.", ok: false)
        }
    }

    func run(_ command: DisplayCommand) {
        #if DEBUG
        if session.isDemo {
            demo?.run(command)
            state = demo?.state
            pendingDeadline = state?.pending.map { Date().addingTimeInterval(TimeInterval($0.secondsLeft)) }
            if let deadline = pendingDeadline { demoRevert(at: deadline) }
            if case .brightness = command { return }
            return demoAnswer()
        }
        #endif
        if case .keepChanges = command { pendingDeadline = nil }
        if case .revertChanges = command { pendingDeadline = nil }
        session.send(.displayCommand(id: UUID(), command: command))
    }

    /// Night Shift is one of the Mac controls; the next state shows it changed.
    func toggleNightShift() {
        #if DEBUG
        if session.isDemo {
            let on = demo?.state.nightShift ?? false
            demo?.state.nightShift = !on
            state = demo?.state
            return demoAnswer()
        }
        #endif
        session.send(.remoteSystem(id: UUID(), action: .nightShift))
        if let on = state?.nightShift { state?.nightShift = !on }
    }

    private func showSplit(_ text: String, ok: Bool) {
        let notice = SplitNotice(text: text, ok: ok)
        splitNotice = notice
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.splitNotice == notice { self.splitNotice = nil }
        }
    }

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self.notice = nil
        }
    }

    // MARK: Demo

    #if DEBUG
    @ObservationIgnored private var demo: DisplaysDemo?

    /// Like the Mac: no Keep in time, and the change goes back.
    private func demoRevert(at deadline: Date) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
            guard self.pendingDeadline == deadline else { return }
            self.run(.revertChanges)
        }
    }

    private func demoAnswer() {
        Haptics.shared.play(.detent)
        if let s = state { demo?.state = s }
    }

    /// Debug: start from another sample arrangement (`one`, `two`, `three`), with a change
    /// waiting for Keep when `pending` is set.
    func applyDemo(_ name: String?, pending: Bool) {
        demo = DisplaysDemo(name ?? "two")
        if pending { demo?.run(.resolution(display: 2, id: 23)) }
        state = demo?.state
        pendingDeadline = state?.pending.map { Date().addingTimeInterval(TimeInterval($0.secondsLeft)) }
    }
    #endif
}

/// One Split Screen result.
struct SplitNotice: Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
}

#if DEBUG
/// A sample Mac for simulator screenshots: a 14 inch MacBook Pro, a Studio Display beside it,
/// and a third display above in `three`. Commands change it the way the Mac would.
struct DisplaysDemo {
    var state: DisplaysState
    private var before: DisplaysState?

    init(_ name: String = "two") {
        let laptopResolutions = [(1024, 665), (1147, 745), (1312, 848), (1512, 982), (1800, 1169)].enumerated().map { i, s in
            DisplayResolution(id: Int32(10 + i), width: s.0, height: s.1, isDefault: s.0 == 1512)
        }
        let studioResolutions = [(1600, 900), (2048, 1152), (2560, 1440), (2880, 1620), (3200, 1800)].enumerated().map { i, s in
            DisplayResolution(id: Int32(20 + i), width: s.0, height: s.1, isDefault: s.0 == 2560)
        }
        let laptop = MacDisplay(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 874), isMain: true, isBuiltIn: true,
                                notchWidth: 182, brightness: 0.62, resolutions: laptopResolutions, resolutionID: 13)
        let studio = MacDisplay(id: 2, name: "Studio Display", frame: CGRect(x: 1512, y: -458, width: 2560, height: 1440),
                                visibleFrame: CGRect(x: 1512, y: -434, width: 2560, height: 1416), isMain: false,
                                brightness: 0.8, resolutions: studioResolutions, resolutionID: 22)
        let above = MacDisplay(id: 3, name: "LG HD", frame: CGRect(x: -204, y: -1080, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: -204, y: -1056, width: 1920, height: 1056), isMain: false,
                               resolutions: [DisplayResolution(id: 30, width: 1920, height: 1080, isDefault: true)], resolutionID: 30)
        func w(_ id: UInt32, _ bundle: String, _ app: String, _ title: String?, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> MacWindow {
            MacWindow(id: id, bundleID: bundle, appName: app, title: title, frame: CGRect(x: x, y: y, width: width, height: height))
        }
        var windows = [
            w(11, "com.apple.Safari", "Safari", "Apple", 1520, -426, 1268, 1400),
            w(12, "com.apple.mail", "Mail", "Inbox", 60, 90, 980, 660),
            w(13, "com.apple.dt.Xcode", "Xcode", "Glasspad", 2796, -426, 1268, 1400),
            w(14, "com.apple.MobileSMS", "Messages", "Messages", 880, 300, 560, 540),
            w(15, "com.apple.Music", "Music", "Music", 220, 160, 1080, 680),
            w(16, "com.apple.Notes", "Notes", "Ideas", 2100, -300, 700, 620),
        ]
        var displays = [laptop, studio]
        switch name {
        case "one":
            displays = [laptop]
            windows = windows.filter { $0.frame.minX < 1512 }
        case "three":
            displays.append(above)
            windows.append(w(17, "com.apple.Photos", "Photos", "Library", 100, -1000, 1400, 900))
        default:
            break
        }
        state = DisplaysState(displays: displays, windows: windows, nightShift: false, canArrangeWindows: true, tileMargin: 8)
    }

    mutating func run(_ command: DisplayCommand) {
        switch command {
        case .brightness(let id, let value):
            update(id) { $0.brightness = value }
        case .resolution(let id, let modeID):
            guard let d = state.display(id), let r = d.resolutions.first(where: { $0.id == modeID }) else { return }
            before = state
            update(id) { d in
                let top = d.visibleFrame.minY - d.frame.minY
                d.frame.size = CGSize(width: r.width, height: r.height)
                d.visibleFrame = CGRect(x: d.frame.minX, y: d.frame.minY + top, width: CGFloat(r.width), height: CGFloat(r.height) - top)
                d.resolutionID = modeID
            }
            state.pending = PendingDisplayChange(summary: "\(d.name) looks like \(r.title).", secondsLeft: 15)
        case .mirror(let id, let master):
            guard let d = state.display(id) else { return }
            before = state
            update(id) { $0.mirrorOf = master }
            let other = master.flatMap { state.display($0)?.name } ?? ""
            state.pending = PendingDisplayChange(summary: master == nil ? "\(d.name) shows its own picture again."
                                                 : "\(d.name) shows the same picture as \(other).", secondsLeft: 15)
        case .makeMain(let id):
            let origins = DisplayGeometry.origins(makingMain: id, state.shownDisplays.map { ($0.id, $0.frame) })
            arrange(origins)
            for i in state.displays.indices { state.displays[i].isMain = state.displays[i].id == id }
        case .arrange(let origins):
            arrange(origins)
        case .keepChanges:
            before = nil
            state.pending = nil
        case .revertChanges:
            if let before { state = before }
            before = nil
            state.pending = nil
        }
    }

    private mutating func update(_ id: UInt32, _ change: (inout MacDisplay) -> Void) {
        guard let i = state.displays.firstIndex(where: { $0.id == id }) else { return }
        change(&state.displays[i])
    }

    /// Moves each display, and its windows with it.
    private mutating func arrange(_ origins: [DisplayOrigin]) {
        let old = state
        for o in origins {
            guard let d = old.display(o.display) else { continue }
            let dx = o.origin.x - d.frame.minX, dy = o.origin.y - d.frame.minY
            update(o.display) { $0.frame = $0.frame.offsetBy(dx: dx, dy: dy); $0.visibleFrame = $0.visibleFrame.offsetBy(dx: dx, dy: dy) }
            for i in state.windows.indices where old.display(of: old.windows[i])?.id == o.display {
                state.windows[i].frame = old.windows[i].frame.offsetBy(dx: dx, dy: dy)
            }
        }
    }
}
#endif
