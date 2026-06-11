import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

final class LaunchpadEdgePageTurnerTests: XCTestCase {

    private let pageW: CGFloat = 900

    private func leftPoint() -> CGPoint { CGPoint(x: 10, y: 300) }
    private func rightPoint() -> CGPoint { CGPoint(x: 890, y: 300) }
    private func centrePoint() -> CGPoint { CGPoint(x: 450, y: 300) }

    private func update(_ turner: inout LaunchpadEdgePageTurner,
                        _ point: CGPoint, at now: TimeInterval) -> LaunchpadEdgePageTurner.Decision {
        turner.update(point: point, pageWidth: pageW, now: now)
    }

    // MARK: - Dwell fires

    func testDwellFiresLeftAfter0_7s() {
        var t = LaunchpadEdgePageTurner()
        XCTAssertEqual(update(&t, leftPoint(), at: 0), .none, "进区即 arm，不立即 fire")
        XCTAssertEqual(update(&t, leftPoint(), at: 0.5), .none)
        XCTAssertEqual(update(&t, leftPoint(), at: 0.71), .flip(direction: -1), "驻留满 0.7s 应向左翻")
    }

    func testDwellFiresRightAfter0_7s() {
        var t = LaunchpadEdgePageTurner()
        XCTAssertEqual(update(&t, rightPoint(), at: 0), .none)
        XCTAssertEqual(update(&t, rightPoint(), at: 0.71), .flip(direction: 1), "驻留满 0.7s 应向右翻")
    }

    // MARK: - Reset paths

    func testLeavingZoneResetsDwell() {
        var t = LaunchpadEdgePageTurner()
        _ = update(&t, leftPoint(), at: 0)
        XCTAssertEqual(update(&t, centrePoint(), at: 0.4), .none)
        XCTAssertEqual(t.state, .idle, "离区应回 idle")
        _ = update(&t, leftPoint(), at: 0.5)                       // re-enter restarts the dwell
        XCTAssertEqual(update(&t, leftPoint(), at: 1.1), .none, "重进区后 0.6s 不应 fire")
        XCTAssertEqual(update(&t, leftPoint(), at: 1.21), .flip(direction: -1))
    }

    func testSwitchingZonesRestartsDwell() {
        var t = LaunchpadEdgePageTurner()
        _ = update(&t, leftPoint(), at: 0)
        XCTAssertEqual(update(&t, rightPoint(), at: 0.4), .none, "换边重计，不沿用左缘的驻留")
        XCTAssertEqual(update(&t, rightPoint(), at: 1.0), .none)
        XCTAssertEqual(update(&t, rightPoint(), at: 1.11), .flip(direction: 1))
    }

    func testResetReturnsToIdle() {
        var t = LaunchpadEdgePageTurner()
        _ = update(&t, leftPoint(), at: 0)
        t.reset()
        XCTAssertEqual(t.state, .idle)
        XCTAssertEqual(update(&t, leftPoint(), at: 0.71), .none, "reset 后重新驻留，旧时间不算数")
    }

    // MARK: - Cooldown / dwell-and-repeat

    func testCooldownBlocksSecondFire() {
        var t = LaunchpadEdgePageTurner()
        _ = update(&t, leftPoint(), at: 0)
        XCTAssertEqual(update(&t, leftPoint(), at: 0.7), .flip(direction: -1))
        XCTAssertEqual(update(&t, leftPoint(), at: 1.0), .none, "cooldown 内不得二发")
        XCTAssertEqual(update(&t, leftPoint(), at: 1.49), .none)
        XCTAssertEqual(update(&t, leftPoint(), at: 1.5), .flip(direction: -1), "cooldown 期满按节拍连发")
    }

    func testDwellAndRepeatCadenceOverThreeSeconds() {
        var t = LaunchpadEdgePageTurner()
        var fires: [TimeInterval] = []
        var now: TimeInterval = 0
        while now <= 3.0 {                                          // 33ms jittered stepping (30Hz tick)
            if case .flip = update(&t, leftPoint(), at: now) { fires.append(now) }
            now += 0.033
        }
        XCTAssertEqual(fires.count, 3, "3s 驻留应连翻三页（~0.7/1.5/2.3）")
        // 30Hz stepping quantizes each fire up to one tick late; assert the
        // cadence (dwell once, then steady cooldown beats), not exact instants.
        XCTAssertEqual(fires[0], 0.7, accuracy: 0.04)
        XCTAssertEqual(fires[1] - fires[0], 0.8, accuracy: 0.04)
        XCTAssertEqual(fires[2] - fires[1], 0.8, accuracy: 0.04)
    }

    func testRefireAfterLeavingZoneNeedsFullDwell() {
        var t = LaunchpadEdgePageTurner()
        _ = update(&t, leftPoint(), at: 0)
        XCTAssertEqual(update(&t, leftPoint(), at: 0.7), .flip(direction: -1))
        _ = update(&t, centrePoint(), at: 0.9)                      // leave during cooldown
        _ = update(&t, leftPoint(), at: 1.0)                        // back in: full dwell again
        XCTAssertEqual(update(&t, leftPoint(), at: 1.6), .none, "回区后未满 dwell 不得 fire")
        XCTAssertEqual(update(&t, leftPoint(), at: 1.71), .flip(direction: -1))
    }

    // MARK: - Zone classification

