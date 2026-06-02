import Foundation

@MainActor
struct SelectedTextCapturePipeline {
    let strategies: [any SelectedTextCapturing]

    static func live() -> SelectedTextCapturePipeline {
        SelectedTextCapturePipeline(strategies: [
            AccessibilitySelectedTextCapture(),
            BrowserAppleScriptSelectedTextCapture(),
            MenuCopySelectedTextCapture(),
            SimulatedCopySelectedTextCapture(),
        ])
    }

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        var permissionRequiredResult: SelectedTextCaptureResult?

        for strategy in strategies {
            let result = await strategy.capture(context: context)
            let trimmedText = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedText.isEmpty else {
                if permissionRequiredResult == nil,
                   result.failureReason == "需要辅助功能授权" {
                    permissionRequiredResult = result
                }

                continue
            }

            return SelectedTextCaptureResult(
                text: trimmedText,
                strategyID: result.strategyID,
                isEditable: result.isEditable,
                sourceApplicationBundleID: result.sourceApplicationBundleID,
                failureReason: nil
            )
        }

        if let permissionRequiredResult {
            return permissionRequiredResult
        }

        return .missing
    }
}
