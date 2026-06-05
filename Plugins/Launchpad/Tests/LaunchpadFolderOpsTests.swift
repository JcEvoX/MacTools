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
}
