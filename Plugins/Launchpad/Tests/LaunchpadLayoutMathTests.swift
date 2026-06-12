import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// P1 equivalence proofs for the pure layout layer (design §1.6): `pageGrid` must
/// reproduce the algorithm previously embedded in `LaunchpadGridView.updateLayout`,
/// `compactFrame(legacyCap: true)` must reproduce the overlay controller's historical
/// compact formula, and the chrome constants must pin today's literals.
@MainActor
final class LaunchpadLayoutMathTests: XCTestCase {

    // MARK: pageGrid ≡ legacy updateLayout

    /// The algorithm verbatim as it lived in `LaunchpadGridView.updateLayout(size:)`
    /// before P1 (116/124/8/16 mirror constants + the 26pt page-dot reserve).
    private func legacyLayout(size: CGSize, columnsPreference: Int) -> (columns: Int, rows: Int) {
        let cellWidth: CGFloat = 116
        let cellHeight: CGFloat = 124
        let columnSpacing: CGFloat = 8
        let rowSpacing: CGFloat = 16
        let columns: Int
        if columnsPreference != LaunchpadPreferences.autoColumns {
            columns = max(1, columnsPreference)
        } else {
            let usable = max(size.width, cellWidth)
            columns = max(1, Int(usable / (cellWidth + columnSpacing)))
        }
        let usableHeight = max(cellHeight, size.height - 26)
        let rows = max(1, Int((usableHeight + rowSpacing) / (cellHeight + rowSpacing)))
        return (columns, rows)
    }

    func testPageGridMatchesLegacyUpdateLayoutAcrossSizes() {
        let sizes: [CGSize] = [
            CGSize(width: 140, height: 140),     // tiny — both floors engage
            CGSize(width: 320, height: 300),
            CGSize(width: 800, height: 600),
            CGSize(width: 912, height: 594),     // compact panel viewport
            CGSize(width: 1416, height: 842),    // fullscreen 1512×982 viewport
            CGSize(width: 1456, height: 900),    // design §1.6 anchor size
            CGSize(width: 2000, height: 1200),
            CGSize(width: 3008, height: 1600),
        ]
        let preferences = [LaunchpadPreferences.autoColumns, 4, 7, 12]
        for size in sizes {
            for pref in preferences {
                let expected = legacyLayout(size: size, columnsPreference: pref)
                // `clampsOverflowingFixedColumns: false` — the historical algorithm never
                // clamped, so the equivalence proof must run the legacy branch (production
                // has clamped by default since P2, ruling A4 — pinned separately below).
                let actual = LaunchpadLayoutMath.pageGrid(
                    viewport: size,
                    metrics: LaunchpadGridMetrics(),
                    fixedColumns: pref == LaunchpadPreferences.autoColumns ? nil : pref,
                    clampsOverflowingFixedColumns: false
                )
                XCTAssertEqual(actual.columns, expected.columns,
                               "columns 漂移 @\(size) pref=\(pref)")
                XCTAssertEqual(actual.rows, expected.rows,
                               "rows 漂移 @\(size) pref=\(pref)")
            }
        }
    }

    /// Hand-computed anchor (design §1.6): 1456×900, default metrics, auto columns.
    func testPageGridHandComputedAnchor() {
        let grid = LaunchpadLayoutMath.pageGrid(
            viewport: CGSize(width: 1456, height: 900),
            metrics: LaunchpadGridMetrics(),
            fixedColumns: nil
        )
        XCTAssertEqual(grid.columns, 11)   // ⌊1456 / 124⌋
        XCTAssertEqual(grid.rows, 6)       // ⌊(900 − 26 + 16) / 140⌋
    }

    func testPageGridTinyViewportFloorsAtOneByOne() {
        let grid = LaunchpadLayoutMath.pageGrid(
            viewport: CGSize(width: 10, height: 10),
            metrics: LaunchpadGridMetrics(),
            fixedColumns: nil
        )
        XCTAssertGreaterThanOrEqual(grid.columns, 1)
        XCTAssertGreaterThanOrEqual(grid.rows, 1)
    }

