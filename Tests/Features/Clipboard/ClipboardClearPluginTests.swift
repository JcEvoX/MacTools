import XCTest
import AppKit
@testable import MacTools

final class ClipboardClearPluginTests: XCTestCase {
    @MainActor
    func testPanelStateIsDisabledWhenClipboardIsEmpty() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let plugin = ClipboardClearPlugin()
        plugin.refresh()

        XCTAssertFalse(plugin.panelState.isEnabled)
    }

    @MainActor
    func testPanelStateIsEnabledWhenClipboardHasContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("测试内容", forType: .string)

        let plugin = ClipboardClearPlugin()
        plugin.refresh()

        XCTAssertTrue(plugin.panelState.isEnabled)
    }

    @MainActor
    func testClearClipboardActuallyClears() {
        // 1. 先写入内容
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("测试内容", forType: .string)
        XCTAssertEqual(pasteboard.string(forType: .string), "测试内容")

        // 2. 调用插件清空
        let plugin = ClipboardClearPlugin()
        plugin.handlePanelAction(.invokeAction(controlID: "execute"))

        // 3. 验证内容已清空
        let result = pasteboard.string(forType: .string)
        XCTAssertNil(result, "剪贴板内容应被清空")
        XCTAssertFalse(plugin.panelState.isEnabled)
    }
}
