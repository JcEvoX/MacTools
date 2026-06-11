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
}
