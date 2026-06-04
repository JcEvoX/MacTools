import XCTest
@testable import MacTools

final class PluginPackageManifestTests: XCTestCase {
    func testManifestValidationAcceptsCurrentPackageFormat() throws {
        let manifest = PluginPackageManifest(
            id: "com.example.demo",
            displayName: "Demo",
            version: "1.0.0",
            minHostVersion: "0.15.0",
            bundleRelativePath: "Demo.bundle",
            capabilities: .init(primaryPanel: true)
        )

        XCTAssertNoThrow(try PluginPackageManifestLoader.validate(manifest, hostVersion: "0.16.0"))
    }

    func testManifestValidationRejectsPreviousPluginKitVersion() {
        let manifest = PluginPackageManifest(
            id: "com.example.demo",
            displayName: "Demo",
            version: "1.0.0",
            minHostVersion: "0.15.0",
            pluginKitVersion: 1,
            bundleRelativePath: "Demo.bundle"
        )

        XCTAssertThrowsError(try PluginPackageManifestLoader.validate(manifest, hostVersion: "0.16.0")) { error in
            XCTAssertEqual(error as? PluginPackageManifestError, .unsupportedPluginKitVersion(1))
        }
    }

    func testManifestValidationRejectsUnsafeBundlePath() {
        let manifest = PluginPackageManifest(
            id: "com.example.demo",
            displayName: "Demo",
            version: "1.0.0",
            minHostVersion: "0.15.0",
            bundleRelativePath: "../Demo.bundle"
        )

        XCTAssertThrowsError(try PluginPackageManifestLoader.validate(manifest, hostVersion: "0.16.0")) { error in
            XCTAssertEqual(error as? PluginPackageManifestError, .invalidBundleRelativePath("../Demo.bundle"))
        }
    }

    func testManifestValidationRejectsInvalidVersion() {
        let manifest = PluginPackageManifest(
            id: "com.example.demo",
            displayName: "Demo",
            version: "1.0-beta",
            minHostVersion: "0.15.0",
            bundleRelativePath: "Demo.bundle"
        )

        XCTAssertThrowsError(try PluginPackageManifestLoader.validate(manifest, hostVersion: "0.16.0")) { error in
            XCTAssertEqual(error as? PluginPackageManifestError, .invalidVersion("1.0-beta"))
        }
    }

    func testManifestValidationRejectsIncompatibleHostVersion() {
        let manifest = PluginPackageManifest(
            id: "com.example.demo",
            displayName: "Demo",
            version: "1.0.0",
            minHostVersion: "1.0.0",
            bundleRelativePath: "Demo.bundle"
        )

        XCTAssertThrowsError(try PluginPackageManifestLoader.validate(manifest, hostVersion: "0.16.0")) { error in
            XCTAssertEqual(
                error as? PluginPackageManifestError,
                .incompatibleHostVersion(required: "1.0.0", current: "0.16.0")
            )
        }
    }

    func testManifestDecodesWithCategoryAndReleaseChannel() throws {
        let json = """
        {
          "id": "demo",
          "displayName": "Demo",
          "version": "1.0.0",
          "minHostVersion": "0.15.0",
          "pluginKitVersion": 1,
          "bundleRelativePath": "Demo.bundle",
          "capabilities": { "primaryPanel": true, "componentPanel": false, "configuration": false },
          "permissions": [],
          "category": "display",
          "releaseChannel": "beta"
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PluginPackageManifest.self, from: json)
        XCTAssertEqual(manifest.category, "display")
        XCTAssertEqual(manifest.releaseChannel, "beta")
    }

    func testManifestDecodesWithoutCategoryAndReleaseChannelGracefully() throws {
        // Legacy plugin.json files without category/releaseChannel should still decode.
        let json = """
        {
          "id": "demo",
          "displayName": "Demo",
          "version": "1.0.0",
          "minHostVersion": "0.15.0",
          "pluginKitVersion": 1,
          "bundleRelativePath": "Demo.bundle",
          "capabilities": { "primaryPanel": true, "componentPanel": false, "configuration": false },
          "permissions": []
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(PluginPackageManifest.self, from: json)
        XCTAssertNil(manifest.category)
        XCTAssertNil(manifest.releaseChannel)
    }
}
