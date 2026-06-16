import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Step-3 carry-session skeleton (design §1/§10-C, folder-origin rows): lift opens a session,
/// cancel produces no token and no store write, and a commit lands in the store SYNCHRONOUSLY in
/// mouseUp — exactly once — through the injected storeApplier, with the `@Published` token reduced
/// to a pure visual channel. `resolveCarryCommit` is driven directly as a pure function.
@MainActor
final class LaunchpadCarrySessionTests: XCTestCase {

    /// Spy presenter (design §10-①): records the floating-icon lifecycle without any NSWindow.
    private final class FloatingIconSpy: LaunchpadFloatingIconPresenting {
        private(set) var presentCount = 0
        private(set) var dismissCount = 0
        private(set) var movedPoints: [NSPoint] = []
        private(set) var isPresenting = false

        func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
            presentCount += 1
            isPresenting = true
        }

        func move(toScreenPoint p: NSPoint) { movedPoints.append(p) }

        func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void) {
            isPresenting = false
            completion()
        }

        func dismiss() {
            dismissCount += 1
            isPresenting = false
        }
    }

    private var coordinator: LaunchpadDragCoordinator!
    private var spy: FloatingIconSpy!
    private var storage: FakePluginStorage!
    private var store: LaunchpadLayoutStore!
    private var applierCalls = 0

    override func setUp() {
        super.setUp()
        coordinator = LaunchpadDragCoordinator()
        spy = FloatingIconSpy()
        let spy = self.spy!
        coordinator.floatingPresenterFactory = { spy }
        storage = FakePluginStorage()
        store = LaunchpadLayoutStore(storage: storage)
        applierCalls = 0
    }

    override func tearDown() {
        coordinator.cancelCarry(.shutdown)      // never leak a session/floating icon across tests
        coordinator = nil
        spy = nil
        store = nil
        storage = nil
        super.tearDown()
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    // MARK: Fixture — apps A/B/X inside folder F1, loose C/D; one root page container

    private let folderID = "F1"
    private var appA: LaunchpadAppItem { app("/Apps/A.app", "A") }
    private var appB: LaunchpadAppItem { app("/Apps/B.app", "B") }
    private var appX: LaunchpadAppItem { app("/Apps/X.app", "X") }
    private var appC: LaunchpadAppItem { app("/Apps/C.app", "C") }
    private var appD: LaunchpadAppItem { app("/Apps/D.app", "D") }

    /// Root display cells matching the seeded layout: [F1(A,B,X), C, D].
    private var rootCells: [LaunchpadDisplayCell] {
        [.folder(id: folderID, name: "F", items: [appA, appB, appX]), .app(appC), .app(appD)]
    }

    /// Seeds the layout store with folder F1(A,B,X) + loose C/D and returns the write count the
    /// seeding consumed, so commit tests can assert "exactly one more write".
    private func seedStore() -> Int {
        store.captureVisibleOrder([appA, appB, appX, appC, appD])
        store.makeFolder(target: appA.id, dragged: appB.id, name: "F", id: folderID)
        store.addToFolder(folderID, app: appX.id)
        return storage.writeCount
    }

    /// Routes the coordinator's data path through the PRODUCTION applier mapping, counting calls.
    private func injectProductionApplier() {
        coordinator.storeApplier = { [store] action, frozenOrder in
            self.applierCalls += 1
            return LaunchpadOverlayController.apply(action, frozenOrder: frozenOrder,
                                                    to: store!, folderName: "未命名")
        }
    }

    private func makePage(_ items: [LaunchpadDisplayCell], page: Int,
                          coordinator: LaunchpadDragCoordinator? = nil) -> LaunchpadGridContainerView {
        let coordinator = coordinator ?? self.coordinator!
        let grid = LaunchpadDragGrid(
            items: items,
            columns: 7,
            selectedID: nil,
            isCompact: false,
            iconProvider: { _ in NSImage() },
            onActivate: { _ in },
            onReveal: { _ in },
            onCopyPath: { _ in },
            onHide: { _ in },
            onMoveToFront: { _ in },
            onMoveToEnd: { _ in },
            onSelect: { _ in },
            onReorder: { _, _ in },
            onMakeFolder: { _, _ in },
            onAddToFolder: { _, _ in },
            onDragBegan: {},
            onPageSwipe: { _ in },
            onPageDrag: { _, _, _ in },
            onPageScroll: { _, _ in },
            onDismiss: {},
            coordinator: coordinator,
            pageIndex: page
        )
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: grid)
        container.layout()
        return container
    }

    private func pushGeometry(to coordinator: LaunchpadDragCoordinator? = nil) {
        (coordinator ?? self.coordinator).syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 1, perPage: 21,
            viewportMinX: 100, viewportTopY: 700))
    }

    /// The window point whose CarrySpace page-local image is `local`.
    private func windowPoint(forLocal local: NSPoint) -> NSPoint {
        NSPoint(x: local.x + 100, y: 700 - local.y)
    }

    @discardableResult
    private func beginFolderCarry(of item: LaunchpadAppItem) -> Bool {
        coordinator.beginCarry(itemID: item.id, origin: .folder(sourceFolderID: folderID), isApp: true,
                               icon: nil, iconSide: 64, atScreenPoint: .zero, aboveLevel: .normal)
    }

    // MARK: - Lift opens a session (folder origin, carrying(.tracking))

    func testLiftOpensFolderOriginTrackingSession() {
        let container = makePage(rootCells, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        coordinator.freezeVisibleOrder(rootCells)

        XCTAssertTrue(beginFolderCarry(of: appA))

        guard let session = coordinator.carrySession else { return XCTFail("lift 必须开会话") }
        XCTAssertEqual(session.state, .carrying(.tracking))
        XCTAssertEqual(session.origin, .folder(sourceFolderID: folderID))
        XCTAssertEqual(session.frozenVisibleOrder, rootCells, "onDragBegan 冻结的快照必须随会话走")
        XCTAssertTrue(session.editableAtBegin)
        XCTAssertTrue(coordinator.carryActive)
        XCTAssertTrue(coordinator.folderEjectActive, "folder origin 必须同时升 folderEjectActive（驱动关夹）")
        XCTAssertEqual(spy.presentCount, 1, "浮窗经注入工厂创建")
        XCTAssertTrue(coordinator.hasFloatingWindow)

        // The visible page started making way: a move at a cell's near side opens a gap.
        let edge = NSPoint(x: container.cellViews[1].frame.maxX - 4, y: container.cellViews[1].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: edge))
        XCTAssertNotNil(container.externalGapIndex, "lift 即 beginExternalDrag：当前页必须能让位")
    }

    func testSecondLiftWhileCarryingIsRejected() {
        coordinator.freezeVisibleOrder(rootCells)
        XCTAssertTrue(beginFolderCarry(of: appA))
        let first = coordinator.carrySession

        XCTAssertFalse(beginFolderCarry(of: appB), "carrying 期重入 lift 必须被拒")
        XCTAssertTrue(coordinator.carrySession === first, "原会话不受影响")
        XCTAssertEqual(spy.presentCount, 1, "被拒的 lift 不得新建浮窗")
    }

    // MARK: - cancel(carrying): no token, no write

    func testCancelWhileCarryingProducesNoTokenAndNoStoreWrite() {
        let container = makePage(rootCells, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        let seedWrites = seedStore()
        injectProductionApplier()
        let layoutBefore = store.layout

        coordinator.freezeVisibleOrder(rootCells)
        beginFolderCarry(of: appA)
        let edge = NSPoint(x: container.cellViews[1].frame.maxX - 4, y: container.cellViews[1].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: edge))
        XCTAssertNotNil(container.externalGapIndex)

        coordinator.cancelCarry(.searchActivated)

        XCTAssertNil(coordinator.carrySession, "cancel 后会话即终结（无 .ended 僵尸态）")
        XCTAssertEqual(coordinator.commitToken, 0, "cancel 不产生视觉 token")
        XCTAssertEqual(applierCalls, 0, "cancel 不触发 storeApplier")
        XCTAssertEqual(storage.writeCount, seedWrites, "cancel 零写盘")
        XCTAssertEqual(store.layout, layoutBefore, "布局数据不被 cancel 触碰")
        XCTAssertNil(coordinator.pendingVisualCommit)
        XCTAssertFalse(coordinator.carryActive)
        XCTAssertFalse(coordinator.folderEjectActive)
        XCTAssertEqual(spy.dismissCount, 1, "浮窗必须拆除")
        XCTAssertNil(container.externalGapIndex, "让位 gap 收口")
    }

    func testCancelWithNoSessionIsIgnored() {
        coordinator.cancelCarry(.overlayClosed)     // nil-safe (约束 1：调用点不变)
        XCTAssertEqual(coordinator.commitToken, 0)
        XCTAssertNil(coordinator.pendingVisualCommit)
    }

    // MARK: - commit: data lands synchronously, exactly once

    func testCommitLandsInStoreSynchronouslyExactlyOnce() {
        let container = makePage(rootCells, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        let seedWrites = seedStore()
        injectProductionApplier()

        coordinator.freezeVisibleOrder(rootCells)
        beginFolderCarry(of: appA)
        // Hover C's right seam → make-way gap right of C; release at the same point.
        let edge = NSPoint(x: container.cellViews[1].frame.maxX - 4, y: container.cellViews[1].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: edge))
        coordinator.carryReleased(atWindowPoint: windowPoint(forLocal: edge))

        // Data: synchronous, exactly one applier call, exactly one persistence write.
        XCTAssertEqual(applierCalls, 1, "commit 必须恰好走一次 storeApplier")
        XCTAssertEqual(storage.writeCount, seedWrites + 1, "恰一次写盘（capture 无新增 app 不写）")
        XCTAssertEqual(store.layout?.nodes.map(\.rootID), [folderID, appC.id, appA.id, appD.id],
                       "A 出夹落在 C 之后——mouseUp 调用栈内即已落库")
        if case .folder(_, _, let children)? = store.layout?.nodes.first {
            XCTAssertEqual(children.map(\.id), [appB.id, appX.id], "源夹只剩 B/X")
        } else {
            XCTFail("F1 应保留为夹")
        }

        // Visual channel: token bumped AFTER the data landed; landing id follows the app.
        XCTAssertEqual(coordinator.commitToken, 1)
        XCTAssertEqual(coordinator.pendingVisualCommit?.landingID, appA.id)
        XCTAssertEqual(coordinator.pendingVisualCommit?.itemID, appA.id)

        // Session torn down, floating icon gone (hard-cut settle).
        XCTAssertNil(coordinator.carrySession)
        XCTAssertFalse(coordinator.hasFloatingWindow)
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertFalse(coordinator.carryActive)
        XCTAssertFalse(coordinator.folderEjectActive)
    }

    func testCommitWhenNotEditableSkipsTheWriteButKeepsVisuals() {
        let seedWrites = seedStore()
        injectProductionApplier()

        coordinator.freezeVisibleOrder(rootCells, editable: false)   // lift began in search mode
        beginFolderCarry(of: appA)
        coordinator.carryReleased(atWindowPoint: NSPoint(x: 60, y: 60))

        XCTAssertEqual(applierCalls, 0, "editableAtBegin == false → 数据通路关闭")
        XCTAssertEqual(storage.writeCount, seedWrites)
        XCTAssertEqual(coordinator.commitToken, 1, "视觉通道照常（关夹）")
        XCTAssertNil(coordinator.pendingVisualCommit?.landingID)
        XCTAssertNil(coordinator.carrySession)
    }

    // MARK: - Orphan-gesture insurance (design §1.2 — a cancelled gesture stays cancelled)

    func testOrphanReleaseAfterSearchCancelCannotRecommit() {
        _ = makePage(rootCells, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        let seedWrites = seedStore()
        injectProductionApplier()

        coordinator.freezeVisibleOrder(rootCells)
        beginFolderCarry(of: appA)
        coordinator.cancelCarry(.searchActivated)
        XCTAssertNil(coordinator.carrySession)

        // The SAME gesture's orphan mouseUp arrives through the grid's legacy late-eject path
        // (commitOut with no session). It must NOT re-open a session and resurrect the commit.
        coordinator.commitOut(folderID: folderID, appID: appA.id,
                              atWindowPoint: windowPoint(forLocal: NSPoint(x: 60, y: 60)))

        XCTAssertEqual(applierCalls, 0, "cancel 后的孤儿 release 不得复活写库")
        XCTAssertEqual(storage.writeCount, seedWrites)
        XCTAssertEqual(coordinator.commitToken, 0, "孤儿 release 不产生视觉 token")
        XCTAssertNil(coordinator.pendingVisualCommit)
        XCTAssertNil(coordinator.carrySession)
        XCTAssertEqual(spy.presentCount, 1, "孤儿 release 不得重建浮窗")
        XCTAssertFalse(coordinator.hasFloatingWindow)
    }

    func testNewGestureAfterCancelCanCarryAgain() {
        coordinator.freezeVisibleOrder(rootCells)
        beginFolderCarry(of: appA)
        coordinator.cancelCarry(.searchActivated)

        coordinator.freezeVisibleOrder(rootCells)       // next gesture begins (onDragBegan)
        XCTAssertTrue(beginFolderCarry(of: appB), "新手势必须不受上一手势 cancel 拍闸的影响")
        XCTAssertEqual(coordinator.carrySession?.itemID, appB.id)
    }

    // MARK: - Production wiring (overlay controller injects the applier; close() cancels)

    func testOverlayControllerProductionApplierLandsCommitInStore() {
        let controller = LaunchpadOverlayController(
            preferences: LaunchpadPreferences(storage: FakePluginStorage()),
            layoutStore: store)
        let coord = controller.dragCoordinator
        let spy = self.spy!
        coord.floatingPresenterFactory = { spy }
        let container = makePage(rootCells, page: 0, coordinator: coord)
        pushGeometry(to: coord)
        coord.currentPageDidChange(0)
        let seedWrites = seedStore()

        coord.freezeVisibleOrder(rootCells)
        coord.beginCarry(itemID: appA.id, origin: .folder(sourceFolderID: folderID), isApp: true,
                         icon: nil, iconSide: 64, atScreenPoint: .zero, aboveLevel: .normal)
        let edge = NSPoint(x: container.cellViews[1].frame.maxX - 4, y: container.cellViews[1].frame.midY)
        coord.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: edge))
        coord.carryReleased(atWindowPoint: windowPoint(forLocal: edge))

        // The store changed through the controller's OWN injected applier — no test applier here.
        XCTAssertEqual(storage.writeCount, seedWrites + 1, "生产注入的 applier 必须真实写库")
        XCTAssertEqual(store.layout?.nodes.map(\.rootID), [folderID, appC.id, appA.id, appD.id],
                       "A 经生产线路出夹落在 C 之后")
        XCTAssertEqual(coord.pendingVisualCommit?.landingID, appA.id)
        XCTAssertEqual(coord.commitToken, 1)
        XCTAssertNil(coord.carrySession)
    }

    func testOverlayControllerCloseCancelsInFlightCarryWithoutWriting() {
        let controller = LaunchpadOverlayController(
            preferences: LaunchpadPreferences(storage: FakePluginStorage()),
            layoutStore: store)
        let coord = controller.dragCoordinator
        let spy = self.spy!
        coord.floatingPresenterFactory = { spy }
        let seedWrites = seedStore()

        coord.freezeVisibleOrder(rootCells)
        coord.beginCarry(itemID: appA.id, origin: .folder(sourceFolderID: folderID), isApp: true,
                         icon: nil, iconSide: 64, atScreenPoint: .zero, aboveLevel: .normal)
        XCTAssertTrue(coord.carryActive)

        controller.close()                              // overlay closing mid-carry

        XCTAssertNil(coord.carrySession, "close() 必须同步 cancelCarry(.overlayClosed)")
        XCTAssertFalse(coord.carryActive)
        XCTAssertFalse(coord.hasFloatingWindow, "浮窗不得在 overlay 关闭后存活")
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertEqual(storage.writeCount, seedWrites, "cancel 零写盘")
        XCTAssertEqual(coord.commitToken, 0)
    }

    // MARK: - resolveCarryCommit (pure function, §1.3)

    private func resolve(_ origin: LaunchpadCarrySession.Origin, _ result: LaunchpadExternalDropResult,
                         itemID: String, frozen: [LaunchpadDisplayCell]) -> CarryStoreAction {
        LaunchpadDragCoordinator.resolveCarryCommit(
            LaunchpadCarryCommit(itemID: itemID, origin: origin, result: result),
            frozenOrder: frozen)
    }

    func testResolveFolderOriginPassesResultThroughToMoveOutOfFolder() {
        let frozen = rootCells
        XCTAssertEqual(
            resolve(.folder(sourceFolderID: folderID), .reorder(.after(appC.id)), itemID: appA.id, frozen: frozen),
            .moveOutOfFolder(folderID: folderID, appID: appA.id, result: .reorder(.after(appC.id))))
        XCTAssertEqual(
            resolve(.folder(sourceFolderID: folderID), .makeFolder(targetAppID: appC.id), itemID: appA.id, frozen: frozen),
            .moveOutOfFolder(folderID: folderID, appID: appA.id, result: .makeFolder(targetAppID: appC.id)),
            "夹出 + merge 的子分支原样透传，由 applier 映射 store 三分支")
        XCTAssertEqual(
            resolve(.folder(sourceFolderID: folderID), .reorder(nil), itemID: appA.id, frozen: frozen),
            .moveOutOfFolder(folderID: folderID, appID: appA.id, result: .reorder(nil)),
            "nil-target 落尾由 store 现有逻辑兜底，resolve 不改写")
    }

    func testResolveRootReorderGuardsNoOpAgainstFrozenOrder() {
        let frozen: [LaunchpadDisplayCell] = [.app(appA), .app(appB), .app(appC)]
        XCTAssertEqual(resolve(.rootPage, .reorder(.after(appA.id)), itemID: appB.id, frozen: frozen),
                       .none, "落回原邻位是 no-op：跳过写盘")
        XCTAssertEqual(resolve(.rootPage, .reorder(.before(appB.id)), itemID: appA.id, frozen: frozen),
                       .none)
        XCTAssertEqual(resolve(.rootPage, .reorder(.after(appC.id)), itemID: appA.id, frozen: frozen),
                       .move(id: appA.id, target: .after(appC.id)))
    }

    func testResolveRootReorderNilLandsAtFrozenTail() {
        let frozen: [LaunchpadDisplayCell] = [.app(appA), .app(appB), .app(appC)]
        XCTAssertEqual(resolve(.rootPage, .reorder(nil), itemID: appA.id, frozen: frozen),
                       .move(id: appA.id, target: .after(appC.id)), "出格松手 = 全局落尾（对冻结快照的末项）")
        XCTAssertEqual(resolve(.rootPage, .reorder(nil), itemID: appC.id, frozen: frozen),
                       .none, "已是末项 → no-op")
        XCTAssertEqual(resolve(.rootPage, .reorder(nil), itemID: appA.id, frozen: []),
                       .none, "空快照无可相对的末项 → no-op")
        // The tail node may be a folder — move(after: folderID) is a valid existing operation.
        let folderTail: [LaunchpadDisplayCell] = [.app(appA), .folder(id: folderID, name: "F", items: [appB])]
        XCTAssertEqual(resolve(.rootPage, .reorder(nil), itemID: appA.id, frozen: folderTail),
                       .move(id: appA.id, target: .after(folderID)))
    }

    func testResolveRootMergeMapsDirectly() {
        let frozen = rootCells
        XCTAssertEqual(resolve(.rootPage, .makeFolder(targetAppID: appC.id), itemID: appD.id, frozen: frozen),
                       .makeFolder(targetAppID: appC.id, draggedID: appD.id))
        XCTAssertEqual(resolve(.rootPage, .addToFolder(folderID: folderID), itemID: appC.id, frozen: frozen),
                       .addToFolder(folderID: folderID, appID: appC.id))
    }
}
