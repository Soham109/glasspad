import AppKit
import Foundation
import GlasspadKit

/// What Displays needs from the Mac. `LiveDisplays` uses CoreGraphics and the Accessibility
/// API; tests use a fake, so nothing on the real Mac moves.
@MainActor
public protocol DisplaysBackend: AnyObject {
    func displays() -> [MacDisplay]
    /// Ordinary windows on screen, front to back.
    func windows() -> [MacWindow]
    var canArrangeWindows: Bool { get }
    var tileMargin: CGFloat { get }
    /// nil on success, else why not, in words for the phone.
    func perform(_ operation: WindowOperation, window: UInt32) async -> String?
    /// `permanently` false: macOS undoes it when Glasspad quits, so a crash mid-way never
    /// leaves a blank display behind.
    func apply(_ change: DisplayChange, permanently: Bool) -> Bool
    /// Back to the last permanent setup (what was there before an unconfirmed change).
    func restorePermanent()
    func setBrightness(_ value: Double, display: UInt32)
    /// One window's frame (global display coordinates) without reading the others or asking
    /// apps through Accessibility; nil when it has closed.
    func frame(of window: UInt32) -> CGRect?
    /// Outlines this frame (global display coordinates) for a moment, over everything and
    /// without taking clicks; nothing moves or comes forward.
    func highlight(_ frame: CGRect)
}

/// One thing done to one window, with the frame already worked out.
public enum WindowOperation: Equatable, Sendable {
    case setFrame(CGRect)
    /// This window on the left of `visible` and `with` on the right, `gap` around and between
    /// them; `display` names the display in messages.
    case split(with: UInt32, visible: CGRect, gap: CGFloat, display: String)
    /// This window and `with` in their places of `arrangement` on `visible`, in order.
    case arrange(WindowArrangement, with: [UInt32], visible: CGRect, gap: CGFloat, display: String)
    /// Split View: this window on the left in full screen, `with` on the right.
    case fullScreenSplit(with: UInt32)
    case raise
    case minimize
    case close
    case fullScreen
}

/// One change to the display setup.
public enum DisplayChange: Equatable, Sendable {
    case resolution(display: UInt32, id: Int32)
    case mirror(display: UInt32, of: UInt32?)
    case origins([DisplayOrigin])
}

/// The Displays screen's Mac side: sends the displays and windows while the phone watches,
/// moves windows, and changes displays. A new resolution or mirroring waits 15 seconds for
/// Keep, like macOS's own "Keep these display settings?", and goes back by itself otherwise.
@MainActor
public final class DisplaysMode {
    public var send: (ModeMessage) -> Void = { _ in }
    /// Icons for apps the phone has not been sent yet (DockMode's, PNG keyed by bundle id).
    public var icons: ([String]) -> [DockApp] = { _ in [] }
    /// Night Shift on now, nil when unknown.
    public var nightShift: @MainActor () -> Bool? = { nil }

    /// How long an unconfirmed change waits for Keep.
    public static let keepSeconds = 15
    /// Window positions are read this often while the phone watches.
    public static let pollInterval: TimeInterval = 0.25

    let backend: DisplaysBackend
    var now: () -> Date = Date.init
    public private(set) var isWatching = false
    private var timer: Timer?
    private var last: DisplaysState?
    private var iconsSent: Set<String> = []
    private var pending: Pending?
    /// The window command running now, which the next one waits for.
    private var windowWork: Task<Void, Never>?

    private struct Pending {
        var token = UUID()
        var change: DisplayChange
        var summary: String
        var deadline: Date
    }

    public init(backend: DisplaysBackend) {
        self.backend = backend
    }

    // MARK: Watching

