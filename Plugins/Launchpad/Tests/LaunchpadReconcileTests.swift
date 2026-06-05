import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

final class LaunchpadReconcileTests: XCTestCase {

    private let a = "/Applications/Alpha.app"
    private let b = "/Applications/Bravo.app"
    private let c = "/Applications/Charlie.app"
    private let d = "/Applications/Delta.app"

    private func app(_ path: String, _ name: String) -> LaunchpadAppItem {
        LaunchpadAppItem(id: path, name: name, url: URL(fileURLWithPath: path))
    }

    /// Alphabetical sample, exactly as `LaunchpadAppScanner` would deliver.
    private func sample() -> [LaunchpadAppItem] {
        [app(a, "Alpha"), app(b, "Bravo"), app(c, "Charlie")]
    }

    /// Build an all-`.app` layout from a list of ids (names are irrelevant to ordering).
    private func appLayout(_ ids: [String]) -> LaunchpadLayout {
        LaunchpadLayout(nodes: ids.map { .app(LaunchpadAppRef(id: $0, name: $0)) })
    }

    private func reconcileIDs(
        _ apps: [LaunchpadAppItem],
        _ layout: LaunchpadLayout?,
        hidden: Set<String> = []
    ) -> [String] {
        LaunchpadLayoutReconciler.reconcile(apps: apps, layout: layout, hidden: hidden).map(\.id)
    }

    // MARK: - Default (nil layout)

    func testNilLayoutReturnsAlphabetical() {
        XCTAssertEqual(reconcileIDs(sample(), nil), [a, b, c])
    }

    // MARK: - Four invariants

    /// 不变量 1：visible 中已在布局的 id，相对顺序 == 布局相对顺序。
    func testKnownIdsPreserveLayoutOrder() {
        XCTAssertEqual(reconcileIDs(sample(), appLayout([c, a, b])), [c, a, b])
    }

    /// 不变量 2：visible 中不在布局的新 id，全部追加到末尾且内部按字母序。
    func testNewIdsAppendedAtTailAlphabetically() {
        let apps4 = [app(a, "Alpha"), app(b, "Bravo"), app(c, "Charlie"), app(d, "Delta")]
        XCTAssertEqual(reconcileIDs(apps4, appLayout([b, a])), [b, a, c, d])
    }

    /// 不变量 3：布局中存在但 visible 缺失的 id（卸载/移动）静默跳过。
    func testMissingLayoutIdsSilentlySkipped() {
        let present = [app(a, "Alpha"), app(c, "Charlie")]   // b 卸载了
        XCTAssertEqual(reconcileIDs(present, appLayout([a, b, c])), [a, c])
    }

    /// 不变量 4：hidden 先过滤再套布局。
    func testHiddenFilteredBeforeLayout() {
        XCTAssertEqual(reconcileIDs(sample(), appLayout([c, b, a]), hidden: [b]), [c, a])
    }

    // MARK: - Set identity + stability

    /// reconcile 输出元素集合恒等于 visible（只是顺序不同）——下游分页/选择因此零改动。
    func testOutputSetEqualsVisible() {
        let out = Set(reconcileIDs(sample(), appLayout([c, a])))   // 布局只引用部分
        XCTAssertEqual(out, [a, b, c])
    }

    /// 异步「数量不变但内容变化」（b 卸载、x 装上）→ 旧序不乱、新 id 进末尾。
    func testCountStableButContentSwappedDoesNotShuffle() {
        let layout = appLayout([a, b, c])
        let x = "/Applications/Xenon.app"
        let reloaded = [app(a, "Alpha"), app(c, "Charlie"), app(x, "Xenon")]
        XCTAssertEqual(reconcileIDs(reloaded, layout), [a, c, x])
    }

    /// 同名双路径（/Applications vs ~/Applications）→ 路径主键区分，各占一条不合并。
    func testSameNameDifferentPathsStayDistinct() {
        let sys = "/Applications/X.app"
        let user = "/Users/me/Applications/X.app"
        let two = [app(sys, "X"), app(user, "X")]
        XCTAssertEqual(reconcileIDs(two, nil), [sys, user])
        XCTAssertEqual(reconcileIDs(two, appLayout([user, sys])), [user, sys])
    }

