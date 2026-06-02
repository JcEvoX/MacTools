import AppKit
import Foundation

struct MenuCopySelectedTextCapture: SelectedTextCapturing {
    let strategyID: SelectedTextCaptureStrategyID = .menuCopy

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        let didSendCopy = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        guard didSendCopy else {
            guard snapshot.restore(to: pasteboard) else {
                return failure(context: context, reason: "无法恢复剪贴板")
            }
            return failure(context: context, reason: "复制菜单不可用")
        }

        await waitForPasteboardChange(from: clearedChangeCount, in: pasteboard)
        let text = pasteboard.string(forType: .string)
        guard snapshot.restore(to: pasteboard) else {
            return failure(context: context, reason: "无法恢复剪贴板")
        }

        guard let text, !text.isEmpty else {
            return failure(context: context, reason: "未找到选中文本")
        }

        return SelectedTextCaptureResult(
            text: text,
            strategyID: strategyID,
            isEditable: false,
            sourceApplicationBundleID: context.frontmostApplicationBundleID,
            failureReason: nil
        )
    }

    private func waitForPasteboardChange(from clearedChangeCount: Int, in pasteboard: NSPasteboard) async {
        let deadline = Date().addingTimeInterval(0.8)
        while pasteboard.changeCount == clearedChangeCount && Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        if pasteboard.changeCount != clearedChangeCount {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    private func failure(context: SelectedTextCaptureContext, reason: String) -> SelectedTextCaptureResult {
        SelectedTextCaptureResult(
            text: nil,
            strategyID: strategyID,
            isEditable: false,
            sourceApplicationBundleID: context.frontmostApplicationBundleID,
            failureReason: reason
        )
    }
}
