import XCTest
@testable import MenuBarHiddenPlugin

@MainActor
final class MenuBarHiddenSnapshotTests: XCTestCase {

    func testEmptySnapshotHasZeroCounts() {
        let snap = MenuBarHiddenSnapshot.empty
        XCTAssertEqual(snap.hiddenCount, 0)
        XCTAssertTrue(snap.allItems.isEmpty)
    }

    func testSnapshotCountsReflectSections() {
        let items = (0..<6).map { i in makeItem(pid: pid_t(i), title: "Item\(i)", instance: 0) }
        let snap = MenuBarHiddenSnapshot(
            visibleItems: Array(items.suffix(3)),
            hiddenItems: Array(items.prefix(2)),
            alwaysHiddenItems: [items[2]],
            permissions: MenuBarHiddenPermissionsStatus(hasAccessibility: true, hasScreenRecording: false)
        )
        XCTAssertEqual(snap.hiddenCount, 2)
        XCTAssertEqual(snap.visibleItems.count, 3)
        XCTAssertEqual(snap.allItems.count, 6)
    }

    func testLayoutPolicyKeepsHostIconVisibleWhenLeftOfDivider() {
        let dividerBounds = CGRect(x: 100, y: 0, width: 10, height: 20)
        let host = makeItem(
            pid: ProcessInfo.processInfo.processIdentifier,
            title: "MacTools",
            instance: 0,
            bounds: CGRect(x: 60, y: 0, width: 20, height: 20)
        )
        let hidden = makeItem(
            pid: 42,
            title: "Hidden",
            instance: 0,
            bounds: CGRect(x: 60, y: 0, width: 20, height: 20)
        )
        let visible = makeItem(
            pid: 43,
            title: "Visible",
            instance: 0,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 20)
        )

        let hiddenItems = MenuBarHiddenLayoutPolicy.hiddenItems(
            from: [host, hidden, visible],
            hiddenDividerBounds: dividerBounds
        )
        let visibleItems = MenuBarHiddenLayoutPolicy.visibleItems(
            from: [host, hidden, visible],
            hiddenDividerBounds: dividerBounds
        )

