import Foundation

/// Lists and runs the user's Apple Shortcuts with `/usr/bin/shortcuts`.
public struct ShortcutsCLI: ShortcutsRunning {
    public static let executable = "/usr/bin/shortcuts"
    let runner: any ProcessRunning
    /// Generous: shortcuts may show dialogs or wait on the network.
    let runTimeoutMs: Int

    public init(runner: any ProcessRunning = SystemProcessRunner(), runTimeoutMs: Int = 300_000) {
        self.runner = runner
        self.runTimeoutMs = runTimeoutMs
    }

    /// One line of `shortcuts list --show-identifiers`: `Name (UUID)`.
    /// Names may themselves contain parentheses, so only a trailing UUID in
    /// parentheses counts as the identifier.
    public static func parseLine(_ line: Substring) -> (name: String, identifier: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix(")"), let open = trimmed.range(of: " (", options: .backwards) {
            let candidate = String(trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)])
            if UUID(uuidString: candidate) != nil {
                return (String(trimmed[..<open.lowerBound]), candidate)
            }
        }
        return (trimmed, nil)
    }

    public static func parseList(_ output: String, folder: String?) -> [ShortcutInfo] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            parseLine(line).map { ShortcutInfo(name: $0.name, identifier: $0.identifier, folder: folder) }
        }
    }

    private func call(_ args: [String], timeoutMs: Int = 30_000) async throws -> String {
        let r = try await runner.run(Self.executable, args, timeoutMs: timeoutMs)
        guard r.status == 0, !r.timedOut else {
            let msg = r.timedOut ? "timed out" : r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MacroError.shortcutFailed(name: args.dropFirst().first ?? args.first ?? "", message: msg)
        }
        return r.stdout
    }

    /// Every shortcut with its folder. Folders are listed first, then each
    /// folder's contents, then the shortcuts in no folder.
    public func list() async throws -> [ShortcutInfo] {
        let folders = Self.parseList(try await call(["list", "--folders", "--show-identifiers"]), folder: nil)
        var result: [ShortcutInfo] = []
        for folder in folders {
            let selector = folder.identifier ?? folder.name
            result += Self.parseList(try await call(["list", "--folder-name", selector, "--show-identifiers"]),
                                     folder: folder.name)
        }
        result += Self.parseList(try await call(["list", "--folder-name", "none", "--show-identifiers"]), folder: nil)
        return result
    }

    /// Runs a shortcut. Text input is passed through a temporary file (the
    /// CLI only takes input as paths); output is requested as plain text.
    public func run(_ nameOrID: String, input: String?) async throws -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glasspad-shortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let outURL = dir.appendingPathComponent("output.txt")
        var args = ["run", nameOrID, "--output-path", outURL.path, "--output-type", "public.plain-text"]
        if let input {
            let inURL = dir.appendingPathComponent("input.txt")
            try Data(input.utf8).write(to: inURL)
            args += ["--input-path", inURL.path]
        }
        let r = try await runner.run(Self.executable, args, timeoutMs: runTimeoutMs)
        guard r.status == 0, !r.timedOut else {
            throw MacroError.shortcutFailed(
                name: nameOrID,
                message: r.timedOut ? "timed out" : r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let data = try? Data(contentsOf: outURL), !data.isEmpty {
            return String(decoding: data, as: UTF8.self)
        }
        let stdout = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? nil : stdout
    }
}
