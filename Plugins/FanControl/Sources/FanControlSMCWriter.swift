import Foundation

// MARK: - FanControlSMCWriter

/// Writes SMC fan control values via the `smc-helper` CLI tool (requires root).
/// The tool is expected at `/usr/local/bin/smc-helper` (installed by user from the
/// solofan project: https://github.com/yourusername/solofan).
///
/// Write flow:
///   1. Try `sudo -n smc-helper …` (succeeds if the user configured password-less
///      sudo for this binary, or is already authenticated).
///   2. Fall back to an AppleScript `do shell script … with administrator privileges`
///      prompt so the user can authenticate interactively.
@MainActor
final class FanControlSMCWriter: FanControlSMCWriting {
    /// Possible paths for the smc-helper binary.
    private static let candidatePaths = [
        "/usr/local/bin/smc-helper",
        "/opt/homebrew/bin/smc-helper",
    ]

    /// Cached resolved path (nil = not found).
    private var resolvedHelperPath: String?

    // MARK: - Public API

    typealias WriteError = FanWriteError

    var isHelperAvailable: Bool {
        helperPath != nil
    }

    /// Apply `strategy` to all fans described by `snapshot`.
    /// - Returns: `nil` on success, or an error description on failure.
    @discardableResult
    func apply(strategy: FanControlStrategy, snapshot: FanSnapshot) -> FanWriteError? {
        guard let path = helperPath else {
            FanControlLog.writer.error("smc-helper not found")
            return .helperNotFound
        }

        let fanCount = max(1, snapshot.fanCount)

        switch strategy {
        case .auto:
            var allOK = true
            for i in 0..<fanCount {
                if !runHelper(path: path, args: ["auto", "\(i)"]) { allOK = false }
            }
            if !allOK {
                return .writeFailed("部分风扇恢复自动控制失败")
            }

        case .fullSpeed:
            var allOK = true
            for i in 0..<fanCount {
                let maxRPM = i < snapshot.fanMaxSpeeds.count
                    ? snapshot.fanMaxSpeeds[i]
                    : FanRPMLimits.fallbackMax
                let safe = max(FanRPMLimits.absoluteMin, min(FanRPMLimits.absoluteMax, maxRPM))
                if !runHelper(path: path, args: ["set", "\(i)", "\(safe)"]) { allOK = false }
            }
            if !allOK {
                return .writeFailed("部分风扇设置全速失败")
            }

        case .fixed(let rpm):
            let safe = max(FanRPMLimits.absoluteMin, min(FanRPMLimits.absoluteMax, rpm))
            var allOK = true
            for i in 0..<fanCount {
                let perFanMax = i < snapshot.fanMaxSpeeds.count
                    ? snapshot.fanMaxSpeeds[i]
                    : FanRPMLimits.fallbackMax
                let perFanMin = i < snapshot.fanMinSpeeds.count
                    ? snapshot.fanMinSpeeds[i]
                    : FanRPMLimits.fallbackMin
                let clamped = max(perFanMin, min(perFanMax, safe))
                if !runHelper(path: path, args: ["set", "\(i)", "\(clamped)"]) { allOK = false }
            }
            if !allOK {
                return .writeFailed("部分风扇设置目标转速失败")
            }
        }

        return nil
    }

    // MARK: - Private

    private var helperPath: String? {
        if let cached = resolvedHelperPath { return cached }
        for path in Self.candidatePaths where FileManager.default.fileExists(atPath: path) {
            resolvedHelperPath = path
            return path
        }
        return nil
    }

    /// Run smc-helper with `sudo -n` first; fall back to AppleScript if that fails.
    @discardableResult
    private func runHelper(path: String, args: [String]) -> Bool {
        // Attempt 1: sudo -n (no-password, already-authenticated)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", path] + args
        task.environment = ["LANG": "C"]
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { return true }
        } catch {
            FanControlLog.writer.error("sudo -n failed: \(error.localizedDescription, privacy: .public)")
        }

        // Attempt 2: AppleScript with administrator privileges
        FanControlLog.writer.info("Falling back to AppleScript for smc-helper")
        // Shell-escape the path (handle spaces)
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let argString = args
            .map { $0.replacingOccurrences(of: "'", with: "'\\''") }
            .map { "'\($0)'" }
            .joined(separator: " ")
        let command = "'\(escapedPath)' \(argString)"
        let script = "do shell script \"\(command)\" with administrator privileges"
        var appleScriptError: NSDictionary?
        if let scriptObj = NSAppleScript(source: script) {
            _ = scriptObj.executeAndReturnError(&appleScriptError)
            if appleScriptError == nil { return true }
            let msg = appleScriptError?["NSAppleScriptErrorMessage"] as? String ?? "unknown"
            FanControlLog.writer.error("AppleScript failed: \(msg, privacy: .public)")
        }
        return false
    }
}
