import AppKit
import Foundation

struct BrowserAppleScriptSelectedTextCapture: SelectedTextCapturing {
    let strategyID: SelectedTextCaptureStrategyID = .browserAppleScript

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        guard let bundleID = context.frontmostApplicationBundleID else {
            return failure(context: context, reason: "未找到当前应用")
        }

        guard AppCaptureCompatibility.supportsAppleScriptSelection(bundleID) else {
            return failure(context: context, reason: "当前浏览器不支持自动化取词")
        }

        guard let script = script(bundleID: bundleID),
              let appleScript = NSAppleScript(source: script) else {
            return failure(context: context, reason: "自动化脚本无效")
        }

        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            return failure(context: context, reason: "自动化取词失败")
        }

        return SelectedTextCaptureResult(
            text: descriptor.stringValue,
            strategyID: strategyID,
            isEditable: false,
            sourceApplicationBundleID: bundleID,
            failureReason: descriptor.stringValue == nil ? "未找到选中文本" : nil
        )
    }

    private func script(bundleID: String) -> String? {
        if AppCaptureCompatibility.isSafari(bundleID) {
            return """
            tell application id "\(bundleID)"
                do JavaScript "window.getSelection().toString();" in current tab of front window
            end tell
            """
        }

        guard AppCaptureCompatibility.supportsAppleScriptSelection(bundleID) else {
            return nil
        }

        return """
        tell application id "\(bundleID)"
            tell active tab of front window
                execute javascript "window.getSelection().toString();"
            end tell
        end tell
        """
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
