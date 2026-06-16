import XCTest
@testable import DisplayBrightnessPlugin

@MainActor
final class DisplayDisableCoordinatorTests: XCTestCase {
    func testDisableRejectsWhenBuiltInDisplayIsMissing() async {
        let service = FakeDisplayDisableService(
            onlineDisplays: [
                DisplayDisableDisplay(
                    id: 2,
                    name: "Studio Display",
                    isBuiltin: false,
                    isActive: true,
                    isInMirrorSet: false,
                    isVisibleToAppKit: true
                )
            ]
        )
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: InMemoryDisplayDisableStateStore()
        )

        await coordinator.disableBuiltInDisplay()

        XCTAssertEqual(coordinator.snapshot.status, .unavailable)
        XCTAssertEqual(coordinator.snapshot.message, "未检测到内建显示屏")
        XCTAssertTrue(service.setEnabledCalls.isEmpty)
    }

    func testDisableRejectsWhenNoExternalSurvivorExists() async {
        let service = FakeDisplayDisableService(
            onlineDisplays: [
                DisplayDisableDisplay(
                    id: 1,
                    name: "内建显示屏",
                    isBuiltin: true,
                    isActive: true,
                    isInMirrorSet: false,
                    isVisibleToAppKit: true
                )
            ]
        )
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: InMemoryDisplayDisableStateStore()
        )

        await coordinator.disableBuiltInDisplay()

        XCTAssertEqual(coordinator.snapshot.status, .available)
        XCTAssertEqual(coordinator.snapshot.message, "连接外接显示器后可关闭内建显示屏")
        XCTAssertTrue(service.setEnabledCalls.isEmpty)
    }

    func testDisableRejectsMirrorMode() async {
        let service = FakeDisplayDisableService(
            onlineDisplays: [
                DisplayDisableDisplay(
                    id: 1,
                    name: "内建显示屏",
                    isBuiltin: true,
                    isActive: true,
                    isInMirrorSet: true,
                    isVisibleToAppKit: true
                ),
                DisplayDisableDisplay(
                    id: 2,
                    name: "Studio Display",
                    isBuiltin: false,
                    isActive: true,
                    isInMirrorSet: true,
                    isVisibleToAppKit: true
                )
            ]
        )
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: InMemoryDisplayDisableStateStore()
        )

        await coordinator.disableBuiltInDisplay()

        XCTAssertEqual(coordinator.snapshot.status, .available)
        XCTAssertEqual(coordinator.snapshot.message, "镜像显示时暂不支持关闭内建显示屏")
        XCTAssertTrue(service.setEnabledCalls.isEmpty)
    }

    func testDisableSuccessStoresStateAfterVerificationPasses() async {
        let builtIn = DisplayDisableDisplay(
            id: 1,
            name: "内建显示屏",
            isBuiltin: true,
            isActive: true,
            isInMirrorSet: false,
            isVisibleToAppKit: true
        )
        let external = DisplayDisableDisplay(
            id: 2,
            name: "Studio Display",
            isBuiltin: false,
            isActive: true,
            isInMirrorSet: false,
            isVisibleToAppKit: true
        )
        let service = FakeDisplayDisableService(onlineDisplays: [builtIn, external])
        service.displaysAfterDisable = [
            builtIn.withActive(false).withVisibleToAppKit(false),
            external
        ]
        let store = InMemoryDisplayDisableStateStore()
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: store,
            verificationSettleDelay: .zero
        )

        await coordinator.disableBuiltInDisplay()

        XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 1, enabled: false)])
        XCTAssertEqual(coordinator.snapshot.status, .disabled)
        XCTAssertTrue(coordinator.snapshot.isRestoreAllowed)
        XCTAssertEqual(store.snapshot?.builtInDisplayID, 1)
    }

    func testDisableVerificationFailureRollsBackBuiltInDisplay() async {
        let builtIn = DisplayDisableDisplay(
            id: 1,
            name: "内建显示屏",
            isBuiltin: true,
            isActive: true,
            isInMirrorSet: false,
            isVisibleToAppKit: true
        )
        let external = DisplayDisableDisplay(
            id: 2,
            name: "Studio Display",
            isBuiltin: false,
            isActive: true,
            isInMirrorSet: false,
            isVisibleToAppKit: true
        )
        let service = FakeDisplayDisableService(onlineDisplays: [builtIn, external])
        service.displaysAfterDisable = [builtIn, external]
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: InMemoryDisplayDisableStateStore(),
            verificationSettleDelay: .zero
        )

        await coordinator.disableBuiltInDisplay()

        XCTAssertEqual(service.setEnabledCalls, [
            .init(displayID: 1, enabled: false),
            .init(displayID: 1, enabled: true)
        ])
        XCTAssertEqual(coordinator.snapshot.status, .failed)
        XCTAssertEqual(coordinator.snapshot.message, "关闭内建显示屏失败，已尝试恢复")
    }

    func testRestoreUsesOnlineBuiltInDisplayWhenStoredIDChanged() {
        let oldSnapshot = DisplayDisableRecoverySnapshot(
            createdAt: Date(timeIntervalSince1970: 1),
            builtInDisplayID: 1,
            vendorNumber: nil,
            modelNumber: nil,
            serialNumber: nil,
            survivorDisplayIDs: [2],
            originalMainDisplayID: 2
        )
        let currentBuiltIn = DisplayDisableDisplay(
            id: 9,
            name: "内建显示屏",
            isBuiltin: true,
            isActive: false,
            isInMirrorSet: false,
            isVisibleToAppKit: false
        )
        let external = DisplayDisableDisplay(
            id: 2,
            name: "Studio Display",
            isBuiltin: false,
            isActive: true,
            isInMirrorSet: false,
            isVisibleToAppKit: true
        )
        let service = FakeDisplayDisableService(onlineDisplays: [currentBuiltIn, external])
        let store = InMemoryDisplayDisableStateStore(snapshot: oldSnapshot)
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: store,
            verificationSettleDelay: .zero
        )

        coordinator.restoreBuiltInDisplay()

        XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 9, enabled: true)])
        XCTAssertNil(store.snapshot)
    }

    func testReconcileRestoresWhenExternalSurvivorDisappears() async {
        let disabledSnapshot = DisplayDisableRecoverySnapshot(
            createdAt: Date(timeIntervalSince1970: 1),
            builtInDisplayID: 1,
            vendorNumber: nil,
            modelNumber: nil,
            serialNumber: nil,
            survivorDisplayIDs: [2],
            originalMainDisplayID: 2
        )
        let builtIn = DisplayDisableDisplay(
            id: 1,
            name: "内建显示屏",
            isBuiltin: true,
            isActive: false,
            isInMirrorSet: false,
            isVisibleToAppKit: false
        )
        let service = FakeDisplayDisableService(onlineDisplays: [builtIn])
        let store = InMemoryDisplayDisableStateStore(snapshot: disabledSnapshot)
        let coordinator = DisplayDisableCoordinator(
            service: service,
            store: store,
            verificationSettleDelay: .zero
        )

        await coordinator.reconcileTopology()

        XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 1, enabled: true)])
    }

    func testInitRestoresWhenStoredSnapshotHasNoExternalSurvivor() {
        let disabledSnapshot = DisplayDisableRecoverySnapshot(
            createdAt: Date(timeIntervalSince1970: 1),
            builtInDisplayID: 1,
            vendorNumber: nil,
            modelNumber: nil,
            serialNumber: nil,
            survivorDisplayIDs: [2],
            originalMainDisplayID: 2
        )
        let builtIn = DisplayDisableDisplay(
            id: 1,
            name: "内建显示屏",
            isBuiltin: true,
            isActive: false,
            isInMirrorSet: false,
            isVisibleToAppKit: false
        )
        let service = FakeDisplayDisableService(onlineDisplays: [builtIn])
        let store = InMemoryDisplayDisableStateStore(snapshot: disabledSnapshot)

        _ = DisplayDisableCoordinator(
            service: service,
            store: store,
            verificationSettleDelay: .zero
        )

        XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 1, enabled: true)])
        XCTAssertNil(store.snapshot)
    }
}
