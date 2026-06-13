import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// The folder-rename state machine (single-resolution latch, design §2.3), the field
/// coordinator's event forwarding, and the Esc routing rule (§2.4) — all without a live
/// folder panel.
@MainActor
final class LaunchpadRenameEditSessionTests: XCTestCase {

    // MARK: - Pure session latch table

    func testReturnCommitsOnceAndTrailingEndEditingIsInert() {
        var session = LaunchpadRenameEditSession.begin(originalName: "旧名")
        session.textChanged("新名")
        XCTAssertEqual(session.commit(), .commit("新名"))
        XCTAssertTrue(session.hasResolved)
        XCTAssertNil(session.endEditing(), "回车后的 end-editing 必须被 latch 吃掉（单次提交）")
        XCTAssertNil(session.commit(), "重复 commit 也不再产出 resolution")
    }

    func testEscCancelsRestoresOriginalAndNeverCommits() {
        var session = LaunchpadRenameEditSession.begin(originalName: "旧名")
        session.textChanged("敲了一半")
        XCTAssertEqual(session.cancel(), .cancel(restore: "旧名"))
        XCTAssertNil(session.endEditing(), "Esc 后的 end-editing 不得变成 commit（撤销不能被失焦覆盖）")
    }

    func testPlainBlurCommitsCurrentTextExactlyOnce() {
        var session = LaunchpadRenameEditSession.begin(originalName: "旧名")
        session.textChanged("新名")
        XCTAssertEqual(session.endEditing(), .commit("新名"), "纯失焦 = 提交")
        XCTAssertNil(session.endEditing())
    }

    func testTextChangedAfterResolutionIsIgnored() {
        var session = LaunchpadRenameEditSession.begin(originalName: "旧名")
        _ = session.commit()
        session.textChanged("迟到的输入")
        XCTAssertEqual(session.currentText, "旧名", "resolution 之后的字段通知不得改写会话")
    }

    func testUntouchedSessionCommitsOriginalName() {
        var session = LaunchpadRenameEditSession.begin(originalName: "旧名")
        XCTAssertEqual(session.endEditing(), .commit("旧名"),
                       "点开又点走：提交原名（store 的 no-change guard 负责不写盘）")
    }

    // MARK: - Coordinator forwarding (no field editor / window needed)

    private func makeCoordinator(
        onCommit: @escaping (String) -> Void = { _ in }
    ) -> LaunchpadFolderRenameField.Coordinator {
        let field = LaunchpadFolderRenameField(
            folderID: "F1", name: "旧名", placeholder: "文件夹名称",
            focusRequestID: nil, controller: nil, onCommit: onCommit
        )
        return LaunchpadFolderRenameField.Coordinator(field)
    }

