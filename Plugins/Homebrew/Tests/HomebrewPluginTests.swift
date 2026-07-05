import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import HomebrewPlugin

@MainActor
final class HomebrewPluginTests: XCTestCase {
    
    // Fake runner for testing
    @MainActor
    final class FakeHomebrewCommandRunner: HomebrewCommandRunning {
        var stubbedStatus: Int32 = 0
        var stubbedOutputs: [String: String] = [:]
        var runCalls: [[String]] = []
        var isCancelled = false
        
        func run(
            executable: String,
            arguments: [String],
            onOutput: @escaping @MainActor (String) -> Void,
            onError: @escaping @MainActor (String) -> Void
        ) async throws -> Int32 {
            runCalls.append(arguments)
            
            // Determine stubbed output based on arguments
            var matchKey = ""
            if arguments.contains("tap") {
                matchKey = "tap"
            } else if arguments.contains("list") && arguments.contains("--formula") {
                matchKey = "list-formula"
            } else if arguments.contains("list") && arguments.contains("--cask") {
                matchKey = "list-cask"
            } else if arguments.contains("outdated") {
                matchKey = "outdated"
            } else if arguments.contains("info") && arguments.contains("--installed") {
                matchKey = "info-installed"
            }
            
            if let output = stubbedOutputs[matchKey] {
                onOutput(output)
            }
            
            return stubbedStatus
        }
        
        func cancel() async {
            isCancelled = true
        }
    }
    
    func testMetadataIdentifiesHomebrewPlugin() {
        let runner = FakeHomebrewCommandRunner()
        let controller = HomebrewController(runner: runner)
        let localization = PluginLocalization(bundle: .main)
        let plugin = HomebrewPlugin(controller: controller, localization: localization)
        
        XCTAssertEqual(plugin.metadata.id, "homebrew")
        XCTAssertEqual(plugin.metadata.title, "Homebrew")
    }
    
    func testControlStyleIsDisclosure() {
        let runner = FakeHomebrewCommandRunner()
        let controller = HomebrewController(runner: runner)
        let localization = PluginLocalization(bundle: .main)
        let plugin = HomebrewPlugin(controller: controller, localization: localization)
        
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .disclosure)
    }
    
    func testScanPopulatesPackagesAndTaps() async throws {
        let runner = FakeHomebrewCommandRunner()
        runner.stubbedOutputs = [
            "tap": "homebrew/core\nhomebrew/cask\n",
            "list-formula": "git 2.51.0\nripgrep 15.1.0\n",
            "list-cask": "iterm2 3.5.0\n",
            "outdated": "{\"formulae\":[{\"name\":\"git\",\"installed_versions\":[\"2.51.0\"],\"current_version\":\"2.55.0\",\"pinned\":false}],\"casks\":[]}",
            "info-installed": "{\"formulae\":[{\"name\":\"git\",\"desc\":\"Distributed revision control system\",\"homepage\":\"https://git-scm.com/\",\"dependencies\":[\"pcre2\",\"openssl\"]}],\"casks\":[]}"
        ]
        
        let controller = HomebrewController(runner: runner)
        controller.isBrewAvailable = true // override for testing
        controller.brewPath = "/opt/homebrew/bin/brew"
        
        // Trigger scan
        controller.scanAll()
        
        // Wait for async operations to settle in controller (robust wait loop)
        let deadline = Date().addingTimeInterval(5.0)
        while controller.isBusy && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        
        XCTAssertEqual(controller.taps.count, 2)
        XCTAssertEqual(controller.taps.map(\.name), ["homebrew/core", "homebrew/cask"])
        
        XCTAssertEqual(controller.installedPackages.count, 3)
        let gitPkg = try XCTUnwrap(controller.installedPackages.first { $0.name == "git" })
        XCTAssertEqual(gitPkg.version, "2.51.0")
        XCTAssertEqual(gitPkg.latestVersion, "2.55.0")
        XCTAssertTrue(gitPkg.isOutdated)
        XCTAssertEqual(gitPkg.desc, "Distributed revision control system")
        XCTAssertEqual(gitPkg.homepage, "https://git-scm.com/")
        XCTAssertEqual(gitPkg.dependencies, ["pcre2", "openssl"])
        
        // Verify reverse dependency logic
        let ripPkg = try XCTUnwrap(controller.installedPackages.first { $0.name == "ripgrep" })
        XCTAssertFalse(ripPkg.isOutdated)
        XCTAssertEqual(ripPkg.requiredBy(in: controller.installedPackages), [])
    }
    
    func testCustomPathPersistence() {
        let runner = FakeHomebrewCommandRunner()
        let controller = HomebrewController(runner: runner)
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempBrewFile = tempDir.appendingPathComponent("brew")
        try? "test".write(to: tempBrewFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: tempBrewFile)
            UserDefaults.standard.removeObject(forKey: "mactools.homebrew.customPath")
        }
        
        // Test updating path
        controller.updateCustomPath(tempBrewFile.path)
        XCTAssertTrue(controller.isBrewAvailable)
        XCTAssertEqual(controller.brewPath, tempBrewFile.path)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mactools.homebrew.customPath"), tempBrewFile.path)
        
        // Test empty path resets standard path discovery
        controller.updateCustomPath("")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mactools.homebrew.customPath"), nil)
    }
}
