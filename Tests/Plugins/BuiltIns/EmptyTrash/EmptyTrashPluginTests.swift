import XCTest
@testable import MacTools

@MainActor
final class EmptyTrashPluginTests: XCTestCase {
    func testMetadataIdentifiesEmptyTrashPlugin() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.metadata.id, "empty-trash")
        XCTAssertEqual(plugin.metadata.title, "清空废纸篓")
    }

    func testControlStyleIsButton() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertEqual(plugin.primaryPanelDescriptor.buttonTitle, "清空")
    }

    func testInitialStateIsOffAndDisabled() {
        let plugin = EmptyTrashPlugin()

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertFalse(state.isEnabled)
    }

    func testInitialSubtitleShowsEmpty() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "废纸篓为空")
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

        XCTAssertEqual(plugin.metadata.defaultDescription, "清空废纸篓中的所有项目")
    }

    func testMenuActionBehaviorIsKeepPresented() {
        let plugin = EmptyTrashPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.menuActionBehavior, .keepPresented)
    }
}
