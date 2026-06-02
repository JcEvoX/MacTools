import AppKit
import ApplicationServices
import Carbon
import Foundation

struct SimulatedCopySelectedTextCapture: SelectedTextCapturing {
    let strategyID: SelectedTextCaptureStrategyID = .simulatedCopy

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        guard AccessibilityCheck.isTrusted() else {
            return failure(context: context, reason: "需要辅助功能授权")
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        guard sendCommandC() else {
            guard snapshot.restore(to: pasteboard) else {
                return failure(context: context, reason: "无法恢复剪贴板")
            }
            return failure(context: context, reason: "模拟复制失败")
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

    private func sendCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: false
              ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
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
