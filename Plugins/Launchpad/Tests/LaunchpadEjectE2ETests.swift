import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// End-to-end folder-eject harness with a REAL NSWindow — the audit gap ("eject E2E 真窗口链路无
/// 自动化覆盖"). beginEject needs `window.convertPoint(toScreen:)`, so the windowless fixtures can
/// never reach it; this one mounts the folder grid and the root page grid in one borderless window
/// at production-like positions and drives the exact carry path through the container methods the
/// real mouse handlers call.
@MainActor
final class LaunchpadEjectE2ETests: XCTestCase {

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private var window: NSWindow!
    private var coordinator: LaunchpadDragCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = LaunchpadDragCoordinator()
        window = KeyableWindow(
            contentRect: NSRect(x: -3000, y: -3000, width: 1728, height: 1117),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.orderFront(nil)
    }

    override func tearDown() {
        coordinator.cancelEject()
        window.orderOut(nil)
        window = nil
        coordinator = nil
        super.tearDown()
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func makeGrid(
        items: [LaunchpadDisplayCell],
        columns: Int,
        folderContextID: String? = nil,
        pageIndex: Int? = nil,
        recordReorder: (((String, LaunchpadDropTarget)) -> Void)? = nil
    ) -> LaunchpadDragGrid {
        LaunchpadDragGrid(
            items: items,
            columns: columns,
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
            onReorder: { recordReorder?(($0, $1)) },
            onMakeFolder: { _, _ in },
            onAddToFolder: { _, _ in },
            onDragBegan: {},
            onPageSwipe: { _ in },
            onPageDrag: { _, _, _ in },
            onPageScroll: { _, _ in },
            onDismiss: {},
            allowFolderCreation: folderContextID == nil,
            coordinator: coordinator,
            folderContextID: folderContextID,
            pageIndex: pageIndex
        )
    }

    /// Reproduces the 2026-06-11 runtime choreography: 2-app folder open over page 1, drag the
    /// first app out below the panel (eject arms), wander back UP across the panel's generous
    /// top margin, release just above the panel — over the root grid's row 3.
    func testCarrySurvivesReentryAndCommitsOnRelease() {
        // Root page-1 grid at the viewport position (window coords, y-up → frame y measured from bottom).
        // Viewport: x 48, top y 1009, height ~900 → frame (48, 109, 1632, 900).
        let rootApps: [LaunchpadDisplayCell] = (0..<26).map { i in
            .app(app("/Apps/Root\(i).app", "Root\(i)"))
        }
        let root = LaunchpadGridContainerView(frame: NSRect(x: 48, y: 109, width: 1632, height: 900))
        window.contentView!.addSubview(root)
        root.apply(grid: makeGrid(items: rootApps, columns: 13, pageIndex: 1))
        root.layout()

        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 1632, gridHeight: 900, pageCount: 2, perPage: 78,
            viewportMinX: 48, viewportTopY: 1009))
        coordinator.currentPageDidChange(1)

        // Folder grid (2 apps) where the panel sat: cells around window y ~517-577.
        let postman = app("/Apps/Postman.app", "Postman")
        let chess = app("/Apps/Chess.app", "Chess")
        let folder = LaunchpadGridContainerView(frame: NSRect(x: 700, y: 480, width: 330, height: 160))
        window.contentView!.addSubview(folder)
        folder.apply(grid: makeGrid(items: [.app(postman), .app(chess)], columns: 2,
                                    folderContextID: "F-TEST"))
        folder.layout()

        let postmanCell = folder.cellViews[0]
        let grab = NSPoint(x: postmanCell.frame.midX + folder.frame.minX,
                           y: folder.frame.maxY - postmanCell.frame.midY)   // window point over the cell

        folder.beginDirectDrag(postmanCell, atWindowPoint: grab)
        XCTAssertFalse(coordinator.ejectActive)

        folder.updateDirectDrag(atWindowPoint: NSPoint(x: grab.x + 8, y: grab.y - 8))
        folder.updateDirectDrag(atWindowPoint: NSPoint(x: 700, y: 457))
        folder.updateDirectDrag(atWindowPoint: NSPoint(x: 615, y: 357))     // far below the panel
        XCTAssertTrue(coordinator.ejectActive, "被拖 cell 明确离开夹区域后必须 arm eject")

        folder.updateDirectDrag(atWindowPoint: NSPoint(x: 615, y: 517))     // wander back up across the panel
        folder.updateDirectDrag(atWindowPoint: NSPoint(x: 615, y: 637))
        folder.updateDirectDrag(atWindowPoint: NSPoint(x: 618, y: 677))
        XCTAssertTrue(coordinator.ejectActive, "carry 一旦 arm，重穿面板区域不得自取消")

        let tokenBefore = coordinator.ejectToken
        folder.endDirectDrag(atWindowPoint: NSPoint(x: 618, y: 679))        // release above the panel

