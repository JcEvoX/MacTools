import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Drop no-op detection (`LaunchpadDropTarget.isNoOp`) — the guard that stops a drop which
/// changes nothing visible from flipping alphabetical → custom mode (Codex P2).
final class LaunchpadReorderTests: XCTestCase {
    private let order = ["a", "b", "c", "d"]

    func testDropOnSelfIsNoOp() {
        XCTAssertTrue(LaunchpadDropTarget.before("a").isNoOp(dragged: "a", in: order))
        XCTAssertTrue(LaunchpadDropTarget.after("a").isNoOp(dragged: "a", in: order))
    }

    func testDropBeforeAlreadyFollowingItemIsNoOp() {
        // a 已紧邻 b 之前 → before(b) 不改变顺序
        XCTAssertTrue(LaunchpadDropTarget.before("b").isNoOp(dragged: "a", in: order))
    }

    func testDropAfterAlreadyPrecedingItemIsNoOp() {
        // b 已紧邻 a 之后 → after(a) 不改变顺序
        XCTAssertTrue(LaunchpadDropTarget.after("a").isNoOp(dragged: "b", in: order))
    }

    func testRealMovesAreNotNoOp() {
        XCTAssertFalse(LaunchpadDropTarget.before("a").isNoOp(dragged: "c", in: order))  // c → 最前
        XCTAssertFalse(LaunchpadDropTarget.after("d").isNoOp(dragged: "a", in: order))   // a → 最后
        XCTAssertFalse(LaunchpadDropTarget.before("d").isNoOp(dragged: "a", in: order))  // a → d 之前
    }

    func testMissingDraggedIsTreatedAsNoOp() {
        XCTAssertTrue(LaunchpadDropTarget.before("a").isNoOp(dragged: "zzz", in: order))
    }
}
