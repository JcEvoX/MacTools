import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Proves `LaunchpadGridCellView.hitTest` uses the correct coordinate system: the point
/// arrives in the *superview's* coordinates (Apple's documented contract), so a cell at a
/// non-zero grid origin still hits over its icon and falls through over its side padding.
/// (Guards against the Codex P1 concern about a double coordinate conversion.)
@MainActor
final class LaunchpadCellHitTestTests: XCTestCase {

    private final class FlippedContainer: NSView { override var isFlipped: Bool { true } }

    private func makeCell() -> LaunchpadGridCellView {
        let app = LaunchpadAppItem(id: "/A.app", name: "A", url: URL(fileURLWithPath: "/A.app"))
        return LaunchpadGridCellView(
            cell: .app(app),
            icons: [NSImage()],
            metrics: LaunchpadGridMetrics()
        )
    }

    func testIconAreaHitsCellAtNonZeroOrigin() {
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let cell = makeCell()
        cell.frame = NSRect(x: 124, y: 140, width: 116, height: 124)   // non-zero grid origin
        container.addSubview(cell)

        // Icon centre, expressed in CONTAINER coords (= the cell's superview coords).
        // Icon frame inside the cell is (26, 8, 64, 64) → centre (58, 40).
        let iconCentre = NSPoint(x: 124 + 58, y: 140 + 40)
        XCTAssertEqual(cell.hitTest(iconCentre), cell, "图标区域应命中 cell（坐标转换正确）")
    }

    func testSidePaddingFallsThroughAtNonZeroOrigin() {
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let cell = makeCell()
        cell.frame = NSRect(x: 124, y: 140, width: 116, height: 124)
        container.addSubview(cell)

        // A point in the left side padding (cell-local x = 4, left of the icon column).
        let padding = NSPoint(x: 124 + 4, y: 140 + 40)
        XCTAssertNil(cell.hitTest(padding), "侧边 padding 应落空，交给容器翻页")
    }

    // MARK: Hidden labels (design §1.2/§1.6 — P1 plumbing; wired to a preference in P2)

    private func makeHiddenLabelCell() -> (cell: LaunchpadGridCellView, metrics: LaunchpadGridMetrics) {
        let metrics = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 64, showsLabels: false))
        let app = LaunchpadAppItem(id: "/A.app", name: "A", url: URL(fileURLWithPath: "/A.app"))
        let cell = LaunchpadGridCellView(cell: .app(app), icons: [NSImage()], metrics: metrics)
        return (cell, metrics)
    }

    func testHiddenLabelsIconStillHits() {
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let (cell, metrics) = makeHiddenLabelCell()
        cell.frame = NSRect(x: 124, y: 140, width: metrics.cellWidth, height: metrics.cellHeight)
        container.addSubview(cell)

        // Icon frame inside the 92×84 cell is (14, 8, 64, 64) → centre (46, 40).
        let iconCentre = NSPoint(x: 124 + 46, y: 140 + 40)
        XCTAssertEqual(cell.hitTest(iconCentre), cell, "隐藏名字时图标区域仍应命中")
    }

    func testHiddenLabelsLabelStripFallsThrough() {
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let (cell, metrics) = makeHiddenLabelCell()
        cell.frame = NSRect(x: 124, y: 140, width: metrics.cellWidth, height: metrics.cellHeight)
        container.addSubview(cell)

        // Below the icon (+2pt hit slop): cell-local y = 78 is inside the 84pt-tall
        // cell but past the icon's hit region (8−2 ... 72+2) → must fall through.
        let belowIcon = NSPoint(x: 124 + 46, y: 140 + 78)
        XCTAssertNil(cell.hitTest(belowIcon), "隐藏名字时 label 条应落空，交给容器翻页")
    }
}
