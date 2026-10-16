import AppKit
import ApplicationServices
import GlasspadKit

/// The real Mac behind Displays. Windows come from the window server's list (order and frames,
/// no Screen Recording needed) and their names from the Accessibility API, which also moves
/// them. Displays come from CoreGraphics and AppKit; changes go through a CoreGraphics display
/// configuration.
@MainActor
public final class LiveDisplays: DisplaysBackend {
    private var cachedDisplays: [MacDisplay] = []
    private var displaysReadAt = Date.distantPast
    private var resolutionCache: [String: [DisplayResolution]] = [:]
    /// Accessibility windows by window id, refreshed at most once a second.
    private var axWindows: [UInt32: (app: AXUIElement, window: AXUIElement, title: String?)] = [:]
    private var axReadAt = Date.distantPast
    private var marginReadAt = Date.distantPast
    private var margin: CGFloat = DisplayGeometry.tileMargin
    private var screenObserver: NSObjectProtocol?

    public init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in self?.displaysReadAt = .distantPast }
        }
    }

    public var canArrangeWindows: Bool { AXIsProcessTrusted() }

    /// The gap from "Tiled windows have margins" (on unless the person turned it off).
    public var tileMargin: CGFloat {
        if Date().timeIntervalSince(marginReadAt) > 2 {
            marginReadAt = Date()
            let domain = "com.apple.WindowManager" as CFString
            CFPreferencesAppSynchronize(domain)
            let on = CFPreferencesCopyAppValue("EnableTiledWindowMargins" as CFString, domain) as? Bool
            margin = on ?? true ? DisplayGeometry.tileMargin : 0
        }
        return margin
    }

    // MARK: Displays

    public func displays() -> [MacDisplay] {
        // Brightness moves on its own (the keys, ambient light), so read once a second.
        if Date().timeIntervalSince(displaysReadAt) < 1 { return cachedDisplays }
        displaysReadAt = Date()
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let screens = Dictionary(NSScreen.screens.compactMap { s in
            (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { ($0.uint32Value, s) }
        }, uniquingKeysWith: { a, _ in a })
        cachedDisplays = ids.prefix(Int(count)).compactMap { id -> MacDisplay? in
            let master = CGDisplayMirrorsDisplay(id)
            guard CGDisplayIsActive(id) != 0 || master != kCGNullDirectDisplay, CGDisplayIsAsleep(id) == 0 else { return nil }
            let frame = CGDisplayBounds(id)
            let screen = screens[id]
            let visible = screen.map { DisplayGeometry.quartz($0.visibleFrame, mainHeight: mainHeight) } ?? frame
            var notch: Double?
            if let screen, screen.safeAreaInsets.top > 0,
               let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notch = Double(screen.frame.width - left.width - right.width)
            }
            let current = CGDisplayCopyDisplayMode(id)
            return MacDisplay(id: id, name: screen?.localizedName ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display"),
                              frame: frame, visibleFrame: visible, isMain: CGDisplayIsMain(id) != 0,
                              isBuiltIn: CGDisplayIsBuiltin(id) != 0, notchWidth: notch,
                              mirrorOf: master == kCGNullDirectDisplay ? nil : master,
                              brightness: Brightness.get(display: id).map(Double.init),
                              resolutions: resolutions(id, current: current),
                              resolutionID: current.map { $0.ioDisplayModeID })
        }
        return cachedDisplays
    }

    private func allModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    }

    /// Reading every mode is slow, so the choices are kept per display and mode in use.
    private func resolutions(_ id: CGDirectDisplayID, current: CGDisplayMode?) -> [DisplayResolution] {
        let key = "\(id)/\(current?.ioDisplayModeID ?? 0)"
        if let cached = resolutionCache[key] { return cached }
        func mode(_ m: CGDisplayMode) -> ResolutionChoices.Mode {
            // kDisplayModeDefaultFlag (IOKit IOGraphicsTypes.h).
            ResolutionChoices.Mode(id: m.ioDisplayModeID, width: m.width, height: m.height, pixelWidth: m.pixelWidth,
                                   pixelHeight: m.pixelHeight, refreshRate: m.refreshRate,
                                   usable: m.isUsableForDesktopGUI(), isDefault: m.ioFlags & 0x4 != 0)
        }
        let choices = ResolutionChoices.choices(allModes(id).map(mode), current: current.map(mode))
        resolutionCache[key] = choices
        return choices
    }

    public func setBrightness(_ value: Double, display: UInt32) {
        Brightness.set(Float(value), display: display)
        displaysReadAt = .distantPast
    }

    public func apply(_ change: DisplayChange, permanently: Bool) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        var ok = true
        switch change {
        case .resolution(let display, let id):
            if let mode = allModes(display).first(where: { $0.ioDisplayModeID == id }) {
                ok = CGConfigureDisplayWithDisplayMode(config, display, mode, nil) == .success
            } else {
                ok = false
            }
        case .mirror(let display, let master):
            ok = CGConfigureDisplayMirrorOfDisplay(config, display, master ?? kCGNullDirectDisplay) == .success
        case .origins(let origins):
            for o in origins where ok {
                ok = CGConfigureDisplayOrigin(config, o.display, Int32(o.origin.x.rounded()), Int32(o.origin.y.rounded())) == .success
            }
        }
        guard ok else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        displaysReadAt = .distantPast
        return CGCompleteDisplayConfiguration(config, permanently ? .permanently : .forAppOnly) == .success
    }

    public func restorePermanent() {
        CGRestorePermanentDisplayConfiguration()
        displaysReadAt = .distantPast
    }

    // MARK: Windows

    public func windows() -> [MacWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: NSRunningApplication?] = [:]
        var out: [MacWindow] = []
        var pids = Set<pid_t>()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 40, bounds.height >= 40 else { continue }
            if apps[pid] == nil { apps[pid] = NSRunningApplication(processIdentifier: pid) }
            guard let app = apps[pid] ?? nil, app.activationPolicy == .regular else { continue }
            pids.insert(pid)
            out.append(MacWindow(id: id, bundleID: app.bundleIdentifier,
                                 appName: app.localizedName ?? info[kCGWindowOwnerName as String] as? String ?? "App",
                                 frame: bounds))
        }
        refreshAccessibility(pids: pids, force: false)
        return out.map { w in
            var w = w
            w.title = axWindows[w.id]?.title
            return w
        }
    }

    /// Names and handles of every window of these apps (Accessibility, so no Screen Recording).
    private func refreshAccessibility(pids: Set<pid_t>, force: Bool) {
        guard AXIsProcessTrusted(), force || Date().timeIntervalSince(axReadAt) >= 1 else { return }
        axReadAt = Date()
        var found: [UInt32: (app: AXUIElement, window: AXUIElement, title: String?)] = [:]
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            // A busy app must never stall the poll.
            AXUIElementSetMessagingTimeout(app, 0.2)
            for window in Self.elements(app, kAXWindowsAttribute) {
                guard let id = Self.windowID(window) else { continue }
                found[id] = (app, window, Self.attribute(window, kAXTitleAttribute) as? String)
            }
        }
        axWindows = found
    }

    public func perform(_ operation: WindowOperation, window id: UInt32) -> String? {
        guard AXIsProcessTrusted() else {
            return "Allow Glasspad in System Settings > Privacy & Security > Accessibility to move windows."
        }
        if axWindows[id] == nil, let pid = ownerPID(id) { refreshAccessibility(pids: [pid], force: true) }
        guard let (app, window, _) = axWindows[id] else { return "That window cannot be reached." }
        let fullScreen = (Self.attribute(window, "AXFullScreen") as? NSNumber)?.boolValue == true
        switch operation {
        case .setFrame(let frame):
            if fullScreen { return "That window is in full screen." }
            return Self.set(window, app: app, to: frame) ? nil : "That window cannot be moved."
        case .raise:
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            if let pid = ownerPID(id) { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
            return nil
        case .minimize:
            if fullScreen { return "That window is in full screen." }
            return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
                ? nil : "That window cannot be minimized."
        case .close:
            guard let v = Self.attribute(window, kAXCloseButtonAttribute), CFGetTypeID(v) == AXUIElementGetTypeID(),
                  AXUIElementPerformAction(v as! AXUIElement, kAXPressAction as CFString) == .success
            else { return "That window cannot be closed." }
            return nil
        case .fullScreen:
            let ok = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, (!fullScreen) as CFBoolean) == .success
            return ok ? nil : "That window cannot go full screen."
        }
    }

    private func ownerPID(_ id: UInt32) -> pid_t? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first else { return nil }
        return info[kCGWindowOwnerPID as String] as? pid_t
    }

    // MARK: Accessibility helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let array = attribute(element, name) as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// `_AXUIElementGetWindow`, the private call every window manager uses to match an
    /// Accessibility window with the window server's id. Without it, titles are left out and
    /// windows cannot be moved, but they still show.
    private static let getWindow: GetWindowFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: GetWindowFn.self)
    }()

    private static func windowID(_ window: AXUIElement) -> UInt32? {
        guard let getWindow else { return nil }
        var id = CGWindowID(0)
        return getWindow(window, &id) == .success && id != 0 ? id : nil
    }

    /// Size, position, size again (a window crossing displays can be limited by the display it
    /// starts on). "Enhanced user interface", which some apps turn on for assistive tools,
    /// animates every change and makes sizes land wrong, so it is off while moving.
    private static func set(_ window: AXUIElement, app: AXUIElement, to frame: CGRect) -> Bool {
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        let enhanced = (attribute(app, enhancedKey as String) as? NSNumber)?.boolValue == true
        if enhanced { AXUIElementSetAttributeValue(app, enhancedKey, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, enhancedKey, kCFBooleanTrue) } }
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue) == .success
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return sized || moved
    }
}
