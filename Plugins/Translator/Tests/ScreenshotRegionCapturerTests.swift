import AppKit
import XCTest
@testable import TranslatorPlugin

@MainActor
final class ScreenshotRegionCapturerTests: XCTestCase {
    func testPermissionDeniedSkipsOverlayAndReturnsPermissionError() async {
        let overlay = RecordingScreenshotOverlaySelector(result: .failure(.cancelled))
        let capturer = ScreenshotRegionCapturer(
            screenRecordingPermissionProvider: { false },
            overlaySelector: overlay
        )

        let result = await capturer.captureRegion()

        XCTAssertEqual(result.error, .screenRecordingPermissionRequired)
        XCTAssertEqual(overlay.startCount, 0)
    }

    func testOverlayCancellationReturnsCancelledError() async {
        let overlay = RecordingScreenshotOverlaySelector(result: .failure(.cancelled))
        let capturer = ScreenshotRegionCapturer(
            screenRecordingPermissionProvider: { true },
            overlaySelector: overlay
        )

        let result = await capturer.captureRegion()

        XCTAssertEqual(result.error, .cancelled)
        XCTAssertEqual(overlay.startCount, 1)
    }
}

@MainActor
private final class RecordingScreenshotOverlaySelector: ScreenshotOverlaySelecting {
    var result: ScreenshotOverlaySelectionResult
    private(set) var startCount = 0

    init(result: ScreenshotOverlaySelectionResult) {
        self.result = result
    }

    func selectRegion() async -> ScreenshotOverlaySelectionResult {
        startCount += 1
        return result
    }
}
