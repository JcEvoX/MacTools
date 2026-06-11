import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// §A2: the carry's floating icon must stay inside the overlay's screen even when the locked
/// mouse gesture wanders past its edges. Only the PRESENTED window is clamped — classification
/// and the edge turner keep the real cursor point (the make-way / flip judgement must not drift
/// near the borders), and a windowless harness gets no clamp at all (coordinates stay exact).
@MainActor
final class LaunchpadCarryClampTests: XCTestCase {

    private final class FloatingIconSpy: LaunchpadFloatingIconPresenting {
        private(set) var isPresenting = false
        private(set) var movedTo: NSPoint?

        func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
            isPresenting = true
        }

        func move(toScreenPoint p: NSPoint) { movedTo = p }

        func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void) {
            isPresenting = false
            completion()
        }

        func dismiss() { isPresenting = false }
    }

    private var coordinator: LaunchpadDragCoordinator!
    private var spy: FloatingIconSpy!
    private var window: NSWindow!

    /// The presented side a 64pt icon lifts to (beginCarry presents at iconSide × 1.1).
    private let presentedSide: CGFloat = 64 * 1.1

    override func setUp() {
        super.setUp()
        coordinator = LaunchpadDragCoordinator()
        spy = FloatingIconSpy()
        let spy = self.spy!
        coordinator.floatingPresenterFactory = { spy }
        coordinator.storeApplier = { _, _ in nil }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        coordinator.cancelCarry(.shutdown)
        coordinator = nil
        spy = nil
        window = nil
        super.tearDown()
    }

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private var threeApps: [LaunchpadDisplayCell] {
        [.app(app("/Apps/A.app", "A")), .app(app("/Apps/B.app", "B")), .app(app("/Apps/C.app", "C"))]
    }

    private func makePage(_ items: [LaunchpadDisplayCell], page: Int,
                          windowed: Bool) -> LaunchpadGridContainerView {
        let coordinator = self.coordinator!
        let grid = LaunchpadDragGrid(
            items: items,
            columns: 7,
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
            onDragBegan: { coordinator.freezeVisibleOrder(items) },
            onPageSwipe: { _ in },
            onPageDrag: { _, _, _ in },
            onPageScroll: { _, _ in },
            onDismiss: {},
            coordinator: coordinator,
            pageIndex: page
        )
        let container = LaunchpadGridContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        if windowed { window.contentView?.addSubview(container) }
        container.apply(grid: grid)
        container.layout()
        return container
    }

    private func pushGeometry() {
        coordinator.syncGeometry(LaunchpadPageGeometry(
            pageWidth: 900, gridHeight: 600, pageCount: 1, perPage: 21,
            viewportMinX: 100, viewportTopY: 700))
    }

    private func windowPoint(forLocal local: NSPoint) -> NSPoint {
        NSPoint(x: local.x + 100, y: 700 - local.y)
    }

    /// Lift with grabOffset == .zero: grab exactly at the cell's icon centre.
    private func liftAtIconCentre(_ container: LaunchpadGridContainerView) {
        let metrics = LaunchpadGridMetrics()
        let cell = container.cellViews[0]
        let iconCentre = NSPoint(x: cell.frame.minX + metrics.cellWidth / 2,
                                 y: cell.frame.minY + 8 + metrics.iconSide / 2)
        container.beginDirectDrag(cell, atWindowPoint: windowPoint(forLocal: iconCentre))
        XCTAssertTrue(coordinator.carryActive)
    }

    // MARK: - Pure clamp math

    func testClampedCentreInsideBoundsIsUntouched() {
        let bounds = NSRect(x: 100, y: 50, width: 1000, height: 700)
        let centre = NSPoint(x: 500, y: 300)
        XCTAssertEqual(LaunchpadDragCoordinator.clampedIconCentre(centre, side: 70.4, in: bounds),
                       centre, "界内中心点不得被改写")
    }

    func testClampedCentreKeepsIconRectInsideEachEdge() {
        let bounds = NSRect(x: 100, y: 50, width: 1000, height: 700)
        let side: CGFloat = 70.4
        let half = side / 2

        let low = LaunchpadDragCoordinator.clampedIconCentre(
            NSPoint(x: -5000, y: -5000), side: side, in: bounds)
        XCTAssertEqual(low.x, bounds.minX + half, accuracy: 0.001, "左缘：图标整体留在界内")
        XCTAssertEqual(low.y, bounds.minY + half, accuracy: 0.001, "下缘：图标整体留在界内")

        let high = LaunchpadDragCoordinator.clampedIconCentre(
            NSPoint(x: 5000, y: 5000), side: side, in: bounds)
        XCTAssertEqual(high.x, bounds.maxX - half, accuracy: 0.001, "右缘：图标整体留在界内")
        XCTAssertEqual(high.y, bounds.maxY - half, accuracy: 0.001, "上缘：图标整体留在界内")
    }

    func testDegenerateBoundsPinToMidline() {
        let narrow = NSRect(x: 100, y: 100, width: 40, height: 40)   // narrower than the icon
        let clamped = LaunchpadDragCoordinator.clampedIconCentre(
            NSPoint(x: 5000, y: -5000), side: 70.4, in: narrow)
        XCTAssertEqual(clamped.x, narrow.midX, accuracy: 0.001, "退化边界钳到中线，不得振荡")
        XCTAssertEqual(clamped.y, narrow.midY, accuracy: 0.001)
    }

    func testZeroSideDegradesToPointClamp() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 100)
        let clamped = LaunchpadDragCoordinator.clampedIconCentre(
            NSPoint(x: 500, y: -500), side: 0, in: bounds)
        XCTAssertEqual(clamped, NSPoint(x: 100, y: 0), "iconSide=0（迟开会话）退化为点钳制，无害")
    }

    // MARK: - carryMoved applies the clamp (windowed) / skips it (windowless)

    func testCarryMovedClampsFloatingIconToOverlayScreen() {
        let container = makePage(threeApps, page: 0, windowed: true)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        liftAtIconCentre(container)

        // Production bounds resolution: the engaged container's window → its screen, else the
        // window frame itself (test window may or may not intersect a real screen).
        let bounds = window.screen?.frame ?? window.frame
        let half = presentedSide / 2

        coordinator.carryMoved(atScreenPoint: NSPoint(x: bounds.minX - 5000, y: bounds.minY - 5000),
                               atWindowPoint: windowPoint(forLocal: NSPoint(x: 450, y: 300)))
        XCTAssertEqual(spy.movedTo?.x ?? .nan, bounds.minX + half, accuracy: 0.001,
                       "拖出左/下缘：浮窗中心必须钳回屏内（图标不许飞出启动台）")
        XCTAssertEqual(spy.movedTo?.y ?? .nan, bounds.minY + half, accuracy: 0.001)

        coordinator.carryMoved(atScreenPoint: NSPoint(x: bounds.maxX + 5000, y: bounds.maxY + 5000),
                               atWindowPoint: windowPoint(forLocal: NSPoint(x: 450, y: 300)))
        XCTAssertEqual(spy.movedTo?.x ?? .nan, bounds.maxX - half, accuracy: 0.001,
                       "拖出右/上缘：浮窗中心必须钳回屏内")
        XCTAssertEqual(spy.movedTo?.y ?? .nan, bounds.maxY - half, accuracy: 0.001)

        let inside = NSPoint(x: bounds.midX, y: bounds.midY)
        coordinator.carryMoved(atScreenPoint: inside,
                               atWindowPoint: windowPoint(forLocal: NSPoint(x: 450, y: 300)))
        XCTAssertEqual(spy.movedTo?.x ?? .nan, inside.x, accuracy: 0.001, "界内移动不受钳制影响")
        XCTAssertEqual(spy.movedTo?.y ?? .nan, inside.y, accuracy: 0.001)
    }

    func testCarryMovedClampNeverTouchesClassificationPoint() {
        let container = makePage(threeApps, page: 0, windowed: true)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        liftAtIconCentre(container)

        // Screen point far off the screen, window point over C's right seam: the gap must still
        // open from the REAL cursor point — the clamp is presenter-only.
        let cFrame = container.cellViews[2].frame
        let seam = NSPoint(x: cFrame.maxX - 4, y: cFrame.midY)
        coordinator.carryMoved(atScreenPoint: NSPoint(x: -99999, y: -99999),
                               atWindowPoint: windowPoint(forLocal: seam))
        XCTAssertEqual(container.externalGapIndex, 2, "分类必须继续用真实光标点（钳的是浮窗，不是数据流）")
    }

    func testWindowlessCarryIsNeverClamped() {
        let container = makePage(threeApps, page: 0, windowed: false)
        pushGeometry()
        coordinator.currentPageDidChange(0)
        liftAtIconCentre(container)

        let far = NSPoint(x: -10_000, y: -10_000)
        coordinator.carryMoved(atScreenPoint: far,
                               atWindowPoint: windowPoint(forLocal: NSPoint(x: 450, y: 300)))
        XCTAssertEqual(spy.movedTo, far,
                       "无窗 harness 不得钳制——生产 carry 必从已挂载容器开始，测试坐标保持精确")
    }
}