        XCTAssertEqual(hiddenItems.map(\.tag), [hidden.tag])
        XCTAssertEqual(visibleItems.map(\.tag), [host.tag, visible.tag])
    }

    func testLayoutPolicyUsesDividerBoundsAndMidpoints() {
        let dividerBounds = CGRect(x: 100, y: 0, width: 10, height: 20)
        let hidden = makeItem(
            pid: 42,
            title: "Hidden",
            instance: 0,
            bounds: CGRect(x: 70, y: 0, width: 30, height: 20)
        )
        let crossing = makeItem(
            pid: 43,
            title: "Crossing",
            instance: 0,
            bounds: CGRect(x: 96, y: 0, width: 12, height: 20)
        )
        let crossingVisible = makeItem(
            pid: 45,
            title: "CrossingVisible",
            instance: 0,
            bounds: CGRect(x: 104, y: 0, width: 12, height: 20)
        )
        let visible = makeItem(
            pid: 44,
            title: "Visible",
            instance: 0,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 20)
        )

        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.hiddenItems(
                from: [hidden, crossing, crossingVisible, visible],
                hiddenDividerBounds: dividerBounds
            ).map(\.tag),
            [hidden.tag, crossing.tag]
        )
        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.visibleItems(
                from: [hidden, crossing, crossingVisible, visible],
                hiddenDividerBounds: dividerBounds
            ).map(\.tag),
            [crossingVisible.tag, visible.tag]
        )
    }

    func testLayoutPolicySplitsAlwaysHiddenHiddenAndVisibleLikeThaw() {
        let alwaysHiddenDividerBounds = CGRect(x: 60, y: 0, width: 10, height: 20)
        let hiddenDividerBounds = CGRect(x: 100, y: 0, width: 10, height: 20)
        let alwaysHidden = makeItem(
            pid: 41,
            title: "AlwaysHidden",
            instance: 0,
            bounds: CGRect(x: 20, y: 0, width: 20, height: 20)
        )
        let hidden = makeItem(
            pid: 42,
            title: "Hidden",
            instance: 0,
            bounds: CGRect(x: 78, y: 0, width: 20, height: 20)
        )
        let visible = makeItem(
            pid: 43,
            title: "Visible",
            instance: 0,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 20)
        )

        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.alwaysHiddenItems(
                from: [alwaysHidden, hidden, visible],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [alwaysHidden.tag]
        )
        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.hiddenItems(
                from: [alwaysHidden, hidden, visible],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [hidden.tag]
        )
        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.visibleItems(
                from: [alwaysHidden, hidden, visible],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [visible.tag]
        )
    }

    func testLayoutPolicyKeepsExistingHiddenItemsWhenAlwaysHiddenIsEnabled() {
        let alwaysHiddenDividerBounds = CGRect(x: 40, y: 0, width: 10, height: 20)
        let hiddenDividerBounds = CGRect(x: 100, y: 0, width: 10, height: 20)
        let alwaysHidden = makeItem(
            pid: 41,
            title: "AlwaysHidden",
            instance: 0,
            bounds: CGRect(x: 10, y: 0, width: 20, height: 20)
        )
        let existingHidden = makeItem(
            pid: 42,
            title: "ExistingHidden",
            instance: 0,
            bounds: CGRect(x: 70, y: 0, width: 20, height: 20)
        )

        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.alwaysHiddenItems(
                from: [alwaysHidden, existingHidden],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [alwaysHidden.tag]
        )
        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.hiddenItems(
                from: [alwaysHidden, existingHidden],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [existingHidden.tag]
        )
    }

    func testAlwaysHiddenRestorePolicyReturnsRecordedVisibleAndHiddenItemsOnly() {
        let recordedVisible = makeItem(pid: 41, title: "RecordedVisible", instance: 0)
        let recordedHidden = makeItem(pid: 42, title: "RecordedHidden", instance: 0)
        let alreadyAlwaysHidden = makeItem(pid: 43, title: "AlreadyAlwaysHidden", instance: 0)
        let unrecorded = makeItem(pid: 44, title: "Unrecorded", instance: 0)
        let snapshot = MenuBarHiddenSnapshot(
            visibleItems: [recordedVisible, unrecorded],
            hiddenItems: [recordedHidden],
            alwaysHiddenItems: [alreadyAlwaysHidden],
            permissions: MenuBarHiddenPermissionsStatus(hasAccessibility: true, hasScreenRecording: true)
        )

        let candidates = MenuBarHiddenAlwaysHiddenRestorePolicy.restoreCandidates(
            snapshot: snapshot,
            recordedStableKeys: [
                recordedVisible.tag.stableKey,
                recordedHidden.tag.stableKey,
                alreadyAlwaysHidden.tag.stableKey,
            ]
        )

        XCTAssertEqual(candidates.map(\.tag), [recordedVisible.tag, recordedHidden.tag])
    }

    func testAlwaysHiddenRestorePolicySkipsNonHideableItems() {
        let audioVideo = makeItem(namespace: "com.apple.controlcenter", title: "AudioVideoModule")
        let snapshot = MenuBarHiddenSnapshot(
            visibleItems: [audioVideo],
            hiddenItems: [],
            alwaysHiddenItems: [],
            permissions: MenuBarHiddenPermissionsStatus(hasAccessibility: true, hasScreenRecording: true)
        )

        let candidates = MenuBarHiddenAlwaysHiddenRestorePolicy.restoreCandidates(
            snapshot: snapshot,
            recordedStableKeys: [audioVideo.tag.stableKey]
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testLayoutPolicyDetectsReversedAlwaysHiddenDividerOrder() {
        XCTAssertTrue(
            MenuBarHiddenLayoutPolicy.alwaysHiddenDividerNeedsRecovery(
                hiddenDividerBounds: CGRect(x: 100, y: 0, width: 10, height: 20),
                alwaysHiddenDividerBounds: CGRect(x: 120, y: 0, width: 10, height: 20)
            )
        )
        XCTAssertFalse(
            MenuBarHiddenLayoutPolicy.alwaysHiddenDividerNeedsRecovery(
                hiddenDividerBounds: CGRect(x: 100, y: 0, width: 10, height: 20),
                alwaysHiddenDividerBounds: CGRect(x: 40, y: 0, width: 10, height: 20)
            )
        )
    }

    func testLayoutPolicyUsesAlwaysHiddenDividerMidpointForStraddlingItems() {
        let alwaysHiddenDividerBounds = CGRect(x: 60, y: 0, width: 10, height: 20)
        let hiddenDividerBounds = CGRect(x: 100, y: 0, width: 10, height: 20)
        let crossingAlwaysHidden = makeItem(
            pid: 41,
            title: "CrossingAlwaysHidden",
            instance: 0,
            bounds: CGRect(x: 56, y: 0, width: 12, height: 20)
        )
        let crossingHidden = makeItem(
            pid: 42,
            title: "CrossingHidden",
            instance: 0,
            bounds: CGRect(x: 64, y: 0, width: 12, height: 20)
        )

        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.alwaysHiddenItems(
                from: [crossingAlwaysHidden, crossingHidden],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [crossingAlwaysHidden.tag]
        )
        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.hiddenItems(
                from: [crossingAlwaysHidden, crossingHidden],
                hiddenDividerBounds: hiddenDividerBounds,
                alwaysHiddenDividerBounds: alwaysHiddenDividerBounds
            ).map(\.tag),
            [crossingHidden.tag]
        )
    }

    func testLayoutPolicyRejectsMovingHostIconIntoHiddenSection() {
        let host = makeItem(
            pid: ProcessInfo.processInfo.processIdentifier,
            title: "MacTools",
            instance: 0
        )
        let other = makeItem(pid: 99, title: "Other", instance: 0)

        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: host, section: .hidden))
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: host, section: .alwaysHidden))
        XCTAssertFalse(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: host, section: .visible))
        XCTAssertFalse(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: other, section: .hidden))
    }

    func testThawSystemImmovableItemsAreNotMovable() {
        let clock = makeItem(namespace: "com.apple.controlcenter", title: "Clock")
        let controlCenter = makeItem(namespace: "com.apple.controlcenter", title: "BentoBox-0")
        let screenSharing = makeItem(namespace: "com.apple.SSMenuAgent", title: "Item-0")
        let other = makeItem(namespace: "com.example.app", title: "Item")

        XCTAssertFalse(clock.isMovable)
        XCTAssertFalse(controlCenter.isMovable)
        XCTAssertFalse(screenSharing.isMovable)
        XCTAssertTrue(other.isMovable)
    }

    func testThawSystemNonHideableItemsCannotMoveIntoHiddenSection() {
        let audioVideo = makeItem(namespace: "com.apple.controlcenter", title: "AudioVideoModule")
        let faceTime = makeItem(namespace: "com.apple.controlcenter", title: "FaceTime")
        let screenCapture = makeItem(namespace: "com.apple.screencaptureui", title: "Item-0")
        let gameMode = makeItem(namespace: "GamePolicyAgent", title: "Item-0")
        let other = makeItem(namespace: "com.example.app", title: "Item")

        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: audioVideo, section: .hidden))
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: faceTime, section: .hidden))
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: screenCapture, section: .hidden))
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: gameMode, section: .hidden))
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: audioVideo, section: .alwaysHidden))
        XCTAssertFalse(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: other, section: .hidden))
        XCTAssertFalse(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: audioVideo, section: .visible))
    }

    func testThawTransientSystemIndicatorsAreFilteredFromLayoutEditor() {
        let audioVideo = makeItem(namespace: "com.apple.controlcenter", title: "AudioVideoModule")
        let faceTime = makeItem(namespace: "com.apple.controlcenter", title: "FaceTime")
        let screenCapture = makeItem(namespace: "com.apple.screencaptureui", title: "Item-0")
        let liveActivity = makeItem(namespace: "com.apple.controlcenter", title: "Item-12", sourcePID: 777)
        let clock = makeItem(namespace: "com.apple.controlcenter", title: "Clock")
        let other = makeItem(namespace: "com.example.app", title: "Item")

        XCTAssertEqual(
            MenuBarHiddenLayoutPolicy.layoutEditorItems(
                from: [audioVideo, faceTime, screenCapture, liveActivity, clock, other]
            ).map(\.tag),
            [clock.tag, other.tag]
        )
    }

    func testUnresolvedControlCenterGenericItemIsKeptLikeThaw() {
        let unresolved = makeItem(namespace: "com.apple.controlcenter", title: "Item-12", sourcePID: nil)

        XCTAssertEqual(MenuBarHiddenLayoutPolicy.layoutEditorItems(from: [unresolved]).map(\.tag), [unresolved.tag])
        XCTAssertFalse(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: unresolved, section: .hidden))
    }

    func testVisibleControlItemCannotMoveIntoHiddenSection() {
        let visibleControl = makeItem(namespace: "cc.ggbond.mactools", title: MenuBarHiddenConstants.visibleControlItemTitle)

        XCTAssertTrue(visibleControl.isHostApplicationIcon)
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: visibleControl, section: .hidden))
        XCTAssertTrue(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: visibleControl, section: .alwaysHidden))
        XCTAssertFalse(MenuBarHiddenLayoutPolicy.shouldRejectMoveToSection(item: visibleControl, section: .visible))
    }

    func testTemporaryShowReturnDestinationUsesNeighborLikeThaw() {
        let left = makeItem(pid: 41, title: "Left", instance: 0)
        let target = makeItem(pid: 42, title: "Target", instance: 0)
        let right = makeItem(pid: 43, title: "Right", instance: 0)

        let destination = MenuBarHiddenLayoutPolicy.returnDestination(
            for: target,
            in: [left, target, right],
            section: .hidden
        )

        XCTAssertEqual(destination?.section, .hidden)
        XCTAssertEqual(destination?.placement, .before(right.tag))
        XCTAssertEqual(destination?.fallbackPlacement, .after(left.tag))
    }

    func testWindowInfoRecognizesPopupMenuLevels() {
        let popupWindow = makeWindow(
            id: 100,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.popUpMenuWindow)
        )
        let popupCompanionWindow = makeWindow(
            id: 101,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.popUpMenuWindow) - 1
        )
        let statusWindow = makeWindow(
            id: 102,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.statusWindow)
        )

        XCTAssertTrue(popupWindow.isPopupMenuWindow)
        XCTAssertTrue(popupCompanionWindow.isPopupMenuWindow)
        XCTAssertFalse(statusWindow.isPopupMenuWindow)
    }

    func testWindowInfoRecognizesMenuRelatedWindowsLikeThaw() {
        let windowServerPopup = makeWindow(
            id: 106,
            ownerPID: 88,
            layer: CGWindowLevelForKey(.popUpMenuWindow),
            ownerName: "Window Server"
        )
        let appPopup = makeWindow(
            id: 107,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.popUpMenuWindow),
            ownerName: "Control Center"
        )
        let windowServerStatus = makeWindow(
            id: 108,
            ownerPID: 88,
            layer: CGWindowLevelForKey(.statusWindow),
            ownerName: "Window Server"
        )
        let normalWindow = makeWindow(
            id: 109,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.normalWindow),
            ownerName: "Control Center"
        )

        XCTAssertTrue(windowServerPopup.isWindowServerWindow)
        XCTAssertTrue(windowServerPopup.isMenuRelated)
        XCTAssertTrue(appPopup.isMenuRelated)
        XCTAssertTrue(windowServerStatus.isMenuRelated)
        XCTAssertFalse(normalWindow.isMenuRelated)
    }

    func testWindowInfoRecognizesStatusAndMainMenuLevelsSeparately() {
        let statusWindow = makeWindow(
            id: 103,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.statusWindow)
        )
        let mainMenuWindow = makeWindow(
            id: 104,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.mainMenuWindow)
        )
        let popupWindow = makeWindow(
            id: 105,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.popUpMenuWindow)
        )

        XCTAssertTrue(statusWindow.isStatusOrMainMenuWindow)
        XCTAssertTrue(mainMenuWindow.isStatusOrMainMenuWindow)
        XCTAssertFalse(popupWindow.isStatusOrMainMenuWindow)
    }

    func testTemporaryItemIdentityMatchesSameWindowWhenSourcePIDChanges() {
        let tag = MenuBarItemTag(namespace: "com.apple.controlcenter", title: "Item-12", windowID: nil, instanceIndex: 0)
        let original = makeItem(
            tag: tag,
            windowID: 700,
            pid: 42,
            title: tag.title,
            sourcePID: nil,
            bounds: CGRect(x: -100, y: 0, width: 20, height: 20)
        )
        let resolvedLater = makeItem(
            tag: tag,
            windowID: 700,
            pid: 42,
            title: tag.title,
            sourcePID: 99,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 20)
        )

        XCTAssertTrue(MenuBarHiddenTemporaryItemIdentity(item: original).matches(resolvedLater))
    }

    func testTemporaryItemIdentityDoesNotMatchDifferentResolvedPIDWithSameGenericTag() {
        let tag = MenuBarItemTag(namespace: "com.apple.controlcenter", title: "Item-12", windowID: nil, instanceIndex: 0)
        let original = makeItem(
            tag: tag,
            windowID: 700,
            pid: 42,
            title: tag.title,
            sourcePID: nil,
            bounds: CGRect(x: -100, y: 0, width: 20, height: 20)
        )
        let differentItem = makeItem(
            tag: tag,
            windowID: 701,
            pid: 42,
            title: tag.title,
            sourcePID: 99,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 20)
        )

        XCTAssertFalse(MenuBarHiddenTemporaryItemIdentity(item: original).matches(differentItem))
    }

    func testTemporaryPopupDetectionUsesOwnerPIDFallbackLikeThaw() {
        XCTAssertEqual(
            MenuBarHiddenTemporaryInterfacePolicy.popupDetectionPID(
                sourcePID: nil,
                ownerPID: 42
            ),
            42
        )
        XCTAssertEqual(
            MenuBarHiddenTemporaryInterfacePolicy.popupDetectionPID(
                sourcePID: 99,
                ownerPID: 42
            ),
            99
        )
    }

    func testTemporaryMenuDetectionAcceptsStandardMenuWindowsForThirdPartyItems() {
        let item = makeItem(namespace: "com.example.app", title: "Item")
        let popup = makeWindow(
            id: 501,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.popUpMenuWindow)
        )
        let otherMenuBarItem = makeWindow(
            id: 500,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.statusWindow)
        )
        let itemWindow = makeWindow(
            id: 499,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.statusWindow)
        )
        let normalPanel = makeWindow(
            id: 502,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.normalWindow) + 1
        )

        XCTAssertTrue(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                popup,
                item: item,
                contextWindowID: 499,
                baselineWindowIDs: [500]
            )
        )
        XCTAssertFalse(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                itemWindow,
                item: item,
                contextWindowID: 499,
                baselineWindowIDs: [500]
            )
        )
        XCTAssertFalse(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                otherMenuBarItem,
                item: item,
                contextWindowID: 499,
                baselineWindowIDs: [500]
            )
        )
        XCTAssertFalse(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                normalPanel,
                item: item,
                contextWindowID: 499,
                baselineWindowIDs: [500]
            )
        )
        XCTAssertFalse(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                popup,
                item: item,
                contextWindowID: 499,
                baselineWindowIDs: [501]
            )
        )
    }

    func testTemporaryMenuDetectionAcceptsSystemMenuBarInterfaceWindowsForSystemItems() {
        let controlCenterItem = makeItem(namespace: "com.apple.controlcenter", title: "WiFi")
        let systemStatusWindow = makeWindow(
            id: 601,
            ownerPID: 88,
            layer: CGWindowLevelForKey(.statusWindow),
            ownerName: "Control Center"
        )
        let systemMainMenuWindow = makeWindow(
            id: 602,
            ownerPID: 88,
            layer: CGWindowLevelForKey(.mainMenuWindow),
            ownerName: "Window Server"
        )
        let systemHighPanel = makeWindow(
            id: 603,
            ownerPID: 88,
            layer: CGWindowLevelForKey(.normalWindow) + 1,
            ownerName: "Control Center"
        )
        let thirdPartyHighPanel = makeWindow(
            id: 604,
            ownerPID: 42,
            layer: CGWindowLevelForKey(.normalWindow) + 1,
            ownerName: "Example"
        )
        let thirdPartyItem = makeItem(namespace: "com.example.app", title: "Item")

        XCTAssertTrue(controlCenterItem.usesSystemMenuBarInterface)
        XCTAssertFalse(thirdPartyItem.usesSystemMenuBarInterface)
        XCTAssertTrue(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                systemStatusWindow,
                item: controlCenterItem,
                contextWindowID: 600,
                baselineWindowIDs: []
            )
        )
        XCTAssertTrue(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                systemMainMenuWindow,
                item: controlCenterItem,
                contextWindowID: 600,
                baselineWindowIDs: []
            )
        )
        XCTAssertTrue(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                systemHighPanel,
                item: controlCenterItem,
                contextWindowID: 600,
                baselineWindowIDs: []
            )
        )
        XCTAssertFalse(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                thirdPartyHighPanel,
                item: controlCenterItem,
                contextWindowID: 600,
                baselineWindowIDs: []
            )
        )
        XCTAssertFalse(
            MenuBarHiddenTemporaryInterfacePolicy.isNewTemporaryInterfaceWindow(
                systemHighPanel,
                item: thirdPartyItem,
                contextWindowID: 600,
                baselineWindowIDs: []
            )
        )
    }

    func testPermissionsStatus() {
        let full = MenuBarHiddenPermissionsStatus(hasAccessibility: true, hasScreenRecording: true)
        XCTAssertTrue(full.canManageItems)

        let axOnly = MenuBarHiddenPermissionsStatus(hasAccessibility: true, hasScreenRecording: false)
        XCTAssertFalse(axOnly.canManageItems)

        let srOnly = MenuBarHiddenPermissionsStatus(hasAccessibility: false, hasScreenRecording: true)
        XCTAssertFalse(srOnly.canManageItems)

        let none = MenuBarHiddenPermissionsStatus(hasAccessibility: false, hasScreenRecording: false)
        XCTAssertFalse(none.canManageItems)
    }

    // MARK: - MenuBarItemTag stability

    func testTagStableKeyIncludesAllComponents() {
        let tag = MenuBarItemTag(
            namespace: "com.example.clock",
            title: "Clock",
            windowID: nil,
            instanceIndex: 2
        )
        XCTAssertEqual(tag.stableKey, "com.example.clock:Clock:2")
    }

    func testTagsWithDifferentInstancesAreNotEqual() {
        let t1 = MenuBarItemTag(namespace: "app", title: "X", windowID: nil, instanceIndex: 0)
        let t2 = MenuBarItemTag(namespace: "app", title: "X", windowID: nil, instanceIndex: 1)
        XCTAssertNotEqual(t1, t2)
    }

    // MARK: - Helpers

    private func makeItem(pid: pid_t, title: String, instance: Int) -> MenuBarItem {
        makeItem(pid: pid, title: title, instance: instance, bounds: .zero)
    }

    private func makeItem(pid: pid_t, title: String, instance: Int, bounds: CGRect) -> MenuBarItem {
        let tag = MenuBarItemTag(namespace: "\(pid)", title: title, windowID: nil, instanceIndex: instance)
        return makeItem(tag: tag, pid: pid, title: title, bounds: bounds)
    }

    private func makeItem(namespace: String, title: String, sourcePID: pid_t? = nil) -> MenuBarItem {
        makeItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, windowID: nil, instanceIndex: 0),
            pid: 42,
            title: title,
            sourcePID: sourcePID,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 20)
        )
    }

    private func makeItem(
        tag: MenuBarItemTag,
        windowID: CGWindowID = 0,
        pid: pid_t,
        title: String,
        sourcePID: pid_t? = nil,
        bounds: CGRect
    ) -> MenuBarItem {
        return MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: pid,
            sourcePID: sourcePID,
            bounds: bounds,
            title: title,
            isOnScreen: bounds.minX >= 0
        )
    }

    private func makeWindow(
        id: CGWindowID,
        ownerPID: pid_t,
        layer: CGWindowLevel,
        title: String? = nil,
        ownerName: String? = nil
    ) -> WindowInfo {
        WindowInfo(
            windowID: id,
            ownerPID: ownerPID,
            layer: Int(layer),
            title: title,
            ownerName: ownerName,
            isOnScreen: true
        )
    }
}
