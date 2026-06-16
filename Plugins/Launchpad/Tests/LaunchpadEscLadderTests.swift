import AppKit
import Combine
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// The §2.4 Esc ladder as a whole — 取消改名 → 关文件夹 → 关启动台 — resolved by the
/// controller's pure `resolveEscape` rule, plus the coordinator's folder-visibility mirror
/// and close-request token the middle rung rides on. The implementation-period review only
/// tested the rename exemption; the MIDDLE rung (close the open folder, not the launcher)
/// was unreachable because the key monitor swallowed Esc before any responder could see it.
@MainActor
final class LaunchpadEscLadderTests: XCTestCase {

    // MARK: - resolveEscape ladder table

    func testEscWithNothingSpecialClosesTheOverlay() {
        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: nil, isFolderOpen: false, carryLive: false),
            .closeOverlay)
    }

    func testEscWithOpenFolderClosesTheFolderNotTheOverlay() {
        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: nil, isFolderOpen: true, carryLive: false),
            .closeFolder,
            "夹开着的 Esc 必须走中段（只关夹）——这是终审确认缺失的一级")
    }

    func testEscDuringLiveCarryKeepsAbortEverythingSemantics() {
        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: nil, isFolderOpen: true, carryLive: true),
            .closeOverlay,
            "carry 进行中 Esc 沿用整窗关闭（close → cancelCarry），不被夹豁免拦截")
    }

    func testRenameFieldEditorOwnsEscBeforeTheFolderRung() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = content
        let rename = LaunchpadRenameTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        rename.isEditable = true
        content.addSubview(rename)
        window.makeFirstResponder(rename)

        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: window.firstResponder, isFolderOpen: true, carryLive: false),
            .routeToFieldEditor,
            "改名编辑中的 Esc 必须先取消改名——夹豁免不得抢在它前面（阶梯顺序）")
        window.close()
    }

    func testSearchFieldEditorWithoutMarkedTextFallsThroughTheLadder() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = content
        let search = NSSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        content.addSubview(search)
        window.makeFirstResponder(search)

        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: window.firstResponder, isFolderOpen: true, carryLive: false),
            .closeFolder,
            "搜索框（无 marked text）不豁免——夹开时落到中段")
        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: window.firstResponder, isFolderOpen: false, carryLive: false),
            .closeOverlay)
        window.close()
    }

    func testMarkedTextRoutesToFieldEditorEvenWithFolderOpen() {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText(), "前提：marked text 已挂上")
        XCTAssertEqual(
            LaunchpadOverlayController.resolveEscape(
                firstResponder: editor, isFolderOpen: true, carryLive: false),
            .routeToFieldEditor,
            "IME 组合中的 Esc 永远先交还候选窗（第一豁免保持最高优先级）")
    }

    // MARK: - Coordinator mirror + close-request token

    func testFolderPanelMirrorFlipsAndDedupes() {
        let coordinator = LaunchpadDragCoordinator()
        var publishes = 0
        let subscription = coordinator.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        XCTAssertFalse(coordinator.isFolderOpen)
        coordinator.folderPanelDidChange(open: true)
        XCTAssertTrue(coordinator.isFolderOpen)
        XCTAssertEqual(publishes, 1)
        coordinator.folderPanelDidChange(open: true)    // safety-net re-sync must not republish
        XCTAssertEqual(publishes, 1, "同值镜像写入必须去重（安全网 onChange 会反复喂）")
        coordinator.folderPanelDidChange(open: false)
        XCTAssertFalse(coordinator.isFolderOpen)
        XCTAssertEqual(publishes, 2)
    }

    func testFolderCloseRequestTokenBumpsPerRequest() {
        let coordinator = LaunchpadDragCoordinator()
        XCTAssertEqual(coordinator.folderCloseRequestToken, 0)
        coordinator.requestFolderClose()
        coordinator.requestFolderClose()
        XCTAssertEqual(coordinator.folderCloseRequestToken, 2,
                       "连续 Esc 各自递增 token——每次请求都能被 onChange 消费")
    }
}
