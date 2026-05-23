import XCTest
@testable import MacTools
@testable import XcodeCleanPlugin

@MainActor
final class XcodeCleanControllerTests: XCTestCase {
    func testInitialStateIsIdleAndAllCategoriesSelected() {
        let controller = makeController()

        XCTAssertEqual(controller.snapshot.phase, .idle)
        XCTAssertEqual(controller.snapshot.selectedCategories, Set(XcodeCleanCategory.allCases))
        XCTAssertNil(controller.snapshot.scanResult)
        XCTAssertFalse(controller.snapshot.isXcodeRunning)
    }

    func testScanTransitionsThroughScanningToScanned() async {
        let result = makeScanResult(categories: Set(XcodeCleanCategory.allCases))
        let scanner = FakeXcodeCleanScanner(result: result, delayNanoseconds: 20_000_000)
        let controller = makeController(scanner: scanner)

        controller.scan()

        XCTAssertEqual(controller.snapshot.phase, .scanning)
        await waitUntil { controller.snapshot.phase == .scanned }
        XCTAssertEqual(controller.snapshot.scanResult, result)
        XCTAssertTrue(controller.snapshot.canClean)
    }

    func testToggleCategoryAfterScanMarksResultStale() async {
        let result = makeScanResult(categories: Set(XcodeCleanCategory.allCases))
        let scanner = FakeXcodeCleanScanner(result: result)
        let executor = FakeXcodeCleanExecutor()
        let controller = makeController(scanner: scanner, executor: executor)

        controller.scan()
        await waitUntil { controller.snapshot.phase == .scanned }
        controller.setCategory(.archives, isSelected: false)
        controller.cleanSelected(candidateIDs: ["candidate"])

        XCTAssertTrue(controller.snapshot.isResultStale)
        XCTAssertFalse(controller.snapshot.canClean)
        XCTAssertEqual(executor.cleanCalls.count, 0)
    }

    func testCleanTransitionsToCompleted() async {
        let result = makeScanResult(categories: Set(XcodeCleanCategory.allCases))
        let executionResult = XcodeCleanExecutionResult(itemResults: [
            XcodeCleanExecutionItemResult(
                candidateID: "candidate",
                path: "/tmp/path",
                outcome: .removed(reclaimedBytes: 10)
            )
        ])
        let controller = makeController(
            scanner: FakeXcodeCleanScanner(result: result),
            executor: FakeXcodeCleanExecutor(result: executionResult, delayNanoseconds: 20_000_000)
        )

        controller.scan()
        await waitUntil { controller.snapshot.phase == .scanned }
        controller.cleanSelected(candidateIDs: ["candidate"])

        XCTAssertEqual(controller.snapshot.phase, .cleaning)
        await waitUntil { controller.snapshot.phase == .completed }
        XCTAssertEqual(controller.snapshot.executionResult, executionResult)
    }

    func testScannerErrorBecomesUserFacingMessage() async {
        let scanner = FakeXcodeCleanScanner(error: TestXcodeCleanError(message: "boom"))
        let controller = makeController(scanner: scanner)

        controller.scan()
        await waitUntil { controller.snapshot.errorMessage == "boom" }
        XCTAssertEqual(controller.snapshot.phase, .idle)
    }

    func testCancelScanReturnsToIdle() async {
        let scanner = FakeXcodeCleanScanner(
            result: makeScanResult(categories: Set(XcodeCleanCategory.allCases)),
            delayNanoseconds: 1_000_000_000
        )
        let controller = makeController(scanner: scanner)

        controller.scan()
        XCTAssertEqual(controller.snapshot.phase, .scanning)
        controller.cancelCurrentOperation()
        await waitUntil { controller.snapshot.phase == .idle }
    }

    func testXcodeRunningPreventsScan() async {
        let scanner = FakeXcodeCleanScanner(result: makeScanResult(categories: Set(XcodeCleanCategory.allCases)))
        let controller = makeController(scanner: scanner)

        controller.updateXcodeRunningState(true)
        XCTAssertTrue(controller.snapshot.isXcodeRunning)
        XCTAssertFalse(controller.snapshot.canScan)

        controller.scan()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(scanner.scanCalls.count, 0)
        XCTAssertEqual(controller.snapshot.phase, .idle)
    }

    func testXcodeLaunchingDuringScanInterruptsTask() async {
        let scanner = FakeXcodeCleanScanner(
            result: makeScanResult(categories: Set(XcodeCleanCategory.allCases)),
            delayNanoseconds: 1_000_000_000
        )
        let controller = makeController(scanner: scanner)

        controller.scan()
        XCTAssertEqual(controller.snapshot.phase, .scanning)
        controller.updateXcodeRunningState(true)
        await waitUntil { controller.snapshot.phase == .idle }
        XCTAssertTrue(controller.snapshot.isXcodeRunning)
    }

    // MARK: - Helpers

    private func makeController(
        scanner: XcodeCleanScanning = FakeXcodeCleanScanner(),
        executor: XcodeCleanExecuting = FakeXcodeCleanExecutor()
    ) -> XcodeCleanController {
        XcodeCleanController(scanner: scanner, executor: executor)
    }

    private func makeScanResult(categories: Set<XcodeCleanCategory>) -> XcodeCleanScanResult {
        XcodeCleanScanResult(
            categories: categories,
            candidates: [
                XcodeCleanCandidate(
                    id: "candidate",
                    category: .derivedData,
                    path: "/tmp/path",
                    sizeBytes: 10,
                    safety: .allowed
                )
            ],
            scannedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if predicate() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

private struct TestXcodeCleanError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class FakeXcodeCleanScanner: XcodeCleanScanning, @unchecked Sendable {
    var result: XcodeCleanScanResult
    var error: Error?
    var delayNanoseconds: UInt64
    private(set) var scanCalls: [Set<XcodeCleanCategory>] = []

    init(
        result: XcodeCleanScanResult = XcodeCleanScanResult(
            categories: Set(XcodeCleanCategory.allCases),
            candidates: [],
            scannedAt: Date(timeIntervalSince1970: 0)
        ),
        error: Error? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func scan(
        categories: Set<XcodeCleanCategory>,
        progress: XcodeCleanScanProgressHandler
    ) async throws -> XcodeCleanScanResult {
        scanCalls.append(categories)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
        return result
    }
}

private final class FakeXcodeCleanExecutor: XcodeCleanExecuting, @unchecked Sendable {
    struct CleanCall: Equatable {
        let candidates: [XcodeCleanCandidate]
        let selectedCandidateIDs: Set<XcodeCleanCandidate.ID>
    }

    var result: XcodeCleanExecutionResult
    var error: Error?
    var delayNanoseconds: UInt64
    private(set) var cleanCalls: [CleanCall] = []

    init(
        result: XcodeCleanExecutionResult = XcodeCleanExecutionResult(itemResults: []),
        error: Error? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func clean(
        candidates: [XcodeCleanCandidate],
        selectedCandidateIDs: Set<XcodeCleanCandidate.ID>
    ) async throws -> XcodeCleanExecutionResult {
        cleanCalls.append(CleanCall(candidates: candidates, selectedCandidateIDs: selectedCandidateIDs))
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
        return result
    }
}
