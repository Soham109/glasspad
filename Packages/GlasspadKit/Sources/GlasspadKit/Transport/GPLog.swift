import Foundation
import os

/// Diagnostic log for the connection path. Always goes to the unified log (subsystem
/// `com.soham109.glasspad`); also echoed to stderr when `GLASSPAD_LOG=1` is set, which is how
/// `xcrun devicectl device process launch --console` shows it from a real iPhone.
public enum GPLog {
    private static let logger = Logger(subsystem: "com.soham109.glasspad", category: "link")
    private static let echo = ProcessInfo.processInfo.environment["GLASSPAD_LOG"] == "1"

    public static func log(_ message: @autoclosure () -> String) {
        let m = message()
        logger.log("\(m, privacy: .public)")
        if echo { FileHandle.standardError.write(Data("[glasspad] \(m)\n".utf8)) }
    }
}