    /// 防御：布局重复引用同一 id 只输出一次（集合仍 == visible）。
    func testDuplicateLayoutReferenceEmittedOnce() {
        XCTAssertEqual(reconcileIDs(sample(), appLayout([a, a, b])), [a, b, c])
    }

    /// 隐藏的 app 不渲染，但取消隐藏后回到布局原位（hidden 与排序正交）。
    func testHiddenAppExcludedThenReappearsAtLayoutPosition() {
        let layout = appLayout([c, b, a])
        XCTAssertEqual(reconcileIDs(sample(), layout, hidden: [b]), [c, a])
        XCTAssertEqual(reconcileIDs(sample(), layout, hidden: []), [c, b, a])
    }

    /// 退化场景：全部 app 被隐藏 → visible 为空 → 输出空；取消隐藏后整套布局回来。
    func testAllAppsHiddenReturnsEmptyThenRestores() {
        let layout = appLayout([c, b, a])
        XCTAssertEqual(reconcileIDs(sample(), layout, hidden: [a, b, c]), [])
        XCTAssertEqual(reconcileIDs(sample(), layout, hidden: []), [c, b, a])
    }

    // MARK: - 19b folders

    private func ref(_ id: String) -> LaunchpadAppRef { LaunchpadAppRef(id: id, name: id) }

    private func folderItems(_ cell: LaunchpadDisplayCell?) -> [String]? {
        guard case .folder(_, _, let items) = cell else { return nil }
        return items.map(\.id)
    }

    func testFolderRendersValidChildren() {
        let layout = LaunchpadLayout(nodes: [.app(ref(a)), .folder(id: "F1", name: "F", children: [ref(b), ref(c)])])
        let cells = LaunchpadLayoutReconciler.reconcile(apps: sample(), layout: layout, hidden: [])
        XCTAssertEqual(cells.map(\.id), [a, "folder.F1"])
        XCTAssertEqual(folderItems(cells.last), [b, c])
    }

    func testFolderSkipsMissingChildren() {
        let present = [app(a, "Alpha"), app(c, "Charlie")]   // b 卸载
        let layout = LaunchpadLayout(nodes: [.folder(id: "F1", name: "F", children: [ref(b), ref(c)]), .app(ref(a))])
        let cells = LaunchpadLayoutReconciler.reconcile(apps: present, layout: layout, hidden: [])
        XCTAssertEqual(cells.map(\.id), ["folder.F1", a])
        XCTAssertEqual(folderItems(cells.first), [c])   // 只剩 c
    }

    func testEmptyFolderIsDropped() {
        let present = [app(a, "Alpha")]                     // b、c 都不在
        let layout = LaunchpadLayout(nodes: [.folder(id: "F1", name: "F", children: [ref(b), ref(c)]), .app(ref(a))])
        let cells = LaunchpadLayoutReconciler.reconcile(apps: present, layout: layout, hidden: [])
        XCTAssertEqual(cells.map(\.id), [a], "children 全没了 → 空夹不渲染")
    }

    func testAppInFolderNotReappendedAtTail() {
        // a、b 在文件夹里；c 是新装 → 进根层末尾；a、b 不重复出现在顶层
        let layout = LaunchpadLayout(nodes: [.folder(id: "F1", name: "F", children: [ref(a), ref(b)])])
        let cells = LaunchpadLayoutReconciler.reconcile(apps: sample(), layout: layout, hidden: [])
        XCTAssertEqual(cells.map(\.id), ["folder.F1", c])
        XCTAssertEqual(folderItems(cells.first), [a, b])
    }

    func testHiddenFolderChildExcluded() {
        let layout = LaunchpadLayout(nodes: [.folder(id: "F1", name: "F", children: [ref(a), ref(b)])])
        let cells = LaunchpadLayoutReconciler.reconcile(apps: sample(), layout: layout, hidden: [b])
        XCTAssertEqual(cells.map(\.id), ["folder.F1", c])
        XCTAssertEqual(folderItems(cells.first), [a], "隐藏的 folder 内 app 不进缩略")
    }
}
