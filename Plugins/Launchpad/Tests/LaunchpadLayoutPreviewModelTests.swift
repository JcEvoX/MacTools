import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Design §4.3: the preview model must be a pure projection of the SAME
/// `LaunchpadLayoutMath` pipeline the live overlay runs — capacity equals `pageGrid`'s
/// output verbatim, tiles fill exactly one page, every rect nests (icon ⊆ window ⊆
/// canvas), hidden names drop label rects, and the compact two-layer drawing keeps the
/// real window-to-screen proportion (ruling P1).
@MainActor
final class LaunchpadLayoutPreviewModelTests: XCTestCase {

    /// MacBook-class anchor screen (the design's fallback size) + a settings-card canvas.
    private let anchorScreen = CGSize(width: 1512, height: 982)
    private let anchorCanvas = CGSize(width: 280, height: 168)

    /// `visible` defaults to the whole screen frame — fixtures with a menu bar / Dock
    /// pass an inset rect (top-left space, like the view's converted `visibleFrame`).
    private func makeModel(
        appearance: LaunchpadAppearance = LaunchpadAppearance(),
        mode: LaunchpadPreferences.WindowMode = .fullscreen,
        fixedColumns: Int? = nil,
        compactScale: Int = 72,
        screen: CGSize? = nil,
        visible: CGRect? = nil,
        canvas: CGSize? = nil
    ) -> LaunchpadLayoutPreviewModel {
        let frame = screen ?? anchorScreen
        return LaunchpadLayoutPreviewModel.make(
            appearance: appearance,
            mode: mode,
            fixedColumns: fixedColumns,
            compactScalePercent: compactScale,
            screenFrame: frame,
            visibleFrame: visible ?? CGRect(origin: .zero, size: frame),
            canvas: canvas ?? anchorCanvas
        )
    }

    /// The production pipeline run directly — what the model's numbers must equal.
    /// Screen sources mirror `LaunchpadOverlayController.targetFrame(on:)`: fullscreen
    /// windows cover the PHYSICAL screen frame, compact panels size off the VISIBLE
    /// frame — the two deliberately differ whenever a menu bar or Dock is present.
    private func expectedGrid(
        appearance: LaunchpadAppearance,
        mode: LaunchpadPreferences.WindowMode,
        fixedColumns: Int?,
        compactScale: Int,
        screen: CGSize,
        visible: CGRect? = nil
    ) -> (columns: Int, rows: Int) {
        let metrics = LaunchpadGridMetrics.resolve(appearance)
        let windowSize: CGSize
        switch mode {
        case .fullscreen:
            windowSize = screen
        case .compact:
            windowSize = LaunchpadLayoutMath.compactFrame(
                visible: visible ?? CGRect(origin: .zero, size: screen),
                scalePercent: compactScale,
                metrics: metrics,
                legacyCap: false
            ).size
        }
        return LaunchpadLayoutMath.pageGrid(
            viewport: LaunchpadLayoutMath.gridViewport(mode: mode, windowSize: windowSize),
            metrics: metrics,
            fixedColumns: fixedColumns
        )
    }

    // MARK: Same geometry source as the live view (the WYSIWYG anchor)

    /// Defaults must equal `pageGrid` fed through `gridViewport` — the model adds no
    /// arithmetic of its own. Hand-pinned: 1512×982 → viewport 1416×842 → 11 × 5.
    func testFullscreenDefaultsMatchTheSharedPageGridPipeline() {
        let model = makeModel()
        let expected = expectedGrid(
            appearance: LaunchpadAppearance(), mode: .fullscreen,
            fixedColumns: nil, compactScale: 72, screen: anchorScreen)
        XCTAssertEqual(model.columns, expected.columns)
        XCTAssertEqual(model.rows, expected.rows)
        XCTAssertEqual(model.columns, 11, "⌊1416 / 124⌋")
        XCTAssertEqual(model.rows, 5, "⌊(842 − 26 + 16) / 140⌋")
        XCTAssertEqual(model.perPage, 55)
        XCTAssertEqual(model.tiles.count, model.perPage, "满页占位 = rows × columns（拍板 P2）")
    }

