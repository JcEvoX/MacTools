import AppKit

/// Appearance preference snapshot (design §1.2) — the single input to
/// `LaunchpadGridMetrics.resolve(_:)` and, later, the settings layout preview.
/// Features 7/8 (hide names / icon size) own the writes; everything else only consumes.
struct LaunchpadAppearance: Equatable {
    /// Feature 8: 48...96pt, step 4. Default mirrors the long-standing 64pt icon.
    var iconSide: CGFloat = 64
    /// Feature 7: `!hidesAppNames`. Default = labels visible (today's behaviour).
    var showsLabels: Bool = true
}

extension LaunchpadGridMetrics {
    /// The ONLY resolution entry point from appearance preferences to grid metrics.
    /// Regression anchor (design §1.2): `resolve(LaunchpadAppearance())` must equal
    /// `LaunchpadGridMetrics()` field by field — the default appearance reproduces the
    /// historical hardcoded layout byte for byte.
    ///
    /// Derivation (@64pt check): labels shown → cellWidth = iconSide + 52 = 116,
    /// cellHeight = 8 + iconSide + 8 + 32 + 12 = iconSide + 60 = 124. Labels hidden
    /// (ruling A3, tightened) → cellWidth = iconSide + 28, cellHeight = 8 + iconSide
    /// + 12 = iconSide + 20, labelHeight = 0. Fixed chrome rather than a scale factor:
    /// at 48pt the label still fits two lines; at 96pt density approaches iOS.
    /// Spacing stays fixed in v1 (ruling A7); the parameters reserve the slot.
    static func resolve(
        _ appearance: LaunchpadAppearance,
        columnSpacing: CGFloat = 8,
        rowSpacing: CGFloat = 16
    ) -> LaunchpadGridMetrics {
        let iconSide = appearance.iconSide
        let showsLabels = appearance.showsLabels
        return LaunchpadGridMetrics(
            cellWidth: iconSide + (showsLabels ? 52 : 28),
            cellHeight: iconSide + (showsLabels ? 60 : 20),
            iconSide: iconSide,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            showsLabels: showsLabels,
            iconTopInset: 8,
            labelGap: 8,
            labelHeight: showsLabels ? 32 : 0
        )
    }
}

/// Pure layout math shared by the real launcher views and (P3) the settings preview —
/// one source of truth, so WYSIWYG is a structural guarantee, not a convention
/// (design §1.2). No view state, no side effects: everything here is unit-testable.
enum LaunchpadLayoutMath {
    /// Chrome constants pulled out of `LaunchpadGridView.body` / `updateLayout` so the
    /// live view and the preview read the SAME numbers (design §1.1 — anti-drift).
    struct Chrome: Equatable {
        var searchBarWidth: CGFloat
        var searchBarHeight: CGFloat
        /// VStack spacing between the search bar and the paged grid.
        var stackSpacing: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        var horizontalPadding: CGFloat
        /// Height reserved below the grid for the page-indicator row (shared by
        /// `pageGrid` and the preview's "subtract chrome" math).
        static let pageIndicatorReserve: CGFloat = 26

        static func standard(isCompact: Bool) -> Chrome {
            Chrome(
                searchBarWidth: 360,
                searchBarHeight: 28,
                stackSpacing: isCompact ? 14 : 20,
                topPadding: isCompact ? 24 : 60,
                bottomPadding: isCompact ? 20 : 32,
                horizontalPadding: isCompact ? 24 : 48
            )
        }
    }

    /// The compact panel's frame on `visible` (the screen's `visibleFrame`).
    ///
    /// P1 wiring keeps `legacyCap: true` — byte-compatible with the historical
    /// `min(960, w × 0.72) × min(680, h × 0.82)` centred formula. P2 flips the cap off
    /// and wires `scalePercent`/`metrics` (design §3.3, ruling A5 — removing the hard
    /// cap is a deliberate behaviour change that must NOT ship with the P1 plumbing).
    static func compactFrame(
        visible: NSRect,
        scalePercent: Int = 72,
        metrics: LaunchpadGridMetrics = LaunchpadGridMetrics(),
        legacyCap: Bool = true
    ) -> NSRect {
        let width: CGFloat
        let height: CGFloat
        if legacyCap {
            width = min(960, visible.width * 0.72)
            height = min(680, visible.height * 0.82)
        } else {
            let s = CGFloat(scalePercent) / 100
            // Floor: a 4-column × 3-row grid plus chrome must always fit (§3.3), so a
            // bigger icon raises the floor and the panel can never shrink below 4×3.
            let minW = 4 * metrics.cellWidth + 3 * metrics.columnSpacing + 48
            let minH = 3 * metrics.cellHeight + 2 * metrics.rowSpacing + 112
            width = min(max(visible.width * s, minW), visible.width * 0.95)
            height = min(max(visible.height * min(s + 0.10, 0.92), minH), visible.height * 0.95)
        }
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Window size → the paged grid's viewport (what `LaunchpadGridView`'s
    /// GeometryReader measures): subtract the outer paddings, the search bar and the
    /// VStack spacing. The page-indicator reserve deliberately stays inside `pageGrid`,
    /// exactly like the live view (the GeometryReader wraps grid + dots together).
    static func gridViewport(mode: LaunchpadPreferences.WindowMode, windowSize: CGSize) -> CGSize {
        let chrome = Chrome.standard(isCompact: mode == .compact)
        return CGSize(
            width: max(0, windowSize.width - 2 * chrome.horizontalPadding),
            height: max(0, windowSize.height - chrome.topPadding - chrome.bottomPadding
                - chrome.searchBarHeight - chrome.stackSpacing)
        )
    }

    /// Page capacity — `LaunchpadGridView.updateLayout(size:)` made pure, algorithm
    /// byte-compatible. `fixedColumns == nil` fits columns to the width.
    ///
    /// `clampsOverflowingFixedColumns` reserves ruling A4 for P2 (a fixed column count
    /// that cannot fit the width gets silently clamped to what fits); the P1 wiring
    /// passes the default `false`, preserving today's overflow behaviour exactly.
    static func pageGrid(
        viewport: CGSize,
        metrics: LaunchpadGridMetrics,
        fixedColumns: Int?,
        clampsOverflowingFixedColumns: Bool = false
    ) -> (columns: Int, rows: Int) {
        func columnsThatFit(_ width: CGFloat) -> Int {
            let usable = max(width, metrics.cellWidth)
            return max(1, Int(usable / (metrics.cellWidth + metrics.columnSpacing)))
        }
        let columns: Int
        if let fixed = fixedColumns {
            let requested = max(1, fixed)
            columns = clampsOverflowingFixedColumns
                ? min(requested, columnsThatFit(viewport.width))
                : requested
        } else {
            columns = columnsThatFit(viewport.width)
        }
        // Reserve ~26pt for the page indicator row below the grid.
        let usableHeight = max(metrics.cellHeight, viewport.height - Chrome.pageIndicatorReserve)
        let rows = max(1, Int((usableHeight + metrics.rowSpacing) / (metrics.cellHeight + metrics.rowSpacing)))
        return (columns, rows)
    }
}
