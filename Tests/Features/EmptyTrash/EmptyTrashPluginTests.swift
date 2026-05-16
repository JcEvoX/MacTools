import XCTest
@testable import MacTools

@MainActor
final class EmptyTrashPluginTests: XCTestCase {
    func testManifestIdentifiesEmptyTrashPlugin() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.manifest.id, "empty-trash")
        XCTAssertEqual(plugin.manifest.title, "清空废纸篓")
    }

    func testControlStyleIsButton() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.manifest.controlStyle, .button)
        XCTAssertEqual(plugin.manifest.buttonTitle, "清空")
    }

    func testInitialStateIsOffAndDisabled() {
        let plugin = EmptyTrashPlugin()

        let state = plugin.panelState
        XCTAssertFalse(state.isOn)
        XCTAssertFalse(state.isEnabled)
    }

    func testInitialSubtitleShowsEmpty() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.panelState.subtitle, "废纸篓为空")
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = EmptyTrashPlugin()

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testDefaultPluginHostIncludesEmptyTrash() {
        let host = PluginHost()

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "empty-trash" })
    }

    func testPluginDescriptionMatches() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.manifest.defaultDescription, "清空废纸篓中的所有项目")
    }

    func testMenuActionBehaviorIsKeepPresented() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.manifest.menuActionBehavior, .keepPresented)
    }
}
