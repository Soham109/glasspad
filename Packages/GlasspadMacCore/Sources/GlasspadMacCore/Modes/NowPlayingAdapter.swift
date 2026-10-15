import Foundation
import GlasspadKit

/// Reads the now-playing helper's output: one JSON object per line, in mediaremote-adapter's
/// stream format (https://github.com/ungive/mediaremote-adapter, BSD 3-Clause):
/// `{"type":"data","diff":false,"payload":{...}}`. Full payloads replace the state; diff
/// payloads update it, and a key set to null is removed. Times may be seconds (`duration`,
/// `elapsedTime`, ISO `timestamp`) or microseconds (`durationMicros`, `elapsedTimeMicros`,
/// `timestampEpochMicros`).
struct AdapterStreamParser {
    enum Event: Equatable {
        /// Nothing is playing.
        case nothing
        case snapshot(NowPlayingSnapshot)
        /// The helper cannot use MediaRemote.
        case failed(String)
    }

    private var payload: [String: Any]?

    /// nil for lines that change nothing (blank, unknown type, malformed).
    mutating func consume(_ line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]
        else { return nil }
        switch object["type"] as? String {
        case "error":
            return .failed(object["message"] as? String ?? "The now-playing helper failed")
        case "data":
            break
        default:
            return nil
        }
        let diff = object["diff"] as? Bool ?? false
        guard let incoming = object["payload"] as? [String: Any] else {
            payload = nil
            return .nothing
        }
        if diff, var merged = payload {
            for (key, value) in incoming {
                if value is NSNull { merged[key] = nil } else { merged[key] = value }
            }
            payload = merged
        } else {
            payload = incoming
        }
        guard let payload, let snapshot = Self.snapshot(from: payload) else { return .nothing }
        return .snapshot(snapshot)
    }

    static func snapshot(from p: [String: Any]) -> NowPlayingSnapshot? {
        guard let title = string(p["title"]), !title.isEmpty else { return nil }
        let rate = number(p["playbackRate"])
        let playing = (p["playing"] as? Bool) ?? rate.map { $0 > 0 } ?? false
        var at: Date?
        if let micros = number(p["timestampEpochMicros"]) {
            at = Date(timeIntervalSince1970: micros / 1_000_000)
        } else if let iso = string(p["timestamp"]) {
            at = ISO8601DateFormatter().date(from: iso)
        }
        let artwork = string(p["artworkData"]).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        return NowPlayingSnapshot(
            provider: .mediaRemote, title: title, artist: string(p["artist"]), album: string(p["album"]),
            duration: seconds(p, "duration"), elapsed: seconds(p, "elapsedTime"), elapsedAt: at,
            playbackRate: rate, isPlaying: playing, bundleID: string(p["bundleIdentifier"]),
            parentBundleID: string(p["parentApplicationBundleIdentifier"]), appName: string(p["applicationName"]),
            artworkData: artwork.flatMap { $0.isEmpty ? nil : $0 },
            shuffle: number(p["shuffleMode"]).flatMap(shuffle), repeatMode: number(p["repeatMode"]).flatMap(repeatMode),
            trackID: string(p["uniqueIdentifier"]) ?? number(p["uniqueIdentifier"]).map { String(Int64($0)) })
    }

    /// MRMediaRemote shuffle modes: 1 off, 2 albums, 3 tracks (0 unknown).
    static func shuffle(_ mode: Double) -> Bool? { mode >= 1 ? mode > 1 : nil }

    /// MRMediaRemote repeat modes: 1 off, 2 one (track), 3 all (0 unknown).
    static func repeatMode(_ mode: Double) -> MediaRepeatMode? {
        switch Int(mode) {
        case 1: .off
        case 2: .one
        case 3: .all
        default: nil
        }
    }

    private static func seconds(_ p: [String: Any], _ key: String) -> TimeInterval? {
        if let micros = number(p[key + "Micros"]) { return micros / 1_000_000 }
        return number(p[key])
    }

    private static func string(_ v: Any?) -> String? { v as? String }

    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
}

/// Command lines the helper reads on stdin.
enum AdapterCommand: Equatable {
    case send(Int32)
    case seek(TimeInterval)
    case shuffle(Bool)
    case setRepeat(MediaRepeatMode)
    case refresh

    var line: String {
        switch self {
        case .send(let c): "send \(c)"
        case .seek(let t): String(format: "seek %.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, t))
        case .shuffle(let on): "shuffle \(on ? 3 : 1)"
        case .setRepeat(let mode): "repeat \(mode == .off ? 1 : mode == .one ? 2 : 3)"
        case .refresh: "refresh"
        }
    }

    /// MRMediaRemoteCommand values: play 0, pause 1, togglePlayPause 2, nextTrack 4, previousTrack 5.
    static func code(for command: MediaCommand) -> Int32? {
        switch command {
        case .play: 0
        case .pause: 1
        case .playPause: 2
        case .nextTrack: 4
        case .previousTrack: 5
        case .mute: nil
        }
    }
}

/// Runs the helper under /usr/bin/perl and streams its events. Restarts it when it exits, with a
/// growing pause; gives up when it reports that MediaRemote is unusable.
@MainActor
final class NowPlayingAdapter {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        /// No helper library in the app, perl missing, or MediaRemote refused.
        case unavailable(String)
    }

