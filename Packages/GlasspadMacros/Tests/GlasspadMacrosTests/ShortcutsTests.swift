import Foundation
import Testing
@testable import GlasspadMacros

@Suite("Apple Shortcuts")
struct ShortcutsTests {
    // Captured from `shortcuts list --show-identifiers` on macOS 26.
    static let sampleAll = """
    Guitar Notes (3CDA4650-DD0E-4204-8911-E0A1A20F397F)
    Show Screenshots (D9466A41-3CE7-42EB-B4D8-619A23B626E2)
    Make GIF (8CDF5F7A-6BA1-47E9-BA61-7DF47DE0B4F6)
    Resize (50%) for Web (11111111-2222-4333-8444-555555555555)
    Plain (not an id)

    """

    @Test func parsesNamesAndIdentifiersIncludingParenthesesInNames() {
        let list = ShortcutsCLI.parseList(Self.sampleAll, folder: "Starter Shortcuts")
        #expect(list.count == 5)
        #expect(list[0] == ShortcutInfo(name: "Guitar Notes", identifier: "3CDA4650-DD0E-4204-8911-E0A1A20F397F",
                                        folder: "Starter Shortcuts"))
        #expect(list[3].name == "Resize (50%) for Web")
        #expect(list[3].identifier == "11111111-2222-4333-8444-555555555555")
        #expect(list[4] == ShortcutInfo(name: "Plain (not an id)", identifier: nil, folder: "Starter Shortcuts"))
    }

    @Test func listsEveryFolderThenTheUnfiledShortcuts() async throws {
        let runner = FakeProcessRunner { args in
            switch args {
            case ["list", "--folders", "--show-identifiers"]:
                return ProcessResult(status: 0, stdout: "Starter Shortcuts (B574BB56-EADC-4666-AB0B-B511D68FD4C8)\nWork (C574BB56-EADC-4666-AB0B-B511D68FD4C8)\n", stderr: "")
            case ["list", "--folder-name", "B574BB56-EADC-4666-AB0B-B511D68FD4C8", "--show-identifiers"]:
                return ProcessResult(status: 0, stdout: "Make GIF (8CDF5F7A-6BA1-47E9-BA61-7DF47DE0B4F6)\n", stderr: "")
            case ["list", "--folder-name", "C574BB56-EADC-4666-AB0B-B511D68FD4C8", "--show-identifiers"]:
                return ProcessResult(status: 0, stdout: "", stderr: "")
            case ["list", "--folder-name", "none", "--show-identifiers"]:
                return ProcessResult(status: 0, stdout: "Loose (9CDF5F7A-6BA1-47E9-BA61-7DF47DE0B4F6)\n", stderr: "")
            default:
                return ProcessResult(status: 1, stdout: "", stderr: "unexpected \(args)")
            }
        }
        let list = try await ShortcutsCLI(runner: runner).list()
        #expect(list == [
            ShortcutInfo(name: "Make GIF", identifier: "8CDF5F7A-6BA1-47E9-BA61-7DF47DE0B4F6", folder: "Starter Shortcuts"),
            ShortcutInfo(name: "Loose", identifier: "9CDF5F7A-6BA1-47E9-BA61-7DF47DE0B4F6", folder: nil),
        ])
        #expect(runner.allCalls.count == 4)
    }

    @Test func runPassesInputThroughAFileAndReadsOutput() async throws {
        let seenInput = LockedBox<String?>(nil)
        let runner = FakeProcessRunner { args in
            // Behave like the real CLI: read the input file, write the output file.
            if let i = args.firstIndex(of: "--input-path") {
                seenInput.set(try? String(contentsOfFile: args[i + 1], encoding: .utf8))
            }
            if let o = args.firstIndex(of: "--output-path") {
                try? Data("RESULT".utf8).write(to: URL(fileURLWithPath: args[o + 1]))
            }
            return ProcessResult(status: 0, stdout: "", stderr: "")
        }
        let out = try await ShortcutsCLI(runner: runner).run("Make GIF", input: "héllo")
        #expect(out == "RESULT")
        #expect(seenInput.get() == "héllo")
        let args = try #require(runner.allCalls.first)
        #expect(Array(args.prefix(2)) == ["run", "Make GIF"])
        #expect(args.contains("public.plain-text"))
        // Temporary files are cleaned up.
        let outPath = args[args.firstIndex(of: "--output-path")! + 1]
        #expect(!FileManager.default.fileExists(atPath: outPath))
    }

    @Test func runWithoutInputOrOutputAndFailures() async throws {
        let ok = FakeProcessRunner { _ in ProcessResult(status: 0, stdout: "", stderr: "") }
        #expect(try await ShortcutsCLI(runner: ok).run("Silent", input: nil) == nil)
        #expect(!ok.allCalls[0].contains("--input-path"))

        let failing = FakeProcessRunner { _ in ProcessResult(status: 1, stdout: "", stderr: "Error: The operation couldn’t be completed.\n") }
        await #expect(throws: MacroError.shortcutFailed(name: "Nope", message: "Error: The operation couldn’t be completed.")) {
            try await ShortcutsCLI(runner: failing).run("Nope", input: nil)
        }
    }
}

@Suite("Script runner")
struct ScriptRunnerTests {
    @Test func shellReportsOutputFailureAndTimeout() async throws {
        let runner = FakeProcessRunner { args in
            switch args.last! {
            case "echo ok": return ProcessResult(status: 0, stdout: "ok\n", stderr: "")
            case "false": return ProcessResult(status: 1, stdout: "", stderr: "boom\n")
            default: return ProcessResult(status: 15, stdout: "", stderr: "", timedOut: true)
            }
        }
        let scripts = SystemScriptRunner(processRunner: runner)
        #expect(try await scripts.runShell("echo ok", timeoutMs: 100) == "ok")
        #expect(runner.allCalls[0] == ["-c", "echo ok"])
        await #expect(throws: MacroError.shellFailed(exitCode: 1, stderr: "boom")) {
            try await scripts.runShell("false", timeoutMs: 100)
        }
        await #expect(throws: MacroError.shellTimedOut) { try await scripts.runShell("sleep 99", timeoutMs: 100) }
    }

    @Test func realProcessRunnerCapturesOutputAndEnforcesTimeout() async throws {
        // Runs harmless local processes only; posts no events.
        let runner = SystemProcessRunner()
        let r = try await runner.run("/bin/echo", ["hello"], timeoutMs: 5000)
        #expect(r == ProcessResult(status: 0, stdout: "hello\n", stderr: ""))
        let started = ContinuousClock.now
        let slow = try await runner.run("/bin/sleep", ["10"], timeoutMs: 200)
        #expect(slow.timedOut)
        #expect(ContinuousClock.now - started < .seconds(5))
        // GUI apps get Homebrew on PATH.
        #expect(SystemProcessRunner.environment()["PATH"]!.contains("/opt/homebrew/bin"))
    }
}