    /// A sweep of preference combinations: the model's capacity never drifts from the
    /// pipeline's — for every icon size, label mode, window mode and column setting.
    func testCapacityMatchesPipelineAcrossPreferenceCombinations() {
        for side in [CGFloat(48), 64, 96] {
            for showsLabels in [true, false] {
                for mode in [LaunchpadPreferences.WindowMode.fullscreen, .compact] {
                    for fixed in [nil, 4, 12] as [Int?] {
                        let appearance = LaunchpadAppearance(
                            iconSide: side, showsLabels: showsLabels)
                        let model = makeModel(
                            appearance: appearance, mode: mode, fixedColumns: fixed)
                        let expected = expectedGrid(
                            appearance: appearance, mode: mode, fixedColumns: fixed,
                            compactScale: 72, screen: anchorScreen)
                        XCTAssertEqual(
                            model.columns, expected.columns,
                            "columns 漂移 @icon \(side) labels \(showsLabels) \(mode) fixed \(String(describing: fixed))")
                        XCTAssertEqual(
                            model.rows, expected.rows,
                            "rows 漂移 @icon \(side) labels \(showsLabels) \(mode) fixed \(String(describing: fixed))")
                        XCTAssertEqual(model.tiles.count, expected.columns * expected.rows)
                    }
                }
            }
        }
    }

    /// Fixed columns that fit are honoured exactly; overflowing ones surface CLAMPED —
    /// the caption derived from these numbers is the A4 ruling's user-facing signal.
    func testFixedColumnsHonouredAndOverflowSurfacesClamped() {
        XCTAssertEqual(makeModel(fixedColumns: 4).columns, 4)

        let big = makeModel(
            appearance: LaunchpadAppearance(iconSide: 96),
            fixedColumns: 12,
            screen: CGSize(width: 1024, height: 768))
        XCTAssertLessThan(big.columns, 12, "96pt × 12 列放不进 1024pt 屏，必须以 clamp 后数字示人")
        let expected = expectedGrid(
            appearance: LaunchpadAppearance(iconSide: 96), mode: .fullscreen,
            fixedColumns: 12, compactScale: 72, screen: CGSize(width: 1024, height: 768))
        XCTAssertEqual(big.columns, expected.columns)
    }

    // MARK: Screen-frame parity with `targetFrame(on:)` (frame ≠ visibleFrame)

    /// Fullscreen capacity must derive from the PHYSICAL screen frame, not the visible
    /// frame — the real overlay covers `screen.frame` (menu bar + Dock included), see
    /// `LaunchpadOverlayController.targetFrame(on:)`. Fixture: 1512×982 frame with a
    /// 38pt menu bar (visible height 944). 64pt icons + hidden names → row pitch 100,
    /// fullscreen vertical chrome 150: frame ⌊(982−150)/100⌋ = 8 rows; deriving from
    /// the visible frame would show 7 and the caption would contradict the real grid
    /// on the very same screen.
    func testFullscreenRowsUseTheScreenFrameNotTheVisibleFrame() {
        let model = makeModel(
            appearance: LaunchpadAppearance(showsLabels: false),
            mode: .fullscreen,
            visible: CGRect(x: 0, y: 38, width: 1512, height: 944))
        XCTAssertEqual(model.rows, 8, "fullscreen 行数必须按整屏 frame 算（与真实 overlay 同口径）")
    }

    /// Same parity on the horizontal axis: a left-hand Dock (75pt visible inset) must
    /// not cost the fullscreen preview a column. Default 64pt + labels → pitch 124:
    /// frame ⌊(1512−96)/124⌋ = 11 columns; the Dock-clipped width would give 10.
    func testFullscreenColumnsIgnoreADockedVisibleInset() {
        let model = makeModel(
            mode: .fullscreen,
            visible: CGRect(x: 75, y: 38, width: 1437, height: 944))
        XCTAssertEqual(model.columns, 11, "fullscreen 列数不受 Dock 占用的 visibleFrame 影响")
    }

