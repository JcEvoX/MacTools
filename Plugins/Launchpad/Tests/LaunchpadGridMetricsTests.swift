import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// P1 regression anchors for the appearance → metrics resolution (design §1.2/§1.6):
/// the default appearance must reproduce the historical hardcoded metrics byte for
/// byte, hidden labels follow the agreed derivation (ruling A3), and a metrics change
/// with unchanged items must rebuild the cells (`apply(grid:)` sameMetrics, §1.3).
@MainActor
final class LaunchpadGridMetricsTests: XCTestCase {

    // MARK: resolve(_:) — byte-compat anchor

    /// THE anchor: `resolve(LaunchpadAppearance())` == `LaunchpadGridMetrics()` field by
    /// field. If this breaks, the P1 "zero behaviour change" promise is broken.
    func testResolveDefaultAppearanceMatchesDefaultMetricsFieldByField() {
        let resolved = LaunchpadGridMetrics.resolve(LaunchpadAppearance())
        let legacy = LaunchpadGridMetrics()
        XCTAssertEqual(resolved.cellWidth, legacy.cellWidth, "cellWidth 必须与默认初始化器一致")
        XCTAssertEqual(resolved.cellHeight, legacy.cellHeight, "cellHeight 必须与默认初始化器一致")
        XCTAssertEqual(resolved.iconSide, legacy.iconSide, "iconSide 必须与默认初始化器一致")
        XCTAssertEqual(resolved.columnSpacing, legacy.columnSpacing, "columnSpacing 必须与默认初始化器一致")
        XCTAssertEqual(resolved.rowSpacing, legacy.rowSpacing, "rowSpacing 必须与默认初始化器一致")
        XCTAssertEqual(resolved.showsLabels, legacy.showsLabels, "showsLabels 必须与默认初始化器一致")
        XCTAssertEqual(resolved.iconTopInset, legacy.iconTopInset, "iconTopInset 必须与默认初始化器一致")
        XCTAssertEqual(resolved.labelGap, legacy.labelGap, "labelGap 必须与默认初始化器一致")
        XCTAssertEqual(resolved.labelHeight, legacy.labelHeight, "labelHeight 必须与默认初始化器一致")
        XCTAssertEqual(resolved, legacy, "整体 Equatable 也必须相等（锚点）")
    }

    /// The legacy default values themselves, pinned: 116/124/64/8/16 + 8/8/32/shown.
    func testDefaultMetricsPinTheHistoricalValues() {
        let m = LaunchpadGridMetrics()
        XCTAssertEqual(m.cellWidth, 116)
        XCTAssertEqual(m.cellHeight, 124)
        XCTAssertEqual(m.iconSide, 64)
        XCTAssertEqual(m.columnSpacing, 8)
        XCTAssertEqual(m.rowSpacing, 16)
        XCTAssertTrue(m.showsLabels)
        XCTAssertEqual(m.iconTopInset, 8)
        XCTAssertEqual(m.labelGap, 8)
        XCTAssertEqual(m.labelHeight, 32)
    }

    // MARK: resolve(_:) — hidden labels (ruling A3)

