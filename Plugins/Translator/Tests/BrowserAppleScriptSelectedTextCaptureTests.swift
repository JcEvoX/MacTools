import Foundation
import XCTest
@testable import TranslatorPlugin

@MainActor
final class BrowserAppleScriptSelectedTextCaptureTests: XCTestCase {
    func testTimedOutAppleScriptReturnsFailureInsteadOfHanging() async {
        let capture = BrowserAppleScriptSelectedTextCapture(
            executor: SlowBrowserAppleScriptExecutor(),
            timeout: 0.01
        )

        let result = await capture.capture(
            context: SelectedTextCaptureContext(frontmostApplicationBundleID: "com.apple.Safari")
        )

        XCTAssertNil(result.text)
        XCTAssertEqual(result.strategyID, .browserAppleScript)
        XCTAssertEqual(result.sourceApplicationBundleID, "com.apple.Safari")
        XCTAssertEqual(result.failureReason, "自动化取词超时")
    }
}

private struct SlowBrowserAppleScriptExecutor: BrowserAppleScriptExecuting {
    func execute(_ script: String) async throws -> String? {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "late selection"
    }
}
