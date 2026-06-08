import AppKit
import Foundation
import XCTest
@testable import TranslatorPlugin

@MainActor
final class TranslatorCoordinatorTests: XCTestCase {
    private var originalPasteboardString: String?

    override func setUp() async throws {
        try await super.setUp()
        originalPasteboardString = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
    }

    override func tearDown() async throws {
        NSPasteboard.general.clearContents()
        if let originalPasteboardString {
            NSPasteboard.general.setString(originalPasteboardString, forType: .string)
        }
        try await super.tearDown()
    }

    func testMissingSelectionShowsMissingSelectionError() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: .missing,
            providerFactory: { .provider(RecordingTranslationProvider(resultText: "unused")) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.missingSelection))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.missingSelection))
        XCTAssertEqual(coordinator.snapshot.errorMessage, "未找到选中文本")
        XCTAssertNil(coordinator.snapshot.sourceText)
        XCTAssertTrue(panel.updatedSnapshots.contains { $0.phase == .capturing })
        XCTAssertTrue(panel.updatedSnapshots.contains { $0.phase == .error(.missingSelection) })
    }

    func testMissingSelectionPreservesConfiguredProviderCards() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: .missing,
            providerFactory: {
                .providers([
                    ResolvedTranslationProvider(
                        id: "openai",
                        title: "OpenAI",
                        provider: RecordingTranslationProvider(resultText: "unused")
                    ),
                    ResolvedTranslationProvider(
                        id: "deepseek",
                        title: "DeepSeek",
                        provider: RecordingTranslationProvider(resultText: "unused")
                    ),
                ])
            },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.missingSelection))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.missingSelection))
        XCTAssertEqual(coordinator.snapshot.providerResults.map(\.providerTitle), ["OpenAI", "DeepSeek"])
        XCTAssertEqual(coordinator.snapshot.providerResults.map(\.phase), [.waiting, .waiting])
    }

    func testAccessibilityFailureShowsPermissionRequiredError() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captures: [
                RecordingSelectedTextCapture(
                    strategyID: .accessibility,
                    result: SelectedTextCaptureResult(
                        text: nil,
                        strategyID: .accessibility,
                        isEditable: false,
                        sourceApplicationBundleID: "com.example.secure",
                        failureReason: "需要辅助功能授权"
                    )
                ),
                RecordingSelectedTextCapture(
                    strategyID: .simulatedCopy,
                    result: SelectedTextCaptureResult(
                        text: nil,
                        strategyID: .simulatedCopy,
                        isEditable: false,
                        sourceApplicationBundleID: nil,
                        failureReason: "复制失败"
                    )
                ),
            ],
            providerFactory: { .provider(RecordingTranslationProvider(resultText: "unused")) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.permissionRequired))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.permissionRequired))
        XCTAssertEqual(coordinator.snapshot.errorMessage, "需要辅助功能授权")
        XCTAssertNil(coordinator.snapshot.sourceText)
        XCTAssertNil(coordinator.snapshot.languageSelection)
        XCTAssertNil(coordinator.snapshot.translation)
    }

    func testMissingConfigurationPreservesCapturedSourceText() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: { .missing(message: "请配置 API Key") },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.missingConfiguration))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.missingConfiguration))
        XCTAssertEqual(coordinator.snapshot.sourceText, "hello")
        XCTAssertEqual(coordinator.snapshot.errorMessage, "请配置 API Key")
        XCTAssertNil(coordinator.snapshot.translation)
    }

    func testSuccessfulTranslationUpdatesSuccessAndTranslationText() async throws {
        let provider = RecordingTranslationProvider(resultText: "你好")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.success)

        XCTAssertEqual(coordinator.snapshot.phase, .success)
        XCTAssertEqual(coordinator.snapshot.sourceText, "hello")
        XCTAssertEqual(coordinator.snapshot.translation?.text, "你好")
        XCTAssertEqual(provider.requests.map(\.text), ["hello"])
        XCTAssertTrue(panel.updatedSnapshots.contains { $0.phase == .capturing })
        XCTAssertTrue(panel.updatedSnapshots.contains { $0.phase == .translating })
        XCTAssertTrue(panel.updatedSnapshots.contains { $0.phase == .success })
    }

    func testMultipleProvidersUpdateIndependentResultsAndFirstSuccess() async throws {
        let firstProvider = RecordingTranslationProvider(resultText: "你好")
        let secondProvider = RecordingTranslationProvider(error: TestTranslationError(message: "服务失败"))
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: {
                .providers([
                    ResolvedTranslationProvider(id: "first", title: "服务一", provider: firstProvider),
                    ResolvedTranslationProvider(id: "second", title: "服务二", provider: secondProvider),
                ])
            },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.success)

        XCTAssertEqual(coordinator.snapshot.phase, .success)
        XCTAssertEqual(coordinator.snapshot.translation?.text, "你好")
        XCTAssertEqual(coordinator.snapshot.providerResults.count, 2)
        XCTAssertEqual(coordinator.snapshot.providerResults[0].phase, .success)
        XCTAssertEqual(coordinator.snapshot.providerResults[0].translation?.text, "你好")
        XCTAssertEqual(coordinator.snapshot.providerResults[1].phase, .error)
        XCTAssertEqual(coordinator.snapshot.providerResults[1].errorMessage, "服务失败")
    }

    func testAllProvidersFailShowsRequestFailedButKeepsProviderErrors() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: {
                .providers([
                    ResolvedTranslationProvider(
                        id: "first",
                        title: "服务一",
                        provider: RecordingTranslationProvider(error: TestTranslationError(message: "服务一失败"))
                    ),
                    ResolvedTranslationProvider(
                        id: "second",
                        title: "服务二",
                        provider: RecordingTranslationProvider(error: TestTranslationError(message: "服务二失败"))
                    ),
                ])
            },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.requestFailed("服务一失败")))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.requestFailed("服务一失败")))
        XCTAssertNil(coordinator.snapshot.translation)
        XCTAssertEqual(coordinator.snapshot.providerResults.map(\.phase), [.error, .error])
    }

    func testProviderScopedCopyWritesSelectedProviderTranslation() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: {
                .providers([
                    ResolvedTranslationProvider(
                        id: "first",
                        title: "服务一",
                        provider: RecordingTranslationProvider(resultText: "你好")
                    ),
                    ResolvedTranslationProvider(
                        id: "second",
                        title: "服务二",
                        provider: RecordingTranslationProvider(resultText: "您好")
                    ),
                ])
            },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.success)
        await coordinator.handle(.copyProviderTranslation("second"))

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "您好")
    }

    func testTranslationFailurePreservesSourceAndLanguageSelection() async throws {
        let provider = RecordingTranslationProvider(error: TestTranslationError(message: "网络失败"))
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.requestFailed("网络失败")))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.requestFailed("网络失败")))
        XCTAssertEqual(coordinator.snapshot.sourceText, "hello")
        XCTAssertEqual(coordinator.snapshot.errorMessage, "网络失败")
        XCTAssertEqual(coordinator.snapshot.languageSelection?.source, .english)
        XCTAssertEqual(coordinator.snapshot.languageSelection?.target, .simplifiedChinese)
    }

    func testRetryWithLastSourceRetranslatesWithoutRecapturing() async {
        let capture = RecordingSelectedTextCapture(result: selectedText("hello"))
        let provider = RecordingTranslationProvider(resultText: "你好")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            capture: capture,
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.success)
        provider.resultText = "您好"

        await coordinator.handle(.retry)
        await panel.waitUntilShown(.success, count: 2)

        XCTAssertEqual(capture.captureCount, 1)
        XCTAssertEqual(provider.requests.map(\.text), ["hello", "hello"])
        XCTAssertEqual(coordinator.snapshot.translation?.text, "您好")
    }

    func testRetryWithoutLastSourceStartsCapture() async {
        let capture = RecordingSelectedTextCapture(result: selectedText("fresh"))
        let provider = RecordingTranslationProvider(resultText: "新文本")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            capture: capture,
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        await coordinator.handle(.retry)
        await panel.waitUntilShown(.success)

        XCTAssertEqual(capture.captureCount, 1)
        XCTAssertEqual(provider.requests.map(\.text), ["fresh"])
        XCTAssertEqual(coordinator.snapshot.translation?.text, "新文本")
    }

    func testScreenshotTranslationRecognizesTextAndTranslates() async {
        let screenshotCapturer = RecordingScreenshotRegionCapturer(result: .success(image: NSImage(size: NSSize(width: 20, height: 20)), selectedRect: CGRect(x: 0, y: 0, width: 20, height: 20), screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let ocrRecognizer = RecordingOCRTextRecognizer(
            result: OCRTextRecognitionResult(
                text: "Hello from screenshot",
                lines: [
                    OCRRecognizedLine(
                        text: "Hello from screenshot",
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                        confidence: 0.9
                    ),
                ]
            )
        )
        let provider = RecordingTranslationProvider(resultText: "截图译文")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            screenshotCapturer: screenshotCapturer,
            ocrRecognizer: ocrRecognizer,
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startScreenshotTranslation()
        await panel.waitUntilShown(.success)

        XCTAssertEqual(screenshotCapturer.captureCount, 1)
        XCTAssertEqual(ocrRecognizer.requests.count, 1)
        XCTAssertEqual(provider.requests.map(\.text), ["Hello from screenshot"])
        XCTAssertEqual(coordinator.snapshot.querySource, .screenshot)
        XCTAssertEqual(coordinator.snapshot.sourceText, "Hello from screenshot")
        XCTAssertEqual(coordinator.snapshot.translation?.text, "截图译文")
    }

    func testScreenshotTranslationDoesNotResolveProviderBeforeOCRTextExists() async {
        let screenshotCapturer = DeferredScreenshotRegionCapturer(
            result: .success(
                image: NSImage(size: NSSize(width: 20, height: 20)),
                selectedRect: CGRect(x: 0, y: 0, width: 20, height: 20),
                screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )
        let ocrRecognizer = DeferredOCRTextRecognizer(
            result: OCRTextRecognitionResult(text: "captured text", lines: [])
        )
        let provider = RecordingTranslationProvider(resultText: "译文")
        let panel = RecordingTranslatorPanelController()
        var providerFactoryCallCount = 0
        let coordinator = makeCoordinator(
            screenshotCapturer: screenshotCapturer,
            ocrRecognizer: ocrRecognizer,
            providerFactory: {
                providerFactoryCallCount += 1
                return .provider(provider)
            },
            panelController: panel
        )

        coordinator.startScreenshotTranslation()
        await screenshotCapturer.waitUntilStarted()
        XCTAssertEqual(providerFactoryCallCount, 0)

        screenshotCapturer.resume()
        await ocrRecognizer.waitUntilStarted()
        XCTAssertEqual(providerFactoryCallCount, 0)

        ocrRecognizer.resume()
        await panel.waitUntilShown(.success)

        XCTAssertEqual(providerFactoryCallCount, 1)
        XCTAssertEqual(provider.requests.map(\.text), ["captured text"])
    }

    func testScreenshotCancellationDoesNotResolveProvider() async {
        let screenshotCapturer = RecordingScreenshotRegionCapturer(result: .failure(.cancelled))
        let ocrRecognizer = RecordingOCRTextRecognizer(
            result: OCRTextRecognitionResult(text: "unused", lines: [])
        )
        let panel = RecordingTranslatorPanelController()
        var providerFactoryCallCount = 0
        let coordinator = makeCoordinator(
            screenshotCapturer: screenshotCapturer,
            ocrRecognizer: ocrRecognizer,
            providerFactory: {
                providerFactoryCallCount += 1
                return .provider(RecordingTranslationProvider(resultText: "unused"))
            },
            panelController: panel
        )

        coordinator.startScreenshotTranslation()
        await panel.waitUntilShown(.error(.screenshotCancelled))

        XCTAssertEqual(providerFactoryCallCount, 0)
    }

    func testScreenshotTranslationEmptyOCRShowsMissingOCRText() async {
        let screenshotCapturer = RecordingScreenshotRegionCapturer(result: .success(image: NSImage(size: NSSize(width: 20, height: 20)), selectedRect: CGRect(x: 0, y: 0, width: 20, height: 20), screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let ocrRecognizer = RecordingOCRTextRecognizer(error: OCRTextRecognitionError.emptyResult)
        let provider = RecordingTranslationProvider(resultText: "unused")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            screenshotCapturer: screenshotCapturer,
            ocrRecognizer: ocrRecognizer,
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startScreenshotTranslation()
        await panel.waitUntilShown(.error(.missingOCRText))

        XCTAssertEqual(coordinator.snapshot.phase, .error(.missingOCRText))
        XCTAssertEqual(coordinator.snapshot.querySource, .screenshot)
        XCTAssertEqual(coordinator.snapshot.errorMessage, "截图中没有识别到文字")
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testRetryAfterScreenshotFailureStartsScreenshotCaptureAgain() async {
        let screenshotCapturer = RecordingScreenshotRegionCapturer(result: .failure(.cancelled))
        let ocrRecognizer = RecordingOCRTextRecognizer(
            result: OCRTextRecognitionResult(text: "fresh screenshot", lines: [])
        )
        let provider = RecordingTranslationProvider(resultText: "新截图译文")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            screenshotCapturer: screenshotCapturer,
            ocrRecognizer: ocrRecognizer,
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startScreenshotTranslation()
        await panel.waitUntilShown(.error(.screenshotCancelled))
        screenshotCapturer.result = .success(
            image: NSImage(size: NSSize(width: 20, height: 20)),
            selectedRect: CGRect(x: 0, y: 0, width: 20, height: 20),
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        await coordinator.handle(.retry)
        await panel.waitUntilShown(.success)

        XCTAssertEqual(screenshotCapturer.captureCount, 2)
        XCTAssertEqual(provider.requests.map(\.text), ["fresh screenshot"])
        XCTAssertEqual(coordinator.snapshot.querySource, .screenshot)
    }

    func testRetryAfterFreshMissingSelectionDoesNotRetranslatePreviousSource() async {
        let capture = RecordingSelectedTextCapture(result: selectedText("first"))
        let provider = RecordingTranslationProvider(resultText: "第一段")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            capture: capture,
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.success)
        capture.result = .missing
        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.error(.missingSelection))
        await coordinator.handle(.retry)
        await panel.waitUntilShown(.error(.missingSelection), count: 2)

        XCTAssertEqual(capture.captureCount, 3)
        XCTAssertEqual(provider.requests.map(\.text), ["first"])
        XCTAssertEqual(coordinator.snapshot.phase, .error(.missingSelection))
    }

    func testCloseInvalidatesSessionAndClosesPanel() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: { .provider(RecordingTranslationProvider(resultText: "你好")) },
            panelController: panel
        )

        await coordinator.handle(.close)

        XCTAssertTrue(panel.didClose)
    }

    func testCloseDuringPendingCapturePreventsProviderInvocation() async {
        let capture = DeferredSelectedTextCapture(result: selectedText("hello"))
        let provider = RecordingTranslationProvider(resultText: "你好")
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captures: [capture],
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await capture.waitUntilStarted()

        await coordinator.handle(.close)
        capture.resume()
        await capture.waitUntilCompleted()

        XCTAssertTrue(panel.didClose)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testCloseDuringPendingTranslationCancelsProviderTask() async {
        let provider = DeferredTranslationProvider()
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: { .provider(provider) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await provider.waitUntilStarted()

        await coordinator.handle(.close)
        await provider.waitUntilCancelled()

        XCTAssertTrue(panel.didClose)
    }

    func testCopySourceAndTranslationWriteToGeneralPasteboard() async {
        let panel = RecordingTranslatorPanelController()
        let coordinator = makeCoordinator(
            captureResult: selectedText("hello"),
            providerFactory: { .provider(RecordingTranslationProvider(resultText: "你好")) },
            panelController: panel
        )

        coordinator.startSelectTranslation()
        await panel.waitUntilShown(.success)
        await coordinator.handle(.copySource)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")

        await coordinator.handle(.copyTranslation)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "你好")
    }

    private func makeCoordinator(
        captureResult: SelectedTextCaptureResult,
        providerFactory: @escaping TranslatorProviderFactory,
        panelController: TranslatorPanelControlling? = nil
    ) -> TranslatorCoordinator {
        makeCoordinator(
            capture: RecordingSelectedTextCapture(result: captureResult),
            providerFactory: providerFactory,
            panelController: panelController
        )
    }

    private func makeCoordinator(
        capture: RecordingSelectedTextCapture,
        providerFactory: @escaping TranslatorProviderFactory,
        panelController: TranslatorPanelControlling? = nil
    ) -> TranslatorCoordinator {
        makeCoordinator(
            captures: [capture],
            providerFactory: providerFactory,
            panelController: panelController
        )
    }

    private func makeCoordinator(
        captures: [any SelectedTextCapturing],
        screenshotCapturer: (any ScreenshotRegionCapturing)? = nil,
        ocrRecognizer: (any OCRTextRecognizing)? = nil,
        providerFactory: @escaping TranslatorProviderFactory,
        panelController: TranslatorPanelControlling? = nil
    ) -> TranslatorCoordinator {
        let storage = TranslatorInMemoryPluginStorage()
        let languagePreferenceStore = LanguagePreferenceStore(storage: storage)
        languagePreferenceStore.savePair(
            TranslatorLanguagePair(first: .simplifiedChinese, second: .english)
        )

        return TranslatorCoordinator(
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: captures),
            screenshotRegionCapturer: screenshotCapturer,
            ocrTextRecognizer: ocrRecognizer,
            languagePreferenceStore: languagePreferenceStore,
            providerFactory: providerFactory,
            panelController: panelController
        )
    }

    private func makeCoordinator(
        screenshotCapturer: any ScreenshotRegionCapturing,
        ocrRecognizer: any OCRTextRecognizing,
        providerFactory: @escaping TranslatorProviderFactory,
        panelController: TranslatorPanelControlling? = nil
    ) -> TranslatorCoordinator {
        makeCoordinator(
            captures: [RecordingSelectedTextCapture(result: .missing)],
            screenshotCapturer: screenshotCapturer,
            ocrRecognizer: ocrRecognizer,
            providerFactory: providerFactory,
            panelController: panelController
        )
    }

    private func selectedText(_ text: String) -> SelectedTextCaptureResult {
        SelectedTextCaptureResult(
            text: text,
            strategyID: .accessibility,
            isEditable: false,
            sourceApplicationBundleID: "com.example.app",
            failureReason: nil
        )
    }
}

@MainActor
private final class RecordingScreenshotRegionCapturer: ScreenshotRegionCapturing {
    var result: ScreenshotCaptureResult
    private(set) var captureCount = 0

    init(result: ScreenshotCaptureResult) {
        self.result = result
    }

    func captureRegion() async -> ScreenshotCaptureResult {
        captureCount += 1
        return result
    }
}

private final class RecordingOCRTextRecognizer: OCRTextRecognizing {
    var result: OCRTextRecognitionResult?
    var error: Error?
    private(set) var requests: [NSImage] = []

    init(result: OCRTextRecognitionResult) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func recognizeText(in image: NSImage) async throws -> OCRTextRecognitionResult {
        requests.append(image)
        if let error {
            throw error
        }
        guard let result else {
            throw OCRTextRecognitionError.emptyResult
        }
        return result
    }
}

@MainActor
private final class DeferredScreenshotRegionCapturer: ScreenshotRegionCapturing {
    let result: ScreenshotCaptureResult
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<ScreenshotCaptureResult, Never>?
    private var didStart = false

    init(result: ScreenshotCaptureResult) {
        self.result = result
    }

    func captureRegion() async -> ScreenshotCaptureResult {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if didStart { return }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private final class DeferredOCRTextRecognizer: OCRTextRecognizing {
    let result: OCRTextRecognitionResult
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<OCRTextRecognitionResult, Error>?
    private var didStart = false

    init(result: OCRTextRecognitionResult) {
        self.result = result
    }

    func recognizeText(in image: NSImage) async throws -> OCRTextRecognitionResult {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if didStart { return }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

@MainActor
private final class RecordingTranslatorPanelController: TranslatorPanelControlling {
    var onAction: ((TranslatorPanelAction) -> Void)?
    private(set) var shownSnapshots: [TranslatorPanelSnapshot] = []
    private(set) var updatedSnapshots: [TranslatorPanelSnapshot] = []
    private(set) var didClose = false
    private var shownPhaseWaiters: [(TranslatorPanelPhase, Int, CheckedContinuation<Void, Never>)] = []
    private var updatedPhaseWaiters: [(TranslatorPanelPhase, Int, CheckedContinuation<Void, Never>)] = []

    func show(snapshot: TranslatorPanelSnapshot) {
        shownSnapshots.append(snapshot)
        resumeShownWaiters(matching: snapshot.phase)
    }

    func update(snapshot: TranslatorPanelSnapshot) {
        updatedSnapshots.append(snapshot)
        resumeUpdatedWaiters(matching: snapshot.phase)
    }

    func close() {
        didClose = true
    }

    func waitUntilShown(_ phase: TranslatorPanelPhase, count: Int = 1) async {
        if shownSnapshots.filter({ $0.phase == phase }).count >= count { return }

        await withCheckedContinuation { continuation in
            shownPhaseWaiters.append((phase, count, continuation))
        }
    }

    func waitUntilUpdated(_ phase: TranslatorPanelPhase, count: Int = 1) async {
        if updatedSnapshots.filter({ $0.phase == phase }).count >= count { return }

        await withCheckedContinuation { continuation in
            updatedPhaseWaiters.append((phase, count, continuation))
        }
    }

    private func resumeShownWaiters(matching phase: TranslatorPanelPhase) {
        let currentCount = shownSnapshots.filter { $0.phase == phase }.count
        let matching = shownPhaseWaiters.filter { $0.0 == phase && currentCount >= $0.1 }
        shownPhaseWaiters.removeAll { $0.0 == phase && currentCount >= $0.1 }
        matching.forEach { $0.2.resume() }
    }

    private func resumeUpdatedWaiters(matching phase: TranslatorPanelPhase) {
        let currentCount = updatedSnapshots.filter { $0.phase == phase }.count
        let matching = updatedPhaseWaiters.filter { $0.0 == phase && currentCount >= $0.1 }
        updatedPhaseWaiters.removeAll { $0.0 == phase && currentCount >= $0.1 }
        matching.forEach { $0.2.resume() }
    }
}

@MainActor
private final class RecordingSelectedTextCapture: SelectedTextCapturing {
    let strategyID: SelectedTextCaptureStrategyID
    var result: SelectedTextCaptureResult
    private(set) var captureCount = 0

    init(
        strategyID: SelectedTextCaptureStrategyID = .accessibility,
        result: SelectedTextCaptureResult
    ) {
        self.strategyID = strategyID
        self.result = result
    }

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        captureCount += 1
        return result
    }
}

@MainActor
private final class DeferredSelectedTextCapture: SelectedTextCapturing {
    let strategyID: SelectedTextCaptureStrategyID
    let result: SelectedTextCaptureResult
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var completedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<SelectedTextCaptureResult, Never>?
    private var didStart = false
    private var didComplete = false

    init(
        strategyID: SelectedTextCaptureStrategyID = .accessibility,
        result: SelectedTextCaptureResult
    ) {
        self.strategyID = strategyID
        self.result = result
    }

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        let result = await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
        didComplete = true
        completedContinuation?.resume()
        completedContinuation = nil
        return result
    }

    func waitUntilStarted() async {
        if didStart { return }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }

    func waitUntilCompleted() async {
        if didComplete { return }

        await withCheckedContinuation { continuation in
            completedContinuation = continuation
        }
    }
}

private struct TranslationRequest: Equatable {
    var text: String
    var languageSelection: TranslatorLanguageSelection
}

private final class RecordingTranslationProvider: TranslationProviding, @unchecked Sendable {
    var resultText: String
    var error: Error?
    private(set) var requests: [TranslationRequest] = []

    init(resultText: String = "", error: Error? = nil) {
        self.resultText = resultText
        self.error = error
    }

    func translate(
        text: String,
        languageSelection: TranslatorLanguageSelection
    ) async throws -> TranslationResult {
        requests.append(TranslationRequest(text: text, languageSelection: languageSelection))

        if let error {
            throw error
        }

        return TranslationResult(
            providerTitle: "测试翻译",
            text: resultText,
            sourceText: text,
            languageSelection: languageSelection
        )
    }
}

@MainActor
private final class DeferredTranslationProvider: TranslationProviding, @unchecked Sendable {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var cancelledContinuation: CheckedContinuation<Void, Never>?
    private var translationContinuation: CheckedContinuation<TranslationResult, Error>?
    private var didStart = false
    private var didCancel = false

    func translate(
        text: String,
        languageSelection: TranslatorLanguageSelection
    ) async throws -> TranslationResult {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                translationContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                didCancel = true
                translationContinuation?.resume(throwing: CancellationError())
                translationContinuation = nil
                cancelledContinuation?.resume()
                cancelledContinuation = nil
            }
        }
    }

    func waitUntilStarted() async {
        if didStart { return }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func waitUntilCancelled() async {
        if didCancel { return }

        await withCheckedContinuation { continuation in
            cancelledContinuation = continuation
        }
    }
}

private struct TestTranslationError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
