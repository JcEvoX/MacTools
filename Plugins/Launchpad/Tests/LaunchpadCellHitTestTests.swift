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
        LaunchpadGridCellView(
            app: LaunchpadAppItem(id: "/A.app", name: "A", url: URL(fileURLWithPath: "/A.app")),
            metrics: LaunchpadGridMetrics()
        )
    }

    func testIconAreaHitsCellAtNonZeroOrigin() {
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let cell = makeCell()
        cell.frame = NSRect(x: 124, y: 140, width: 116, height: 124)   // non-zero grid origin
        container.addSubview(cell)

        // Icon centre, expressed in CONTAINER coords (= the cell's superview coords).
        // Icon frame inside the cell is (22, 8, 72, 72) → centre (58, 44).
        let iconCentre = NSPoint(x: 124 + 58, y: 140 + 44)
        XCTAssertEqual(cell.hitTest(iconCentre), cell, "图标区域应命中 cell（坐标转换正确）")
    }

    func testSidePaddingFallsThroughAtNonZeroOrigin() {
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let cell = makeCell()
        cell.frame = NSRect(x: 124, y: 140, width: 116, height: 124)
        container.addSubview(cell)

        // A point in the left side padding (cell-local x = 4, left of the icon column).
        let padding = NSPoint(x: 124 + 4, y: 140 + 44)
        XCTAssertNil(cell.hitTest(padding), "侧边 padding 应落空，交给容器翻页")
    }
}
