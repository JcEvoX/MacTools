import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Folder context menu (design §2.5, R2) and the post-creation auto-open trigger
/// (§2.6, R1=B): folder cells gain 打开/重命名/解散, app cells don't change, and a
/// commit that CREATES a folder publishes the reveal token the grid view consumes.
@MainActor
final class LaunchpadFolderMenuTests: XCTestCase {

    private final class Recorder {
        var renamed: [String] = []
        var dissolved: [String] = []
        var activated: [String] = []
    }

    private final class FloatingIconSpy: LaunchpadFloatingIconPresenting {
        private(set) var isPresenting = false
        func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
            isPresenting = true
        }
        func move(toScreenPoint p: NSPoint) {}
        func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void) {
            isPresenting = false
            completion()
        }
        func dismiss() { isPresenting = false }
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func makeContainer(
        _ items: [LaunchpadDisplayCell],
        _ rec: Recorder,
        coordinator: LaunchpadDragCoordinator? = nil,
        pageIndex: Int? = nil
    ) -> LaunchpadGridContainerView {
        let grid = LaunchpadDragGrid(
            items: items,
            columns: 7,
            selectedID: nil,
            isCompact: false,
            iconProvider: { _ in NSImage() },
            onActivate: { rec.activated.append($0.layoutID) },
            onReveal: { _ in },
            onCopyPath: { _ in },
            onHide: { _ in },
            onMoveToFront: { _ in },
            onMoveToEnd: { _ in },
            onSelect: { _ in },
            onReorder: { _, _ in },
            onMakeFolder: { _, _ in },
            onAddToFolder: { _, _ in },
            onRenameFolder: { rec.renamed.append($0) },
            onDissolveFolder: { rec.dissolved.append($0) },
            onDragBegan: { coordinator?.freezeVisibleOrder(items) },
            onPageSwipe: { _ in },
            onPageDrag: { _, _, _ in },
            onPageScroll: { _, _ in },
            onDismiss: {},
            coordinator: coordinator,
            pageIndex: pageIndex
        )
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: grid)
        container.layout()
        return container
    }

    private func fire(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    // MARK: - Menu contents

    func testFolderCellMenuOffersOpenRenameDissolve() {
        let rec = Recorder()
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "工具",
                                                 items: [app("/Apps/X.app", "X"), app("/Apps/Y.app", "Y")])
        let container = makeContainer([.app(app("/Apps/A.app", "A")), folder], rec)
        let menu = container.contextMenu(for: container.cellViews[1])

        XCTAssertNotNil(menu, "folder cell 不再抑制右键菜单（19b-4 占位解除）")
        let titles = menu!.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, ["打开", "重命名", "解散文件夹"], "R2：带解散、无确认")
    }

    func testAppCellMenuHasNoFolderActions() {
        let rec = Recorder()
        let container = makeContainer([.app(app("/Apps/A.app", "A"))], rec)
        let menu = container.contextMenu(for: container.cellViews[0])

        let titles = menu!.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertFalse(titles.contains("重命名"), "app cell 不得出现 folder 专属项")
        XCTAssertFalse(titles.contains("解散文件夹"))
        XCTAssertTrue(titles.contains("隐藏"), "app 菜单原样保留")
    }

    // MARK: - Menu actions

    func testRenameAndDissolveActionsForwardFolderID() {
        let rec = Recorder()
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "工具", items: [app("/Apps/X.app", "X")])
        let container = makeContainer([folder], rec)
        let items = container.contextMenu(for: container.cellViews[0])!.items.filter { !$0.isSeparatorItem }

        fire(items[1])                                   // 重命名
        XCTAssertEqual(rec.renamed, ["F1"])
        fire(items[2])                                   // 解散文件夹
        XCTAssertEqual(rec.dissolved, ["F1"])
        XCTAssertEqual(rec.activated, [], "重命名/解散不触发激活")
    }

    func testOpenActionActivatesTheFolderCell() {
        let rec = Recorder()
        let folder = LaunchpadDisplayCell.folder(id: "F1", name: "工具", items: [app("/Apps/X.app", "X")])
        let container = makeContainer([folder], rec)
        let items = container.contextMenu(for: container.cellViews[0])!.items.filter { !$0.isSeparatorItem }

        fire(items[0])                                   // 打开
        XCTAssertEqual(rec.activated, ["F1"], "打开 = onActivate(folder) → 开夹")
    }

    // MARK: - Step 5: created-folder reveal (design §2.6, R1=B)

    func testVisualCommitCreatedFolderIDDerivation() {
        typealias VC = LaunchpadDragCoordinator.VisualCommit
        let make = VC(itemID: "/Apps/A.app", origin: .rootPage,
                      result: .makeFolder(targetAppID: "/Apps/B.app"), landingID: "F-NEW")
        XCTAssertEqual(make.createdFolderID, "F-NEW", "makeFolder 的 landingID 即新夹 id")

        let add = VC(itemID: "/Apps/A.app", origin: .rootPage,
                     result: .addToFolder(folderID: "F1"), landingID: "F1")
        XCTAssertNil(add.createdFolderID, "addToFolder 落点是既有夹，不触发自动打开")

        let move = VC(itemID: "/Apps/A.app", origin: .rootPage,
                      result: .reorder(.after("/Apps/B.app")), landingID: "/Apps/A.app")
        XCTAssertNil(move.createdFolderID)
    }

    /// Windowless harness → hard-cut settle: the reveal happens in the same mouseUp stack,
    /// so the token publishes immediately (the flight-branch timing is pinned in
    /// `LaunchpadSettleFlightTests`).
    func testHardCutMergeCommitPublishesFolderReveal() {
        let rec = Recorder()
        let coordinator = LaunchpadDragCoordinator()
        let spy = FloatingIconSpy()
        coordinator.floatingPresenterFactory = { spy }
        coordinator.storeApplier = { action, _ in
            if case .makeFolder = action { return "F-NEW" }
            return nil
        }
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B")
        let container = makeContainer([.app(a), .app(b)], rec, coordinator: coordinator, pageIndex: 0)
        let cells = container.cellViews
        let bCentre = NSPoint(x: cells[1].frame.midX, y: cells[1].frame.midY)

        container.beginDirectDrag(cells[0], atWindowPoint: NSPoint(x: cells[0].frame.midX, y: cells[0].frame.midY))
        container.updateDirectDrag(atWindowPoint: bCentre)
        XCTAssertTrue(container.stackTargetCell === cells[1])
        container.endDirectDrag(atWindowPoint: bCentre)

        XCTAssertEqual(coordinator.revealedFolderID, "F-NEW")
        XCTAssertEqual(coordinator.folderRevealToken, 1, "hard-cut：mouseUp 栈内即发布")
    }

    func testHardCutReorderCommitPublishesNoFolderReveal() {
        let rec = Recorder()
        let coordinator = LaunchpadDragCoordinator()
        let spy = FloatingIconSpy()
        coordinator.floatingPresenterFactory = { spy }
        coordinator.storeApplier = { _, _ in "/Apps/A.app" }
        let a = app("/Apps/A.app", "A"), b = app("/Apps/B.app", "B"), c = app("/Apps/C.app", "C")
        let container = makeContainer([.app(a), .app(b), .app(c)], rec, coordinator: coordinator, pageIndex: 0)
        let cells = container.cellViews
        let seam = NSPoint(x: cells[2].frame.maxX - 4, y: cells[2].frame.midY)

        container.beginDirectDrag(cells[0], atWindowPoint: NSPoint(x: cells[0].frame.midX, y: cells[0].frame.midY))
        container.updateDirectDrag(atWindowPoint: seam)
        container.endDirectDrag(atWindowPoint: seam)

        XCTAssertEqual(coordinator.folderRevealToken, 0, "重排 commit 绝不触发自动开夹")
        XCTAssertNil(coordinator.revealedFolderID)
    }
}
