import AppKit
import SwiftUI
import XCTest
import MacToolsPluginKit
@testable import MacTools

final class PluginComponentModelsTests: XCTestCase {
    func testComponentSpanAcceptsSupportedSizes() {
        XCTAssertEqual(PluginComponentSpan(width: 1, height: 1), .oneByOne)
        XCTAssertEqual(PluginComponentSpan(width: 1, height: 2), .oneByTwo)
        XCTAssertEqual(PluginComponentSpan(width: 2, height: 1), .twoByOne)
        XCTAssertEqual(PluginComponentSpan(width: 2, height: 2), .twoByTwo)
        XCTAssertEqual(PluginComponentSpan(width: 4, height: 2), .fourByTwo)
        XCTAssertEqual(PluginComponentSpan(width: 2, height: 4)?.height, 4)
    }

    func testComponentSpanRejectsUnsupportedSizes() {
        XCTAssertNil(PluginComponentSpan(width: 0, height: 1))
        XCTAssertNil(PluginComponentSpan(width: 5, height: 1))
        XCTAssertNil(PluginComponentSpan(width: 1, height: 0))
    }

    func testDefaultComponentPanelLayoutMetricsUseCompactRows() {
        let metrics = PluginComponentPanelLayoutMetrics.default

        XCTAssertEqual(metrics.columns, PluginComponentSpan.maximumWidth)
        XCTAssertEqual(metrics.cellWidth, 70)
        XCTAssertEqual(metrics.originalCellHeight, 94)
        XCTAssertEqual(metrics.verticalSpacing, 8)
        XCTAssertEqual(metrics.cellHeight, 8)
        XCTAssertEqual(metrics.itemHeight(forSpanHeight: 1), 8)
        XCTAssertEqual(metrics.itemHeight(forSpanHeight: 2), 16)
        XCTAssertEqual(metrics.itemHeight(forSpanHeight: 12), 96)
        XCTAssertEqual(metrics.heightSpan(fittingContentHeight: 22), 3)
        XCTAssertEqual(metrics.heightSpan(fittingContentHeight: 34), 5)
        XCTAssertEqual(metrics.heightSpan(fittingContentHeight: 64), 8)
        XCTAssertEqual(metrics.heightSpan(closestToOriginalSpanHeight: 1), 12)
        XCTAssertEqual(metrics.heightSpan(closestToOriginalSpanHeight: 2), 25)
        XCTAssertEqual(metrics.heightSpan(closestToOriginalSpanHeight: 3), 37)
        XCTAssertEqual(metrics.heightSpan(closestToOriginalSpanHeight: 10), 127)
    }

    func testPluginMetadataCarriesStableIdentityAndDisplayFields() {
        let metadata = PluginMetadata(
            id: "mock-feature",
            title: "Mock Feature",
            iconName: "sparkles",
            iconTint: Color(nsColor: .systemPurple),
            order: 42,
            defaultDescription: "Feature description"
        )

        XCTAssertEqual(metadata.id, "mock-feature")
        XCTAssertEqual(metadata.title, "Mock Feature")
        XCTAssertEqual(metadata.iconName, "sparkles")
        XCTAssertEqual(metadata.order, 42)
        XCTAssertEqual(metadata.defaultDescription, "Feature description")
    }

    func testPrimaryPanelDescriptorCarriesPanelSpecificFields() {
        let descriptor = PluginPrimaryPanelDescriptor(
            controlStyle: .button,
            menuActionBehavior: .dismissBeforeHandling,
            buttonTitle: "Run"
        )

        XCTAssertEqual(descriptor.controlStyle, .button)
        XCTAssertEqual(descriptor.menuActionBehavior, .dismissBeforeHandling)
        XCTAssertEqual(descriptor.buttonTitle, "Run")
    }
}