    /// The perl side: load the library with DynaLoader and call its entry point as an XSUB.
    nonisolated static let loader = """
    use strict; use DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die "load failed: " . DynaLoader::dl_error() . "\\n";
    my $s = DynaLoader::dl_find_symbol($h, "glasspad_nowplaying_run") or die "entry point missing\\n";
    DynaLoader::dl_install_xsub("main::run", $s);
    run();
    """

    nonisolated static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    /// The helper library inside Glasspad.app (Contents/Frameworks), nil when not bundled (for
    /// example a plain `swift build`).
    static func bundledLibrary(in bundle: Bundle = .main) -> URL? {
        let candidates = [bundle.privateFrameworksURL, bundle.resourceURL].compactMap {
            $0?.appendingPathComponent("GlasspadNowPlaying.dylib")
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private(set) var status: Status = .stopped
    var onEvent: (AdapterStreamParser.Event) -> Void = { _ in }
    var onStatus: (Status) -> Void = { _ in }

    private let library: URL?
    private var process: Process?
    private var stdin: FileHandle?
    private var parser = AdapterStreamParser()
    private var buffer = Data()
    private var restarts = 0
    private var launchedAt: TimeInterval = 0
    /// Restarts in a row (each after a short run) before giving up.
    nonisolated static let maxQuickRestarts = 5
    /// Pause before each restart in a row; the last one repeats. Internal for tests.
    var restartDelays: [TimeInterval] = [1, 2, 4, 8, 16]
    /// A run at least this long counts as healthy and resets the restart count.
    var stableRun: TimeInterval = 30
    private var wanted = false
    private var restartTask: Task<Void, Never>?

    /// The program to run for a library: perl and the loader. Tests swap in a fake helper.
    typealias Launcher = (URL) -> (executable: URL, arguments: [String])
    private let launcher: Launcher
    /// How many times the helper was started (tests).
    private(set) var launches = 0

    init(library: URL? = NowPlayingAdapter.bundledLibrary(),
         launcher: @escaping Launcher = { (NowPlayingAdapter.perl, ["-e", NowPlayingAdapter.loader, $0.path]) }) {
        self.library = library
        self.launcher = launcher
    }

    var isRunning: Bool { status == .running }

    func start() {
        wanted = true
        guard process == nil, restartTask == nil else { return }
        if case .unavailable = status { return }
        guard let library else {
            setStatus(.unavailable("The now-playing helper is not in this build of Glasspad"))
            return
        }
        guard FileManager.default.isExecutableFile(atPath: launcher(library).executable.path) else {
            setStatus(.unavailable("/usr/bin/perl is missing on this Mac"))
            return
        }
        launch(library)
    }

    func stop() {
        wanted = false
        restartTask?.cancel()
        restartTask = nil
        try? stdin?.close()
        process?.terminate()
        process = nil
        stdin = nil
        parser = AdapterStreamParser()
        buffer = Data()
        if case .unavailable = status { return }
        setStatus(.stopped)
    }

    /// Sends a command; false when the helper is not running.
    @discardableResult
    func send(_ command: AdapterCommand) -> Bool {
        guard status == .running, let stdin else { return false }
        do {
            try stdin.write(contentsOf: Data((command.line + "\n").utf8))
            return true
        } catch {
            return false
        }
    }

    private func launch(_ library: URL) {
        setStatus(.starting)
        let p = Process()
        let command = launcher(library)
        p.executableURL = command.executable
        p.arguments = command.arguments
        // A clean environment: no PERL5LIB or similar from the user's shell.
        p.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let out = Pipe(), input = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardInput = input
        p.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            // The main queue keeps chunks in order (separate Tasks might not).
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(chunk) } }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) {
                GPLog.log("now-playing helper: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.exited(proc, code: code) } }
        }
        // A write after the helper died must fail, not kill Glasspad with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try p.run()
            launches += 1
            launchedAt = ProcessInfo.processInfo.systemUptime
            process = p
            stdin = input.fileHandleForWriting
            setStatus(.running)
        } catch {
            setStatus(.unavailable("Could not start /usr/bin/perl: \(error.localizedDescription)"))
        }
    }

    private func received(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8), let event = parser.consume(line) else { continue }
            onEvent(event)
            if case .failed(let message) = event {
                stop()
                setStatus(.unavailable(message))
                return
            }
        }
    }

    private func exited(_ proc: Process, code: Int32) {
        guard proc === process else { return }
        process = nil
        stdin = nil
        buffer = Data()
        parser = AdapterStreamParser()
        if case .unavailable = status { return }
        guard wanted else {
            setStatus(.stopped)
            return
        }
        // Output does not prove health (a helper can print "nothing" and then crash); only a
        // run that stayed up for a while resets the count.
        if ProcessInfo.processInfo.systemUptime - launchedAt >= stableRun { restarts = 0 }
        restarts += 1
        if restarts > Self.maxQuickRestarts {
            setStatus(.unavailable("The now-playing helper keeps stopping (exit \(code))"))
            return
        }
        setStatus(.starting)
        let delay = restartDelays[min(restarts - 1, restartDelays.count - 1)]
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.restartTask = nil
            if self.wanted, let library = self.library { self.launch(library) }
        }
    }

    private func setStatus(_ new: Status) {
        guard new != status else { return }
        status = new
        onStatus(new)
    }
}