    func testHiddenLabelsTightenCellAndCollapseLabel() {
        let m = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 64, showsLabels: false))
        XCTAssertEqual(m.cellWidth, 92, "隐藏名字 cellWidth = iconSide + 28（拍板 A3）")
        XCTAssertEqual(m.cellHeight, 84, "隐藏名字 cellHeight = iconSide + 20")
        XCTAssertEqual(m.labelHeight, 0, "隐藏名字 labelHeight 收为 0")
        XCTAssertFalse(m.showsLabels)
        XCTAssertEqual(m.iconSide, 64)
        XCTAssertEqual(m.iconTopInset, 8, "图标顶部留白不随显隐变化")
        XCTAssertEqual(m.columnSpacing, 8, "间距 v1 固定（拍板 A7）")
        XCTAssertEqual(m.rowSpacing, 16, "间距 v1 固定（拍板 A7）")
    }

    /// Width/height strictly increase with iconSide in both label modes (48...96, step 4).
    func testMetricsMonotonicInIconSide() {
        for showsLabels in [true, false] {
            var previous: LaunchpadGridMetrics?
            for side in stride(from: CGFloat(48), through: 96, by: 4) {
                let m = LaunchpadGridMetrics.resolve(
                    LaunchpadAppearance(iconSide: side, showsLabels: showsLabels))
                if let previous {
                    XCTAssertGreaterThan(m.cellWidth, previous.cellWidth)
                    XCTAssertGreaterThan(m.cellHeight, previous.cellHeight)
                }
                XCTAssertEqual(m.cellHeight, side + (showsLabels ? 60 : 20))
                XCTAssertEqual(m.cellWidth, side + (showsLabels ? 52 : 28))
                previous = m
            }
        }
    }

    // MARK: merge hot zone stays usable across icon sizes (design §1.6)

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func makeGrid(items: [LaunchpadDisplayCell],
                          metrics: LaunchpadGridMetrics) -> LaunchpadDragGrid {
        LaunchpadDragGrid(
            items: items,
            columns: 7,
            selectedID: nil,
            isCompact: false,
            metrics: metrics,
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
    }

    private func makeContainer(metrics: LaunchpadGridMetrics) -> LaunchpadGridContainerView {
        let items: [LaunchpadDisplayCell] = [
            .app(app("/Apps/A.app", "A")), .app(app("/Apps/B.app", "B")),
        ]
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: makeGrid(items: items, metrics: metrics))
        container.layout()
        return container
    }

    /// Dragging onto a neighbour's ICON CENTRE must arm the merge target at 48/64/96pt —
    /// the resolved merge inset (max(6, iconSide × 0.125)) keeps the hot zone usable.
    func testIconCentreArmsMergeTargetAcrossIconSizes() {
        for side in [CGFloat(48), 64, 96] {
            let metrics = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: side))
            let container = makeContainer(metrics: metrics)
            let cells = container.cellViews
            XCTAssertEqual(cells.count, 2)
            container.beginDirectDrag(cells[0], atWindowPoint: .zero)
            let target = cells[1]
            let iconCentre = NSPoint(
                x: target.frame.midX,
                y: target.frame.minY + metrics.iconTopInset + metrics.iconSide / 2
            )
            container.updateDrag(at: iconCentre)
            XCTAssertTrue(container.stackTargetCell === target,
                          "iconSide=\(side)：图标中心应 arm 合并目标")
            container.endDirectDrag(atWindowPoint: iconCentre)
        }
    }

    // MARK: apply(grid:) sameMetrics fast-path fix (design §1.3)

    func testApplyWithSameItemsButNewMetricsRelaysOutCells() {
        let items: [LaunchpadDisplayCell] = [
            .app(app("/Apps/A.app", "A")), .app(app("/Apps/B.app", "B")),
        ]
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: makeGrid(items: items, metrics: LaunchpadGridMetrics()))
        container.layout()
        let framesBefore = container.cellViews.map(\.frame)
        XCTAssertEqual(framesBefore.first?.width, 116)

        let bigger = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 96))
        container.apply(grid: makeGrid(items: items, metrics: bigger))
        container.layout()   // windowless harness: drive the needsLayout pass manually
        let framesAfter = container.cellViews.map(\.frame)
        XCTAssertEqual(framesAfter.first?.width, bigger.cellWidth,
                       "同 items 换 metrics 必须重建 cell 尺寸（不能走 fast path）")
        XCTAssertNotEqual(framesBefore, framesAfter, "cell frame 必须随 metrics 变化")
    }

    /// Control: identical metrics + identical items stays on the fast path (cells keep
    /// their instances — the pre-existing behaviour this fix must not disturb).
    func testApplyWithSameItemsAndSameMetricsKeepsCellInstances() {
        let items: [LaunchpadDisplayCell] = [
            .app(app("/Apps/A.app", "A")), .app(app("/Apps/B.app", "B")),
        ]
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        container.apply(grid: makeGrid(items: items, metrics: LaunchpadGridMetrics()))
        container.layout()
        let before = container.cellViews
        container.apply(grid: makeGrid(items: items, metrics: LaunchpadGridMetrics()))
        let after = container.cellViews
        XCTAssertEqual(before.count, after.count)
        for (lhs, rhs) in zip(before, after) {
            XCTAssertTrue(lhs === rhs, "同 items 同 metrics 应保留 cell 实例（fast path）")
        }
    }
}
