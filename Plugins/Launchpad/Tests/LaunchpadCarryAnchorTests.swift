import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// D4 parking invariants for the root-page carry anchor (design §10-E): the lifted cell stays in
/// the source container's `cells` (its mouse events must keep flowing), parked off-screen by
/// FRAME — never `isHidden` — excluded from every layout pass while parked, and revealed exactly
/// once on commit/cancel. A no-op commit writes nothing yet still reveals (AR-1).
@MainActor
final class LaunchpadCarryAnchorTests: XCTestCase {

    private final class FloatingIconSpy: LaunchpadFloatingIconPresenting {
        private(set) var presentCount = 0
        private(set) var dismissCount = 0
        private(set) var isPresenting = false
        private(set) var presentedAt: NSPoint?
        private(set) var movedTo: NSPoint?

        func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
            presentCount += 1
            presentedAt = p
            isPresenting = true
        }

        func move(toScreenPoint p: NSPoint) { movedTo = p }

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

    private var appA: LaunchpadAppItem { app("/Apps/A.app", "A") }
    private var appB: LaunchpadAppItem { app("/Apps/B.app", "B") }
    private var appC: LaunchpadAppItem { app("/Apps/C.app", "C") }
    private var threeApps: [LaunchpadDisplayCell] { [.app(appA), .app(appB), .app(appC)] }

    /// Root page container whose onDragBegan mirrors production wiring: the visible order is
    /// frozen into the coordinator the moment a drag begins (LaunchpadGridView.pageContent).
    private func makePage(_ items: [LaunchpadDisplayCell], page: Int) -> LaunchpadGridContainerView {
        let coordinator = self.coordinator!
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
            onDragBegan: { coordinator.freezeVisibleOrder(items) },
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

    /// Routes the coordinator's data path through the PRODUCTION applier mapping, counting calls.
    private func injectProductionApplier() {
        coordinator.storeApplier = { [store] action, frozenOrder in
            self.applierCalls += 1
            return LaunchpadOverlayController.apply(action, frozenOrder: frozenOrder,
                                                    to: store!, folderName: "未命名")
        }
    }

    private func centre(of cell: LaunchpadGridCellView) -> NSPoint {
        NSPoint(x: cell.frame.midX, y: cell.frame.midY)
    }

    /// Lift `cells[index]` through the container's real entry point (windowless harness: window
    /// points are container-local).
    @discardableResult
    private func lift(_ container: LaunchpadGridContainerView, cellAt index: Int) -> LaunchpadGridCellView {
        let cell = container.cellViews[index]
        container.beginDirectDrag(cell, atWindowPoint: centre(of: cell))
        return cell
    }

    // MARK: - Parking invariants (design §2.1/§2.2)

    func testLiftParksAnchorWithIdentitySeedGap() {
        let container = makePage(threeApps, page: 0)
        let framesBefore = container.cellViews.map(\.frame)

        let anchor = lift(container, cellAt: 1)

        XCTAssertTrue(coordinator.carryActive, "根页 lift 必须升格为 carry 会话")
        XCTAssertEqual(coordinator.carrySession?.origin, .rootPage)
        XCTAssertEqual(coordinator.carrySession?.frozenVisibleOrder, threeApps,
                       "onDragBegan 冻结的快照必须随会话走")
        XCTAssertTrue(spy.isPresenting, "lift 即浮窗（D2-A）")

        // The anchor: parked by FRAME, still in the cell tree, never hidden, never isLifted.
        XCTAssertEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "锚必须 frame 停泊离屏（D4：禁 isHidden/removeFromSuperview）")
        XCTAssertTrue(anchor.superview === container, "锚必须留在源容器里继续收事件")
        XCTAssertFalse(anchor.isHidden)
        XCTAssertFalse(anchor.isLifted, "放大视觉由浮窗承担，锚不置 isLifted")
        XCTAssertTrue(container.hasActiveDrag, "源容器算作有活动拖拽（hover 抑制/右键守卫）")

        // Seed gap = the anchor's own slot → identity layout: every neighbour stays put.
        XCTAssertTrue(container.externalDragActive, "lift 即 beginExternalDrag（源页让位会话）")
        XCTAssertEqual(container.externalGapIndex, 1, "seedGap 必须是锚的原槽位")
        XCTAssertEqual(container.cellViews[0].frame, framesBefore[0], "邻居 frame 不得移动（恒等布局）")
        XCTAssertEqual(container.cellViews[2].frame, framesBefore[2], "邻居 frame 不得移动（恒等布局）")
    }