    /// Overflowing fixed columns clamp silently BY DEFAULT since P2 (ruling A4): a
    /// fixed count the viewport can't hold collapses to what fits; a count that fits
    /// is honoured exactly; the legacy no-clamp branch stays reachable via `false`.
    func testPageGridFixedColumnOverflowClampsByDefault() {
        let viewport = CGSize(width: 500, height: 600)
        let clamped = LaunchpadLayoutMath.pageGrid(
            viewport: viewport, metrics: LaunchpadGridMetrics(), fixedColumns: 8)
        XCTAssertEqual(clamped.columns, 4, "默认 clamp：8 列放不进 500pt 宽时收到 4（拍板 A4）")

        let fits = LaunchpadLayoutMath.pageGrid(
            viewport: viewport, metrics: LaunchpadGridMetrics(), fixedColumns: 3)
        XCTAssertEqual(fits.columns, 3, "放得下的固定列数不受 clamp 影响")

        let legacy = LaunchpadLayoutMath.pageGrid(
            viewport: viewport, metrics: LaunchpadGridMetrics(), fixedColumns: 8,
            clampsOverflowingFixedColumns: false)
        XCTAssertEqual(legacy.columns, 8, "显式 false 保留 P2 前的溢出行为（等价证明用）")
    }

    /// The clamp is what keeps "fixed 12 columns × 96pt icons" from overflowing a
    /// fullscreen viewport — the concrete A4 scenario the icon-size slider introduces.
    func testPageGridClampHandlesBigIconsWithMaxFixedColumns() {
        let metrics = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 96))
        let grid = LaunchpadLayoutMath.pageGrid(
            viewport: CGSize(width: 1416, height: 842),     // fullscreen 1512×982 viewport
            metrics: metrics,
            fixedColumns: 12)                               // 12 × 148 + 11 × 8 = 1864pt > 1416
        XCTAssertEqual(grid.columns, Int(1416 / (metrics.cellWidth + metrics.columnSpacing)),
                       "12 列 96pt 图标放不下时收到可容纳列数")
        XCTAssertLessThan(grid.columns, 12)
    }

    /// Bigger icons never increase capacity (48...96 property-style sweep).
    func testPageGridCapacityMonotonicNonIncreasingInIconSide() {
        let viewport = CGSize(width: 1456, height: 900)
        for showsLabels in [true, false] {
            var previous: (columns: Int, rows: Int)?
            for side in stride(from: CGFloat(48), through: 96, by: 4) {
                let metrics = LaunchpadGridMetrics.resolve(
                    LaunchpadAppearance(iconSide: side, showsLabels: showsLabels))
                let grid = LaunchpadLayoutMath.pageGrid(
                    viewport: viewport, metrics: metrics, fixedColumns: nil)
                if let previous {
                    XCTAssertLessThanOrEqual(grid.columns, previous.columns)
                    XCTAssertLessThanOrEqual(grid.rows, previous.rows)
                }
                previous = grid
            }
        }
    }

    /// Hidden labels gain rows at the same viewport height (the design's 5 → 7-ish
    /// density jump; at 842pt usable it lands 6 → 8).
    func testHiddenLabelsGainRowsAtSameViewport() {
        let viewport = CGSize(width: 1416, height: 842)
        let shown = LaunchpadLayoutMath.pageGrid(
            viewport: viewport,
            metrics: LaunchpadGridMetrics.resolve(LaunchpadAppearance(showsLabels: true)),
            fixedColumns: nil)
        let hidden = LaunchpadLayoutMath.pageGrid(
            viewport: viewport,
            metrics: LaunchpadGridMetrics.resolve(LaunchpadAppearance(showsLabels: false)),
            fixedColumns: nil)
        XCTAssertGreaterThan(hidden.rows, shown.rows, "隐藏名字应得到更多行")
        XCTAssertGreaterThan(hidden.columns, shown.columns, "收紧 cellWidth 应得到更多列")
    }

    // MARK: compactFrame — legacy formula reproduction

    /// The historical compact formula verbatim from `LaunchpadOverlayController`.
    private func legacyCompactFrame(visible: NSRect) -> NSRect {
        let width = min(960, visible.width * 0.72)
        let height = min(680, visible.height * 0.82)
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    func testCompactFrameLegacyCapMatchesHistoricalFormula() {
        let visibles: [NSRect] = [
            NSRect(x: 0, y: 0, width: 1512, height: 950),     // built-in, cap binds
            NSRect(x: 0, y: 38, width: 1200, height: 662),    // small external, % binds
            NSRect(x: 100, y: 50, width: 2560, height: 1377), // big external, cap binds
            NSRect(x: 0, y: 0, width: 800, height: 500),      // both % bind
        ]
        for visible in visibles {
            let actual = LaunchpadLayoutMath.compactFrame(visible: visible, legacyCap: true)
            XCTAssertEqual(actual, legacyCompactFrame(visible: visible),
                           "legacyCap 帧漂移 @\(visible)")
        }
    }

    /// The default parameter set is the legacy-compatible one — call sites that pass
    /// only `visible:` get today's frame.
    func testCompactFrameDefaultsToLegacyCap() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 950)
        XCTAssertEqual(LaunchpadLayoutMath.compactFrame(visible: visible),
                       legacyCompactFrame(visible: visible))
    }

    /// The production (P2) branch: the default 72% reproduces the historical frame
    /// wherever the old 960×680 cap did not bind (laptop-class screens) — the "default
    /// keeps today's look" half of ruling A5; the cap removal half is pinned below.
    func testCompactFrameScaledDefaultReproducesLegacyWhereCapDidNotBind() {
        let visible = NSRect(x: 0, y: 38, width: 1200, height: 662)   // 1200×0.72 < 960
        let scaled = LaunchpadLayoutMath.compactFrame(
            visible: visible, scalePercent: 72, metrics: LaunchpadGridMetrics(), legacyCap: false)
        XCTAssertEqual(scaled, legacyCompactFrame(visible: visible),
                       "默认 72% 在 cap 不约束的屏幕上必须复现现帧")
    }

    /// Ruling A5's behaviour change, pinned: on a large screen the scaled branch grows
    /// past the old 960×680 cap (otherwise the new slider would be a no-op there), and
    /// a bigger percentage yields a wider frame.
    func testCompactFrameScaledBranchOutgrowsLegacyCapOnBigScreens() {
        let visible = NSRect(x: 100, y: 50, width: 2560, height: 1377)
        let scaled = LaunchpadLayoutMath.compactFrame(
            visible: visible, scalePercent: 72, metrics: LaunchpadGridMetrics(), legacyCap: false)
        XCTAssertGreaterThan(scaled.width, 960, "硬 cap 已移除：大屏 72% 必须超过旧 960 上限")
        XCTAssertGreaterThan(scaled.height, 680)

        let bigger = LaunchpadLayoutMath.compactFrame(
            visible: visible, scalePercent: 90, metrics: LaunchpadGridMetrics(), legacyCap: false)
        XCTAssertGreaterThan(bigger.width, scaled.width, "滑杆增大 → 帧单调变宽")
    }

    /// The P2 branch (cap removed, ruling A5) honours the 4×3 floor — pinned in P1 so
    /// wiring it could not silently regress; now also the production branch. The width
    /// floor must back-add the FOURTH columnSpacing (`columnsThatFit` divides by the
    /// full pitch, so "4 cells + 3 gaps" floors at only 3 columns — the P2 review bug).
    func testCompactFrameScaledBranchHonoursFourByThreeFloor() {
        let metrics = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 96))
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = LaunchpadLayoutMath.compactFrame(
            visible: visible, scalePercent: 55, metrics: metrics, legacyCap: false)
        let minW = 4 * (metrics.cellWidth + metrics.columnSpacing) + 48
        let minH = 3 * metrics.cellHeight + 2 * metrics.rowSpacing + 112
        XCTAssertGreaterThanOrEqual(frame.width, minW)
        XCTAssertGreaterThanOrEqual(frame.height, minH)
        XCTAssertLessThanOrEqual(frame.width, visible.width * 0.95)
        XCTAssertLessThanOrEqual(frame.height, visible.height * 0.95)
    }

    /// The floor's PROMISE, not its formula: a floored compact frame must actually
    /// render ≥ 4 columns × 3 rows once it round-trips through the production chain
    /// compactFrame → gridViewport(.compact) → pageGrid. (The P1 pin only asserted
    /// frame.width ≥ a mirrored minW, so a floor short by one columnSpacing stayed
    /// green while rendering 3 columns — this chained sweep is the regression guard.)
    func testCompactFrameFloorYieldsFourByThreeThroughTheProductionChain() {
        for showsLabels in [true, false] {
            for side in [CGFloat(48), 64, 96] {
                let metrics = LaunchpadGridMetrics.resolve(
                    LaunchpadAppearance(iconSide: side, showsLabels: showsLabels))
                // Size the screen so the floor BINDS (×1.2: 55% of it sits below any
                // sane floor, while the 95% ceiling still clears the floor) — computed
                // from the 4×3 grid's true need, NOT from the production constant.
                let need = CGSize(
                    width: 4 * (metrics.cellWidth + metrics.columnSpacing) + 48,
                    height: 3 * metrics.cellHeight + 2 * metrics.rowSpacing + 112)
                let visible = NSRect(x: 0, y: 0,
                                     width: ceil(need.width * 1.2),
                                     height: ceil(need.height * 1.2))
                let frame = LaunchpadLayoutMath.compactFrame(
                    visible: visible, scalePercent: 55, metrics: metrics, legacyCap: false)
                let viewport = LaunchpadLayoutMath.gridViewport(
                    mode: .compact, windowSize: frame.size)
                let grid = LaunchpadLayoutMath.pageGrid(
                    viewport: viewport, metrics: metrics, fixedColumns: nil)
                XCTAssertGreaterThanOrEqual(
                    grid.columns, 4,
                    "地板帧必须真渲染 ≥4 列（icon \(side) labels \(showsLabels)）")
                XCTAssertGreaterThanOrEqual(
                    grid.rows, 3,
                    "地板帧必须真渲染 ≥3 行（icon \(side) labels \(showsLabels)）")
            }
        }
    }

    // MARK: folderPanelMaxWidth (P2: the 760 literal replaced by a derived cap)

    /// Pins the folder plate's derived width: 672 at the default 64pt (the documented,
    /// deliberate change from the historical 760 literal) and 832 at 96pt (the case the
    /// literal could not hold: a 5 × 148 row is 772 > 760). Folder metrics always show
    /// labels (ruling A1), so only the icon side varies here.
    func testFolderPanelMaxWidthPinsDerivedWidths() {
        XCTAssertEqual(
            LaunchpadLayoutMath.folderPanelMaxWidth(metrics: LaunchpadGridMetrics()), 672,
            "默认 64pt：5×116 + 4×8 + 60 = 672（取代 760 的既定外观变化）")
        XCTAssertEqual(
            LaunchpadLayoutMath.folderPanelMaxWidth(
                metrics: LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 96))), 832,
            "96pt：5×148 + 4×8 + 60 = 832")
        XCTAssertEqual(
            LaunchpadLayoutMath.folderPanelMaxWidth(
                metrics: LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 48))), 592,
            "48pt：5×100 + 4×8 + 60 = 592")
    }

    // MARK: Chrome + gridViewport

    /// Pins the literals that used to live inline in `LaunchpadGridView.body`.
    func testChromeStandardPinsTheHistoricalLiterals() {
        let fullscreen = LaunchpadLayoutMath.Chrome.standard(isCompact: false)
        XCTAssertEqual(fullscreen.searchBarWidth, 360)
        XCTAssertEqual(fullscreen.searchBarHeight, 28)
        XCTAssertEqual(fullscreen.stackSpacing, 20)
        XCTAssertEqual(fullscreen.topPadding, 60)
        XCTAssertEqual(fullscreen.bottomPadding, 32)
        XCTAssertEqual(fullscreen.horizontalPadding, 48)

        let compact = LaunchpadLayoutMath.Chrome.standard(isCompact: true)
        XCTAssertEqual(compact.searchBarWidth, 360)
        XCTAssertEqual(compact.searchBarHeight, 28)
        XCTAssertEqual(compact.stackSpacing, 14)
        XCTAssertEqual(compact.topPadding, 24)
        XCTAssertEqual(compact.bottomPadding, 20)
        XCTAssertEqual(compact.horizontalPadding, 24)

        XCTAssertEqual(LaunchpadLayoutMath.Chrome.pageIndicatorReserve, 26)
    }

    func testGridViewportSubtractsChromeAndStaysPositive() {
        // Fullscreen 1512×982: width − 2×48, height − 60 − 32 − 28 − 20.
        let fullscreen = LaunchpadLayoutMath.gridViewport(
            mode: .fullscreen, windowSize: CGSize(width: 1512, height: 982))
        XCTAssertEqual(fullscreen.width, 1416)
        XCTAssertEqual(fullscreen.height, 842)

        // Compact 960×680: width − 2×24, height − 24 − 20 − 28 − 14.
        let compact = LaunchpadLayoutMath.gridViewport(
            mode: .compact, windowSize: CGSize(width: 960, height: 680))
        XCTAssertEqual(compact.width, 912)
        XCTAssertEqual(compact.height, 594)

        // Degenerate window: clamped at zero, never negative.
        let tiny = LaunchpadLayoutMath.gridViewport(
            mode: .fullscreen, windowSize: CGSize(width: 10, height: 10))
        XCTAssertGreaterThanOrEqual(tiny.width, 0)
        XCTAssertGreaterThanOrEqual(tiny.height, 0)
    }

    // MARK: Shared slot / cell-local frames (live grid + settings preview)

    /// Pins the cell-local hardcodes the live cell view was built around (icon centred
    /// at y = 8; label 2pt side insets, 8 below the icon). `LaunchpadGridCellView` and
    /// the settings preview both read THESE — changing them is a conscious act that
    /// moves both surfaces together, never a silent preview drift.
    func testCellLocalIconAndLabelFramesPinTheHistoricalLayout() {
        let shown = LaunchpadGridMetrics()   // 64pt, labels shown
        XCTAssertEqual(shown.iconFrameInCell, CGRect(x: 26, y: 8, width: 64, height: 64),
                       "icon 居中：(116 − 64) / 2 = 26，y = iconTopInset")
        XCTAssertEqual(shown.labelFrameInCell, CGRect(x: 2, y: 80, width: 112, height: 32),
                       "label：x = 2，y = 8 + 64 + 8，宽 = cellWidth − 4")

        let hidden = LaunchpadGridMetrics.resolve(LaunchpadAppearance(showsLabels: false))
        XCTAssertEqual(hidden.iconFrameInCell, CGRect(x: 14, y: 8, width: 64, height: 64),
                       "隐名 cellWidth = 92 → (92 − 64) / 2 = 14")
        XCTAssertEqual(hidden.labelFrameInCell.height, 0, "隐名 label 高度收为 0")
    }

    /// Pins `slotRect`'s centring contract — floored whole-point left inset, row-major
    /// pitch — byte-compatible with the formula that lived inline in
    /// `LaunchpadGridContainerView.slotRect` before the extraction.
    func testSlotRectPinsFlooredCentringAndRowMajorPitch() {
        let metrics = LaunchpadGridMetrics()
        // 11 columns @116 + 10 gaps @8 → grid 1356; (1416 − 1356) / 2 = 30.
        let first = LaunchpadLayoutMath.slotRect(
            index: 0, columns: 11, containerWidth: 1416, metrics: metrics)
        XCTAssertEqual(first, CGRect(x: 30, y: 0, width: 116, height: 124))

        let second = LaunchpadLayoutMath.slotRect(
            index: 1, columns: 11, containerWidth: 1416, metrics: metrics)
        XCTAssertEqual(second.minX, first.minX + 124, "横向 pitch = cellWidth + columnSpacing")

        let nextRow = LaunchpadLayoutMath.slotRect(
            index: 11, columns: 11, containerWidth: 1416, metrics: metrics)
        XCTAssertEqual(nextRow.minX, first.minX, "row-major 换行回到首列")
        XCTAssertEqual(nextRow.minY, 140, "纵向 pitch = cellHeight + rowSpacing")

        // Fractional leftover floors to a whole point: (1417 − 1356) / 2 = 30.5 → 30.
        let odd = LaunchpadLayoutMath.slotRect(
            index: 0, columns: 11, containerWidth: 1417, metrics: metrics)
        XCTAssertEqual(odd.minX, 30, "inset 向下取整（与真实容器一致）")

        // Narrower than the grid: inset clamps at 0 instead of going negative.
        let cramped = LaunchpadLayoutMath.slotRect(
            index: 0, columns: 11, containerWidth: 1000, metrics: metrics)
        XCTAssertEqual(cramped.minX, 0)
    }
}