    public func watch(_ on: Bool) {
        isWatching = on
        timer?.invalidate()
        timer = nil
        guard on else { return }
        last = nil
        push()
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The phone left: stop reading windows and forget which icons it has. A change waiting for
    /// Keep still goes back on time.
    public func sessionEnded() {
        watch(false)
        iconsSent.removeAll()
    }

    func state() -> DisplaysState {
        let left = pending.map { max(0, Int($0.deadline.timeIntervalSince(now()).rounded(.up))) }
        return DisplaysState(displays: backend.displays(), windows: backend.windows(), nightShift: nightShift(),
                             canArrangeWindows: backend.canArrangeWindows, tileMargin: Double(backend.tileMargin),
                             pending: pending.map { PendingDisplayChange(summary: $0.summary, secondsLeft: left ?? 0) },
                             arrangements: WindowArrangement.allCases.map(\.rawValue), highlightsWindows: true)
    }

    /// Sends the state when it changed, with the icons of apps the phone has not seen first.
    func push() {
        guard isWatching else { return }
        let s = state()
        guard s != last else { return }
        last = s
        let newApps = Set(s.windows.compactMap(\.bundleID)).subtracting(iconsSent)
        if !newApps.isEmpty {
            iconsSent.formUnion(newApps)
            let apps = icons(newApps.sorted()).filter { $0.iconPNG != nil }
            if !apps.isEmpty { send(.dockIcons(apps: apps)) }
        }
        send(.displaysState(s))
    }

    // MARK: Windows

    /// Runs one window command after the ones before it (windows take a moment to land, and
    /// the main thread stays free meanwhile). The task is for tests to wait on.
    @discardableResult
    public func handle(id: UUID, windowID: UInt32, command: WindowCommand) -> Task<Void, Never> {
        let before = windowWork
        let task = Task { @MainActor in
            await before?.value
            let message = await self.run(windowID: windowID, command: command)
            self.send(.displaysResult(id: id, ok: message == nil, message: message))
            self.push()
        }
        windowWork = task
        return task
    }

    private func run(windowID: UInt32, command: WindowCommand) async -> String? {
        let s = DisplaysState(displays: backend.displays(), windows: backend.windows(), tileMargin: Double(backend.tileMargin))
        guard s.window(windowID) != nil else { return "That window has closed." }
        if command != .raise, !backend.canArrangeWindows {
            return "Allow Glasspad in System Settings > Privacy & Security > Accessibility to move windows."
        }
        guard let steps = Self.plan(command, window: windowID, in: s) else { return "That display is not connected any more." }
        for step in steps {
            if let failure = await backend.perform(step.operation, window: step.window) { return failure }
        }
        return nil
    }

    /// The steps for a command: new frames first, then what brings windows forward.
    nonisolated static func plan(_ command: WindowCommand, window id: UInt32,
                                 in s: DisplaysState) -> [(window: UInt32, operation: WindowOperation)]? {
        guard let moves = s.frames(for: command, window: id) else { return nil }
        let framed = moves.map { (window: $0.window, operation: WindowOperation.setFrame($0.frame)) }
        switch command {
        case .raise: return [(id, .raise)]
        case .minimize: return [(id, .minimize)]
        case .close: return [(id, .close)]
        case .fullScreen: return [(id, .fullScreen)]
        case .split(let other):
            // Both together, so a window that will not get narrow enough leaves the other the rest.
            guard let w = s.window(id), let d = s.display(of: w) else { return nil }
            return [(id, .split(with: other, visible: d.visibleFrame, gap: CGFloat(s.tileMargin), display: d.name)),
                    (other, .raise), (id, .raise)]
        case .tile, .move: return framed + [(id, .raise)]
        case .arrange(let arrangement, let ids, let displayID):
            guard let d = s.shownDisplays.first(where: { $0.id == displayID }) else { return nil }
            if arrangement == .fullScreen {
                // Split View happens on the first window's display: over there first.
                guard let w = s.window(id), let from = s.display(of: w) else { return nil }
                let over: [(window: UInt32, operation: WindowOperation)] = from.id == d.id ? []
                    : [(id, .setFrame(DisplayGeometry.moved(w.frame, from: from.visibleFrame, to: d.visibleFrame)))]
                return over + [(id, .fullScreenSplit(with: ids[1]))]
            }
            // All together, so a window that will not get small enough leaves the others the rest.
            return [(id, .arrange(arrangement, with: Array(ids.dropFirst()), visible: d.visibleFrame, gap: CGFloat(s.tileMargin),
                                  display: d.name))]
        }
    }

    /// The phone picked this window: outline it on the Mac so the person sees which one it is.
    /// No answer, and nothing for a window that has closed. Reads that one window only: picks
    /// come often, and the full window list asks every app through Accessibility.
    public func highlight(windowID: UInt32) {
        guard let frame = backend.frame(of: windowID) else { return }
        backend.highlight(frame)
    }

    // MARK: Displays

    public func handle(id: UUID, command: DisplayCommand) {
        let message = run(command)
        send(.displaysResult(id: id, ok: message == nil, message: message))
        push()
    }

    private func run(_ command: DisplayCommand) -> String? {
        let displays = backend.displays()
        func display(_ id: UInt32) -> MacDisplay? { displays.first { $0.id == id } }
        let gone = "That display is not connected any more."
        switch command {
        case .brightness(let id, let value):
            guard let d = display(id), d.brightness != nil else { return "Glasspad cannot change this display's brightness." }
            backend.setBrightness(min(1, max(0, value)), display: d.id)
            return nil
        case .keepChanges:
            guard let p = pending else { return nil }
            pending = nil
            return backend.apply(p.change, permanently: true) ? nil : "Your Mac did not keep the change."
        case .revertChanges:
            guard pending != nil else { return nil }
            pending = nil
            backend.restorePermanent()
            return nil
        default:
            break
        }
        // One change at a time while the last one waits for Keep.
        guard pending == nil else { return "Keep or revert the last change first." }
        switch command {
        case .resolution(let id, let modeID):
            guard let d = display(id) else { return gone }
            guard let r = d.resolutions.first(where: { $0.id == modeID }) else { return "That resolution is not available." }
            guard d.resolutionID != modeID else { return nil }
            return tryChange(.resolution(display: id, id: modeID), summary: "\(d.name) looks like \(r.title).")
        case .mirror(let id, let master):
            guard let d = display(id) else { return gone }
            if let master {
                guard let m = display(master), m.id != id else { return gone }
                // A display that copies another cannot be copied (no loops, no chains).
                guard m.mirrorOf == nil else { return "\(m.name) shows another display's picture." }
                return tryChange(.mirror(display: id, of: master), summary: "\(d.name) shows the same picture as \(m.name).")
            }
            guard d.mirrorOf != nil else { return nil }
            return tryChange(.mirror(display: id, of: nil), summary: "\(d.name) shows its own picture again.")
        case .makeMain(let id):
            guard display(id) != nil else { return gone }
            let origins = DisplayGeometry.origins(makingMain: id, displays.filter { $0.mirrorOf == nil }.map { ($0.id, $0.frame) })
            return backend.apply(.origins(origins), permanently: true) ? nil : "Your Mac did not change the main display."
        case .arrange(let origins):
            // Only displays with their own picture have a place, each named once.
            let shown = displays.filter { $0.mirrorOf == nil }
            guard !origins.isEmpty, Set(origins.map(\.display)).count == origins.count,
                  origins.allSatisfy({ o in shown.contains { $0.id == o.display } }) else { return gone }
            let main = displays.first(where: \.isMain)?.id ?? origins[0].display
            let placed = DisplayGeometry.normalized(origins, main: main)
            // The whole desk afterwards (displays left out keep their place) must be one piece.
            let frames = shown.map { d in
                placed.first { $0.display == d.id }.map { CGRect(origin: $0.origin, size: d.frame.size) } ?? d.frame
            }
            guard DisplayGeometry.isReachableArrangement(frames) else { return "Each display needs to touch another along an edge." }
            return backend.apply(.origins(placed), permanently: true) ? nil : "Your Mac did not move the displays."
        case .brightness, .keepChanges, .revertChanges:
            return nil
        }
    }

    /// Applies a change that could leave a display blank, then waits for Keep.
    private func tryChange(_ change: DisplayChange, summary: String) -> String? {
        guard backend.apply(change, permanently: false) else { return "Your Mac did not make that change." }
        let p = Pending(change: change, summary: summary, deadline: now().addingTimeInterval(TimeInterval(Self.keepSeconds)))
        pending = p
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.keepSeconds))
            self?.timedOut(p.token)
        }
        return nil
    }

    var pendingToken: UUID? { pending?.token }

    /// No Keep in time: back to how it was.
    func timedOut(_ token: UUID) {
        guard pending?.token == token else { return }
        pending = nil
        backend.restorePermanent()
        push()
    }
}

