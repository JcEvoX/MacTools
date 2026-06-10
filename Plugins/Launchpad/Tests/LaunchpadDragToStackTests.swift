import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Drives the AppKit grid container's drag-to-stack path directly (no real NSDraggingSession),
/// proving the dwell → arm → drop wiring fires the right folder callbacks. This is the runtime
/// behaviour that compile + data-layer tests can't reach.
@MainActor
final class LaunchpadDragToStackTests: XCTestCase {

    private final class Recorder {
        var madeFolders: [(target: String, dragged: String)] = []
        var addedToFolders: [(folder: String, app: String)] = []
        var reorders: [(id: String, target: LaunchpadDropTarget)] = []
        var ejectCommits: [(folder: String, app: String, hasTarget: Bool)] = []
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func makeContainer(
        _ items: [LaunchpadDisplayCell],
        _ rec: Recorder,
        allowFolderCreation: Bool = true,
        coordinator: LaunchpadDragCoordinator? = nil,
        folderContextID: String? = nil
    ) -> LaunchpadGridContainerView {
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
            onReorder: { rec.reorders.append(($0, $1)) },
            onMakeFolder: { rec.madeFolders.append(($0, $1)) },
            onAddToFolder: { rec.addedToFolders.append(($0, $1)) },
            onDragBegan: {},
            onPageSwipe: { _ in },
            onPageDrag: { _, _, _ in },
            onPageScroll: { _, _ in },
            onDismiss: {},
            allowFolderCreation: allowFolderCreation,
            coordinator: coordinator,
            folderContextID: folderContextID
        )
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: grid)
        container.layout()                       // assign cell frames so slot math is valid
        return container
    }

    private func centre(of cell: LaunchpadGridCellView) -> NSPoint {
        NSPoint(x: cell.frame.midX, y: cell.frame.midY)
    }

    // MARK: - Arm + drop

    func testDwellOverAppArmsThenDropMakesFolder() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec)
        let cells = container.cellViews
        XCTAssertEqual(cells.count, 3)

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)                       // drag A
        container.updateDrag(at: centre(of: cells[1]))  // dwell over B
        XCTAssertTrue(container.stackTargetCell === cells[1], "停在 B 中心应 arm B")

        XCTAssertTrue(container.commitDrop(dragged: cells[0]))
        XCTAssertEqual(rec.madeFolders.count, 1)
        XCTAssertEqual(rec.madeFolders.first?.target, b.id)
        XCTAssertEqual(rec.madeFolders.first?.dragged, a.id)
        XCTAssertEqual(rec.reorders.count, 0, "叠放不应同时触发重排")
        XCTAssertNil(container.stackTargetCell, "drop 后 disarm")
    }

    func testDwellOverFolderAddsToIt() {
        let rec = Recorder()
        let a = app("/Apps/A.app", "A")
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "夹", items: [app("/Apps/X.app", "X")])
        let container = makeContainer([.app(a), folder], rec)
        let cells = container.cellViews

        container.beginDirectDrag(cells[0], atWindowPoint: .zero)                       // drag A
        container.updateDrag(at: centre(of: cells[1]))  // dwell over the folder
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
        container.commitDrop(dragged: cells[0])             // no dwell armed
        XCTAssertEqual(rec.madeFolders.count, 0)
        XCTAssertEqual(rec.addedToFolders.count, 0)
        XCTAssertEqual(rec.reorders.count, 1, "无 stack target → 退回重排")
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
}
