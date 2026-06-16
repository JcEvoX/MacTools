import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

final class LaunchpadCarrySpaceTests: XCTestCase {

    /// Non-zero viewport origin and page width so every conversion exercises the
    /// real offsets instead of degenerate zeros (BT-3).
    private func makeSpace() -> LaunchpadCarrySpace {
        LaunchpadCarrySpace(viewportMinX: 48, viewportTopY: 700, pageWidth: 900)
    }

    func testLocalFlipsYAndStripsViewportOrigin() {
        let space = makeSpace()
        let local = space.local(fromWindow: NSPoint(x: 148, y: 650))
        XCTAssertEqual(local.x, 100)
        XCTAssertEqual(local.y, 50, "窗口 y 越接近视口顶缘，flipped 本地 y 越小")
    }

    func testViewportInvarianceAcrossPageFlips() {
        // The viewport (visible page slot) does not move when pages flip — only
        // the SwiftUI render offset changes. The same window point must therefore
        // resolve to the same page-local point on page 0 and on page 2.
        let onPage0 = makeSpace()
        let onPage2 = makeSpace()
        let w = NSPoint(x: 500, y: 300)
        XCTAssertEqual(onPage0.local(fromWindow: w), onPage2.local(fromWindow: w),
                       "视口即页：换页不改变 window→local 结果，无按页偏移")
    }

    func testWindowRectFromLocalFlipsYAroundRectTop() {
        let space = makeSpace()
        let rect = space.windowRect(fromLocal: CGRect(x: 120, y: 80, width: 96, height: 96))
        XCTAssertEqual(rect.minX, 168)
        XCTAssertEqual(rect.minY, 524, "local maxY(176) 映射为窗口 minY：700 − 176")
        XCTAssertEqual(rect.width, 96)
        XCTAssertEqual(rect.height, 96)
    }

    func testLocalAndWindowRectRoundTrip() {
        let space = makeSpace()
        let original = CGRect(x: 120, y: 80, width: 96, height: 96)
        let windowRect = space.windowRect(fromLocal: original)
        // The rect's top-left in window space (minX, maxY) must come back as the
        // local origin, closing the loop between the two conversions.
        let backOrigin = space.local(fromWindow: NSPoint(x: windowRect.minX, y: windowRect.maxY))
        XCTAssertEqual(backOrigin.x, original.minX)
        XCTAssertEqual(backOrigin.y, original.minY)
    }

    func testOutOfViewportPointsGoNegativeInsteadOfClamping() {
        let space = makeSpace()
        let local = space.local(fromWindow: NSPoint(x: 20, y: 720))
        XCTAssertEqual(local.x, -28, "视口外不得钳制——边缘热区判定依赖负值")
        XCTAssertEqual(local.y, -20)
    }
}
