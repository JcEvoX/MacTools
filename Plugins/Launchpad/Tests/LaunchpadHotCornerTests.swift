import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

final class LaunchpadHotCornerTests: XCTestCase {
    // Screen coords: bottom-left origin, y up.
    private let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let t: CGFloat = 4

    private func hit(_ p: CGPoint, _ c: LaunchpadPreferences.HotCorner) -> Bool {
        LaunchpadHotCornerMonitor.isInCorner(p, corner: c, screenFrame: frame, threshold: t)
    }

    func testCornersHit() {
        XCTAssertTrue(hit(CGPoint(x: 2, y: 798), .topLeft))       // top-left = (minX, maxY)
        XCTAssertTrue(hit(CGPoint(x: 998, y: 798), .topRight))
        XCTAssertTrue(hit(CGPoint(x: 2, y: 2), .bottomLeft))
        XCTAssertTrue(hit(CGPoint(x: 998, y: 2), .bottomRight))
    }

    func testNearEdgeButWrongAxisMisses() {
        XCTAssertFalse(hit(CGPoint(x: 2, y: 400), .topLeft))      // near left edge, not top
        XCTAssertFalse(hit(CGPoint(x: 500, y: 798), .topLeft))    // near top edge, not left
    }

    func testWrongCornerMisses() {
        XCTAssertFalse(hit(CGPoint(x: 2, y: 798), .bottomLeft))   // it's top-left, not bottom-left
        XCTAssertFalse(hit(CGPoint(x: 2, y: 798), .topRight))
    }

    func testCenterMissesAll() {
        let center = CGPoint(x: 500, y: 400)
        for corner in LaunchpadPreferences.HotCorner.allCases {
            XCTAssertFalse(hit(center, corner))
        }
    }

    func testOffNeverHits() {
        XCTAssertFalse(hit(CGPoint(x: 0, y: 800), .off))
    }

    func testNegativeOriginScreen() {
        // Secondary display to the left of main (negative x).
        let secondary = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        XCTAssertTrue(LaunchpadHotCornerMonitor.isInCorner(
            CGPoint(x: -998, y: 798), corner: .topLeft, screenFrame: secondary, threshold: t))
        XCTAssertTrue(LaunchpadHotCornerMonitor.isInCorner(
            CGPoint(x: -2, y: 2), corner: .bottomRight, screenFrame: secondary, threshold: t))
    }

    /// Pause/resume regression: deactivate stops the poll while the corner preference keeps its
    /// value — re-applying the SAME corner must restart it (an equality guard once blocked this,
    /// leaving the hot corner permanently dead after hide → re-show).
    @MainActor
    func testUpdateRestartsAfterStopEvenWithSameCorner() {
        let monitor = LaunchpadHotCornerMonitor()
        monitor.update(corner: .bottomLeft)
        XCTAssertTrue(monitor.isMonitoring)

        monitor.stop()                          // plugin deactivate（隐藏/停用）
        XCTAssertFalse(monitor.isMonitoring)

        monitor.update(corner: .bottomLeft)     // plugin activate（恢复）：同一角落也要重启
        XCTAssertTrue(monitor.isMonitoring)

        monitor.update(corner: .off)            // off 仍然完全停止
        XCTAssertFalse(monitor.isMonitoring)
    }
}