    /// Compact keeps the OTHER side of the parity: the panel sizes and centres on the
    /// VISIBLE frame (`compactFrame(visible: screen.visibleFrame)`), so with a menu bar
    /// the preview window sits slightly below the screen-frame centre — exactly like
    /// the real panel does on screen.
    func testCompactWindowCentresAndSizesOffTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 38, width: 1512, height: 944)
        let model = makeModel(mode: .compact, visible: visible)
        XCTAssertEqual(model.windowRect.midX, visible.midX * model.scale, accuracy: 0.01)
        XCTAssertEqual(model.windowRect.midY, visible.midY * model.scale, accuracy: 0.01)

        let expected = expectedGrid(
            appearance: LaunchpadAppearance(), mode: .compact, fixedColumns: nil,
            compactScale: 72, screen: anchorScreen, visible: visible)
        XCTAssertEqual(model.columns, expected.columns)
        XCTAssertEqual(model.rows, expected.rows)
    }

    /// A visible rect that is degenerate or escapes the screen frame falls back to the
    /// whole frame instead of producing an off-canvas window.
    func testInvalidVisibleRectFallsBackToTheScreenFrame() {
        let canvasRect = { (model: LaunchpadLayoutPreviewModel) in
            CGRect(origin: .zero, size: model.screenSize).insetBy(dx: -0.01, dy: -0.01)
        }
        let zero = makeModel(mode: .compact, visible: .zero)
        XCTAssertTrue(canvasRect(zero).contains(zero.windowRect))
        XCTAssertEqual(zero, makeModel(mode: .compact))

        let escaping = makeModel(
            mode: .compact,
            visible: CGRect(x: 1000, y: 0, width: 1512, height: 982))
        XCTAssertTrue(canvasRect(escaping).contains(escaping.windowRect))
    }

    // MARK: Tile geometry

    /// Hidden names → no label rects at all; shown names → every tile carries one.
    func testHiddenNamesDropLabelRects() {
        let hidden = makeModel(appearance: LaunchpadAppearance(showsLabels: false))
        XCTAssertTrue(hidden.tiles.allSatisfy { $0.labelRect == nil })

        let shown = makeModel(appearance: LaunchpadAppearance(showsLabels: true))
        XCTAssertTrue(shown.tiles.allSatisfy { $0.labelRect != nil })
        XCTAssertGreaterThan(hidden.rows, shown.rows, "隐名行数应更多（与 LayoutMath 测试一致）")
    }

    /// Nesting invariant: every icon/label rect ⊆ windowRect ⊆ the screen canvas.
    func testRectsNestIconInsideWindowInsideCanvas() {
        for mode in [LaunchpadPreferences.WindowMode.fullscreen, .compact] {
            for showsLabels in [true, false] {
                let model = makeModel(
                    appearance: LaunchpadAppearance(iconSide: 96, showsLabels: showsLabels),
                    mode: mode)
                let canvasRect = CGRect(origin: .zero, size: model.screenSize)
                // Float-scaled rects: tolerate sub-point arithmetic noise at the edges.
                let window = model.windowRect.insetBy(dx: -0.01, dy: -0.01)
                XCTAssertTrue(canvasRect.insetBy(dx: -0.01, dy: -0.01).contains(model.windowRect),
                              "windowRect 必须落在画布内 @\(mode)")
                XCTAssertTrue(window.contains(model.searchBarRect), "搜索栏占位超出窗口 @\(mode)")
                for tile in model.tiles {
                    XCTAssertTrue(window.contains(tile.iconRect), "icon 超出窗口 @\(mode)")
                    if let label = tile.labelRect {
                        XCTAssertTrue(window.contains(label), "label 超出窗口 @\(mode)")
                    }
                }
                XCTAssertTrue(window.contains(
                    CGRect(origin: model.pageDotsCenter, size: .zero)))
            }
        }
    }

    /// Uniform scaling: every icon is iconSide × scale, and the horizontal pitch between
    /// neighbours equals (cellWidth + columnSpacing) × scale — one scale for everything.
    func testUniformScaleAcrossAllTiles() {
        let appearance = LaunchpadAppearance(iconSide: 64, showsLabels: true)
        let model = makeModel(appearance: appearance)
        let metrics = LaunchpadGridMetrics.resolve(appearance)
        for tile in model.tiles {
            XCTAssertEqual(tile.iconRect.width, metrics.iconSide * model.scale, accuracy: 1e-6)
            XCTAssertEqual(tile.iconRect.height, metrics.iconSide * model.scale, accuracy: 1e-6)
        }
        let pitch = (metrics.cellWidth + metrics.columnSpacing) * model.scale
        for index in 1..<model.columns {
            XCTAssertEqual(
                model.tiles[index].iconRect.minX - model.tiles[index - 1].iconRect.minX,
                pitch, accuracy: 1e-6)
        }
        let rowPitch = (metrics.cellHeight + metrics.rowSpacing) * model.scale
        if model.rows > 1 {
            XCTAssertEqual(
                model.tiles[model.columns].iconRect.minY - model.tiles[0].iconRect.minY,
                rowPitch, accuracy: 1e-6)
        }
    }

    // MARK: Window layers (ruling P1: screen frame + centred window)

    /// Fullscreen: the window IS the screen frame — one layer, no inner panel.
    func testFullscreenWindowFillsTheCanvas() {
        let model = makeModel(mode: .fullscreen)
        XCTAssertEqual(model.windowRect.origin, .zero)
        XCTAssertEqual(model.windowRect.width, model.screenSize.width, accuracy: 1e-6)
        XCTAssertEqual(model.windowRect.height, model.screenSize.height, accuracy: 1e-6)
    }

    /// Compact: a second, centred layer whose proportion to the screen frame equals the
    /// REAL compactFrame's proportion — the preview visualises the window-size slider.
    func testCompactWindowIsCentredAndKeepsTheRealProportion() {
        let model = makeModel(mode: .compact, compactScale: 72)
        XCTAssertLessThan(model.windowRect.width, model.screenSize.width)
        XCTAssertLessThan(model.windowRect.height, model.screenSize.height)
        XCTAssertEqual(model.windowRect.midX, model.screenSize.width / 2, accuracy: 0.01)
        XCTAssertEqual(model.windowRect.midY, model.screenSize.height / 2, accuracy: 0.01)

        let real = LaunchpadLayoutMath.compactFrame(
            visible: CGRect(origin: .zero, size: anchorScreen),
            scalePercent: 72,
            metrics: LaunchpadGridMetrics(),
            legacyCap: false)
        XCTAssertEqual(
            model.windowRect.width / model.screenSize.width,
            real.width / anchorScreen.width,
            accuracy: 1e-4, "两层比例必须与真实 compactFrame 一致（拍板 P1）")
        XCTAssertEqual(
            model.windowRect.height / model.screenSize.height,
            real.height / anchorScreen.height,
            accuracy: 1e-4)
    }

    /// The window-size slider moves the preview window monotonically.
    func testCompactScaleSliderGrowsTheWindowLayer() {
        let small = makeModel(mode: .compact, compactScale: 55)
        let large = makeModel(mode: .compact, compactScale: 90)
        XCTAssertGreaterThan(large.windowRect.width, small.windowRect.width)
        XCTAssertGreaterThan(large.windowRect.height, small.windowRect.height)
        XCTAssertLessThanOrEqual(large.windowRect.width, model95CapWidth() + 0.01)
    }

    private func model95CapWidth() -> CGFloat {
        // 95% ceiling of the scaled screen width (compactFrame's hard ceiling).
        makeModel(mode: .compact).screenSize.width * 0.95
    }

    // MARK: Robustness + value semantics

    /// Equatable drives the view's `.animation(value:)` — identical inputs must compare
    /// equal, and a changed preference must compare different.
    func testEquatableTracksInputs() {
        XCTAssertEqual(makeModel(), makeModel())
        XCTAssertNotEqual(makeModel(), makeModel(appearance: LaunchpadAppearance(iconSide: 96)))
        XCTAssertNotEqual(makeModel(mode: .compact, compactScale: 55),
                          makeModel(mode: .compact, compactScale: 90))
    }

    /// Degenerate inputs (first GeometryReader pass at .zero, headless host without a
    /// screen) must yield finite geometry, never NaN/∞ or a crash.
    func testDegenerateInputsStayFinite() {
        let zeroCanvas = makeModel(canvas: .zero)
        XCTAssertGreaterThan(zeroCanvas.scale, 0)
        XCTAssertTrue(zeroCanvas.windowRect.width.isFinite)
        XCTAssertGreaterThanOrEqual(zeroCanvas.tiles.count, 1)

        let zeroScreen = makeModel(screen: .zero)
        XCTAssertTrue(zeroScreen.screenSize.width.isFinite)
        XCTAssertGreaterThan(zeroScreen.screenSize.width, 0)
        XCTAssertGreaterThanOrEqual(zeroScreen.columns, 1)
        XCTAssertGreaterThanOrEqual(zeroScreen.rows, 1)
    }
}
