import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Drives the AppKit grid container's drag-to-stack path directly (no real NSDraggingSession),
/// proving the centre-hover → arm → drop wiring fires the right folder callbacks (arming is
/// instant on entering a cell's central merge rect — there is no dwell timer). This is the
/// runtime behaviour that compile + data-layer tests can't reach.
@MainActor
final class LaunchpadDragToStackTests: XCTestCase {

    private final class Recorder {
        var madeFolders: [(target: String, dragged: String)] = []
        var addedToFolders: [(folder: String, app: String)] = []
        var reorders: [(id: String, target: LaunchpadDropTarget)] = []
        var selections: [String] = []
    }

    /// Spy presenter for the root-carry tests — no real NSWindow (design §10-①).
    private final class FloatingIconSpy: LaunchpadFloatingIconPresenting {
        private(set) var presentCount = 0
        private(set) var isPresenting = false
        func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
            presentCount += 1
            isPresenting = true
        }
        func move(toScreenPoint p: NSPoint) {}
        func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void) {
            isPresenting = false
            completion()
        }
        func dismiss() { isPresenting = false }
    }

    /// Coordinator with a spy floating window and an inert applier (these tests assert the
    /// RESOLUTION via pendingVisualCommit; store mapping is covered by the session/anchor suites).
    private func makeCarryCoordinator() -> (coordinator: LaunchpadDragCoordinator, spy: FloatingIconSpy) {
        let coordinator = LaunchpadDragCoordinator()
        let spy = FloatingIconSpy()
        coordinator.floatingPresenterFactory = { spy }
        coordinator.storeApplier = { _, _ in nil }
        return (coordinator, spy)
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func makeContainer(
        _ items: [LaunchpadDisplayCell],
        _ rec: Recorder,
        allowFolderCreation: Bool = true,
        allowsCustomOrderActions: Bool = true,
        coordinator: LaunchpadDragCoordinator? = nil,
        folderContextID: String? = nil,
        pageIndex: Int? = nil,
        metrics: LaunchpadGridMetrics = LaunchpadGridMetrics(),
        columns: Int = 7,
        onActivate: @escaping (LaunchpadDisplayCell) -> Void = { _ in }
    ) -> LaunchpadGridContainerView {
        let grid = LaunchpadDragGrid(
            items: items,
            columns: columns,
            selectedID: nil,
            isCompact: false,
            metrics: metrics,
            iconProvider: { _ in NSImage() },
            onActivate: onActivate,
            onReveal: { _ in },
            onCopyPath: { _ in },
            onHide: { _ in },
            onMoveToFront: { _ in },
            onMoveToEnd: { _ in },
            onSelect: { rec.selections.append($0) },
            onReorder: { rec.reorders.append(($0, $1)) },
            onMakeFolder: { rec.madeFolders.append(($0, $1)) },
            onAddToFolder: { rec.addedToFolders.append(($0, $1)) },
            onDragBegan: { coordinator?.freezeVisibleOrder(items) },
            onPageSwipe: { _ in },
            onPageDrag: { _, _, _ in },
            onPageScroll: { _, _ in },
            onDismiss: {},
            allowFolderCreation: allowFolderCreation,
            allowsCustomOrderActions: allowsCustomOrderActions,
            coordinator: coordinator,
            folderContextID: folderContextID,
            pageIndex: pageIndex
        )
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: grid)
        container.layout()                       // assign cell frames so slot math is valid
        return container
    }

    private func centre(of cell: LaunchpadGridCellView) -> NSPoint {
        NSPoint(x: cell.frame.midX, y: cell.frame.midY)
    }

    /// Synthesized mouse event located in CONTAINER coordinates (the windowless harness treats
    /// `locationInWindow` as root-view coordinates, matching the container-method tests above).
    private func fakeMouse(_ type: NSEvent.EventType, at p: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    // MARK: - Arm + drop

    func testCentreHoverOverAppArmsThenDropMakesFolder() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews
        XCTAssertEqual(cells.count, 3)

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)                       // drag A
        container.updateDrag(at: centre(of: cells[1]))  // into B's central merge rect
        XCTAssertTrue(container.stackTargetCell === cells[1], "进入 B 中心应 arm B")

        XCTAssertTrue(container.commitDrop(dragged: cells[0]))
        XCTAssertEqual(rec.madeFolders.count, 1)
        XCTAssertEqual(rec.madeFolders.first?.target, b.id)
        XCTAssertEqual(rec.madeFolders.first?.dragged, a.id)
        XCTAssertEqual(rec.reorders.count, 0, "叠放不应同时触发重排")
        XCTAssertNil(container.stackTargetCell, "drop 后 disarm")
    }

    func testCentreHoverOverFolderAddsToIt() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A")
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "夹", items: [app("/Apps/X.app", "X")])
        let container = makeContainer([.app(a), folder], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)                       // drag A
        container.updateDrag(at: centre(of: cells[1]))  // into the folder's central merge rect
        XCTAssertTrue(container.stackTargetCell === cells[1])

        container.commitDrop(dragged: cells[0])
        XCTAssertEqual(rec.addedToFolders.first?.folder, "F1")
        XCTAssertEqual(rec.addedToFolders.first?.app, a.id)
        XCTAssertEqual(rec.madeFolders.count, 0)
    }

    func testNoArmFallsBackToReorder() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        container.commitDrop(dragged: cells[0])             // nothing armed
        XCTAssertEqual(rec.madeFolders.count, 0)
        XCTAssertEqual(rec.addedToFolders.count, 0)
        XCTAssertEqual(rec.reorders.count, 1, "无 stack target → 退回重排")
    }

    func testReorderDropReportsExactRelativeTarget() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews

        // Capture the point BEFORE updateDrag re-layouts the others (slot geometry is stable).
        let rightOfC = NSPoint(x: cells[2].frame.maxX - 4, y: cells[2].frame.midY)
        container.beginDirectDrag(cells[0], atWindowPoint: .zero)        // drag A
        container.updateDrag(at: rightOfC)                               // C 右侧缝隙 → [B, C, A]
        container.commitDrop(dragged: cells[0])
        XCTAssertEqual(rec.reorders.count, 1)
        XCTAssertEqual(rec.reorders.first?.id, a.id)
        XCTAssertEqual(rec.reorders.first?.target, .after(c.id),
                       "落点必须精确为 .after(C) — before/after 颠倒或差一位会在这里暴露")
    }

    /// Appearance-parameterized merge hot zone (design §3.5-4: 48-hidden / 96-shown):
    /// `mergeRect` scales with the icon (inset max(6, iconSide×0.125)), so the centre
    /// must still arm and a seam drop must still resolve to an exact reorder at both
    /// ends of the user-reachable metrics range — not just at the default 64pt.
    func testCentreArmAndSeamReorderTrackMetrics() {
        for appearance in [LaunchpadAppearance(iconSide: 48, showsLabels: false),
                           LaunchpadAppearance(iconSide: 96, showsLabels: true)] {
            let m = LaunchpadGridMetrics.resolve(appearance)
            let columns = LaunchpadLayoutMath.pageGrid(
                viewport: CGSize(width: 900, height: 600), metrics: m, fixedColumns: nil).columns
            let rec = Recorder()
            let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
            let container = makeContainer([.app(a), .app(b), .app(c)], rec,
                                          metrics: m, columns: columns)
            let cells = container.cellViews

            // Capture the seam BEFORE updateDrag re-layouts (slot geometry is stable).
            let rightOfC = NSPoint(x: cells[2].frame.maxX - 4, y: cells[2].frame.midY)
            container.beginDirectDrag(cells[0], atWindowPoint: .zero)        // drag A
            container.updateDrag(at: centre(of: cells[1]))
            XCTAssertTrue(container.stackTargetCell === cells[1],
                          "B 图标中心必须 arm merge（@\(m.iconSide)pt labels=\(m.showsLabels)）")

            // Move on to C's right SEAM (a different cell, so the same-cell anti-jitter
            // keep-alive does not apply): merge clears, the reorder gap opens.
            container.updateDrag(at: rightOfC)
            XCTAssertNil(container.stackTargetCell,
                         "C 右缝必须清除 merge、回到 reorder（@\(m.iconSide)pt labels=\(m.showsLabels)）")

            container.commitDrop(dragged: cells[0])
            XCTAssertEqual(rec.madeFolders.count, 0, "缝隙落点不得建夹")
            XCTAssertEqual(rec.reorders.count, 1)
            XCTAssertEqual(rec.reorders.first?.target, .after(c.id),
                           "缝隙落点必须精确为 .after(C)（@\(m.iconSide)pt labels=\(m.showsLabels)）")
        }
    }

    func testDraggedFolderNeverArms() {
        let rec = Recorder()
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "夹", items: [app("/Apps/X.app", "X")])
        let a = app("/Apps/A.app", "A")
        let container = makeContainer([folder, .app(a)], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)                       // drag the FOLDER
        container.updateDrag(at: centre(of: cells[1]))
        XCTAssertNil(container.stackTargetCell, "拖文件夹永不 arm 叠放（无嵌套）")
    }

    func testArmOnSelfIsIgnored() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        container.updateDrag(at: centre(of: cells[0]))  // over self
        XCTAssertNil(container.stackTargetCell, "停在自己槽上不 arm")
    }

    func testEdgeZoneDoesNotArm() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        // A point near B's left edge (outside the central icon rect) should NOT arm — it's reorder.
        let edge = NSPoint(x: cells[1].frame.minX + 3, y: cells[1].frame.midY)
        container.updateDrag(at: edge)
        XCTAssertNil(container.stackTargetCell, "落在 cell 边缘区不 arm（留给重排）")
    }

    // MARK: - In-folder behaviour (merge disabled, finger-bound drag-out)

    func testFolderGridNeverArmsMerge() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec, allowFolderCreation: false)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        container.updateDrag(at: centre(of: cells[1]))          // over B's centre
        XCTAssertNil(container.stackTargetCell, "文件夹内禁止建夹：拖到中心也不 arm")
        container.commitDrop(dragged: cells[0])
        XCTAssertEqual(rec.madeFolders.count, 0, "文件夹内不应嵌套建夹")
    }

    func testRootDropTargetResolvesSlotFromWindowPoint() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)   // a plain root grid
        let cells = container.cellViews

        let bLeft = NSPoint(x: cells[1].frame.minX + 4, y: cells[1].frame.midY)
        let bRight = NSPoint(x: cells[1].frame.maxX - 4, y: cells[1].frame.midY)
        guard case .before(let lid)? = container.rootDropTarget(atWindowPoint: bLeft) else {
            return XCTFail("左半应 .before(B)")
        }
        XCTAssertEqual(lid, b.id)
        guard case .after(let rid)? = container.rootDropTarget(atWindowPoint: bRight) else {
            return XCTFail("右半应 .after(B)")
        }
        XCTAssertEqual(rid, b.id)
    }

    func testDragOutOfFolderEjectsViaCoordinator() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let coord = LaunchpadDragCoordinator()
        let container = makeContainer([.app(a), .app(b)], rec,
                                      allowFolderCreation: false, coordinator: coord, folderContextID: "F1")
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        container.updateDirectDrag(atWindowPoint: NSPoint(x: 60, y: container.bounds.height + 200))  // clearly out
        container.endDirectDrag()
        XCTAssertEqual(coord.pendingEject?.folderID, "F1", "在外面松手 → 请求移出文件夹")
        XCTAssertEqual(coord.pendingEject?.appID, a.id)
        XCTAssertEqual(coord.ejectToken, 1, "eject token 被 bump（驱动 SwiftUI 关闭）")
        XCTAssertEqual(rec.reorders.count, 0, "eject 不触发夹内重排")
    }

    // MARK: - External drag (an app ejected from a folder, carried over the root grid)

    func testExternalDragOverAppCentreArmsMakeFolder() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews

        container.beginExternalDrag(appID: "/Apps/Ext.app")
        container.updateExternalDrag(atWindowPoint: centre(of: cells[1]))   // over B's centre → merge
        XCTAssertTrue(container.stackTargetCell === cells[1], "停在 app 中心 → arm 建夹")
        XCTAssertEqual(container.commitExternalDrag(), .makeFolder(targetAppID: b.id))
    }

    func testExternalDragOverFolderArmsAddToFolder() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A")
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "夹", items: [app("/Apps/X.app", "X")])
        let container = makeContainer([.app(a), folder], rec)
        let cells = container.cellViews

        container.beginExternalDrag(appID: "/Apps/Ext.app")
        container.updateExternalDrag(atWindowPoint: centre(of: cells[1]))   // over the folder
        XCTAssertEqual(container.commitExternalDrag(), .addToFolder(folderID: "F1"))
    }

    func testExternalDragNearSideOpensGapAndReorders() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews

        container.beginExternalDrag(appID: "/Apps/Ext.app")
        container.updateExternalDrag(atWindowPoint: NSPoint(x: cells[1].frame.maxX - 4, y: cells[1].frame.midY))
        XCTAssertNotNil(container.externalGapIndex, "边缘 → 开让位 gap，不 arm 建夹")
        XCTAssertNil(container.stackTargetCell)
        XCTAssertEqual(container.commitExternalDrag(), .reorder(.after(b.id)))
    }

    func testEndExternalDragClearsState() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec)
        let cells = container.cellViews

        container.beginExternalDrag(appID: "/Apps/Ext.app")
        container.updateExternalDrag(atWindowPoint: NSPoint(x: cells[0].frame.minX + 2, y: cells[0].frame.midY))
        container.endExternalDrag()
        XCTAssertNil(container.externalGapIndex)
        XCTAssertNil(container.stackTargetCell)
    }

    func testExternalDragMutuallyExclusiveWithRealDrag() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)            // a real drag is live
        container.beginExternalDrag(appID: "/Apps/Ext.app")                  // must be a no-op
        container.updateExternalDrag(atWindowPoint: centre(of: cells[1]))
        XCTAssertNil(container.externalGapIndex, "有真拖拽时外部拖拽不生效")
    }

    // MARK: - Search mode (read-only projection)

    func testSearchModeDragIsConsumedNotTreatedAsClick() {
        let rec = Recorder()
        var activated: [String] = []
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec,
                                      allowsCustomOrderActions: false,
                                      onActivate: { activated.append($0.layoutID) })
        let cell = container.cellViews[0]
        let start = centre(of: cell)

        cell.mouseDown(with: fakeMouse(.leftMouseDown, at: start))
        cell.mouseDragged(with: fakeMouse(.leftMouseDragged, at: NSPoint(x: start.x + 40, y: start.y)))
        XCTAssertFalse(container.hasActiveDrag, "搜索态不开始重排拖拽")
        cell.mouseUp(with: fakeMouse(.leftMouseUp, at: NSPoint(x: start.x + 40, y: start.y)))
        XCTAssertTrue(activated.isEmpty, "拖过阈值再松手是被取消的拖拽，不能当点击启动 app")

        cell.mouseDown(with: fakeMouse(.leftMouseDown, at: start))
        cell.mouseUp(with: fakeMouse(.leftMouseUp, at: start))
        XCTAssertEqual(activated, [a.id], "纯点击仍然激活")
    }

    // MARK: - Row-capped (scrollable) folder eject

    func testClippedFolderEjectsWhenLeavingVisibleViewport() {
        let rec = Recorder()
        let coord = LaunchpadDragCoordinator()
        let apps = (0..<21).map { i in app("/Apps/App\(i).app", "A\(i)") }
        let container = makeContainer(apps.map(LaunchpadDisplayCell.app), rec,
                                      allowFolderCreation: false, coordinator: coord, folderContextID: "F1")
        // Row-capped folder: a scroll view clips the ~404pt 3-row content to ~160pt.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 160))
        scroll.documentView = container
        container.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        container.layout()
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        cells[0].setFrameOrigin(NSPoint(x: 60, y: 300))   // 完整内容范围内、但在可见视口下方（被裁切不可见）
        container.endDirectDrag(atWindowPoint: NSPoint(x: 60, y: 300))
        XCTAssertEqual(coord.pendingEject?.appID, apps[0].id, "被裁切的行不构成盲区：拖出可见区域即出夹")
        XCTAssertEqual(coord.ejectToken, 1)
    }

    // MARK: - Aborting a carry (unmount / overlay close must not leak the floating window)

    func testCancelEjectTearsDownWithoutCommit() {
        let coord = LaunchpadDragCoordinator()
        coord.beginEject(appID: "/Apps/A.app", sourceFolderID: "F1", icon: nil, iconSide: 64,
                         atScreenPoint: .zero, aboveLevel: .normal)
        XCTAssertTrue(coord.ejectActive)
        XCTAssertEqual(coord.carriedAppID, "/Apps/A.app")

        coord.cancelEject()
        XCTAssertFalse(coord.ejectActive, "取消必须收掉浮动图标并退出 carry 态")
        XCTAssertNil(coord.carriedAppID)
        XCTAssertNil(coord.pendingEject, "中止不产生 commit")
        XCTAssertEqual(coord.ejectToken, 0)
    }

    func testUnmountMidCarryCancelsEjectAndDragState() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let coord = LaunchpadDragCoordinator()
        let container = makeContainer([.app(a), .app(b)], rec,
                                      allowFolderCreation: false, coordinator: coord, folderContextID: "F1")
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        // Windowless harness can't pass the screen-conversion gate in updateDirectDrag, so enter
        // the carry directly — the state the container must clean up is the same.
        coord.beginEject(appID: a.id, sourceFolderID: "F1", icon: nil, iconSide: 64,
                         atScreenPoint: .zero, aboveLevel: .normal)
        XCTAssertTrue(coord.ejectActive)

        container.viewWillMove(toWindow: nil)   // folder panel unmounted mid-carry (Esc / 打字 / overlay 关闭)
        XCTAssertFalse(coord.ejectActive, "卸载中止 carry：浮动图标窗口必须被收掉")
        XCTAssertFalse(container.hasActiveDrag, "本地拖拽状态一并清理")
        XCTAssertNil(coord.pendingEject)
        XCTAssertEqual(coord.ejectToken, 0, "中止不触发 SwiftUI commit")
    }

    func testUnmountMidExternalCarrySettlesRootGap() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec)
        let cells = container.cellViews

        container.beginExternalDrag(appID: "/Apps/Ext.app")
        container.updateExternalDrag(atWindowPoint: NSPoint(x: cells[0].frame.minX + 2, y: cells[0].frame.midY))
        XCTAssertNotNil(container.externalGapIndex)

        container.viewWillMove(toWindow: nil)   // root page unmounted mid-carry
        XCTAssertNil(container.externalGapIndex, "卸载收掉外部让位 gap")
        XCTAssertNil(container.stackTargetCell)
    }

    func testDropInsideFolderGridReordersNotEject() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let coord = LaunchpadDragCoordinator()
        let container = makeContainer([.app(a), .app(b), .app(c)], rec,
                                      allowFolderCreation: false, coordinator: coord, folderContextID: "F1")
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        container.updateDirectDrag(atWindowPoint: centre(of: cells[2]))   // stay inside the grid
        container.endDirectDrag()
        XCTAssertEqual(coord.ejectToken, 0, "网格内松手不移出（撤销）")
        XCTAssertNil(coord.pendingEject)
    }

    // MARK: - Root-page lift = carry (design §10-F: routing, precision counterparts, gates)

    func testRootLiftWithCoordinatorRoutesToCarryNotLocalDrag() {
        let rec = Recorder()
        let (coord, spy) = makeCarryCoordinator()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec,
                                      coordinator: coord, pageIndex: 0)
        let cell = container.cellViews[0]
        let framesBefore = container.cellViews.map(\.frame)
        let start = centre(of: cell)

        // Drive the REAL arbitration: 6pt threshold inside the cell's mouse handlers.
        cell.mouseDown(with: fakeMouse(.leftMouseDown, at: start))
        cell.mouseDragged(with: fakeMouse(.leftMouseDragged, at: NSPoint(x: start.x + 10, y: start.y)))

        XCTAssertTrue(coord.carryActive, "根页过阈值 lift 必须路由到 carry，不走本地直拖")
        XCTAssertEqual(coord.carrySession?.origin, .rootPage)
        XCTAssertTrue(spy.isPresenting, "lift 即浮窗")
        XCTAssertFalse(cell.isLifted, "锚不置 isLifted——放大视觉由浮窗承担")
        XCTAssertEqual(cell.frame.origin, LaunchpadGridContainerView.carryParkOrigin, "锚停泊离屏，全程不动")
        XCTAssertTrue(container.externalDragActive, "源页即让位会话")
        XCTAssertEqual(container.externalGapIndex, 0, "seedGap = 锚原槽")
        XCTAssertEqual(container.cellViews[1].frame, framesBefore[1], "邻居不动（恒等布局）")
        XCTAssertTrue(container.hasActiveDrag)

        // mouseUp routes through the container's FIRST-LINE branch (no draggedCell to guard on).
        cell.mouseUp(with: fakeMouse(.leftMouseUp, at: NSPoint(x: start.x + 10, y: start.y)))
        XCTAssertFalse(coord.carryActive)
        XCTAssertEqual(coord.commitToken, 1, "release 必须经 endDirectDrag 首行分支触发 commit（BR-7）")
        XCTAssertEqual(rec.reorders.count, 0, "carry 数据走 coordinator，不触发容器本地回调")
        XCTAssertEqual(rec.madeFolders.count, 0)
    }

    func testRootCarryHoverAppCentreResolvesMakeFolderOfTarget() {
        let rec = Recorder()
        let (coord, _) = makeCarryCoordinator()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec,
                                      coordinator: coord, pageIndex: 0)
        let cells = container.cellViews
        let bCentre = centre(of: cells[1])

        container.beginDirectDrag(cells[0], atWindowPoint: centre(of: cells[0]))   // carry A
        container.updateDirectDrag(atWindowPoint: bCentre)                          // hover B's centre
        XCTAssertTrue(container.stackTargetCell === cells[1], "锚在场时悬停他 app 中心必须 arm 该目标")

        container.endDirectDrag(atWindowPoint: bCentre)
        XCTAssertEqual(coord.pendingVisualCommit?.result, .makeFolder(targetAppID: b.id),
                       "落点必须精确为 makeFolder(B)——carry 形态与本地直拖同精度（BT-6 对仗）")
    }

    func testRootCarrySeamResolvesPreciseReorderTarget() {
        let rec = Recorder()
        let (coord, _) = makeCarryCoordinator()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec,
                                      coordinator: coord, pageIndex: 0)
        let cells = container.cellViews
        let rightOfC = NSPoint(x: cells[2].frame.maxX - 4, y: cells[2].frame.midY)

        container.beginDirectDrag(cells[0], atWindowPoint: centre(of: cells[0]))   // carry A
        container.updateDirectDrag(atWindowPoint: rightOfC)                         // C 右缝
        container.endDirectDrag(atWindowPoint: rightOfC)

        XCTAssertEqual(coord.pendingVisualCommit?.result, .reorder(.after(c.id)),
                       "落点必须精确为 .after(C)——before/after 颠倒或差一位会在这里暴露")
    }

    func testRootCarryTargetNeverResolvesToAnchor() {
        let rec = Recorder()
        let (coord, _) = makeCarryCoordinator()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec,
                                      coordinator: coord, pageIndex: 0)
        let cells = container.cellViews
        let anchorSlotCentre = centre(of: cells[1])          // B's committed slot, captured pre-lift

        container.beginDirectDrag(cells[1], atWindowPoint: anchorSlotCentre)   // carry B (middle)
        container.updateDirectDrag(atWindowPoint: anchorSlotCentre)            // hover OWN slot
        XCTAssertNil(container.stackTargetCell, "锚自己的槽位是死区：永不 arm（原位抖动不得建夹）")
        XCTAssertEqual(container.externalGapIndex, 1, "自家槽位保持 seed gap")

        container.endDirectDrag(atWindowPoint: anchorSlotCentre)
        guard case .reorder(let target?) = coord.pendingVisualCommit?.result else {
            return XCTFail("own-slot release 应是 reorder，得到 \(String(describing: coord.pendingVisualCommit?.result))")
        }
        switch target {
        case .before(let id), .after(let id):
            XCTAssertNotEqual(id, b.id, "目标永不等于锚 id（§10-F 对仗不变量）")
        }
    }

    func testSearchModeLongDragWithCoordinatorOpensNoSession() {
        let rec = Recorder()
        let (coord, spy) = makeCarryCoordinator()
        var activated: [String] = []
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec,
                                      allowsCustomOrderActions: false,
                                      coordinator: coord, pageIndex: 0,
                                      onActivate: { activated.append($0.layoutID) })
        let cell = container.cellViews[0]
        let start = centre(of: cell)

        cell.mouseDown(with: fakeMouse(.leftMouseDown, at: start))
        cell.mouseDragged(with: fakeMouse(.leftMouseDragged, at: NSPoint(x: start.x + 40, y: start.y)))
        XCTAssertNil(coord.carrySession, "搜索态不开 carry 会话")
        XCTAssertFalse(coord.carryActive)
        XCTAssertEqual(spy.presentCount, 0, "不得创建浮窗")
        cell.mouseUp(with: fakeMouse(.leftMouseUp, at: NSPoint(x: start.x + 40, y: start.y)))
        XCTAssertTrue(activated.isEmpty, "长拖被吞，不当点击启动 app")
    }

    func testNilCoordinatorFallsBackToLocalDirectDrag() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)   // coordinator == nil
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)
        XCTAssertTrue(cells[0].isLifted, "coordinator==nil 必须保留旧本地直拖语义（旧测例钉死）")
        XCTAssertTrue(container.hasActiveDrag)
        XCTAssertFalse(container.externalDragActive, "本地路径不开让位会话")

        let rightOfC = NSPoint(x: cells[2].frame.maxX - 4, y: cells[2].frame.midY)
        container.updateDrag(at: rightOfC)
        container.commitDrop(dragged: cells[0])
        XCTAssertEqual(rec.reorders.first?.target, .after(c.id), "本地直拖照常走容器回调")
    }

    func testMidCarryRightClickOnNonSourcePageIsGated() {
        let rec0 = Recorder(), rec1 = Recorder()
        let (coord, _) = makeCarryCoordinator()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let d = app("/Apps/D.app", "D"), e = app("/Apps/E.app", "E")
        let source = makeContainer([.app(a), .app(b)], rec0, coordinator: coord, pageIndex: 0)
        let other = makeContainer([.app(d), .app(e)], rec1, coordinator: coord, pageIndex: 1)

        source.beginDirectDrag(source.cellViews[0], atWindowPoint: centre(of: source.cellViews[0]))
        XCTAssertTrue(coord.carryActive)
        XCTAssertFalse(other.hasActiveDrag, "非源页本地无拖拽——必须由 coordinator 级 gate 拦截")

        let target = other.cellViews[0]
        target.rightMouseDown(with: fakeMouse(.rightMouseDown, at: centre(of: target)))
        XCTAssertTrue(rec1.selections.isEmpty,
                      "mid-carry 非源页右键必须被吞（菜单 tracking loop 会吞 mouseUp 卡死会话，§9.1 行 10）")

        source.endDirectDrag(atWindowPoint: centre(of: source.cellViews[0]))
    }
}