final class MenuBarControlItemDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "MenuBarControlItemDefaultsTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        if let suiteName {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        try super.tearDownWithError()
    }

    func testVisibleControlItemDefaultsRightOfHiddenDivider() {
        MenuBarControlItemDefaults.prepareVisibleControlItem(userDefaults: userDefaults)

        XCTAssertEqual(
            userDefaults.double(forKey: preferredPositionKey(MenuBarControlItemDefaults.visibleAutosaveName)),
            0.5
        )
        XCTAssertTrue(userDefaults.bool(forKey: visibleKey(MenuBarControlItemDefaults.visibleAutosaveName)))
        XCTAssertTrue(userDefaults.bool(forKey: visibleControlCenterKey(MenuBarControlItemDefaults.visibleAutosaveName)))
    }

    func testVisibleControlItemPositionResetRestoresPositionRightOfHiddenDivider() {
        userDefaults.set(12, forKey: preferredPositionKey(MenuBarControlItemDefaults.visibleAutosaveName))

        MenuBarControlItemDefaults.resetVisibleControlItemPosition(userDefaults: userDefaults)

        XCTAssertEqual(
            userDefaults.double(forKey: preferredPositionKey(MenuBarControlItemDefaults.visibleAutosaveName)),
            0.5
        )
    }

    func testVisibleControlItemPreferredPositionCanBeCachedAndRestored() {
        MenuBarControlItemDefaults.resetVisibleControlItemPosition(userDefaults: userDefaults)
        let cached = MenuBarControlItemDefaults.visibleControlItemPreferredPosition(userDefaults: userDefaults)

        MenuBarControlItemDefaults.setVisibleControlItemPreferredPosition(nil, userDefaults: userDefaults)
        XCTAssertNil(MenuBarControlItemDefaults.visibleControlItemPreferredPosition(userDefaults: userDefaults))

        MenuBarControlItemDefaults.setVisibleControlItemPreferredPosition(cached, userDefaults: userDefaults)
        XCTAssertEqual(MenuBarControlItemDefaults.visibleControlItemPreferredPosition(userDefaults: userDefaults), 0.5)
    }

    func testHiddenDividerDefaultsToPreferredPositionOneWhenMissing() {
        MenuBarControlItemDefaults.prepareHiddenDividerControlItem(userDefaults: userDefaults)

        XCTAssertEqual(
            userDefaults.double(forKey: preferredPositionKey(MenuBarControlItemDefaults.hiddenAutosaveName)),
            1
        )
    }

    func testHiddenDividerResetsMovedPreferredPosition() {
        userDefaults.set(12, forKey: preferredPositionKey(MenuBarControlItemDefaults.hiddenAutosaveName))

        MenuBarControlItemDefaults.prepareHiddenDividerControlItem(userDefaults: userDefaults)

        XCTAssertEqual(
            userDefaults.double(forKey: preferredPositionKey(MenuBarControlItemDefaults.hiddenAutosaveName)),
            1
        )
    }

    func testVisibleRecoveryUsesCurrentDividerPosition() {
        MenuBarControlItemDefaults.setHiddenDividerControlItemPreferredPosition(8, userDefaults: userDefaults)

        XCTAssertEqual(
            MenuBarControlItemDefaults.preferredPositionForVisibleControlItemRightOfHiddenDivider(
                userDefaults: userDefaults
            ),
            7.5
        )
    }

    func testDividerRecoveryUsesCurrentVisiblePosition() {
        MenuBarControlItemDefaults.setVisibleControlItemPreferredPosition(4, userDefaults: userDefaults)

        XCTAssertEqual(
            MenuBarControlItemDefaults.preferredPositionForHiddenDividerLeftOfVisibleControlItem(
                userDefaults: userDefaults
            ),
            4.5
        )
    }

    func testAlwaysHiddenDividerPreflightDoesNotForcePreferredPosition() {
        MenuBarControlItemDefaults.setAlwaysHiddenDividerControlItemPreferredPosition(8, userDefaults: userDefaults)

        MenuBarControlItemDefaults.prepareAlwaysHiddenDividerControlItem(userDefaults: userDefaults)

        XCTAssertNil(
            userDefaults.object(forKey: preferredPositionKey(MenuBarControlItemDefaults.alwaysHiddenAutosaveName))
        )
        XCTAssertTrue(userDefaults.bool(forKey: visibleKey(MenuBarControlItemDefaults.alwaysHiddenAutosaveName)))
        XCTAssertTrue(userDefaults.bool(forKey: visibleControlCenterKey(MenuBarControlItemDefaults.alwaysHiddenAutosaveName)))
    }

    func testControlItemRecoveryRestoresThawDefaultOrder() {
        MenuBarControlItemDefaults.setVisibleControlItemPreferredPosition(12, userDefaults: userDefaults)
        MenuBarControlItemDefaults.setHiddenDividerControlItemPreferredPosition(18, userDefaults: userDefaults)

        MenuBarControlItemDefaults.recoverVisibleAndHiddenControlItemDefaultPositions(userDefaults: userDefaults)

        XCTAssertEqual(
            userDefaults.double(forKey: preferredPositionKey(MenuBarControlItemDefaults.visibleAutosaveName)),
            0.5
        )
        XCTAssertEqual(
            userDefaults.double(forKey: preferredPositionKey(MenuBarControlItemDefaults.hiddenAutosaveName)),
            1
        )
    }

    private func preferredPositionKey(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    private func visibleKey(_ autosaveName: String) -> String {
        "NSStatusItem Visible \(autosaveName)"
    }

    private func visibleControlCenterKey(_ autosaveName: String) -> String {
        "NSStatusItem VisibleCC \(autosaveName)"
    }
}
