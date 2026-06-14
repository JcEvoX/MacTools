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
        // Label-style fields: defaults must reproduce the historical implicit rendering.
        XCTAssertEqual(resolved.labelColor, legacy.labelColor, "labelColor 默认必须 == .automatic")
        XCTAssertEqual(resolved.labelColor, .automatic, "默认 labelColor 锚定 .automatic（→ .labelColor）")
        XCTAssertEqual(resolved.labelFontSize, legacy.labelFontSize, "labelFontSize 默认必须 == 12")
        XCTAssertEqual(resolved.labelFontSize, 12, "默认 labelFontSize 锚定历史 12pt")
        XCTAssertEqual(resolved.labelFontWeight, legacy.labelFontWeight, "labelFontWeight 默认必须 == .regular")
        XCTAssertEqual(resolved.labelFontWeight, .regular, "默认 labelFontWeight 锚定 .regular")
        XCTAssertEqual(resolved.folderTitleFontSize, legacy.folderTitleFontSize,
                       "folderTitleFontSize 默认必须 == 历史 title2 字号")
        XCTAssertEqual(resolved.folderTitleWeight, legacy.folderTitleWeight,
                       "folderTitleWeight 默认必须 == .semibold")
        XCTAssertEqual(resolved.folderTitleWeight, .semibold, "默认 folderTitleWeight 锚定历史 .semibold")
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
        XCTAssertEqual(m.labelColor, .automatic)
        XCTAssertEqual(m.labelFontSize, 12)
        XCTAssertEqual(m.labelFontWeight, .regular)
        XCTAssertEqual(m.folderTitleFontSize, LaunchpadGridMetrics.defaultFolderTitleFontSize)
        XCTAssertEqual(m.folderTitleWeight, .semibold)
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

    // MARK: resolve(_:) — label-style injection (design 2026-06-13)

    /// The label size tier drives `labelFontSize` and, only above the historical baseline,
    /// the two-line `labelHeight`. The default `.medium` (12pt @64) and the `large` tier at
    /// 64pt (13pt) stay at exactly 32; only the larger tiers at big icons grow the strip,
    /// and `cellHeight` cannot shrink the icon for it (cellHeight = iconSide + 60 in label mode).
    func testLabelSizeDrivesLabelHeight() {
        // Default medium @64 → 12pt, height pinned at 32 (byte-compat).
        let medium64 = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(iconSide: 64, labelSize: .medium))
        XCTAssertEqual(medium64.labelFontSize, 12)
        XCTAssertEqual(medium64.labelHeight, 32, "默认字号档 labelHeight 必须严格 == 32（守 byte-compat）")

        // small @64 → 11pt, still 32 (smaller font never shrinks below the floor).
        let small64 = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(iconSide: 64, labelSize: .small))
        XCTAssertEqual(small64.labelFontSize, 11)
        XCTAssertEqual(small64.labelHeight, 32, "小字号档不低于 32 下限")

        // large @64 → 13pt, line height 16, ceil(16*2)=32 → still pinned at 32.
        let large64 = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(iconSide: 64, labelSize: .large))
        XCTAssertEqual(large64.labelFontSize, 13)
        XCTAssertEqual(large64.labelHeight, 32, "large@64 仍未越过 32 阈值")

        // large @96 → 17pt, line height 20, ceil(20*2)=40 → strip grows; cellHeight tracks the
        // labels-shown formula (iconSide + 60) which already reserves room above the label band.
        let large96 = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(iconSide: 96, labelSize: .large))
        XCTAssertEqual(large96.labelFontSize, 17)
        XCTAssertGreaterThan(large96.labelHeight, 32, "大字号大图标必须长高")
        XCTAssertEqual(large96.labelHeight,
                       LaunchpadGridMetrics.labelHeight(forFontSize: 17, weight: .regular),
                       "labelHeight 必须由字号/字重纯函数派生")

        // medium @96 → 15pt, line height 18, ceil(18*2)=36 → grows but less than large.
        let medium96 = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(iconSide: 96, labelSize: .medium))
        XCTAssertEqual(medium96.labelFontSize, 15)
        XCTAssertGreaterThan(medium96.labelHeight, 32)
        XCTAssertLessThan(medium96.labelHeight, large96.labelHeight, "字号越大 labelHeight 越高")
    }

    /// `resolve` injects the weight/colour preset and the icon-coordinated size verbatim into
    /// the metrics, and derives the folder big-title style (≥ app name, weight ≥ semibold).
    func testResolveInjectsLabelStyleIntoMetrics() {
        let m = LaunchpadGridMetrics.resolve(LaunchpadAppearance(
            iconSide: 80,
            labelColor: .accent,
            labelWeight: .semibold,
            labelSize: .large))

        // Color is carried as the preset (never an NSColor) so Equatable stays clean.
        XCTAssertEqual(m.labelColor, .accent)
        // Weight passes through.
        XCTAssertEqual(m.labelFontWeight, NSFont.Weight.semibold)
        // Size is the tier's pure function of the icon side.
        XCTAssertEqual(m.labelFontSize, LaunchpadLabelSize.large.fontSize(iconSide: 80))

        // Folder title: weight = emphasized selection, size = max(title2, app-name size).
        XCTAssertEqual(m.folderTitleWeight, LaunchpadLabelWeight.semibold.emphasized)
        XCTAssertGreaterThanOrEqual(m.folderTitleFontSize, m.labelFontSize, "标题字号 ≥ app 名字号")
        XCTAssertGreaterThanOrEqual(m.folderTitleFontSize, LaunchpadGridMetrics.defaultFolderTitleFontSize,
                                    "标题字号永不低于历史 title2")

        // A regular weight selection still floors the title at semibold (title never thinner).
        let regular = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(labelWeight: .regular))
        XCTAssertEqual(regular.folderTitleWeight, NSFont.Weight.semibold,
                       "常规字重下文件夹标题仍保底 .semibold")

        // A bold selection emphasises the title to bold while the grid label stays bold too.
        let bold = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(labelWeight: .bold))
        XCTAssertEqual(bold.labelFontWeight, NSFont.Weight.bold)
        XCTAssertEqual(bold.folderTitleWeight, NSFont.Weight.bold)

        // A larger app-name size pushes the folder title up beyond the historical baseline.
        let huge = LaunchpadGridMetrics.resolve(
            LaunchpadAppearance(iconSide: 96, labelSize: .large))
        XCTAssertEqual(huge.folderTitleFontSize, max(LaunchpadGridMetrics.defaultFolderTitleFontSize,
                                                     huge.labelFontSize))
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
        let cellsBefore = container.cellViews
        let framesBefore = cellsBefore.map(\.frame)
        XCTAssertEqual(framesBefore.first?.width, 116)
        // Default style: 12pt regular, `.labelColor` (the historical implicit rendering).
        XCTAssertEqual(cellsBefore.first?.labelFontForTesting?.pointSize, 12)
        XCTAssertEqual(cellsBefore.first?.labelColorForTesting, NSColor.labelColor)

        // A new appearance that changes geometry AND label style: bigger icon (96pt → 17pt large
        // label), bold weight, accent colour. The reused cell instances must re-apply all of it
        // through the `update` path (design 2026-06-13 — `update` must be symmetric with `init`).
        let restyled = LaunchpadGridMetrics.resolve(LaunchpadAppearance(
            iconSide: 96, labelColor: .accent, labelWeight: .bold, labelSize: .large))
        container.apply(grid: makeGrid(items: items, metrics: restyled))
        container.layout()   // windowless harness: drive the needsLayout pass manually
        let cellsAfter = container.cellViews
        let framesAfter = cellsAfter.map(\.frame)
        XCTAssertEqual(framesAfter.first?.width, restyled.cellWidth,
                       "同 items 换 metrics 必须重建 cell 尺寸（不能走 fast path）")
        XCTAssertNotEqual(framesBefore, framesAfter, "cell frame 必须随 metrics 变化")
        // The cells were REUSED (rebuildCells reuses by layoutID), so this proves `update`
        // re-applied the style on a live instance — the regression this change exists to prevent.
        XCTAssertTrue(cellsBefore.first === cellsAfter.first, "cell 实例应被复用（驱动 update 路径）")
        XCTAssertEqual(cellsAfter.first?.labelFontForTesting?.pointSize, restyled.labelFontSize,
                       "update 必须把新字号应用到复用的 cell.label")
        // The applied font must be the resolved system font at the new size+weight (comparing the
        // whole font sidesteps the normalized-vs-raw weight scale of font descriptor traits).
        let expectedFont = NSFont.systemFont(
            ofSize: restyled.labelFontSize, weight: restyled.labelFontWeight)
        XCTAssertEqual(cellsAfter.first?.labelFontForTesting, expectedFont,
                       "update 必须把新字号/字重应用到复用的 cell.label")
        XCTAssertEqual(cellsAfter.first?.labelColorForTesting, NSColor.controlAccentColor,
                       "update 必须把新颜色应用到复用的 cell.label")
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