    func testRepeatedLayoutPassesNeverWriteAnchorFrame() {
        let c0 = makePage(threeApps, page: 0)
        let framesBefore = c0.cellViews.map(\.frame)
        let anchor = lift(c0, cellAt: 1)

        // Engaged (gap path): any number of layout passes must leave the anchor parked and the
        // neighbours in the identity seed layout.
        for _ in 0..<3 { c0.layout() }
        XCTAssertEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "循环 layout()（gap 路径）不得把锚写回槽位")
        XCTAssertEqual(c0.cellViews[0].frame, framesBefore[0])
        XCTAssertEqual(c0.cellViews[2].frame, framesBefore[2])

        // Handed off to another page (source's external drag ends): the fallback layout branch
        // must go COMPACT over activeCells — no hole — and still never touch the anchor (AC-2).
        let c1 = makePage(threeApps, page: 1)
        coordinator.currentPageDidChange(1)
        XCTAssertFalse(c0.externalDragActive, "handoff 后源页让位收口")
        XCTAssertTrue(c1.externalDragActive)
        for _ in 0..<3 { c0.layout() }
        XCTAssertEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "handoff 离开源页后锚仍停泊")
        XCTAssertEqual(c0.cellViews[0].frame, framesBefore[0], "紧凑布局：A 仍在槽 0")
        XCTAssertEqual(c0.cellViews[2].frame, framesBefore[1], "紧凑布局：C 补进原槽 1，无洞")
    }

    // MARK: - Reveal paths (design §2.3/§7 hard-cut)

    func testNoOpCommitRevealsAnchorAtOriginalSlotWithZeroWrites() {
        store.captureVisibleOrder([appA, appB, appC])      // seed a layout so writes are countable
        let seedWrites = storage.writeCount
        injectProductionApplier()
        let container = makePage(threeApps, page: 0)
        let framesBefore = container.cellViews.map(\.frame)

        let anchor = lift(container, cellAt: 1)
        // "Jiggle in place": move within the anchor's own slot — its committed slot is inert
        // (never arms, keeps the seed gap), so the release resolves back to the original spot.
        container.updateDirectDrag(atWindowPoint: NSPoint(x: framesBefore[1].midX + 5,
                                                          y: framesBefore[1].midY))
        XCTAssertNil(container.stackTargetCell, "悬停自己的槽位不得 arm merge")
        XCTAssertEqual(container.externalGapIndex, 1, "自家槽位保持 seed gap")

        container.endDirectDrag(atWindowPoint: NSPoint(x: framesBefore[1].midX, y: framesBefore[1].midY))

        XCTAssertEqual(applierCalls, 0, "no-op commit 必须跳过 storeApplier")
        XCTAssertEqual(storage.writeCount, seedWrites, "no-op commit 零写盘（AR-1）")
        XCTAssertEqual(coordinator.commitToken, 1, "视觉通道照常 bump")
        XCTAssertNil(coordinator.carrySession)
        XCTAssertFalse(container.hasActiveDrag)
        XCTAssertFalse(container.externalDragActive)
        XCTAssertEqual(spy.dismissCount, 1, "浮窗拆除")

        container.layout()                                   // settle the reveal deterministically
        XCTAssertEqual(anchor.frame, framesBefore[1], "reveal 必须把锚复位回原槽位")
        for (index, cell) in container.cellViews.enumerated() {
            XCTAssertEqual(cell.frame, framesBefore[index], "no-op 后整个棋盘复原")
        }
    }

    func testCommitToNewTargetWritesStoreOnceAndRevealsAnchor() {
        store.captureVisibleOrder([appA, appB, appC])
        let seedWrites = storage.writeCount
        injectProductionApplier()
        let container = makePage(threeApps, page: 0)
        let framesBefore = container.cellViews.map(\.frame)

        let anchor = lift(container, cellAt: 0)              // carry A
        // Hover C's right seam → gap after C (active indexing), release there.
        let seam = NSPoint(x: framesBefore[2].maxX - 4, y: framesBefore[2].midY)
        container.updateDirectDrag(atWindowPoint: seam)
        XCTAssertNotNil(container.externalGapIndex)
        container.endDirectDrag(atWindowPoint: seam)

        XCTAssertEqual(applierCalls, 1, "commit 恰好走一次 storeApplier")
        XCTAssertEqual(storage.writeCount, seedWrites + 1, "恰一次写盘（capture 无新增 app 不写）")
        XCTAssertEqual(store.layout?.nodes.map(\.rootID), [appB.id, appC.id, appA.id],
                       "A 落在 C 之后——mouseUp 调用栈内同步落库")
        XCTAssertEqual(coordinator.pendingVisualCommit?.landingID, appA.id)
        XCTAssertEqual(coordinator.commitToken, 1)

        // Hard-cut reveal: the anchor is back in the layout surfaces immediately; the unit
        // harness has no SwiftUI apply, so the container still shows the pre-commit model —
        // the anchor must land back in a REAL slot (its committed one), not stay parked.
        container.layout()
        XCTAssertEqual(anchor.frame, framesBefore[0], "reveal 后锚必须离开停泊点回到真实槽位")
        XCTAssertFalse(container.hasActiveDrag)
    }

    func testCancelRestoresAnchorImmediately() {
        let container = makePage(threeApps, page: 0)
        let framesBefore = container.cellViews.map(\.frame)
        let anchor = lift(container, cellAt: 1)
        // Open a real gap elsewhere so cancel has visible state to unwind.
        container.updateDirectDrag(atWindowPoint: NSPoint(x: framesBefore[2].maxX - 4,
                                                          y: framesBefore[2].midY))

        coordinator.cancelCarry(.searchActivated)

        XCTAssertNil(coordinator.carrySession)
        XCTAssertFalse(coordinator.carryActive)
        XCTAssertFalse(container.externalDragActive, "cancel 收口让位会话")
        XCTAssertNil(container.externalGapIndex)
        XCTAssertFalse(container.hasActiveDrag)
        XCTAssertEqual(spy.dismissCount, 1)

        container.layout()
        for (index, cell) in container.cellViews.enumerated() {
            XCTAssertEqual(cell.frame, framesBefore[index], "cancel 即时复原：锚回真实槽位、邻居归位")
        }
        XCTAssertEqual(anchor.frame, framesBefore[1])
    }

    func testSourceUnmountMidCarryCancelsAndCleansUp() {
        let container = makePage(threeApps, page: 0)
        lift(container, cellAt: 0)
        XCTAssertTrue(coordinator.carryActive)

        container.viewWillMove(toWindow: nil)               // filtered shrink / overlay teardown

        XCTAssertNil(coordinator.carrySession, "源页卸载必须 cancelCarry(.anchorUnmounted)")
        XCTAssertFalse(coordinator.carryActive)
        XCTAssertFalse(spy.isPresenting, "浮窗不得在源页卸载后存活")
        XCTAssertFalse(container.hasActiveDrag, "锚一并清理")
        XCTAssertEqual(coordinator.registeredPageIndices, [], "容器反注册")
        XCTAssertEqual(coordinator.commitToken, 0, "中止不产生 commit")

        // The next gesture — on a freshly mounted replacement container — must lift again:
        // the cancelled-gesture latch must not survive an .anchorUnmounted cancel either.
        let remounted = makePage(threeApps, page: 0)
        lift(remounted, cellAt: 0)
        XCTAssertTrue(coordinator.carryActive, "anchorUnmounted cancel 后新手势必须能重新 lift")
    }

    // MARK: - Cancel must not wedge the NEXT gesture (the latch regression)

    /// A mid-carry cancel latches the coordinator so the SAME gesture's orphan events stay
    /// orphaned — but the latch must die at the next gesture boundary. Reproduction chain per
    /// reachable cancel entry: lift → cancel → orphan mouseUp (swallowed) → brand-new lift must
    /// open a fresh carry with a normal seed gap. Before the fix the root-lift gate read the
    /// latch BEFORE `onDragBegan` (its only reset point) could run, so one cancel permanently
    /// swallowed every later root drag until an in-folder drag or an app restart.
    func testNextGestureLiftsAgainAfterEveryCancelReason() {
        let container = makePage(threeApps, page: 0)
        let framesBefore = container.cellViews.map(\.frame)
        let reasons: [LaunchpadDragCoordinator.CarryCancelReason] =
            [.searchActivated, .overlayClosed, .geometryChanged]

        for reason in reasons {
            lift(container, cellAt: 1)
            XCTAssertTrue(coordinator.carryActive, "\(reason): lift 应开 carry")
            coordinator.cancelCarry(reason)

            // The cancelled gesture's orphan mouseUp: swallowed — no commit, no new session.
            container.endDirectDrag(atWindowPoint: centre(of: container.cellViews[1]))
            XCTAssertNil(coordinator.carrySession, "\(reason): 孤儿 mouseUp 不得重开会话")
            XCTAssertEqual(coordinator.commitToken, 0, "\(reason): 孤儿 mouseUp 不产出 commit")

            // NEXT gesture: must lift normally — the latch must not survive into it.
            let anchor = lift(container, cellAt: 1)
            XCTAssertTrue(coordinator.carryActive,
                          "\(reason): cancel 后的新手势必须能重新 lift（闩锁不得跨手势存活）")
            XCTAssertEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                           "\(reason): 第二次 lift 锚照常停泊")
            XCTAssertTrue(container.externalDragActive)
            XCTAssertEqual(container.externalGapIndex, 1, "\(reason): seedGap 回到锚原槽位")
            XCTAssertEqual(container.cellViews[0].frame, framesBefore[0], "\(reason): 邻居恒等布局")
            XCTAssertEqual(container.cellViews[2].frame, framesBefore[2], "\(reason): 邻居恒等布局")

            coordinator.cancelCarry(.shutdown)               // close this round's session
            container.layout()                               // settle the restore deterministically
        }
    }

    // MARK: - Mid-carry geometry mutation fail-safe (appearance design §1.5-5)

    /// A perPage change mid-carry (window resize / column reflow re-pushing geometry)
    /// invalidates the calibration space — the coordinator must cancel, dismiss the
    /// floating icon and restore the anchor, never try to re-calibrate in flight.
    /// Appearance-driven metrics changes are unreachable mid-session (the overlay
    /// snapshots metrics at open()), so this resize path is the only live mutation.
    func testMidCarryPerPageChangeCancelsAndDismissesFloatingIcon() {
        let container = makePage(threeApps, page: 0)
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 2, perPage: 20,
            viewportMinX: 0, viewportTopY: 600))
        let anchor = lift(container, cellAt: 1)
        XCTAssertTrue(coordinator.carryActive)
        XCTAssertTrue(spy.isPresenting)

        // Same pageWidth, perPage 20 → 12 (the design's reference mutation).
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 2, perPage: 12,
            viewportMinX: 0, viewportTopY: 600))

        XCTAssertNil(coordinator.carrySession, "mid-carry perPage 变化必须 cancel（fail-safe）")
        XCTAssertEqual(coordinator.endReason, .cancelled)
        XCTAssertEqual(spy.dismissCount, 1, "浮窗必须随 cancel 拆除")
        container.layout()
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "cancel 后锚必须复原（不许永久隐身）")
        XCTAssertEqual(applierCalls, 0, "几何突变 cancel 零写盘")
    }

    // MARK: - Grab offset through pushed geometry (design §2.1-4 / §5)

    /// The lift's grab offset must come from the PUSHED geometry, never the container frame
    /// chain: `convert` is blind to the SwiftUI paging offset, so on page > 0 it would skew the
    /// offset by page×pageWidth and the floating icon would ride that far from the cursor for
    /// the whole carry. The pushed mapping is page-invariant ("viewport is the page"), so
    /// asserting the arithmetic path here is the unit-level lock; the page>0 visual itself
    /// stays on the make-run checklist (§10-G) — a windowless harness cannot observe it.
    func testLiftGrabOffsetMapsThroughPushedGeometry() {
        let container = makePage(threeApps, page: 0)
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 2, perPage: 21,
            viewportMinX: 100, viewportTopY: 700))

        // Grab B 10pt right of / 5pt below its icon centre (page-local, flipped y), expressed
        // as the WINDOW point whose CarrySpace image is that local point.
        let metrics = LaunchpadGridMetrics()
        let cell = container.cellViews[1]
        let iconCentre = NSPoint(x: cell.frame.minX + metrics.cellWidth / 2,
                                 y: cell.frame.minY + 8 + metrics.iconSide / 2)
        let grabLocal = NSPoint(x: iconCentre.x + 10, y: iconCentre.y + 5)
        let windowPoint = NSPoint(x: grabLocal.x + 100, y: 700 - grabLocal.y)

        container.beginDirectDrag(cell, atWindowPoint: windowPoint)

        // grabOffset = (local.x − centre.x, centre.y − local.y) = (10, −5). The windowless
        // screen point is .zero, so the icon presents at −grabOffset…
        XCTAssertEqual(spy.presentedAt?.x ?? .nan, -10, accuracy: 0.001,
                       "grab offset 必须经推送几何换算——frame-chain convert 在 page>0 偏 page×pageWidth")
        XCTAssertEqual(spy.presentedAt?.y ?? .nan, 5, accuracy: 0.001)

        // …and every later move keeps the same offset (grab point preserved all carry long).
        coordinator.carryMoved(atScreenPoint: NSPoint(x: 500, y: 400),
                               atWindowPoint: NSPoint(x: 450, y: 300))
        XCTAssertEqual(spy.movedTo?.x ?? .nan, 490, accuracy: 0.001, "整个 carry 期间保持抓取点")
        XCTAssertEqual(spy.movedTo?.y ?? .nan, 405, accuracy: 0.001)
    }
}
