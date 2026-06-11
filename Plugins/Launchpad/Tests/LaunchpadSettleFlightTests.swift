import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Step-8 flight settle (design §7/§1.2 settling row): on release the data lands synchronously
/// (unchanged), the session survives in `.settling` while the floating icon flies to the resolved
/// slot, and the landed cell stays PARKED until the flight's completion — guarded by a generation
/// token against stale callbacks and by a watchdog timeout against a lost completion. Windowed
/// fixtures: the flight branch needs container.window for the screen-rect conversion; every
/// windowless release stays on the hard-cut branch (pinned by the existing carry test fleet).
@MainActor
final class LaunchpadSettleFlightTests: XCTestCase {

    /// Spy presenter whose settle is MANUAL: the flight stays airborne until the test lands it,
    /// so the parked-while-flying window is observable (design §10-①, flight extension).
    private final class FlightSpy: LaunchpadFloatingIconPresenting {
        private(set) var presentCount = 0
        private(set) var dismissCount = 0
        private(set) var isPresenting = false
        private(set) var settleTargets: [NSRect] = []
        private var pendingCompletions: [@MainActor () -> Void] = []
        var pendingSettleCount: Int { pendingCompletions.count }

        func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
            presentCount += 1
            isPresenting = true
        }

        func move(toScreenPoint p: NSPoint) {}

