import XCTest
@testable import ActivityBarPlugin

final class ActivityBarHookInstallerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityBarHookInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testInstallWritesScriptsAndToolConfigurations() throws {
        let paths = ActivityBarHookInstallerPaths(
            homeDirectory: temporaryDirectory,
            hookScriptsDirectory: temporaryDirectory.appendingPathComponent("hooks")
        )
        let installer = ActivityBarHookInstaller(paths: paths, socketPath: "/tmp/mactools-test.sock")

        let summary = try installer.install()

        XCTAssertEqual(summary.installedTools, ["Claude Code", "Cursor", "Codex"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.hookScriptsDirectory.path))

        let claudeScript = paths.hookScriptsDirectory.appendingPathComponent("mactools-activity-claude-hook.sh")
        let scriptText = try String(contentsOf: claudeScript, encoding: .utf8)
        XCTAssertTrue(scriptText.contains("/tmp/mactools-test.sock"))

        let permissions = try FileManager.default.attributesOfItem(atPath: claudeScript.path)[.posixPermissions] as? Int
        XCTAssertEqual((permissions ?? 0) & 0o111, 0o111)

        let claudeSettings = try readJSONObject(paths.claudeSettingsPath)
        let claudeHooks = try XCTUnwrap(claudeSettings["hooks"] as? [String: Any])
        XCTAssertNotNil(claudeHooks["UserPromptSubmit"])

        let cursorSettings = try readJSONObject(paths.cursorHooksPath)
        let cursorHooks = try XCTUnwrap(cursorSettings["hooks"] as? [String: Any])
        XCTAssertNotNil(cursorHooks["beforeSubmitPrompt"])

        let codexConfig = try String(contentsOf: paths.codexConfigPath, encoding: .utf8)
        XCTAssertTrue(codexConfig.contains("codex_hooks = true"))

        let codexSettings = try readJSONObject(paths.codexHooksPath)
        let codexHooks = try XCTUnwrap(codexSettings["hooks"] as? [String: Any])
        XCTAssertNotNil(codexHooks["PreToolUse"])
    }

    func testInstallIsIdempotentForClaudeHooks() throws {
        let paths = ActivityBarHookInstallerPaths(
            homeDirectory: temporaryDirectory,
            hookScriptsDirectory: temporaryDirectory.appendingPathComponent("hooks")
        )
        let installer = ActivityBarHookInstaller(paths: paths, socketPath: "/tmp/mactools-test.sock")

        _ = try installer.install()
        let first = try Data(contentsOf: paths.claudeSettingsPath)
        _ = try installer.install()
        let second = try Data(contentsOf: paths.claudeSettingsPath)

        XCTAssertEqual(first, second)
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
