import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// §A4: a make-way gap on a FULL page pushes the last cell past the page capacity. The
/// container's row-major slot math knows no page boundary, so before the fix the overflow cell
/// landed on a phantom row BELOW the grid (visible — the paging strip only clips at the viewport
/// edges). With `rows` injected, the overflow cell flies out of the RIGHT edge (reads as
/// "cascades to the next page"), and the settle flight never aims at a phantom slot.
@MainActor
final class LaunchpadGapOverflowTests: XCTestCase {

    private let metrics = LaunchpadGridMetrics()

    private func app(_ index: Int) -> LaunchpadDisplayCell {
        let path = "/Apps/App\(index).app"
        return .app(LaunchpadAppItem(id: path, name: "App\(index)", url: URL(fileURLWithPath: path)))
    }

    /// rows × columns container (windowless: container points are page-local by the test seam).
    private func makeContainer(items: [LaunchpadDisplayCell], columns: Int,
                               rows: Int) -> LaunchpadGridContainerView {
        let grid = LaunchpadDragGrid(
            items: items,
            columns: columns,
            rows: rows,
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
            onDismiss: {}
        )
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        container.apply(grid: grid)
        container.layout()
        return container
    }

    /// 2×3 page filled to capacity (6 cells) — the §A4 reproduction board.
    private func makeFullPage() -> LaunchpadGridContainerView {
        makeContainer(items: (0..<6).map(app), columns: 3, rows: 2)
    }

    // Geometry helpers mirroring slotRect: 400pt bounds, grid 3×116 + 2×8 = 364 → inset 18.
    private var leftInset: CGFloat { 18 }
    private func slotOrigin(col: Int, row: Int) -> NSPoint {
        NSPoint(x: leftInset + CGFloat(col) * (metrics.cellWidth + metrics.columnSpacing),
                y: CGFloat(row) * (metrics.cellHeight + metrics.rowSpacing))
    }

    func testFullPageGapSendsOverflowCellOutTheRightEdgeNotAPhantomRow() {
        let container = makeFullPage()
        let lastCell = container.cellViews[5]
        XCTAssertEqual(lastCell.frame.origin, slotOrigin(col: 2, row: 1), "前提：满页末 cell 在末槽")

        container.beginExternalDrag(appID: "/Apps/X.app")
        // Hover the FIRST cell's left seam → gap 0 → every cell shifts one slot forward and the
        // last one falls past capacity (slot 6 on a 6-slot page).
        let first = container.cellViews[0].frame
        container.updateExternalDrag(atContainerPoint: NSPoint(x: first.minX + 2, y: first.midY))
        XCTAssertEqual(container.externalGapIndex, 0)
        container.layout()                                   // settle the animated make-way deterministically

        XCTAssertGreaterThan(lastCell.frame.minX, container.bounds.width,
                             "溢出 cell 必须飞出右缘（视口 clip 吃掉=去下一页），不得另起一行")
        XCTAssertEqual(lastCell.frame.minY, slotOrigin(col: 0, row: 1).y,
                       "溢出 cell 保持最后可见行的 y——绝不出现第 rows+1 行")
        XCTAssertEqual(lastCell.frame.minX, container.bounds.width + metrics.cellWidth,
                       "溢出槽位 = 右缘外一格")

        // Every other cell stays within the page.
        for cell in container.cellViews where cell !== lastCell {
            XCTAssertLessThanOrEqual(cell.frame.maxX, container.bounds.width,
                                     "非溢出 cell 不得越界")
            XCTAssertLessThanOrEqual(cell.frame.maxY,
                                     CGFloat(2) * (metrics.cellHeight + metrics.rowSpacing),
                                     "非溢出 cell 不得越过页行数")
        }

        // Gap closes (cursor left / handoff): the cell glides straight back into its real slot.
        container.endExternalDrag()
        container.layout()                                   // settle the close animation deterministically
        XCTAssertEqual(lastCell.frame.origin, slotOrigin(col: 2, row: 1),
                       "gap 收口后溢出 cell 必须回到真实末槽")
    }

    func testSettleTargetIsNilForOverflowGap() {
        let container = makeFullPage()
        container.beginExternalDrag(appID: "/Apps/X.app")
        // Last cell's RIGHT seam on a full page → gap == capacity: no visible slot on this page.
        let last = container.cellViews[5].frame
        container.updateExternalDrag(atContainerPoint: NSPoint(x: last.maxX - 4, y: last.midY))
        XCTAssertEqual(container.externalGapIndex, 6, "满页末缝 → gap == 容量")

        XCTAssertNil(container.settleTargetLocalRect(),
                     "溢出 gap 不得给出飞行目标（浮窗绝不朝幻影行/右缘外飞）——降级走 hard-cut")
    }

    func testSettleTargetStillResolvesForInPageGap() {
        let container = makeFullPage()
        container.beginExternalDrag(appID: "/Apps/X.app")
        let first = container.cellViews[0].frame
        container.updateExternalDrag(atContainerPoint: NSPoint(x: first.minX + 2, y: first.midY))
        XCTAssertEqual(container.externalGapIndex, 0)

        let target = container.settleTargetLocalRect()
        XCTAssertEqual(target, CGRect(x: first.minX + (metrics.cellWidth - metrics.iconSide) / 2,
                                      y: 8, width: metrics.iconSide, height: metrics.iconSide),
                       "页内 gap 的飞行目标照常解析（容量守卫不得误伤正常路径）")
    }

    func testUncappedRowsKeepLegacyUnboundedLayout() {
        // rows == 0 (folder grids / legacy fixtures): capacity unbounded — the gap may open a
        // new row, exactly as before this change (folder grids scroll vertically by design).
        let container = makeContainer(items: (0..<6).map(app), columns: 3, rows: 0)
        let lastCell = container.cellViews[5]
        container.beginExternalDrag(appID: "/Apps/X.app")
        let first = container.cellViews[0].frame
        container.updateExternalDrag(atContainerPoint: NSPoint(x: first.minX + 2, y: first.midY))
        container.layout()                                   // settle the animated make-way deterministically

        XCTAssertEqual(lastCell.frame.origin, slotOrigin(col: 0, row: 2),
                       "rows=0 保持旧行为：不限页容量（夹内多行合法形态）")
        XCTAssertNotNil(container.settleTargetLocalRect())
    }
}
