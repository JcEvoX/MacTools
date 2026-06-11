import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Step-2 wiring of the cross-page carry design (§3/§5): the per-page container registry, the
/// pushed page-geometry snapshot, and the coordinator routing external-drag classification to the
/// CURRENT page's container through explicit `LaunchpadCarrySpace` arithmetic instead of `convert`
/// (which is blind to the SwiftUI paging offset — the page>0 eject-drop bug).
@MainActor
final class LaunchpadCrossPageCarryTests: XCTestCase {

    private var coordinator: LaunchpadDragCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = LaunchpadDragCoordinator()
    }

    override func tearDown() {
        coordinator.cancelEject()       // never leak a floating window across tests
        coordinator = nil
        super.tearDown()
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func makePage(
        _ items: [LaunchpadDisplayCell],
        page: Int?
    ) -> (container: LaunchpadGridContainerView, grid: LaunchpadDragGrid) {
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
            // Mirrors production wiring: a beginning drag freezes the visible order into the
            // coordinator so a root lift's session adopts it (LaunchpadGridView.pageContent).
            onDragBegan: { [coordinator] in coordinator?.freezeVisibleOrder(items) },
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
        return (container, grid)
    }

    private func threeApps() -> [LaunchpadDisplayCell] {
        [.app(app("/Apps/A.app", "A")), .app(app("/Apps/B.app", "B")), .app(app("/Apps/C.app", "C"))]
    }

    /// Window-space geometry used across the routing tests: viewport at (100, top 700), 900pt pages.
    private func pushGeometry() {
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 2, perPage: 21,
            viewportMinX: 100, viewportTopY: 700))
    }

    /// The window point whose CarrySpace page-local image is `local`.
    private func windowPoint(forLocal local: NSPoint) -> NSPoint {
        NSPoint(x: local.x + 100, y: 700 - local.y)
    }

    // MARK: - Registry

    func testContainersRegisterByPageAndUnregisterOnUnmount() {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        XCTAssertEqual(coordinator.registeredPageIndices, [0, 1])

        c0.viewWillMove(toWindow: nil)                       // page-count shrink / overlay teardown
        XCTAssertEqual(coordinator.registeredPageIndices, [1])
        _ = c1   // keep alive until the assertion above
    }

    func testFolderGridsNeverRegister() {
        _ = makePage(threeApps(), page: nil)                 // folder grid: pageIndex nil
        XCTAssertEqual(coordinator.registeredPageIndices, [])
    }

    func testRegistrationSurvivesActiveDragOnReapply() {
        let (c0, grid) = makePage(threeApps(), page: 0)
        coordinator.unregisterPageContainer(c0)
        XCTAssertEqual(coordinator.registeredPageIndices, [])

        c0.beginDirectDrag(c0.cellViews[0], atWindowPoint: .zero)   // isDragging → apply defers cells…
        c0.apply(grid: grid)
        XCTAssertEqual(coordinator.registeredPageIndices, [0],
                       "注册必须在 isDragging guard 之前：拖拽中翻走再翻回源页要能重注册（§3.1）")
        c0.endDirectDrag(atWindowPoint: .zero)
    }

    // MARK: - Cross-page routing through CarrySpace (the page>0 fix)

    func testMoveEjectClassifiesAgainstCurrentPageWithPageLocalPoint() {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(1)                  // viewer is on page 1

        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre = NSPoint(x: c1.cellViews[1].frame.midX, y: c1.cellViews[1].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre))

        XCTAssertTrue(c1.stackTargetCell === c1.cellViews[1],
                      "window 点必须经 CarrySpace 显式算术变成 page-local 再喂当前页容器——convert 在 page>0 偏差 page×pageWidth")
        XCTAssertNil(c0.stackTargetCell, "分类只喂当前页的容器")
    }

    func testCommitOutResolvesOnCurrentPageContainer() {
        let (_, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(1)

        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre = NSPoint(x: c1.cellViews[1].frame.midX, y: c1.cellViews[1].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre))
        let tokenBefore = coordinator.ejectToken
        coordinator.commitOut(folderID: "F1", appID: "/Apps/X.app",
                              atWindowPoint: windowPoint(forLocal: centre))

        XCTAssertEqual(coordinator.pendingEject?.result, .makeFolder(targetAppID: c1.cellViews[1].layoutID))
        XCTAssertEqual(coordinator.ejectToken, tokenBefore + 1)
        XCTAssertFalse(coordinator.hasFloatingWindow, "commit 后浮窗必须拆除")
    }

    // MARK: - Handoff (design §3, step 4)

    func testPageFunnelHandsOffGapToNewContainer() {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre0 = NSPoint(x: c0.cellViews[0].frame.midX, y: c0.cellViews[0].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre0))
        XCTAssertTrue(c0.stackTargetCell === c0.cellViews[0])
        XCTAssertTrue(c0.externalDragActive)

        coordinator.currentPageDidChange(1)
        XCTAssertFalse(c0.externalDragActive, "旧页 gap 必须在 handoff 时收口（gap1 残留缺陷）")
        XCTAssertNil(c0.stackTargetCell)
        XCTAssertTrue(c1.externalDragActive, "新页容器必须收到 beginExternalDrag 接管让位")

        // The last cursor point is replayed into the NEW container — its merge/gap opens without
        // waiting for the next mouse event. The replayed local point is centre0, which maps onto
        // the same slot geometry in c1.
        XCTAssertTrue(c1.stackTargetCell === c1.cellViews[0], "handoff 必须重喂 last 点，新页立即让位/arm")
    }

    func testFlipAwayAndBackReengagesOriginalContainer() {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre = NSPoint(x: c0.cellViews[1].frame.midX, y: c0.cellViews[1].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre))

        coordinator.currentPageDidChange(1)
        coordinator.currentPageDidChange(0)
        XCTAssertFalse(c1.externalDragActive, "翻回后 page 1 的让位必须收口")
        XCTAssertTrue(c0.externalDragActive, "翻回后原页容器重新接管")
        XCTAssertTrue(c0.stackTargetCell === c0.cellViews[1], "重喂 last 点恢复原 arm")
    }

    func testLateRegistrationAfterFlipTakesOverViaReattach() {
        let (c0, _) = makePage(threeApps(), page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre = NSPoint(x: c0.cellViews[0].frame.midX, y: c0.cellViews[0].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre))

        coordinator.currentPageDidChange(1)                  // no page-1 container registered yet
        XCTAssertFalse(c0.externalDragActive, "旧页让位先收口，即使新页容器还没到")

        let (c1, _) = makePage(threeApps(), page: 1)         // late mount → registers → reattach
        XCTAssertTrue(c1.externalDragActive, "迟到注册的目标页容器必须经 reattach 补 beginExternalDrag（AT-4）")
        XCTAssertTrue(c1.stackTargetCell === c1.cellViews[0], "reattach 同样重喂 last 点")
    }

    func testSamePageContainerSwapReattachesByIdentity() {
        let (c0, _) = makePage(threeApps(), page: 0)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre = NSPoint(x: c0.cellViews[0].frame.midX, y: c0.cellViews[0].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre))
        XCTAssertTrue(c0.externalDragActive)

        let (c0b, _) = makePage(threeApps(), page: 0)        // same page, NEW container instance
        XCTAssertFalse(c0.externalDragActive, "同页换容器：旧实例让位收口（身份比较，不是页号）")
        XCTAssertTrue(c0b.externalDragActive, "新实例接管")
    }

    // MARK: - Edge-dwell flips (design §4, step 5)

    private func startCarryOnPage0WithClock() -> (c0: LaunchpadGridContainerView, c1: LaunchpadGridContainerView) {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        return (c0, c1)
    }

    /// Right-edge page-local point (zone is x > pageWidth − 44 = 856).
    private func rightEdgeLocal() -> NSPoint { NSPoint(x: 880, y: 300) }

    func testEdgeDwellPublishesFlipAndSuspendsClassification() {
        var fakeNow: TimeInterval = 0
        coordinator.now = { fakeNow }
        coordinator.dwellTimerFactory = { _ in nil }
        let (c0, c1) = startCarryOnPage0WithClock()

        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertNil(coordinator.flipRequest, "进区即 arm，不立即翻")

        fakeNow = 0.71
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertEqual(coordinator.flipRequest?.targetPage, 1, "驻留 0.7s 应发布右翻请求")
        XCTAssertEqual(coordinator.carrySession?.state, .carrying(.awaitingHandoff(targetPage: 1)))

        // Classification is suspended while the flip is in flight: a move over a cell centre on
        // the (still engaged) old page must not arm a merge.
        let centre = NSPoint(x: c0.cellViews[1].frame.midX, y: c0.cellViews[1].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre))
        XCTAssertNil(c0.stackTargetCell, "awaitingHandoff 期间不喂分类")

        // The funnel (GridView's goToPage → currentPage onChange) completes the handoff.
        coordinator.currentPageDidChange(1)
        XCTAssertEqual(coordinator.carrySession?.state, .carrying(.tracking), "handoff 后恢复 tracking")
        XCTAssertTrue(c1.externalDragActive)
    }

    func testLastRealPageFlipsToVirtualTailWhenEditable() {
        var fakeNow: TimeInterval = 0
        coordinator.now = { fakeNow }
        coordinator.dwellTimerFactory = { _ in nil }
        let (_, c1) = startCarryOnPage0WithClock()
        coordinator.currentPageDidChange(1)                  // hand off to the LAST real page
        XCTAssertTrue(c1.externalDragActive)

        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        fakeNow = 0.71
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertEqual(coordinator.flipRequest?.targetPage, 2,
                       "末真页右缘驻留必须能翻到虚拟尾页（index == pageCount，§6.1）")

        // The funnel hands off to the (empty) virtual page; the old page's gap closes and the
        // release there resolves to the tail via the resolve branch (§6.2).
        coordinator.currentPageDidChange(2)
        XCTAssertFalse(c1.externalDragActive, "翻到虚拟页后末真页让位收口")
        coordinator.commitOut(folderID: "F1", appID: "/Apps/X.app",
                              atWindowPoint: windowPoint(forLocal: NSPoint(x: 450, y: 300)))
        XCTAssertEqual(coordinator.pendingEject?.result, .reorder(nil), "虚拟空页松手 = 全局落尾语义")
    }

    func testVirtualTailFlipBlockedWhenNotEditable() {
        var fakeNow: TimeInterval = 0
        coordinator.now = { fakeNow }
        coordinator.dwellTimerFactory = { _ in nil }
        let (c0, _) = makePage(threeApps(), page: 0)
        let (_, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(1)
        coordinator.freezeVisibleOrder([], editable: false)  // search-like read-only projection
        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)

        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        fakeNow = 0.71
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertNil(coordinator.flipRequest, "不可编辑会话不得翻出虚拟尾页（displayPageCount 不 +1）")
        XCTAssertEqual(coordinator.carrySession?.state, .carrying(.tracking))
        _ = c0
    }

    func testStationaryCursorFiresViaDwellTick() {
        var fakeNow: TimeInterval = 0
        coordinator.now = { fakeNow }
        coordinator.dwellTimerFactory = { _ in nil }
        _ = startCarryOnPage0WithClock()

        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        fakeNow = 0.71
        coordinator.tickDwell()                              // mouse holds still: the tick is the driver
        XCTAssertEqual(coordinator.flipRequest?.targetPage, 1, "光标静止时 30Hz tick 必须能独立驱动 dwell")
    }

    func testReleaseWithdrawsFlipRequest() {
        var fakeNow: TimeInterval = 0
        coordinator.now = { fakeNow }
        coordinator.dwellTimerFactory = { _ in nil }
        _ = startCarryOnPage0WithClock()
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        fakeNow = 0.71
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertNotNil(coordinator.flipRequest)

        coordinator.commitOut(folderID: "F1", appID: "/Apps/X.app",
                              atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertNil(coordinator.flipRequest, "release 必须先撤销未消费的翻页请求（§1.4-4）")
    }

    func testCancelStopsDwellTimerAndWithdrawsFlip() {
        var fakeNow: TimeInterval = 0
        coordinator.now = { fakeNow }
        coordinator.dwellTimerFactory = { tick in Timer(timeInterval: 999, repeats: true) { _ in } }
        _ = startCarryOnPage0WithClock()
        XCTAssertTrue(coordinator.isDwellTimerRunning, "carry 开始即启动 dwell timer")

        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        fakeNow = 0.71
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: rightEdgeLocal()))
        XCTAssertNotNil(coordinator.flipRequest)

        coordinator.cancelCarry(.shutdown)
        XCTAssertNil(coordinator.flipRequest, "cancel 必须撤销未消费的翻页请求")
        XCTAssertFalse(coordinator.isDwellTimerRunning, "cancel 必须停 dwell timer")
    }

    func testHandoffIsInertWithoutASession() {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(1)
        coordinator.currentPageDidChange(0)
        XCTAssertFalse(c0.externalDragActive)
        XCTAssertFalse(c1.externalDragActive, "无会话时漏斗只更新页号，不得触碰任何容器")
    }

    func testColdStartBeforeGeometryPushFallsBackToWindowPath() {
        let (c0, _) = makePage(threeApps(), page: 0)
        coordinator.currentPageDidChange(0)                  // no syncGeometry: cold start

        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        // Windowless containers treat the legacy window point as container-local (test seam).
        let centre = NSPoint(x: c0.cellViews[1].frame.midX, y: c0.cellViews[1].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: centre)
        XCTAssertTrue(c0.stackTargetCell === c0.cellViews[1], "几何未推送时退回 legacy 路径，不得丢拖拽")
    }

    // MARK: - Root-page origin (step 7: the root lift rides the same carry machinery)

    private func pageTwoApps() -> [LaunchpadDisplayCell] {
        [.app(app("/Apps/D.app", "D")), .app(app("/Apps/E.app", "E")), .app(app("/Apps/F.app", "F"))]
    }

    /// Lift `cells[index]` on a root page through the container's real entry point.
    private func rootLift(_ container: LaunchpadGridContainerView, cellAt index: Int,
                          windowPoint: NSPoint) -> LaunchpadGridCellView {
        let cell = container.cellViews[index]
        container.beginDirectDrag(cell, atWindowPoint: windowPoint)
        return cell
    }

    func testRootCarryHandsOffAcrossPagesAndResolvesOnTargetPage() {
        var applied: [CarryStoreAction] = []
        coordinator.storeApplier = { action, _ in applied.append(action); return nil }
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(pageTwoApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let c0Frame0 = c0.cellViews[0].frame
        let liftLocal = NSPoint(x: c0Frame0.midX, y: c0Frame0.midY)
        let anchor = rootLift(c0, cellAt: 0, windowPoint: windowPoint(forLocal: liftLocal))

        XCTAssertTrue(coordinator.carryActive)
        XCTAssertEqual(coordinator.carrySession?.origin, .rootPage)
        XCTAssertTrue(c0.externalDragActive)
        XCTAssertEqual(c0.externalGapIndex, 0, "seedGap = 锚原槽")

        coordinator.currentPageDidChange(1)                  // handoff to page 1
        XCTAssertFalse(c0.externalDragActive, "源页让位收口")
        XCTAssertTrue(c1.externalDragActive, "目标页接管让位")
        c0.layout()
        XCTAssertEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                       "handoff 后锚仍停泊在源容器里")
        XCTAssertEqual(c0.cellViews[1].frame, c0Frame0, "源页紧凑无洞：B 补进锚的槽")

        // Classify + release on page 1: E's right seam → data resolves against the TARGET page.
        let seam = NSPoint(x: c1.cellViews[1].frame.maxX - 4, y: c1.cellViews[1].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: seam))
        XCTAssertNotNil(c1.externalGapIndex, "新页让位 gap 必须打开")
        c0.endDirectDrag(atWindowPoint: windowPoint(forLocal: seam))   // mouseUp 仍到源容器

        XCTAssertEqual(applied, [.move(id: "/Apps/A.app", target: .after("/Apps/E.app"))],
                       "跨页落点必须按目标页让位 gap 解析并同步写库")
        XCTAssertNil(coordinator.carrySession)
        XCTAssertFalse(c1.externalDragActive, "commit 后目标页让位收口")
        c0.layout()
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "commit 后锚必须 reveal（不许永久隐身）")
    }

    func testRootCarryVirtualTailReleaseLandsAtGlobalTail() {
        var applied: [CarryStoreAction] = []
        coordinator.storeApplier = { action, _ in applied.append(action); return nil }
        let (c0, _) = makePage(threeApps(), page: 0)
        // One REAL page; index 1 is the virtual tail (editable session → flippable, §6.1).
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 1, perPage: 21,
            viewportMinX: 100, viewportTopY: 700))
        coordinator.currentPageDidChange(0)

        let frame0 = c0.cellViews[0].frame
        let anchor = rootLift(c0, cellAt: 0,
                              windowPoint: windowPoint(forLocal: NSPoint(x: frame0.midX, y: frame0.midY)))

        coordinator.currentPageDidChange(1)                  // virtual tail page (no container)
        XCTAssertFalse(c0.externalDragActive, "翻到虚拟页后源页让位收口")

        // Release over the empty virtual page: no engaged container → global-tail semantics.
        c0.endDirectDrag(atWindowPoint: windowPoint(forLocal: NSPoint(x: 450, y: 300)))
        XCTAssertEqual(applied, [.move(id: "/Apps/A.app", target: .after("/Apps/C.app"))],
                       "虚拟空页松手 = 对冻结快照末项的全局落尾（§6.2 有意分歧）")
        c0.layout()
        XCTAssertNotEqual(anchor.frame.origin, LaunchpadGridContainerView.carryParkOrigin,
                          "落尾 commit 后锚必须 reveal")
    }

    func testCarriedFolderNeverArmsMergeAnywhere() {
        let folder = LaunchpadDisplayCell.folder(id: "F9", name: "夹", items: [app("/Apps/X.app", "X")])
        let items: [LaunchpadDisplayCell] = [folder, .app(app("/Apps/A.app", "A")), .app(app("/Apps/B.app", "B"))]
        let (c0, _) = makePage(items, page: 0)
        let (c1, _) = makePage(pageTwoApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        let folderFrame = c0.cellViews[0].frame
        _ = rootLift(c0, cellAt: 0,
                     windowPoint: windowPoint(forLocal: NSPoint(x: folderFrame.midX, y: folderFrame.midY)))
        XCTAssertEqual(coordinator.carrySession?.isApp, false, "被携带的是夹")

        // Hover an app's CENTRE on the source page: must never arm (no nested folders).
        let aCentre = NSPoint(x: c0.cellViews[1].frame.midX, y: c0.cellViews[1].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: aCentre))
        XCTAssertNil(c0.stackTargetCell, "被携带 folder 在源页永不 arm merge")

        // …and the same holds after a handoff (the engage primitive forwards allowsMerge).
        coordinator.currentPageDidChange(1)
        let dCentre = NSPoint(x: c1.cellViews[0].frame.midX, y: c1.cellViews[0].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: dCentre))
        XCTAssertNil(c1.stackTargetCell, "handoff 后被携带 folder 仍永不 arm merge")

        // Reorder seams still work for a carried folder.
        let seam = NSPoint(x: c1.cellViews[0].frame.maxX - 4, y: c1.cellViews[0].frame.midY)
        coordinator.carryMoved(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: seam))
        XCTAssertNotNil(c1.externalGapIndex, "夹照常可重排让位")
    }
}