    func testReturnSelectorCommitsThenEndEditingDoesNotDoubleCommit() {
        var commits: [String] = []
        let coordinator = makeCoordinator(onCommit: { commits.append($0) })
        coordinator.beginEditing(original: "旧名")
        coordinator.handleTextChange("新名")

        XCTAssertTrue(coordinator.handleCommand(#selector(NSResponder.insertNewline(_:)), hasMarkedText: false))
        coordinator.handleEndEditing()                       // the refocus-triggered native blur
        XCTAssertEqual(commits, ["新名"], "回车恰好提交一次")
        XCTAssertFalse(coordinator.isEditing)
    }

    func testEscSelectorCancelsAndEndEditingStaysSilent() {
        var commits: [String] = []
        let coordinator = makeCoordinator(onCommit: { commits.append($0) })
        coordinator.beginEditing(original: "旧名")
        coordinator.handleTextChange("敲了一半")

        XCTAssertTrue(coordinator.handleCommand(#selector(NSResponder.cancelOperation(_:)), hasMarkedText: false))
        XCTAssertEqual(coordinator.lastResolution, .cancel(restore: "旧名"))
        coordinator.handleEndEditing()
        XCTAssertEqual(commits, [], "Esc 撤销后绝不提交")
    }

    func testMarkedTextHandsCommandsBackToIME() {
        let coordinator = makeCoordinator()
        coordinator.beginEditing(original: "旧名")
        XCTAssertFalse(coordinator.handleCommand(#selector(NSResponder.insertNewline(_:)), hasMarkedText: true),
                       "IME 组合中回车交还系统（确认候选，不提交改名）")
        XCTAssertFalse(coordinator.handleCommand(#selector(NSResponder.cancelOperation(_:)), hasMarkedText: true))
        XCTAssertTrue(coordinator.isEditing, "组合中的命令不结束会话")
    }

    func testCommandsWithoutSessionFallThrough() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.handleCommand(#selector(NSResponder.insertNewline(_:)), hasMarkedText: false))
    }

    func testEndEditingNowCommitHonoursLatch() {
        var commits: [String] = []
        let coordinator = makeCoordinator(onCommit: { commits.append($0) })
        coordinator.beginEditing(original: "旧名")
        coordinator.handleTextChange("新名")
        coordinator.endEditingNow(commit: true)              // blank-tap / closeFolder hook
        coordinator.endEditingNow(commit: true)              // double hook (scrim + closeFolder) = once
        coordinator.handleEndEditing()
        XCTAssertEqual(commits, ["新名"])
    }

    func testBeginEditingWhileEditingIsIdempotent() {
        let coordinator = makeCoordinator()
        coordinator.beginEditing(original: "旧名")
        coordinator.handleTextChange("改了")
        coordinator.beginEditing(original: "改了")            // spurious focus-in mid-session
        XCTAssertEqual(coordinator.session?.originalName, "旧名", "重复 focus-in 不得重置 originalName")
    }

    // MARK: - Esc routing (§2.4): 取消改名优先于关启动台

    func testShouldRouteEscOnlyForRenameFieldEditor() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = content

        let rename = LaunchpadRenameTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        rename.isEditable = true
        let search = NSSearchField(frame: NSRect(x: 0, y: 40, width: 200, height: 24))
        content.addSubview(rename)
        content.addSubview(search)

        XCTAssertFalse(LaunchpadFolderRenameField.shouldRouteEsc(to: nil))

        window.makeFirstResponder(rename)
        XCTAssertTrue(LaunchpadFolderRenameField.shouldRouteEsc(to: window.firstResponder),
                      "改名字段的 field editor → 放行 Esc 给 cancelOperation")

        window.makeFirstResponder(search)
        XCTAssertFalse(LaunchpadFolderRenameField.shouldRouteEsc(to: window.firstResponder),
                       "搜索框的 field editor → 不放行（沿用关启动台）")
        window.close()
    }

    // MARK: - Whole-window teardown (§2.3): close() resigns first responder → commit

    /// The overlay controller's `close()` calls `makeFirstResponder(nil)` before tearing the
    /// window down (Cmd+Tab / Settings window / in-folder app launch): the field editor must
    /// end editing and commit the typed name exactly once, on the event stack — dismantle is
    /// NOT contracted for an NSHostingView deallocated with its window, so this resign is the
    /// path that keeps the name from being silently lost.
    func testResignFirstResponderViaWindowCommitsRenameExactlyOnce() {
        var commits: [String] = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = content

        let field = LaunchpadRenameTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.isEditable = true
        field.stringValue = "旧名"
        let parent = LaunchpadFolderRenameField(
            folderID: "F1", name: "旧名", placeholder: "文件夹名称",
            focusRequestID: nil, controller: nil, onCommit: { commits.append($0) }
        )
        let coordinator = LaunchpadFolderRenameField.Coordinator(parent)
        coordinator.field = field
        field.delegate = coordinator
        field.onFocusIn = { [weak coordinator, weak field] in
            coordinator?.beginEditing(original: field?.stringValue ?? "")
        }
        content.addSubview(field)

        window.makeFirstResponder(field)
        XCTAssertTrue(coordinator.isEditing, "点击标题（成为 first responder）= 进入编辑")
        guard let editor = window.firstResponder as? NSTextView else {
            return XCTFail("编辑中的字段必须持有 field editor")
        }
        editor.insertText("新名", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))

        window.makeFirstResponder(nil)                       // what close() does pre-teardown
        // Real-time save may commit on the keystroke and again on resign; both carry the edited
        // name. What matters: the edited name is saved and no stale/default name ever leaks.
        XCTAssertFalse(commits.isEmpty, "编辑的名字必须被提交")
        XCTAssertEqual(commits.last, "新名", "最终保存的是在编辑的名字")
        XCTAssertTrue(commits.allSatisfy { $0 == "新名" }, "提交的都是编辑名,无脏数据")
        XCTAssertFalse(coordinator.isEditing)
        let committedAfterResign = commits.count

        // The dismantle backstop may or may not run afterwards — the session already resolved
        // at resign, so it must add NO further commit (stays inert regardless of real-time save).
        LaunchpadFolderRenameField.dismantleNSView(field, coordinator: coordinator)
        XCTAssertEqual(commits.count, committedAfterResign, "resign 已提交后 dismantle 不得二次提交")
        XCTAssertTrue(commits.allSatisfy { $0 == "新名" }, "全程无脏数据")
        window.close()
    }

    func testRenameFieldRefusesFocusWhenGated() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = content
        let rename = LaunchpadRenameTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        rename.isEditable = true
        rename.editGate = { false }                          // mid-carry: rename entry is gated
        content.addSubview(rename)

        window.makeFirstResponder(rename)
        XCTAssertFalse(LaunchpadFolderRenameField.shouldRouteEsc(to: window.firstResponder),
                       "gate 拒绝后字段不得成为 first responder（mid-carry 不可进入改名）")
        window.close()
    }
}
