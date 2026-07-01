import AppKit
import XCTest
@testable import MacTools

@MainActor
final class MenuBarPanelPresenterTests: XCTestCase {
    private let suiteName = "MenuBarPanelPresenterTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPopoverBehaviorLetsStatusControllerOwnDismissal() {
        XCTAssertEqual(MenuBarPanelPresenter.popoverBehavior, .applicationDefined)
    }

    func testUnifiedPanelUsesComponentGridWidth() {
        XCTAssertEqual(MenuBarPanelLayout.baseWidth, ComponentPanelLayout.panelWidth)
    }

    func testUnifiedPanelModelForwardsSelectionWithoutReplacingRoot() {
        let model = MenuBarUnifiedPanelModel(
            selectedTab: .components,
            contentHeight: 100,
            maximumFeatureListHeight: 300,
            isPanelVisible: true
        )
        var selectedTab: MenuBarPanelTab?
        var measuredHeight: CGFloat?
        model.onTabSelection = { selectedTab = $0 }
        model.onPreferredContentHeightChange = { tab, height in
            selectedTab = tab
            measuredHeight = height
        }

        model.selectTab(.features)
        XCTAssertEqual(selectedTab, .features)
        XCTAssertEqual(model.selectedTab, .components)

        model.updatePreferredContentHeight(tab: .features, measuredHeight: 240)
        XCTAssertEqual(selectedTab, .features)
        XCTAssertEqual(measuredHeight, 240)
        XCTAssertEqual(model.contentHeight, 100)
    }

    func testContainsPresentedWindowIncludesMarkedSecondaryPanelWindow() {
        let presenter = makePresenter()
        let window = makeWindow()
        MenuBarPanelWindowRegistry.markSecondaryPanel(window)

        XCTAssertTrue(presenter.containsPresentedWindow(window))
    }

    func testContainsPresentedWindowRejectsUnmarkedWindow() {
        let presenter = makePresenter()
        let window = makeWindow()

        XCTAssertFalse(presenter.containsPresentedWindow(window))
    }

    private func makePresenter() -> MenuBarPanelPresenter {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let host = PluginHost(
            plugins: [],
            shortcutStore: ShortcutStore(userDefaults: defaults),
            pluginDisplayPreferencesStore: PluginDisplayPreferencesStore(userDefaults: defaults),
            globalShortcutManager: GlobalShortcutManager()
        )

        return MenuBarPanelPresenter(
            pluginHost: host,
            onDismiss: {},
            onOpenSettings: {},
            onPresentDiskCleanConfiguration: {},
            onPresentLaunchControlConfiguration: {},
            onAllPanelsClosed: {}
        )
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }
}