        func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void) {
            settleTargets.append(screenRect)
            pendingCompletions.append(completion)        // airborne until the test lands it
        }

        func dismiss() {
            dismissCount += 1
            isPresenting = false
        }

        /// Land the oldest airborne flight (FIFO — matches real completion order).
        func completeNextSettle() {
            guard !pendingCompletions.isEmpty else { return }
            pendingCompletions.removeFirst()()
        }
    }

    private var coordinator: LaunchpadDragCoordinator!
    private var spy: FlightSpy!
    private var window: NSWindow!
    private var applierCalls = 0
    /// Watchdog work captured by the injected scheduler (never auto-fires in tests).
    private var capturedTimeouts: [@MainActor () -> Void] = []

    override func setUp() {
        super.setUp()
        coordinator = LaunchpadDragCoordinator()
        spy = FlightSpy()
        let spy = self.spy!
        coordinator.floatingPresenterFactory = { spy }
        coordinator.storeApplier = { [weak self] _, _ in
            self?.applierCalls += 1
            return nil
        }
        coordinator.settleTimeoutScheduler = { [weak self] _, work in
            self?.capturedTimeouts.append(work)
            return DispatchWorkItem {}      // inert token; the captured work is fired manually
        }
        // Natural completions defer the dismiss one runloop turn in production (reveal paints
        // first). Run it inline here so the existing reveal-ordering assertions stay sharp;
        // the deferral itself is pinned by testNaturalCompletionDefersDismissBehindReveal.
        coordinator.settleDismissScheduler = { work in work() }
        // Borderless window at the screen origin so window space == screen space and the expected
        // settle rect can be computed by hand.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        applierCalls = 0
        capturedTimeouts = []
    }

    override func tearDown() {
        coordinator.cancelCarry(.shutdown)      // force-completes a settling session too
        coordinator = nil
        spy = nil
        window = nil
        capturedTimeouts = []
        super.tearDown()
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private var appA: LaunchpadAppItem { app("/Apps/A.app", "A") }
    private var appB: LaunchpadAppItem { app("/Apps/B.app", "B") }
    private var appC: LaunchpadAppItem { app("/Apps/C.app", "C") }
    private var threeApps: [LaunchpadDisplayCell] { [.app(appA), .app(appB), .app(appC)] }

    /// Root page container HOSTED IN A REAL WINDOW (the flight branch needs `container.window`
    /// for `convertToScreen`); onDragBegan mirrors production wiring (freeze the visible order).
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
        window.contentView?.addSubview(container)
        container.apply(grid: grid)
        container.layout()
        return container
    }

    /// Same window-space convention as the cross-page tests: viewport at (100, top 700).
    private func pushGeometry() {
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 1, perPage: 21,
            viewportMinX: 100, viewportTopY: 700))
    }

    /// The window point whose CarrySpace page-local image is `local`.
    private func windowPoint(forLocal local: NSPoint) -> NSPoint {
        NSPoint(x: local.x + 100, y: 700 - local.y)
    }

    @discardableResult
    private func lift(_ container: LaunchpadGridContainerView, cellAt index: Int) -> LaunchpadGridCellView {
        let cell = container.cellViews[index]
        let centre = NSPoint(x: cell.frame.midX, y: cell.frame.midY)
        container.beginDirectDrag(cell, atWindowPoint: windowPoint(forLocal: centre))
        return cell
    }

    /// Lift A, open the gap at C's right seam, release there → flight settle begins.
    /// Returns the anchor and the seam's local point.
    private func releaseIntoFlight(_ container: LaunchpadGridContainerView) -> LaunchpadGridCellView {
        let anchor = lift(container, cellAt: 0)
        let cFrame = container.cellViews[2].frame
        let seam = NSPoint(x: cFrame.maxX - 4, y: cFrame.midY)
        container.updateDirectDrag(atWindowPoint: windowPoint(forLocal: seam))
        XCTAssertNotNil(container.externalGapIndex)
        container.endDirectDrag(atWindowPoint: windowPoint(forLocal: seam))
        return anchor
    }

    // MARK: - Flight starts at release; reveal waits for the completion (design §7.3)

    func testReleaseStartsFlightAndParksUntilCompletion() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        let framesBefore = container.cellViews.map(\.frame)

        let anchor = lift(container, cellAt: 0)
        let cFrame = container.cellViews[2].frame
        let seam = NSPoint(x: cFrame.maxX - 4, y: cFrame.midY)
        container.updateDirectDrag(atWindowPoint: windowPoint(forLocal: seam))
        XCTAssertEqual(container.externalGapIndex, 2, "C 右缝 → gap 在末位（active indexing）")
        let gapFrames = container.cellViews.map(\.frame)

        container.endDirectDrag(atWindowPoint: windowPoint(forLocal: seam))

        // DATA: landed synchronously in mouseUp, exactly once — settle is pure visual.
        XCTAssertEqual(applierCalls, 1)
        XCTAssertEqual(coordinator.commitToken, 1, "视觉 token 在 mouseUp 即 bump，不等飞行")

        // SESSION: survives in .settling — every input-freeze gate keys on session != nil.
        XCTAssertEqual(coordinator.carrySession?.state, .settling(generation: 1))
        XCTAssertEqual(coordinator.settlingItemID, appA.id)
        XCTAssertFalse(coordinator.carryActive, "虚拟尾页在 mouseUp 即收回")
        XCTAssertTrue(coordinator.hasFloatingWindow, "浮窗飞行中，不得提前拆除")
        XCTAssertEqual(spy.dismissCount, 0)

        // FLIGHT TARGET: gap slot 2's icon rect → CarrySpace window rect → screen (window at 0,0).
        // local icon rect = (268+26, 8, 64, 64); window x = 100+294, y = 700−(8+64).
        XCTAssertEqual(spy.settleTargets, [NSRect(x: 394, y: 628, width: 64, height: 64)],
                       "目标矩形必须经 CarrySpace.windowRect + convertToScreen，禁 convert 进 offset 容器")

        // FREEZE, not end: the make-way frames hold still at release (no double move, BR-5).
        XCTAssertFalse(container.externalDragActive)
        XCTAssertEqual(container.cellViews.map(\.frame), gapFrames, "释放瞬间让位 frame 原地冻结")

        // PARKED through any number of layout passes — only the reveal un-parks (AC-3).
        for _ in 0..<3 { container.layout() }
        XCTAssertEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "飞行期间锚必须保持停泊（防双影）")

        // COMPLETION lands the flight: reveal + dismiss + session gone.
        spy.completeNextSettle()
        XCTAssertNil(coordinator.carrySession)
        XCTAssertNil(coordinator.settlingItemID)
        XCTAssertEqual(spy.dismissCount, 1, "reveal 之后才拆浮窗")
        XCTAssertEqual(anchor.frame, framesBefore[0],
                       "reveal 必须把锚写回真实槽位（单测无 SwiftUI apply，即其原槽）")
    }

    // MARK: - Stale generation (AR-6)

    func testStaleSettleCompletionIsIgnoredAfterRelift() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let anchorA = releaseIntoFlight(container)
        XCTAssertEqual(spy.pendingSettleCount, 1)

        // Re-lift B while the flight is airborne (§1.2 settling × lift): the gesture boundary
        // force-completes the old settle BEFORE the container parks the new anchor.
        let anchorB = lift(container, cellAt: 1)
        XCTAssertNotEqual(anchorA.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "force-complete 必须先 reveal 旧锚")
        XCTAssertEqual(coordinator.carrySession?.itemID, appB.id)
        XCTAssertEqual(coordinator.carrySession?.isCarrying, true)
        XCTAssertEqual(anchorB.frame.origin, LaunchpadGridContainerView.carryParkOrigin)
        XCTAssertEqual(spy.dismissCount, 1, "旧浮窗拆除")
        XCTAssertEqual(spy.presentCount, 2, "新会话照常建浮窗")

        // The OLD flight's animation completion straggles in → stale generation → no-op.
        spy.completeNextSettle()
        XCTAssertEqual(coordinator.carrySession?.itemID, appB.id, "stale 回调不得拆新会话")
        XCTAssertEqual(coordinator.carrySession?.isCarrying, true)
        XCTAssertTrue(spy.isPresenting, "stale 回调不得拆新会话的浮窗")
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertEqual(anchorB.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "stale 回调不得 un-park 新锚")
    }

    // MARK: - Watchdog timeout (design §7.3-4)

    func testSettleTimeoutForcesRevealWhenCompletionNeverArrives() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let anchor = releaseIntoFlight(container)
        XCTAssertEqual(capturedTimeouts.count, 1, "飞行必须武装超时兜底")
        XCTAssertNotNil(coordinator.carrySession)

        capturedTimeouts[0]()                       // completion lost; the watchdog fires

        XCTAssertNil(coordinator.carrySession)
        XCTAssertNil(coordinator.settlingItemID)
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "超时必须强制 reveal——图标不可永久隐身")

        // The real completion straggles in afterwards → stale → no-op.
        spy.completeNextSettle()
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertNil(coordinator.carrySession)
    }

    // MARK: - cancel(settling) fast-forwards (§1.2 / §9.1 rows 2 & 7)

    func testCancelDuringSettlingFastForwardsRevealWithoutSecondWrite() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let anchor = releaseIntoFlight(container)
        XCTAssertEqual(applierCalls, 1)

        coordinator.cancelCarry(.overlayClosed)     // overlay closing mid-flight

        XCTAssertNil(coordinator.carrySession)
        XCTAssertNil(coordinator.settlingItemID)
        XCTAssertEqual(spy.dismissCount, 1, "快进必须拆浮窗（浮窗不得在 overlay 关闭后存活）")
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "快进必须立即 reveal")
        XCTAssertEqual(applierCalls, 1, "数据已在 mouseUp 落库——cancel(settling) 零写")
        XCTAssertEqual(coordinator.endReason, .committed, "数据已提交，endReason 不得改写为 cancelled")
        XCTAssertTrue(coordinator.canBeginCarry, "settling 快进不拍孤儿闩——下一手势必须能 lift")
    }

    // MARK: - Settling never hands off (§1.2 settling × containerRegistered / funnel)

    func testSettlingRegistrationAndFunnelDoNotHandoff() {
        let c0 = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        releaseIntoFlight(c0)
        XCTAssertEqual(coordinator.carrySession?.isCarrying, false)

        // A page container registering mid-settling must NOT be engaged (no make-way begins)…
        let c1 = makePage([.app(app("/Apps/D.app", "D"))], page: 1)
        XCTAssertFalse(c1.externalDragActive, "settling 期注册不得触发 handoff")

        // …and neither must the currentPage funnel.
        coordinator.currentPageDidChange(1)
        XCTAssertFalse(c1.externalDragActive, "settling 期漏斗不得 engage 新容器")
        XCTAssertNil(coordinator.flipRequest)

        spy.completeNextSettle()
        XCTAssertNil(coordinator.carrySession)
    }

    // MARK: - Direct beginCarry during settling (non-grid entry) force-completes first

    func testDirectBeginCarryDuringSettlingForceCompletesOldSettle() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let anchor = releaseIntoFlight(container)
        XCTAssertEqual(spy.pendingSettleCount, 1)

        // A folder-origin carry opened straight through beginCarry (the late-eject entry) while
        // the previous settle is airborne: fast-forward it, then open fresh.
        coordinator.freezeVisibleOrder(threeApps)
        let opened = coordinator.beginCarry(itemID: "/Apps/Z.app",
                                            origin: .folder(sourceFolderID: "F1"), isApp: true,
                                            icon: nil, iconSide: 64,
                                            atScreenPoint: .zero, aboveLevel: .normal)
        XCTAssertTrue(opened, "settling 期重入 lift 必须 force-complete 后开新会话")
        XCTAssertEqual(coordinator.carrySession?.itemID, "/Apps/Z.app")
        XCTAssertEqual(coordinator.carrySession?.isCarrying, true)
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "旧 settle 的锚必须已 reveal")
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertEqual(spy.presentCount, 2)
    }

    // MARK: - Engaged-but-empty virtual tail page → hard-cut, never a flight (§6.2 snap-back race)

    func testReleaseOnEngagedEmptyVirtualTailPageTakesHardCut() {
        var applied: [CarryStoreAction] = []
        coordinator.storeApplier = { action, _ in applied.append(action); return nil }
        let source = makePage(threeApps, page: 0)
        // Production mounts a REAL empty container for the virtual tail (displayPageCount renders
        // an empty items slice), windowed and registered — NOT the unregistered-page fallback the
        // cross-page test covers. The funnel handoff therefore ENGAGES it (externalDragActive).
        let virtualTail = makePage([], page: 1)
        pushGeometry()                                       // pageCount == 1 → index 1 IS the virtual tail
        coordinator.currentPageDidChange(0)

        let anchor = lift(source, cellAt: 0)
        coordinator.currentPageDidChange(1)                  // dwell flip → funnel hands off to the tail
        XCTAssertTrue(virtualTail.externalDragActive, "前提：虚拟尾页容器确实被 engage（生产路径）")
        XCTAssertFalse(source.externalDragActive, "源页让位已收口")

        let drop = NSPoint(x: 450, y: 300)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: drop))
        source.endDirectDrag(atWindowPoint: windowPoint(forLocal: drop))

        // DATA: global-tail semantics, unchanged by the visual branch choice.
        XCTAssertEqual(applied, [.move(id: appA.id, target: .after(appC.id))],
                       "虚拟空页松手 = 对冻结快照末项的全局落尾（§6.2）")

        // VISUAL: hard-cut in the mouseUp stack. A slot-0 flight would race the §6.2 snap-back —
        // the virtual page collapses at mouseUp while currentPage animates home, and the landed
        // cell reveals at the LAST REAL page's tail, nowhere near the collapsing page's slot 0.
        XCTAssertEqual(spy.settleTargets, [], "engaged 空虚拟页 release 不得起飞")
        XCTAssertEqual(spy.pendingSettleCount, 0)
        XCTAssertTrue(capturedTimeouts.isEmpty, "hard-cut 不武装超时兜底")
        XCTAssertFalse(coordinator.hasFloatingWindow, "浮窗必须在 mouseUp 栈内同步拆除")
        XCTAssertEqual(spy.dismissCount, 1)
        XCTAssertNil(coordinator.carrySession)
        XCTAssertNil(coordinator.settlingItemID)
        XCTAssertFalse(virtualTail.externalDragActive, "engaged 空容器在 hard-cut 中收口")
        source.layout()
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "hard-cut 必须同步 reveal 锚——不许等一个不存在的飞行")
    }

    // MARK: - Parked through the post-commit apply (§7.3-2: rebuild parks the landed cell)

    func testPostCommitApplyParksLandedCellUntilReveal() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        releaseIntoFlight(container)                 // data: A moves after C

        // Simulate the store-driven SwiftUI apply landing mid-flight with the NEW model on a
        // NON-source page container (the cross-page case: that container is not isDragging, so
        // the apply runs immediately and must park the landed cell).
        let target = makePage([.app(appB), .app(appC), .app(appA)], page: 1)
        let landed = target.cellViews[2]
        XCTAssertEqual(landed.layoutID, appA.id)
        XCTAssertEqual(landed.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "post-commit apply 必须把落位 cell 停泊（飞行期不得提前现身=双影）")
        for _ in 0..<3 { target.layout() }
        XCTAssertEqual(landed.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "停泊期间任何 layout pass 都不得把 settling cell 写回槽位")

        spy.completeNextSettle()
        XCTAssertNotEqual(landed.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "reveal 广播必须 un-park 落位 cell")
        XCTAssertNil(coordinator.carrySession)
    }

    // MARK: - Merge settle parks the NEW FOLDER cell (§A1: the landed cell is the folder, not the app)

    /// Lift A and release on B's CENTRE (armed merge) → flight settle with a makeFolder commit.
    private func releaseIntoMergeFlight(_ container: LaunchpadGridContainerView) {
        lift(container, cellAt: 0)
        let bCentre = NSPoint(x: container.cellViews[1].frame.midX,
                              y: container.cellViews[1].frame.midY)
        container.updateDirectDrag(atWindowPoint: windowPoint(forLocal: bCentre))
        XCTAssertNotNil(container.stackTargetCell, "B 中心必须 arm merge")
        container.endDirectDrag(atWindowPoint: windowPoint(forLocal: bCentre))
    }

    func testMakeFolderCommitParksNewFolderCellUntilReveal() {
        let newFolderID = "FOLDER-NEW"
        coordinator.storeApplier = { [weak self] action, _ in
            self?.applierCalls += 1
            if case .makeFolder = action { return newFolderID }   // production: the new folder UUID
            return nil
        }
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        releaseIntoMergeFlight(container)
        XCTAssertEqual(applierCalls, 1)
        XCTAssertEqual(coordinator.settlingItemID, newFolderID,
                       "merge 建夹后顶层不存在被拖 app 的 cell——停泊谓词必须改记新夹 id（§A1 闪烁根因）")

        // Post-commit apply lands mid-flight on a non-source page with the NEW model: the fresh
        // folder cell (new UUID) must park until the reveal, or it pops in under the flying icon.
        let folderCell = LaunchpadDisplayCell.folder(id: newFolderID, name: "未命名", items: [appB, appA])
        let target = makePage([folderCell, .app(appC)], page: 1)
        let landedFolder = target.cellViews[0]
        XCTAssertEqual(landedFolder.layoutID, newFolderID)
        XCTAssertEqual(landedFolder.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "新夹 cell 必须停泊到 reveal（飞行中现身=先看到夹再看到落点闪烁）")
        for _ in 0..<3 { target.layout() }
        XCTAssertEqual(landedFolder.frame.origin, LaunchpadGridContainerView.carryParkOrigin)

        spy.completeNextSettle()
        XCTAssertNil(coordinator.settlingItemID)
        XCTAssertNotEqual(landedFolder.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "reveal 必须把新夹 cell 写回真实槽位")
    }

    /// 19/P0a step 5 (design §2.6, R1=B): a merge commit's auto-open trigger must ride the
    /// settle REVEAL — publishing at mouseUp would mount the folder panel under the still-
    /// flying icon and fight the park visuals.
    func testMergeFlightPublishesFolderRevealOnlyAtReveal() {
        coordinator.storeApplier = { action, _ in
            if case .makeFolder = action { return "FOLDER-NEW" }
            return nil
        }
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        releaseIntoMergeFlight(container)
        XCTAssertEqual(coordinator.pendingVisualCommit?.createdFolderID, "FOLDER-NEW")
        XCTAssertEqual(coordinator.folderRevealToken, 0, "飞行中不得发布自动开夹")
        XCTAssertNil(coordinator.revealedFolderID)

        spy.completeNextSettle()
        XCTAssertEqual(coordinator.folderRevealToken, 1, "reveal 完成处恰好发布一次")
        XCTAssertEqual(coordinator.revealedFolderID, "FOLDER-NEW")
    }

    func testReorderFlightPublishesNoFolderReveal() {
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        releaseIntoFlight(container)                      // plain reorder commit (applier → nil)
        spy.completeNextSettle()
        XCTAssertEqual(coordinator.folderRevealToken, 0, "重排 reveal 不触发自动开夹")
    }

    func testAddToFolderCommitKeepsParkingTheCarriedItemID() {
        // addToFolder's landing cell is an EXISTING folder — parking it would blank a visible
        // folder for the whole flight. The park id must stay the carried app's.
        coordinator.storeApplier = { [weak self] _, _ in
            self?.applierCalls += 1
            return "F-EXISTING"
        }
        let folder = LaunchpadDisplayCell.folder(id: "F-EXISTING", name: "夹", items: [appB])
        let container = makePage([.app(appA), folder, .app(appC)], page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        lift(container, cellAt: 0)
        let fCentre = NSPoint(x: container.cellViews[1].frame.midX,
                              y: container.cellViews[1].frame.midY)
        container.updateDirectDrag(atWindowPoint: windowPoint(forLocal: fCentre))
        XCTAssertNotNil(container.stackTargetCell)
        container.endDirectDrag(atWindowPoint: windowPoint(forLocal: fCentre))

        XCTAssertEqual(coordinator.settlingItemID, appA.id,
                       "addToFolder 停泊的是被拖 app（现存夹 cell 必须全程可见）")
        spy.completeNextSettle()
        XCTAssertNil(coordinator.settlingItemID)
    }

    // MARK: - Dismiss defers behind the reveal's paint (§A1 same-page flicker: orderOut beats CA commit)

    func testNaturalCompletionDefersDismissBehindReveal() {
        var deferredDismissals: [@MainActor () -> Void] = []
        coordinator.settleDismissScheduler = { deferredDismissals.append($0) }
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let anchor = releaseIntoFlight(container)
        spy.completeNextSettle()

        // Reveal is fully synchronous — only the floating window's teardown waits a turn, so
        // the freshly applied/parked cell's first paint lands before orderOut hits the server.
        XCTAssertNil(coordinator.carrySession)
        XCTAssertNil(coordinator.settlingItemID)
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "reveal 不得被推迟——只推迟浮窗拆除")
        XCTAssertEqual(spy.dismissCount, 0, "自然完成路径 dismiss 必须延一拍（先画落位 cell）")
        XCTAssertEqual(deferredDismissals.count, 1)

        deferredDismissals[0]()
        XCTAssertEqual(spy.dismissCount, 1)
    }

    func testForceCompleteDismissesSynchronouslyForRelift() {
        var deferredDismissals: [@MainActor () -> Void] = []
        coordinator.settleDismissScheduler = { deferredDismissals.append($0) }
        let container = makePage(threeApps, page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        releaseIntoFlight(container)
        // Re-lift while airborne: the old floating window must die IN THIS STACK — the new
        // session presents its own window next, and a deferred teardown would double the icon.
        lift(container, cellAt: 1)
        XCTAssertEqual(spy.dismissCount, 1, "force-complete 必须同步拆旧浮窗")
        XCTAssertTrue(deferredDismissals.isEmpty, "force-complete 不走延迟通道")
        XCTAssertEqual(coordinator.carrySession?.itemID, appB.id)
    }
}
