import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(status: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Runs a command-line tool. Injected so the Shortcuts parser and shell step
/// can be tested without launching anything.
public protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeoutMs: Int) async throws -> ProcessResult
}

/// Runs processes with `Foundation.Process`. Output is drained on background
/// threads so a chatty command can never fill the pipe and hang. Cancelling
/// the calling task terminates the process.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    /// GUI apps start with a bare PATH; add the usual tool locations so
    /// commands like `brew` or `node` work the same as in Terminal.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let current = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        env["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        return env
    }

    public func run(_ executable: String, _ arguments: [String], timeoutMs: Int) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = Self.environment()
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outData = LockedBox(Data()), errData = LockedBox(Data())
        let group = DispatchGroup()
        for (pipe, box) in [(outPipe, outData), (errPipe, errData)] {
            group.enter()
            DispatchQueue.global().async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }

        let timedOut = LockedBox(false)
        let exited = LockedBox(false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
                process.terminationHandler = { p in
                    exited.set(true)
                    group.notify(queue: .global()) {
                        cont.resume(returning: ProcessResult(
                            status: p.terminationStatus,
                            stdout: String(decoding: outData.get(), as: UTF8.self),
                            stderr: String(decoding: errData.get(), as: UTF8.self),
                            timedOut: timedOut.get()))
                    }
                }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                    guard !exited.get(), process.isRunning else { return }
                    timedOut.set(true)
                    Self.stop(process)
                }
            }
        } onCancel: {
            Self.stop(process)
        }
    }

    /// SIGTERM, then SIGKILL if the process ignores it.
    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
