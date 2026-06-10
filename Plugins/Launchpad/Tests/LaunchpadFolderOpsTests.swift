import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import LaunchpadPlugin

/// Store-level folder operations (19b): create-by-stacking, add, remove (+ auto-dissolve),
/// rename, dissolve — all pure tree edits, persisted, no UI.
@MainActor
final class LaunchpadFolderOpsTests: XCTestCase {

    private let a = "/Applications/Alpha.app"
    private let b = "/Applications/Bravo.app"
    private let c = "/Applications/Charlie.app"
    private let d = "/Applications/Delta.app"

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }
    private func sampleApps() -> [LaunchpadAppItem] {
        [app(a, "Alpha"), app(b, "Bravo"), app(c, "Charlie"), app(d, "Delta")]
    }
    /// A store with the alphabetical snapshot materialised into a layout ([a, b, c, d]).
    private func materializedStore() -> LaunchpadLayoutStore {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        store.materializeIfNeeded(from: sampleApps())
        return store
    }
    private func rootIDs(_ store: LaunchpadLayoutStore) -> [String] {
        (store.layout?.nodes ?? []).map(\.rootID)
    }
    private func folderChildren(_ store: LaunchpadLayoutStore, _ id: String) -> [String]? {
        for node in store.layout?.nodes ?? [] {
            if case .folder(let fid, _, let children) = node, fid == id { return children.map(\.id) }
        }
        return nil
    }
    private func folderName(_ store: LaunchpadLayoutStore, _ id: String) -> String? {
        for node in store.layout?.nodes ?? [] {
            if case .folder(let fid, let name, _) = node, fid == id { return name }
        }
        return nil
    }

    func testMakeFolderStacksTwoAppsAtTargetSlot() {
        let store = materializedStore()
        store.makeFolder(target: b, dragged: d, name: "工具", id: "F1")
        XCTAssertEqual(rootIDs(store), [a, "F1", c], "folder 占被叠 app 的槽，被拖 app 从根层移除")
        XCTAssertEqual(folderChildren(store, "F1"), [b, d], "children = [被叠, 被拖]")
        XCTAssertEqual(folderName(store, "F1"), "工具")
    }

    func testMakeFolderOnSelfIsNoOp() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: a, name: "F", id: "F1")
        XCTAssertEqual(rootIDs(store), [a, b, c, d])
        XCTAssertNil(folderChildren(store, "F1"))
    }

    func testAddToFolderAppendsAndRemovesFromRoot() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")   // [F1, c, d]; F1=[a,b]
        store.addToFolder("F1", app: c)
        XCTAssertEqual(rootIDs(store), ["F1", d])
        XCTAssertEqual(folderChildren(store, "F1"), [a, b, c])
    }

    func testRemoveFromFolderKeepsFolderWhenTwoOrMoreRemain() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")
        store.addToFolder("F1", app: c)                                 // F1=[a,b,c]; root [F1, d]
        store.removeFromFolder("F1", app: b)                            // → F1=[a,c]; b to tail
        XCTAssertEqual(folderChildren(store, "F1"), [a, c])
        XCTAssertEqual(rootIDs(store), ["F1", d, b])
    }

    func testRemoveFromFolderAutoDissolvesAtOneRemaining() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")   // F1=[a,b]; root [F1, c, d]
        store.removeFromFolder("F1", app: b)                            // a remains → dissolve
        XCTAssertNil(folderChildren(store, "F1"), "降到 1 个自动解散")
        XCTAssertEqual(rootIDs(store), [a, c, d, b], "幸存者回 folder 原位(最前)，移出的去末尾")
    }

    func testDissolveFolderReleasesChildrenInPlace() {
        let store = materializedStore()
        store.makeFolder(target: b, dragged: c, name: "F", id: "F1")   // root [a, F1, d]; F1=[b,c]
        store.dissolveFolder("F1")
        XCTAssertEqual(rootIDs(store), [a, b, c, d], "children 在 folder 原位释放回根层")
    }

    func testRenameFolderAndEmptyFallback() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "旧名", id: "F1")
        store.renameFolder("F1", name: "新名")
        XCTAssertEqual(folderName(store, "F1"), "新名")
        store.renameFolder("F1", name: "   ")
        XCTAssertEqual(folderName(store, "F1"), "未命名", "空名回退默认名")
    }

    func testFolderSurvivesPersistenceRoundTrip() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")
        let reloaded = LaunchpadLayoutStore(storage: storage)
        XCTAssertEqual(rootIDs(reloaded), ["F1", c, d])
        XCTAssertEqual(folderChildren(reloaded, "F1"), [a, b])
    }

    func testMoveChildWithinFolderReorders() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // F1=[a,b]
        store.addToFolder("F1", app: c)                                // F1=[a,b,c]
        store.moveChildWithinFolder("F1", child: c, before: a)         // → [c,a,b]
        XCTAssertEqual(folderChildren(store, "F1"), [c, a, b])
        store.moveChildWithinFolder("F1", child: c, after: b)          // → [a,b,c]
        XCTAssertEqual(folderChildren(store, "F1"), [a, b, c])
    }

    // MARK: - moveOutOfFolder (finger-bound exit: drop at a chosen root slot, not the tail)

    func testMoveOutOfFolderInsertsAtTargetSlotNotTail() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // [F1, c, d]; F1=[a,b]
        store.addToFolder("F1", app: c)                                // [F1, d]; F1=[a,b,c]
        store.moveOutOfFolder("F1", app: b, to: .before(d))            // b out, before d
        XCTAssertEqual(folderChildren(store, "F1"), [a, c])
        XCTAssertEqual(rootIDs(store), ["F1", b, d], "落在光标槽位（d 之前），不是末尾")
    }

    func testMoveOutOfFolderAutoDissolvesAndDropsAtCursorSlot() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // [F1, c, d]; F1=[a,b]
        store.moveOutOfFolder("F1", app: b, to: .after(c))            // F1 → [a] dissolves; b after c
        XCTAssertNil(folderChildren(store, "F1"), "降到 1 个自动解散")
        XCTAssertEqual(rootIDs(store), [a, c, b, d], "幸存者归原位(最前)，移出的落在 c 之后")
    }

    func testMoveOutOfFolderNilTargetAppendsTail() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // [F1, c, d]; F1=[a,b]
        store.addToFolder("F1", app: c)                                // [F1, d]; F1=[a,b,c]
        store.moveOutOfFolder("F1", app: b, to: nil)                   // nil → tail (== removeFromFolder)
        XCTAssertEqual(folderChildren(store, "F1"), [a, c])
        XCTAssertEqual(rootIDs(store), ["F1", d, b])
    }

    func testMoveOutOfFolderStaleTargetFallsBackToTail() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // [F1, c, d]; F1=[a,b]
        store.addToFolder("F1", app: c)                                // [F1, d]; F1=[a,b,c]
        store.moveOutOfFolder("F1", app: b, to: .before("/nope.app"))  // stale → tail
        XCTAssertEqual(rootIDs(store), ["F1", d, b])
    }

    func testMoveOutOfFolderTargetOnDissolvedFolderFollowsSurvivorAfter() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // [F1, c, d]; F1=[a,b]
        store.moveOutOfFolder("F1", app: b, to: .after("F1"))         // 落在夹自身 tile 右侧，夹随即解散
        XCTAssertNil(folderChildren(store, "F1"))
        XCTAssertEqual(rootIDs(store), [a, b, c, d], "目标跟随占据原槽的幸存者，而不是落到末尾")
    }

    func testMoveOutOfFolderTargetOnDissolvedFolderFollowsSurvivorBefore() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")  // [F1, c, d]; F1=[a,b]
        store.moveOutOfFolder("F1", app: b, to: .before("F1"))        // 落在夹自身 tile 左侧
        XCTAssertNil(folderChildren(store, "F1"))
        XCTAssertEqual(rootIDs(store), [b, a, c, d], "幸存者 a 占原槽，b 落在它之前")
    }

    // MARK: - eject INTO another app/folder (carry-merge during a folder drag-out)

    func testEjectIntoNewFolderRemovesFromSourceAndStacksAtTarget() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")          // [F1, c, d]; F1=[a,b]
        store.ejectIntoNewFolder(source: "F1", app: b, target: c, name: "X", id: "F2")
        XCTAssertNil(folderChildren(store, "F1"), "源夹降到 1 个自动解散")
        XCTAssertEqual(folderChildren(store, "F2"), [c, b], "新夹 = [被叠, 被拖出]")
        XCTAssertEqual(rootIDs(store), [a, "F2", d])
    }

    func testEjectIntoNewFolderSourceStaysWhenTwoChildrenRemain() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")          // [F1, c, d]; F1=[a,b]
        store.addToFolder("F1", app: c)                                        // [F1, d]; F1=[a,b,c]
        store.ejectIntoNewFolder(source: "F1", app: b, target: d, name: "X", id: "F2")
        XCTAssertEqual(folderChildren(store, "F1"), [a, c], "≥2 不解散")
        XCTAssertEqual(folderChildren(store, "F2"), [d, b])
        XCTAssertEqual(rootIDs(store), ["F1", "F2"])
    }

    func testEjectIntoFolderAppendsToDestination() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F1n", id: "F1")        // [F1, c, d]; F1=[a,b]
        store.makeFolder(target: c, dragged: d, name: "F2n", id: "F2")        // [F1, F2]; F2=[c,d]
        store.ejectIntoFolder(source: "F1", app: b, destination: "F2")
        XCTAssertNil(folderChildren(store, "F1"))
        XCTAssertEqual(folderChildren(store, "F2"), [c, d, b])
        XCTAssertEqual(rootIDs(store), [a, "F2"])
    }

    func testEjectIntoNewFolderStaleTargetFallsBackToTail() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")          // [F1, c, d]; F1=[a,b]
        store.ejectIntoNewFolder(source: "F1", app: b, target: "/nope.app", name: "X", id: "F2")
        XCTAssertNil(folderChildren(store, "F2"), "目标不存在 → 不建夹")
        XCTAssertEqual(rootIDs(store), [a, c, d, b], "被拖出的回末尾，不丢")
    }

    func testEjectIntoFolderBackToSourceIsNoOp() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")          // [F1, c, d]; F1=[a,b]
        store.ejectIntoFolder(source: "F1", app: b, destination: "F1")        // 拖出来又放回源夹
        XCTAssertEqual(folderChildren(store, "F1"), [a, b], "放回源夹 → app 留在夹里（撤销）")
        XCTAssertEqual(rootIDs(store), ["F1", c, d])
    }

    func testEjectIntoNewFolderTargetEqualsSourceIsNoOp() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")          // [F1, c, d]; F1=[a,b]
        store.ejectIntoNewFolder(source: "F1", app: b, target: "F1", name: "X", id: "F2")
        XCTAssertEqual(folderChildren(store, "F1"), [a, b], "目标是源夹本身 → 不动")
        XCTAssertEqual(rootIDs(store), ["F1", c, d])
    }

    func testMoveChildWithinFolderStaleOrSelfIsNoOp() {
        let store = materializedStore()
        store.makeFolder(target: a, dragged: b, name: "F", id: "F1")   // F1=[a,b]
        store.moveChildWithinFolder("F1", child: a, before: d)         // d not in folder → no-op
        XCTAssertEqual(folderChildren(store, "F1"), [a, b])
        store.moveChildWithinFolder("F1", child: a, before: a)         // self → no-op
        XCTAssertEqual(folderChildren(store, "F1"), [a, b])
    }
}