        XCTAssertEqual(coordinator.ejectToken, tokenBefore + 1, "release 必须 commitOut（ejectActive 分支无条件）")
        XCTAssertNotNil(coordinator.pendingEject, "commit 后 pendingEject 必须可供 SwiftUI onChange 消费")
        XCTAssertEqual(coordinator.pendingEject?.appID, postman.id)
        XCTAssertEqual(coordinator.pendingEject?.folderID, "F-TEST")
        if case .reorder(let target)? = coordinator.pendingEject?.result {
            XCTAssertNotNil(target, "落点在根网格内部必须解析出相对目标，不得落尾兜底")
        }
        XCTAssertFalse(coordinator.hasFloatingWindow)
    }

    /// A carry that never leaves the columns' central x-band sets neither a gap nor a merge —
    /// the container's commit yields `.reorder(nil)`. The coordinator must then resolve the
    /// RELEASE point instead of letting an in-grid drop fall back to the tail.
    func testCentralBandReleaseResolvesReleasePointNotTail() {
        let rootApps: [LaunchpadDisplayCell] = (0..<26).map { .app(app("/Apps/Root\($0).app", "Root\($0)")) }
        let root = LaunchpadGridContainerView(frame: NSRect(x: 48, y: 109, width: 1632, height: 900))
        window.contentView!.addSubview(root)
        root.apply(grid: makeGrid(items: rootApps, columns: 13, pageIndex: 1))
        root.layout()
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 1632, gridHeight: 900, pageCount: 2, perPage: 78,
            viewportMinX: 48, viewportTopY: 1009))
        coordinator.currentPageDidChange(1)

        coordinator.beginEject(appID: "/Apps/X.app", sourceFolderID: "F-TEST", icon: nil, iconSide: 64,
                               atScreenPoint: .zero, aboveLevel: .normal)
        // Hover BELOW the last row inside a column's central band: slotIndex clamps the row, the
        // point sits between mergeRect.minX/maxX → update returns without arming or opening a gap.
        let belowRowsLocal = NSPoint(x: root.cellViews[17].frame.midX, y: 700)
        coordinator.moveEject(atScreenPoint: .zero,
                              atWindowPoint: NSPoint(x: belowRowsLocal.x + 48, y: 1009 - belowRowsLocal.y))
        coordinator.commitOut(folderID: "F-TEST", appID: "/Apps/X.app",
                              atWindowPoint: NSPoint(x: belowRowsLocal.x + 48, y: 1009 - belowRowsLocal.y))

        guard case .reorder(let target)? = coordinator.pendingEject?.result else {
            return XCTFail("中央带松手应是 reorder，得到 \(String(describing: coordinator.pendingEject?.result))")
        }
        XCTAssertNotNil(target, "网格内松手必须按 release 点解析相对落点，不得落尾")
    }

    /// Same beginning, but release while still clearly below the panel (the simple straight-out
    /// case) — guards the baseline alongside the re-entry case above.
    func testStraightOutEjectCommits() {
        let root = LaunchpadGridContainerView(frame: NSRect(x: 48, y: 109, width: 1632, height: 900))
        window.contentView!.addSubview(root)
        root.apply(grid: makeGrid(items: (0..<5).map { .app(app("/Apps/R\($0).app", "R\($0)")) },
                                  columns: 13, pageIndex: 1))
        root.layout()
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 1632, gridHeight: 900, pageCount: 2, perPage: 78,
            viewportMinX: 48, viewportTopY: 1009))
        coordinator.currentPageDidChange(1)

        let postman = app("/Apps/Postman.app", "Postman")
        let chess = app("/Apps/Chess.app", "Chess")
        let folder = LaunchpadGridContainerView(frame: NSRect(x: 700, y: 480, width: 330, height: 160))
        window.contentView!.addSubview(folder)
        folder.apply(grid: makeGrid(items: [.app(postman), .app(chess)], columns: 2,
                                    folderContextID: "F-TEST"))
        folder.layout()

        let cell = folder.cellViews[0]
        let grab = NSPoint(x: cell.frame.midX + folder.frame.minX,
                           y: folder.frame.maxY - cell.frame.midY)
        folder.beginDirectDrag(cell, atWindowPoint: grab)
        folder.updateDirectDrag(atWindowPoint: NSPoint(x: grab.x + 8, y: grab.y - 8))
        folder.updateDirectDrag(atWindowPoint: NSPoint(x: 615, y: 300))
        XCTAssertTrue(coordinator.ejectActive)

        let tokenBefore = coordinator.ejectToken
        folder.endDirectDrag(atWindowPoint: NSPoint(x: 615, y: 300))
        XCTAssertEqual(coordinator.ejectToken, tokenBefore + 1)
        XCTAssertNotNil(coordinator.pendingEject)
    }
}