    func testOutOfBoundsXStillClassifiesIntoZones() {
        var t = LaunchpadEdgePageTurner()
        XCTAssertEqual(update(&t, CGPoint(x: -30, y: 300), at: 0), .none)
        XCTAssertEqual(update(&t, CGPoint(x: -30, y: 300), at: 0.71), .flip(direction: -1),
                       "page-local x 为负（光标在条带 padding/屏缘外）必须归左热区")
        t.reset()
        XCTAssertEqual(update(&t, CGPoint(x: pageW + 30, y: 300), at: 0), .none)
        XCTAssertEqual(update(&t, CGPoint(x: pageW + 30, y: 300), at: 0.71), .flip(direction: 1),
                       "超出 pageWidth 必须归右热区")
    }

    // MARK: - Outer-column exemption bands (§A5: edge column = drop aiming, not a flip)

    /// 900pt page, 7 columns, margin 20 → last column spans [764, 880]; zone is x > 872.
    private var lastColumnBand: ClosedRange<CGFloat> { 764...880 }
    private var firstColumnBand: ClosedRange<CGFloat> { 20...136 }

    private func update(_ turner: inout LaunchpadEdgePageTurner, _ point: CGPoint,
                        at now: TimeInterval,
                        exempt: LaunchpadEdgePageTurner.ExemptBands)
        -> LaunchpadEdgePageTurner.Decision {
        turner.update(point: point, pageWidth: pageW, now: now, exempt: exempt)
    }

    func testExemptBandSuppressesRightZoneDwell() {
        var t = LaunchpadEdgePageTurner()
        let exempt = LaunchpadEdgePageTurner.ExemptBands(right: lastColumnBand)
        let overLastColumn = CGPoint(x: 876, y: 300)         // in zone (>872) AND in the band
        XCTAssertEqual(update(&t, overLastColumn, at: 0, exempt: exempt), .none)
        XCTAssertEqual(t.state, .idle, "末列让位带内 = 瞄准落点，必须回 idle 而非 arm")
        XCTAssertEqual(update(&t, overLastColumn, at: 0.71, exempt: exempt), .none,
                       "末列带内驻留再久也不得翻页（§A5 用户复现）")
        XCTAssertEqual(t.state, .idle)
    }

    func testLeavingBandIntoMarginNeedsFullDwell() {
        var t = LaunchpadEdgePageTurner()
        let exempt = LaunchpadEdgePageTurner.ExemptBands(right: lastColumnBand)
        _ = update(&t, CGPoint(x: 876, y: 300), at: 0, exempt: exempt)      // aiming over the column
        _ = update(&t, CGPoint(x: 890, y: 300), at: 1.0, exempt: exempt)    // pushed into the margin
        XCTAssertEqual(update(&t, CGPoint(x: 890, y: 300), at: 1.6, exempt: exempt), .none,
                       "从带内推进边距后必须重新满 dwell")
        XCTAssertEqual(update(&t, CGPoint(x: 890, y: 300), at: 1.71, exempt: exempt),
                       .flip(direction: 1), "真实边距驻留满 0.7s 照常翻页")
    }

    func testExemptBandLeftIsSymmetric() {
        var t = LaunchpadEdgePageTurner()
        let exempt = LaunchpadEdgePageTurner.ExemptBands(left: firstColumnBand)
        XCTAssertEqual(update(&t, CGPoint(x: 25, y: 300), at: 0, exempt: exempt), .none)
        XCTAssertEqual(update(&t, CGPoint(x: 25, y: 300), at: 0.71, exempt: exempt), .none,
                       "首列带内同样豁免（左缘对称）")
        XCTAssertEqual(update(&t, CGPoint(x: 10, y: 300), at: 1.0, exempt: exempt), .none)
        XCTAssertEqual(update(&t, CGPoint(x: 10, y: 300), at: 1.71, exempt: exempt),
                       .flip(direction: -1), "带外的真实左边距照常翻页")
    }

    func testOutOfBoundsXIsNeverExempt() {
        var t = LaunchpadEdgePageTurner()
        let exempt = LaunchpadEdgePageTurner.ExemptBands(left: firstColumnBand, right: lastColumnBand)
        XCTAssertEqual(update(&t, CGPoint(x: pageW + 30, y: 300), at: 0, exempt: exempt), .none)
        XCTAssertEqual(update(&t, CGPoint(x: pageW + 30, y: 300), at: 0.71, exempt: exempt),
                       .flip(direction: 1),
                       "页外/屏缘 x 不在列跨度内——全屏一推到底（Fitts）必须仍可翻页")
    }

    func testEmptyBandsKeepLegacyClassification() {
        var t = LaunchpadEdgePageTurner()
        let none = LaunchpadEdgePageTurner.ExemptBands()
        XCTAssertEqual(update(&t, rightPoint(), at: 0, exempt: none), .none)
        XCTAssertEqual(update(&t, rightPoint(), at: 0.71, exempt: none), .flip(direction: 1),
                       "空豁免带（虚拟尾页 fail-open）= 旧行为")
    }

    // MARK: - Animation-constant interlock (BT-4)

    func testConfigInvariantsHoldAgainstPageAnimationConstants() {
        let config = LaunchpadEdgePageTurner.Config()
        XCTAssertGreaterThanOrEqual(config.dwell, LaunchpadPageAnimation.snapVisualSettle,
                                    "dwell 必须吞掉翻页动画窗口，否则离区回区可在动画未稳时 fire")
        XCTAssertGreaterThanOrEqual(config.repeatCooldown, LaunchpadPageAnimation.snapVisualSettle,
                                    "连翻节拍必须 ≥ 动画视觉沉降，否则连翻叠加动画")
        XCTAssertGreaterThanOrEqual(LaunchpadPageAnimation.snapVisualSettle,
                                    LaunchpadPageAnimation.snapResponse * 1.9,
                                    "沉降估值与 spring 参数的数学锁：改 spring 必须同步改估值")
    }
}
