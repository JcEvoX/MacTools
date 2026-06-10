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

    func testPageFunnelSwitchesActiveContainer() {
        let (c0, _) = makePage(threeApps(), page: 0)
        let (c1, _) = makePage(threeApps(), page: 1)
        pushGeometry()
        coordinator.currentPageDidChange(0)

        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        let centre0 = NSPoint(x: c0.cellViews[0].frame.midX, y: c0.cellViews[0].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre0))
        XCTAssertTrue(c0.stackTargetCell === c0.cellViews[0])

        // Pre-handoff (step 4) the new page gets no beginExternalDrag — routing still must follow
        // the funnel so updates stop reaching the old page (today's behaviour, made explicit).
        coordinator.currentPageDidChange(1)
        let centre1 = NSPoint(x: c1.cellViews[2].frame.midX, y: c1.cellViews[2].frame.midY)
        coordinator.moveEject(atScreenPoint: .zero, atWindowPoint: windowPoint(forLocal: centre1))
        XCTAssertNil(c1.stackTargetCell, "page 1 容器未收到 beginExternalDrag（handoff 是步骤 4）——不得让位")
        XCTAssertTrue(c0.stackTargetCell === c0.cellViews[0], "旧页状态冻结，等步骤 4 的 handoff 收口")
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