/// Picks the "Looks like" sizes System Settings offers from every mode a display has: scaled
/// (HiDPI) sizes in the panel's shape, one per size, at most five spread from Larger Text to
/// More Space, always with the default and the one in use. A display without scaled sizes
/// (most older monitors) gets its plain sizes in the same shape instead.
public enum ResolutionChoices {
    /// One display mode as CoreGraphics reports it.
    public struct Mode: Equatable, Sendable {
        public var id: Int32
        /// Points.
        public var width: Int, height: Int
        public var pixelWidth: Int, pixelHeight: Int
        public var refreshRate: Double
        public var usable: Bool
        public var isDefault: Bool

        public init(id: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double = 60,
                    usable: Bool = true, isDefault: Bool = false) {
            self.id = id
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.refreshRate = refreshRate
            self.usable = usable
            self.isDefault = isDefault
        }

        var isScaled: Bool { pixelWidth == width * 2 && pixelHeight == height * 2 }
    }

    public static let maxChoices = 5

    public static func choices(_ modes: [Mode], current: Mode?) -> [DisplayResolution] {
        let usable = modes.filter { $0.usable && $0.width > 0 && $0.height > 0 }
        // The panel's own pixels: its largest unscaled mode (scaled ones can draw more pixels).
        func larger(_ a: Mode, _ b: Mode) -> Bool { a.pixelWidth * a.pixelHeight < b.pixelWidth * b.pixelHeight }
        guard let native = usable.filter({ !$0.isScaled }).max(by: larger) ?? usable.max(by: larger) else { return [] }
        let shape = Double(native.pixelWidth) / Double(native.pixelHeight)
        let sameShape = usable.filter { abs(Double($0.width) / Double($0.height) - shape) < 0.02 }
        // Scaled sizes down to 60% of the panel's own (smaller ones are only for tiny panels).
        let scaled = sameShape.filter { $0.isScaled && $0.width * 10 >= native.pixelWidth * 3 }
        // Plain sizes: not below 1024 points wide, nothing smaller is a sensible desktop.
        var pool = scaled.isEmpty ? sameShape.filter { !$0.isScaled && $0.width >= 1024 } : scaled
        if let current, current.usable, !pool.contains(where: { $0.width == current.width && $0.height == current.height }) {
            pool.append(current)
        }
        // One mode per size: the current one, else the current refresh rate, else the fastest.
        var bySize: [String: Mode] = [:]
        for m in pool {
            let key = "\(m.width)x\(m.height)"
            guard let have = bySize[key] else { bySize[key] = m; continue }
            func rank(_ x: Mode) -> (Int, Int, Double) {
                (x.id == current?.id ? 1 : 0, x.refreshRate == current?.refreshRate ? 1 : 0, x.refreshRate)
            }
            if rank(m) > rank(have) { bySize[key] = m }
        }
        let sorted = bySize.values.sorted { $0.width < $1.width }
        // Default: the one macOS marks, else half the panel's pixels (what a Mac picks).
        let defaultSize = sorted.first(where: \.isDefault).map { ($0.width, $0.height) }
            ?? sorted.first { $0.pixelWidth == native.pixelWidth && $0.width * 2 == native.pixelWidth }.map { ($0.width, $0.height) }
            ?? (scaled.isEmpty ? (native.width, native.height) : nil)
        var keep = sorted
        if sorted.count > maxChoices {
            var picked = Set<Int>([0, sorted.count - 1])
            if let d = defaultSize, let i = sorted.firstIndex(where: { ($0.width, $0.height) == d }) { picked.insert(i) }
            if let c = current, let i = sorted.firstIndex(where: { $0.width == c.width && $0.height == c.height }) { picked.insert(i) }
            // The rest spread evenly between the ends, then any left, to five in all.
            for k in 1..<(maxChoices - 1) where picked.count < maxChoices {
                picked.insert(Int((Double(k) * Double(sorted.count - 1) / Double(maxChoices - 1)).rounded()))
            }
            for i in sorted.indices where picked.count < maxChoices { picked.insert(i) }
            keep = picked.sorted().map { sorted[$0] }
        }
        return keep.map { m in
            DisplayResolution(id: m.id, width: m.width, height: m.height,
                              isDefault: defaultSize.map { $0 == (m.width, m.height) } ?? false)
        }
    }
}
