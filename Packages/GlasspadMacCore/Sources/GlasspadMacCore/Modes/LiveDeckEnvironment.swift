import AppKit
import AudioToolbox
import CoreAudio
import GlasspadKit

/// The real Mac behind Deck buttons.
@MainActor
public final class LiveDeckEnvironment: DeckEnvironment {
    private let keys: KeysMode
    private let mediaMode: MediaMode?
    /// Wired by the router once macros exist.
    public var macroRunner: ((UUID) async -> (ok: Bool, message: String?))?
    private var savedInputVolume: Float32?

    public init(keys: KeysMode, media: MediaMode? = nil) {
        self.keys = keys
        self.mediaMode = media
    }

    /// `CoreDockSendNotification` (private, in ApplicationServices, loaded with dlsym and checked
    /// before use): the call the Dock's own keys and gestures make.
    private typealias CoreDockSend = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
    private static let coreDockSend: CoreDockSend? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: CoreDockSend.self)
    }()

    public func showDockView(_ view: DockView) -> Bool {
        guard let send = Self.coreDockSend else { return false }
        send(view.rawValue as CFString, nil)
        return true
    }

    public func openApp(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return await withCheckedContinuation { c in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in c.resume(returning: error == nil) }
        }
    }

    public func open(url: URL) -> Bool { NSWorkspace.shared.open(url) }
    public func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    public var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }

    public func run(executable: String, arguments: [String], timeout: TimeInterval) async -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        return await withCheckedContinuation { c in
            let once = ResumeOnce()
            // Read while it runs: a tool that prints more than the pipe holds (64 KB) would
            // otherwise block on its write until the timeout.
            let drain = PipeDrain()
            p.terminationHandler = { proc in
                let out = String(data: drain.wait(), encoding: .utf8) ?? ""
                if once.claim() { c.resume(returning: (proc.terminationStatus == 0, out)) }
            }
            do {
                try p.run()
                drain.start(pipe.fileHandleForReading)
            } catch {
                if once.claim() { c.resume(returning: (false, error.localizedDescription)) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
                if once.claim() { c.resume(returning: (false, "Timed out")) }
            }
        }
    }

    public func start(executable: String, arguments: [String]) -> DeckProcess? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        // An open pipe as input: `screencapture -v` records until it reads a character, and a
        // menu bar app's own input is empty, which would end the recording at once.
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        return LiveDeckProcess(p, input: input)
    }

    public func press(_ keystroke: Keystroke) { keys.press(keystroke) }
    public func type(_ text: String) { keys.type(text) }

    public func runMacro(_ id: UUID) async -> (ok: Bool, message: String?) {
        guard let macroRunner else { return (false, "Macros are not ready") }
        return await macroRunner(id)
    }

    public func media(_ command: MediaCommand) { mediaMode?.send(command) }

    public var outputVolume: Double? { AudioOutput.volume().map(Double.init) }
    public func setOutputVolume(_ value: Double) { AudioOutput.setVolume(Float(value)) }

    public func toggleOutputMute() -> Bool {
        guard let muted = AudioOutput.isMuted() else { return false }
        AudioOutput.setMuted(!muted)
        return true
    }

    public var inputMuted: Bool? { AudioInput.isMuted() }

    public func setInputMuted(_ muted: Bool) -> Bool {
        if AudioInput.setMuted(muted) { return true }
        // No mute switch on this microphone: use its input volume, and put it back after.
        if muted {
            savedInputVolume = AudioInput.volume()
            return AudioInput.setVolume(0)
        }
        return AudioInput.setVolume(savedInputVolume ?? 0.75)
    }

    public var brightness: Double? { Brightness.buttonDisplay().flatMap { Brightness.get(display: $0) }.map(Double.init) }
    public func setBrightness(_ value: Double) {
        guard let display = Brightness.buttonDisplay() else { return }
        Brightness.set(Float(value), display: display)
    }

    public func audioOutputs() -> [String] { AudioDevices.outputs().map(\.name) }

    public func setAudioOutput(name: String) -> Bool {
        guard let device = AudioDevices.outputs().first(where: { $0.name == name }) else { return false }
        return AudioDevices.setDefaultOutput(device.id)
    }

    /// FileManager's unmount answers in a callback, so a disk that is slow to let go never holds
    /// the main thread (NSWorkspace's eject waits for it there).
    public func ejectAll() async -> (ejected: Int, failed: Int) {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var ok = 0, failed = 0
        for v in volumes {
            guard let r = try? v.resourceValues(forKeys: Set(keys)),
                  r.volumeIsEjectable == true || (r.volumeIsRemovable == true && r.volumeIsInternal != true) else { continue }
            let ejected = await withCheckedContinuation { c in
                FileManager.default.unmountVolume(at: v, options: [.allPartitionsAndEjectDisk, .withoutUI]) { error in
                    c.resume(returning: error == nil)
                }
            }
            if ejected { ok += 1 } else { failed += 1 }
        }
        return (ok, failed)
    }

    public func screenshotFolder() -> URL {
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
        if let s = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String {
            let path = (s as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Desktop")
    }

    public func frontWindowID() -> UInt32? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // Front to back; the first normal-layer window of the front app.
        let window = list.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        return (window?[kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }

    public func now() -> Date { Date() }

    /// PNG as captured when it is small enough for one message, else a high quality JPEG,
    /// scaled down only if it is still very large.
    public func phoneImageData(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.count <= 6_000_000 { return data }
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]), jpeg.count <= 9_000_000 {
            return jpeg
        }
        let scale = 0.6
        let w = Int(Double(rep.pixelsWide) * scale), h = Int(Double(rep.pixelsHigh) * scale)
        guard let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return small.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    public func copyImageToClipboard(_ url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }

    public var outputMuted: Bool? { AudioOutput.isMuted() }
    public var displayCount: Int { max(1, NSScreen.screens.count) }

    public func lockScreen() -> Bool { MacSystem.lockScreen() }
    public func toggleDarkMode() -> Bool? { MacSystem.toggleDarkMode() }
    public func toggleDoNotDisturb() async -> DeckSwitchResult { await ControlCenterFocus.toggleDoNotDisturb() }
    public func toggleNightShift() -> DeckSwitchResult { NightShift.toggle() }
    public func toggleKeepAwake() -> DeckSwitchResult { KeepAwake.shared.toggle() }
    public func openNotificationCenter() -> Bool { ControlCenterFocus.openNotificationCenter() }

    public func placeFrontWindow(_ placement: WindowPlacement) -> String? {
        if case .failure(let f) = WindowMover.place(placement) { return f.message }
        return nil
    }

    public func splitFrontWindows() -> String? {
        if case .failure(let f) = WindowMover.split() { return f.message }
        return nil
    }

    public func returnFrontWindowToPreviousSize() -> String? {
        if case .failure(let f) = WindowMover.returnToPreviousSize() { return f.message }
        return nil
    }

    public func moveFrontWindowToNextDisplay() -> String? {
        if case .failure(let f) = WindowMover.toNextScreen() { return f.message }
        return nil
    }

    public func shortcutNames() async -> [String] {
        let r = await run(executable: "/usr/bin/shortcuts", arguments: ["list"], timeout: 10)
        guard r.ok else { return [] }
        return r.output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Reads a pipe to its end on a background thread.
private final class PipeDrain: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()
    func start(_ handle: FileHandle) {
        DispatchQueue.global().async {
            self.data = handle.readDataToEndOfFile()
            self.done.signal()
        }
    }
    func wait() -> Data {
        done.wait()
        return data
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.withLock { defer { used = true }; return !used } }
}

@MainActor
private final class LiveDeckProcess: DeckProcess {
    private let process: Process
    private let input: Pipe
    init(_ p: Process, input: Pipe) {
        process = p
        self.input = input
    }
    var isRunning: Bool { process.isRunning }

    /// "Type any character to stop": a newline finishes and saves the recording. ctrl+C (SIGINT)
    /// does the same, and follows if it is still running a moment later.
    func interrupt() {
        try? input.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if p.isRunning { p.interrupt() }
        }
    }
}

/// Default input device mute and volume (CoreAudio, public).
enum AudioInput {
    static func defaultDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    static func isMuted() -> Bool? {
        guard let dev = defaultDevice() else { return nil }
        var addr = address(kAudioDevicePropertyMute)
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { return v != 0 }
        return volume().map { $0 < 0.001 }
    }

    static func setMuted(_ muted: Bool) -> Bool {
        guard let dev = defaultDevice() else { return false }
        var addr = address(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    static func volume() -> Float32? {
        guard let dev = defaultDevice() else { return nil }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func setVolume(_ value: Float32) -> Bool {
        guard let dev = defaultDevice() else { return false }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var v = value
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }
}

/// Output devices by name, and switching the default output (CoreAudio, public).
enum AudioDevices {
    struct Device { let id: AudioObjectID; let name: String }

    static func outputs() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), canBeDefault(id), let name = name(id) else { return nil }
            return Device(id: id, name: name)
        }
    }

    /// Leaves out hidden helper devices (aggregate and capture devices apps create) that the
    /// Sound menu does not offer either.
    private static func canBeDefault(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var v = UInt32(1)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr else { return true }
        return v != 0
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func name(_ id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let n = name else { return nil }
        return n.takeRetainedValue() as String
    }

    static func setDefaultOutput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }
}
