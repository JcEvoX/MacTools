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
                let actual = LaunchpadLayoutMath.pageGrid(
                    viewport: size,
                    metrics: LaunchpadGridMetrics(),
                    fixedColumns: pref == LaunchpadPreferences.autoColumns ? nil : pref
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

    /// Overflowing fixed columns: default (P1 wiring) preserves today's no-clamp
    /// behaviour; the opt-in flag reserved for P2 (ruling A4) clamps to what fits.
    func testPageGridFixedColumnOverflowClampIsOptIn() {
        let viewport = CGSize(width: 500, height: 600)
        let unclamped = LaunchpadLayoutMath.pageGrid(
            viewport: viewport, metrics: LaunchpadGridMetrics(), fixedColumns: 8)
        XCTAssertEqual(unclamped.columns, 8, "P1 默认不 clamp——保持现状行为")
        let clamped = LaunchpadLayoutMath.pageGrid(
            viewport: viewport, metrics: LaunchpadGridMetrics(), fixedColumns: 8,
            clampsOverflowingFixedColumns: true)
        XCTAssertEqual(clamped.columns, 4, "P2 开关：8 列放不进 500pt 宽时收到 4")
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

    /// The P2 branch (cap removed, ruling A5) honours the 4×3 floor — pinned now so
    /// wiring it later can't silently regress; NOT consumed by any P1 call site.
    func testCompactFrameScaledBranchHonoursFourByThreeFloor() {
        let metrics = LaunchpadGridMetrics.resolve(LaunchpadAppearance(iconSide: 96))
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = LaunchpadLayoutMath.compactFrame(
            visible: visible, scalePercent: 55, metrics: metrics, legacyCap: false)
        let minW = 4 * metrics.cellWidth + 3 * metrics.columnSpacing + 48
        let minH = 3 * metrics.cellHeight + 2 * metrics.rowSpacing + 112
        XCTAssertGreaterThanOrEqual(frame.width, minW)
        XCTAssertGreaterThanOrEqual(frame.height, minH)
        XCTAssertLessThanOrEqual(frame.width, visible.width * 0.95)
        XCTAssertLessThanOrEqual(frame.height, visible.height * 0.95)
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
}
