import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import LaunchpadPlugin

@MainActor
final class LaunchpadLayoutStoreTests: XCTestCase {

    private let a = "/Applications/Alpha.app"
    private let b = "/Applications/Bravo.app"
    private let c = "/Applications/Charlie.app"

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    private func sampleApps() -> [LaunchpadAppItem] {
        [app(a, "Alpha"), app(b, "Bravo"), app(c, "Charlie")]
    }

    private func ids(_ layout: LaunchpadLayout?) -> [String] {
        (layout?.nodes ?? []).map(\.rootID)
    }

    // MARK: - Loading / defaults

    func testEmptyStorageYieldsNilLayout() {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        XCTAssertNil(store.layout, "缺失 customLayout 键应为 nil（字母序）")
    }

    func testCorruptDataFallsBackToNil() {
        let storage = FakePluginStorage()
        storage.values["customLayout"] = Data("not json".utf8)
        let store = LaunchpadLayoutStore(storage: storage)
        XCTAssertNil(store.layout, "坏数据应 fallback 到 nil，不 crash")
    }

    func testBelowCurrentVersionFallsBackToNil() throws {
        let storage = FakePluginStorage()
        let legacy = LaunchpadLayout(version: 1, nodes: [.app(LaunchpadAppRef(id: a, name: "Alpha"))])
        storage.values["customLayout"] = try JSONEncoder().encode(legacy)
        let store = LaunchpadLayoutStore(storage: storage)
        XCTAssertNil(store.layout, "version < currentVersion 应 fallback 到 nil")
    }

    // MARK: - Materialize

    func testMaterializeSnapshotsAlphabeticalAllApps() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())

        XCTAssertEqual(ids(store.layout), [a, b, c])
        XCTAssertNotNil(storage.values["customLayout"] as? Data, "materialize 应落盘")
        for node in store.layout?.nodes ?? [] {
            guard case .app = node else { return XCTFail("19a 快照应全是 .app 节点") }
        }
    }

    func testMaterializeIsNoOpWhenLayoutExists() {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        store.materializeIfNeeded(from: sampleApps())
        store.materializeIfNeeded(from: [app(c, "Charlie")])   // 更小/不同的集合
        XCTAssertEqual(ids(store.layout), [a, b, c], "已有 layout 时 materialize 不再覆盖")
    }

    // MARK: - Move

    func testMoveBefore() {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        store.materializeIfNeeded(from: sampleApps())
        store.move(id: c, before: a)
        XCTAssertEqual(ids(store.layout), [c, a, b])
    }

    func testMoveAfter() {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        store.materializeIfNeeded(from: sampleApps())
        store.move(id: a, after: c)
        XCTAssertEqual(ids(store.layout), [b, c, a])
    }

    func testNoOpMoveDoesNotPersist() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        let writesAfterMaterialize = storage.writeCount

        store.move(id: a, before: b)   // a 已紧邻 b 之前 → 顺序不变
        XCTAssertEqual(ids(store.layout), [a, b, c])
        XCTAssertEqual(storage.writeCount, writesAfterMaterialize, "拖到原位不应写盘")
    }

    func testMoveWithoutLayoutIsNoOp() {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        store.move(id: a, before: b)   // 还没 materialize
        XCTAssertNil(store.layout, "无 layout 时 move 应是 no-op（必须先 materialize）")
    }

    func testMoveWithAbsentSourceIdIsNoOp() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        let writesAfterMaterialize = storage.writeCount

        // 源 app 在拖拽冻结到 drop 之间被隐藏/卸载 → 布局里找不到 → 安全跳过
        store.move(id: "/Applications/Ghost.app", before: a)
        XCTAssertEqual(ids(store.layout), [a, b, c])
        XCTAssertEqual(storage.writeCount, writesAfterMaterialize, "源 id 不在布局中应安全 no-op，不写盘")
    }

    func testMoveToAbsentTargetAppendsAtTail() {
        let store = LaunchpadLayoutStore(storage: FakePluginStorage())
        store.materializeIfNeeded(from: sampleApps())

        // 目标是尚未落盘的新装 app（渲染在末尾但不在布局里）→ 回退为追加到末尾
        store.move(id: a, after: "/Applications/Ghost.app")
        XCTAssertEqual(ids(store.layout), [b, c, a], "目标 id 缺失时被拖 app 追加到根层末尾")
    }

    func testMoveSameIdIsNoOp() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        let writesAfterMaterialize = storage.writeCount

        store.move(id: a, before: a)   // 拖到自身
        XCTAssertEqual(ids(store.layout), [a, b, c])
        XCTAssertEqual(storage.writeCount, writesAfterMaterialize, "源 == 目标应 no-op，不写盘")
    }

    // MARK: - Round-trip persistence

    func testPersistRoundTrip() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        store.move(id: c, before: a)               // [c, a, b]
        let saved = store.layout

        let reloaded = LaunchpadLayoutStore(storage: storage)
        XCTAssertEqual(reloaded.layout, saved)
        XCTAssertEqual(ids(reloaded.layout), [c, a, b])
    }

    // MARK: - Reset

    func testResetToAlphabeticalClearsLayoutAndKey() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        XCTAssertNotNil(store.layout)

        store.resetToAlphabetical()
        XCTAssertNil(store.layout)
        XCTAssertNil(storage.values["customLayout"], "恢复字母序应删除 customLayout 键")
    }

    func testResetWhenAlreadyAlphabeticalIsNoOp() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.resetToAlphabetical()
        XCTAssertNil(store.layout)
        XCTAssertEqual(storage.writeCount, 0, "本就字母序时 reset 不写盘")
    }

    func testResetToAlphabeticalPersistsAcrossReload() {
        let storage = FakePluginStorage()
        let store = LaunchpadLayoutStore(storage: storage)
        store.materializeIfNeeded(from: sampleApps())
        store.resetToAlphabetical()

        // 重建 store：reset 必须持久落盘，新 store 应读回 nil（字母序）
        let reloaded = LaunchpadLayoutStore(storage: storage)
        XCTAssertNil(reloaded.layout, "恢复字母序应持久，重启后仍是字母序")
    }

    // MARK: - Codable schema (locked once for 19a + 19b)

    func testNodeCodableRoundTripBothKinds() throws {
        let layout = LaunchpadLayout(nodes: [
            .app(LaunchpadAppRef(id: a, name: "Alpha")),
            .folder(id: "F1", name: "工具", children: [
                LaunchpadAppRef(id: b, name: "Bravo"),
                LaunchpadAppRef(id: c, name: "Charlie"),
            ]),
        ])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(LaunchpadLayout.self, from: data)
        XCTAssertEqual(decoded, layout, "手写 kind 判别 Codable 对 .app/.folder 都应 round-trip")
    }

    func testAppRefBundleIDDefaultsNilAndSurvivesCoding() throws {
        let ref = LaunchpadAppRef(id: a, name: "Alpha")
        XCTAssertNil(ref.bundleID, "v1 bundleID 恒为 nil")
        let decoded = try JSONDecoder().decode(LaunchpadAppRef.self, from: JSONEncoder().encode(ref))
        XCTAssertNil(decoded.bundleID)
    }
}
