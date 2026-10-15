import Foundation
import CoreGraphics

/// A listen-only Quartz event tap on its own thread and run loop.
///
/// Listen-only taps cannot change or delay events; they need Input Monitoring.
/// The tap thread exists only between `start()` and `stop()`.
final class ListenOnlyEventTap: @unchecked Sendable {
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Void

    private let mask: CGEventMask
    private let handler: Handler
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(types: [CGEventType], handler: @escaping Handler) {
        self.mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        self.handler = handler
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return port != nil
    }

    /// Returns false if the tap could not be created (usually: no Input Monitoring permission).
    func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if port != nil { return true }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<ListenOnlyEventTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                tap.reenable()
            } else {
                tap.handler(type, event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let newPort = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .listenOnly, eventsOfInterest: mask,
                                              callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        port = newPort
        let ready = DispatchSemaphore(value: 0)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newPort, 0)
        let box = LockedBox<CFRunLoop?>(nil)
        // CF types are thread-safe to hand over; the wrapper tells Swift so.
        let refs = UncheckedSendable((source, newPort))
        let t = Thread {
            let rl = CFRunLoopGetCurrent()!
            box.set(rl)
            CFRunLoopAddSource(rl, refs.value.0, .commonModes)
            CGEvent.tapEnable(tap: refs.value.1, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "Glasspad event tap"
        t.qualityOfService = .userInteractive
        t.start()
        ready.wait()
        runLoop = box.get()
        thread = t
        return true
    }

    private func reenable() {
        lock.lock(); defer { lock.unlock() }
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop { CFRunLoopStop(runLoop) }
        self.port = nil
        self.runLoop = nil
        self.thread = nil
    }

    deinit { stop() }
}

extension CGEvent {
    var isFromMacroPlayback: Bool {
        getIntegerValueField(.eventSourceUserData) == MacroEventMarker.userData
    }

    var macroModifiers: KeyModifiers {
        var m: KeyModifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        return m
    }
}
