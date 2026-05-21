import XCTest
@testable import MacTools
@testable import QuitAppsPlugin

@MainActor
final class QuitAppsPluginTests: XCTestCase {

    // MARK: - Plugin Metadata

    func testMetadataIdentifiesQuitAppsPlugin() {
        let plugin = QuitAppsPlugin()

        XCTAssertEqual(plugin.metadata.id, "quit-apps")
        XCTAssertEqual(plugin.metadata.title, "退出应用")
    }

    func testIconIsPower() {
        let plugin = QuitAppsPlugin()

        XCTAssertEqual(plugin.metadata.iconName, "power")
    }

    func testControlStyleIsButton() {
        let plugin = QuitAppsPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertEqual(plugin.primaryPanelDescriptor.buttonTitle, "选择")
    }

    func testMenuActionBehaviorIsDismissBeforeHandling() {
        let plugin = QuitAppsPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.menuActionBehavior, .dismissBeforeHandling)
    }

    func testInitialPanelStateIsNotOn() {
        let plugin = QuitAppsPlugin()

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.errorMessage)
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = QuitAppsPlugin()

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testPluginHostIncludesQuitApps() {
        let host = makePluginHostForTests(plugins: [QuitAppsPlugin()])

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "quit-apps" })
    }

    func testDescriptionMatchesManifest() {
        let plugin = QuitAppsPlugin()

        XCTAssertEqual(plugin.metadata.defaultDescription, "选择并退出正在运行的应用")
    }

    // MARK: - QuitAppsViewModel – confirmTitle

    func testConfirmTitleIsQuitAllWhenNothingSelected() {
        let vm = QuitAppsViewModel()

        XCTAssertEqual(vm.confirmTitle, "退出全部应用")
    }

    func testConfirmTitleReflectsSelectionCount() {
        let vm = QuitAppsViewModel()
        vm.entries = [
            QuitAppEntry(id: "a", app: .current, isSelected: true),
            QuitAppEntry(id: "b", app: .current, isSelected: true),
            QuitAppEntry(id: "c", app: .current, isSelected: false),
        ]

        XCTAssertEqual(vm.confirmTitle, "退出 2 个应用")
    }

    // MARK: - QuitAppsViewModel – invertSelection

    func testInvertSelectionOnEmptyEntriesIsNoop() {
        let vm = QuitAppsViewModel()
        vm.invertSelection()

        XCTAssertTrue(vm.entries.isEmpty)
    }

    func testInvertSelectionTogglesAllEntries() {
        let vm = QuitAppsViewModel()
        vm.entries = [
            QuitAppEntry(id: "a", app: .current, isSelected: false),
            QuitAppEntry(id: "b", app: .current, isSelected: true),
        ]

        vm.invertSelection()

        XCTAssertTrue(vm.entries[0].isSelected)
        XCTAssertFalse(vm.entries[1].isSelected)
    }

    // MARK: - QuitAppsViewModel – toggleEntry

    func testToggleEntryChangesSelectionState() {
        let vm = QuitAppsViewModel()
        vm.entries = [QuitAppEntry(id: "x", app: .current, isSelected: false)]

        vm.toggleEntry(id: "x")

        XCTAssertTrue(vm.entries[0].isSelected)
    }

    func testToggleEntryUnknownIDIsNoop() {
        let vm = QuitAppsViewModel()
        vm.entries = [QuitAppEntry(id: "x", app: .current, isSelected: false)]

        vm.toggleEntry(id: "unknown")

        XCTAssertFalse(vm.entries[0].isSelected)
    }

    // MARK: - QuitAppsViewModel – load

    func testLoadExcludesHostApp() {
        let vm = QuitAppsViewModel()
        vm.load()

        let containsHost = vm.entries.contains { $0.id == Bundle.main.bundleIdentifier }
        XCTAssertFalse(containsHost)
    }

    func testLoadPreservesExistingSelection() {
        let vm = QuitAppsViewModel()
        vm.load()

        guard let first = vm.entries.first else { return }
        vm.toggleEntry(id: first.id)

        vm.load()

        XCTAssertTrue(vm.entries.first { $0.id == first.id }?.isSelected == true)
    }
}
