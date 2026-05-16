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
