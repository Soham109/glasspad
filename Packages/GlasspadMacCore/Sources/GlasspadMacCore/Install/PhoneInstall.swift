import Foundation

/// The iPhone install as the renewal scripts left it, for Settings > iPhone.
///
/// scripts/install-phone.sh records the install in `phone-install.env`, scripts/setup-autorefresh.sh
/// adds the hourly LaunchAgent, and every run of scripts/refresh-phone.sh writes its outcome to
/// `refresh-status.json`. All three live outside the app, so this only reads them, and never
/// runs the env file: it is shell, and only its install time is needed.
public struct PhoneInstallStatus: Equatable, Sendable {
    public var installedAt: Date
    /// The hourly renewal job is set up.
    public var renewsByItself: Bool
    /// The renewal job's last run since this install, if any.
    public var lastCheck: Check?

    public init(installedAt: Date, renewsByItself: Bool, lastCheck: Check? = nil) {
        self.installedAt = installedAt
        self.renewsByItself = renewsByItself
        self.lastCheck = lastCheck
    }

    public struct Check: Equatable, Sendable {
        public var checkedAt: Date
        public var result: Result

        public init(checkedAt: Date, result: Result) {
            self.checkedAt = checkedAt
            self.result = result
        }
    }

    /// What one run of refresh-phone.sh did. The raw values are the script's words.
    public enum Result: String, Sendable {
        case renewed, waitingInUse, notReachable, failed, tooEarly

        /// The run wanted to renew and could not.
        public var isProblem: Bool { self == .notReachable || self == .failed }
    }

    // MARK: Where

    public struct Paths: Sendable {
        public var installFile: URL
        public var statusFile: URL
        public var launchAgent: URL
        public var log: URL

        public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
            let support = home.appendingPathComponent("Library/Application Support/Glasspad", isDirectory: true)
            installFile = support.appendingPathComponent("phone-install.env")
            statusFile = support.appendingPathComponent("refresh-status.json")
            launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.soham109.glasspad.refresh.plist")
            log = home.appendingPathComponent("Library/Logs/Glasspad/refresh.log")
        }
    }

    // MARK: Reading

    /// Nil when no install was recorded. Reads files, so call it off the main thread.
    public static func load(_ paths: Paths = Paths()) -> PhoneInstallStatus? {
        guard let env = try? String(contentsOf: paths.installFile, encoding: .utf8),
              let installed = installedAt(env: env) else { return nil }
        let status = (try? Data(contentsOf: paths.statusFile)).flatMap(check(json:))
        return PhoneInstallStatus(
            installedAt: installed,
            renewsByItself: FileManager.default.fileExists(atPath: paths.launchAgent.path),
            // A run from before the latest install says nothing about this one (an install by
            // hand after a failed renewal, say).
            lastCheck: status.flatMap { $0.checkedAt >= installed ? $0 : nil })
    }

    /// `GLASSPAD_INSTALLED_AT=<seconds since 1970>` from the env file, as text.
    public static func installedAt(env: String) -> Date? {
        for line in env.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "GLASSPAD_INSTALLED_AT" else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "'" || q == "\"", value.last == q {
                value = String(value.dropFirst().dropLast())
            }
            guard let seconds = Int(value), seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }

    /// refresh-status.json: `{"checkedAt": <seconds>, "result": "<word>", "installedAt": <seconds>}`
    /// (the install time there is for people reading the file; the env file's is the one used).
    /// Nil when the check time or the result is missing or not understood.
    public static func check(json: Data) -> Check? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let checked = (object["checkedAt"] as? NSNumber)?.doubleValue, checked > 0,
              let word = object["result"] as? String, let result = Result(rawValue: word) else { return nil }
        return Check(checkedAt: Date(timeIntervalSince1970: checked), result: result)
    }
}

/// Whether a phone is connected now, and when the last one left, for scripts/refresh-phone.sh:
/// it renews an app that is open on the iPhone only once no phone has used this Mac for 30
/// minutes (a suspended app is still a running process, so "open" alone says little).
///
/// `{"active": true}` while connected; `{"active": false, "endedAt": <whole seconds>}` after.
public struct PhoneSessionFile: Sendable {
    public let url: URL

    public init(url: URL = PhoneSessionFile.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Glasspad/phone-session.json")
    }

    /// Records a change. A disconnected state that the file already says keeps its end time, so
    /// starting the app with no phone does not make an old session look recent. Does file work,
    /// so call it off the main thread.
    public func record(active: Bool, now: Date = Date()) {
        if !active, let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["active"] as? Bool == false, object["endedAt"] is NSNumber {
            return
        }
        let text = active ? "{\"active\":true}\n"
            : "{\"active\":false,\"endedAt\":\(Int(now.timeIntervalSince1970))}\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
}
