import XCTest
@testable import MacTools

@MainActor
final class DisplayBrightnessControllerTests: XCTestCase {
    func testRefreshKeepsOnlyDisplaysWithAvailableBackends() {
        let builtIn = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let projector = makeTestDisplay(id: 2, name: "Projector")
        let provider = StubDisplayProvider(displays: [builtIn, projector])
        let builtInBackend = TestBrightnessBackend(
            kind: .appleNative,
            display: builtIn,
            brightness: 0.64
        )
        let builder = StubBrightnessBackendBuilder { displays, _ in
            XCTAssertEqual(displays.map(\.id), [1, 2])
            return [1: builtInBackend]
        }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        let snapshot = controller.snapshot()

        XCTAssertEqual(snapshot.displays.map(\.id), [1])
        XCTAssertEqual(snapshot.displays.first?.brightness, 0.64)
        XCTAssertNil(snapshot.errorMessage)
    }

    func testChangedPhaseUpdatesSnapshotOptimisticallyBeforeWriteCompletes() async {
        let display = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .appleNative, display: display, brightness: 0.4)
        backend.writeDelay = 0.05
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        controller.setBrightness(0.8, for: display.id, phase: .changed)

        let optimisticSnapshot = controller.snapshot()
        XCTAssertEqual(optimisticSnapshot.displays.first?.brightness, 0.8)
        XCTAssertEqual(optimisticSnapshot.displays.first?.isPendingWrite, true)

        await waitUntil {
            controller.snapshot().displays.first?.isPendingWrite == false
        }

        let committedSnapshot = controller.snapshot()
        XCTAssertEqual(committedSnapshot.displays.first?.brightness, 0.8)
        XCTAssertEqual(backend.recordedWrites, [0.8])
        XCTAssertEqual(backend.readCount, 1)
    }

    func testEndedPhaseReadsBackHardwareBrightnessAndUpdatesSnapshot() async {
        let display = makeTestDisplay(id: 1, name: "LG UltraFine")
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.4)
        backend.setStoredBrightnessAfterWrite(0.66)
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        let initialReadCount = backend.readCount
        controller.setBrightness(0.7, for: display.id, phase: .ended)

        XCTAssertEqual(controller.snapshot().displays.first?.brightness, 0.7)

        await waitUntil {
            controller.snapshot().displays.first?.isPendingWrite == false
                && controller.snapshot().displays.first?.brightness == 0.66
        }

        let snapshot = controller.snapshot()
        XCTAssertEqual(snapshot.displays.first?.brightness, 0.66)
        XCTAssertEqual(snapshot.errorMessage, nil)
        XCTAssertEqual(backend.recordedWrites, [0.7])
        XCTAssertEqual(backend.readCount, initialReadCount + 1)
    }

    func testEndedPhaseFailureRollsBackToLastCommittedBrightness() async {
        let display = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .appleNative, display: display, brightness: 0.6)
        backend.enqueueWriteError(DisplayBrightnessControllerError.failed(message: "DDC 写入失败"))
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        controller.setBrightness(0.25, for: display.id, phase: .ended)

        XCTAssertEqual(controller.snapshot().displays.first?.brightness, 0.25)

        await waitUntil {
            controller.snapshot().errorMessage != nil
        }

        let snapshot = controller.snapshot()
        XCTAssertEqual(snapshot.displays.first?.brightness, 0.6)
        XCTAssertEqual(snapshot.errorMessage, "调节失败：DDC 写入失败")
    }

    func testWriteFailureFallsBackToSoftwareBackendWithoutShowingError() async {
        let display = makeTestDisplay(id: 9, name: "U27N3R")
        let provider = StubDisplayProvider(displays: [display])
        let ddcBackend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.6)
        let gammaBackend = TestBrightnessBackend(kind: .gamma, display: display, brightness: 1)
        ddcBackend.enqueueWriteError(DisplayBrightnessControllerError.failed(message: "U27N3R DDC 写入失败"))
        let builder = StubBrightnessBackendBuilder(
            handler: { _, _ in [display.id: ddcBackend] },
            fallbackHandler: { failedBackend, fallbackDisplay, _ in
                XCTAssertEqual(failedBackend.kind, .ddc)
                XCTAssertEqual(fallbackDisplay.id, display.id)
                return gammaBackend
            }
        )

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01,
            minimumWriteInterval: 0
        )
        controller.refresh()

        controller.setBrightness(0.25, for: display.id, phase: .ended)

        await waitUntil {
            gammaBackend.writeCount == 1
                && controller.snapshot().displays.first?.isPendingWrite == false
        }

        let snapshot = controller.snapshot()
        XCTAssertEqual(ddcBackend.recordedWrites, [0.25])
        XCTAssertEqual(gammaBackend.recordedWrites, [0.25])
        XCTAssertEqual(gammaBackend.readCount, 1)
        XCTAssertEqual(ddcBackend.cleanupCount, 1)
        XCTAssertEqual(snapshot.displays.first?.brightness, 0.25)
        XCTAssertNil(snapshot.errorMessage)
        XCTAssertEqual(builder.fallbackCalls.map(\.0), [.ddc])
    }

    func testInFlightWritesRemainSerialAndFlushLatestValue() async {
        let display = makeTestDisplay(id: 1, name: "Studio Display")
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.5)
        backend.blockFirstWrite = true
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        controller.setBrightness(0.2, for: display.id, phase: .ended)

        await waitUntil {
            backend.writeCount == 1
        }

        controller.setBrightness(0.85, for: display.id, phase: .ended)
        backend.allowFirstWriteToFinish.signal()

        await waitUntil {
            backend.writeCount == 2 && controller.snapshot().displays.first?.isPendingWrite == false
        }

        XCTAssertEqual(backend.recordedWrites, [0.2, 0.85])
        XCTAssertEqual(backend.maxConcurrentWrites, 1)
        XCTAssertEqual(controller.snapshot().displays.first?.brightness, 0.85)
    }

    func testRapidChangedWritesCoalesceAndFlushEndedValue() async {
        let display = makeTestDisplay(id: 1, name: "LG UltraFine")
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.5)
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.05,
            minimumWriteInterval: 0
        )
        controller.refresh()

        controller.setBrightness(0.2, for: display.id, phase: .changed)
        controller.setBrightness(0.4, for: display.id, phase: .changed)
        controller.setBrightness(0.6, for: display.id, phase: .changed)
        controller.setBrightness(0.8, for: display.id, phase: .ended)

        await waitUntil {
            controller.snapshot().displays.first?.isPendingWrite == false
        }

        XCTAssertEqual(backend.recordedWrites.last, 0.8)
        XCTAssertLessThanOrEqual(backend.recordedWrites.count, 2)
        XCTAssertEqual(controller.snapshot().displays.first?.brightness, 0.8)
    }

    func testRefreshCleansUpDisconnectedDisplays() {
        let display = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .appleNative, display: display, brightness: 0.6)
        let builder = StubBrightnessBackendBuilder { displays, previous in
            guard let activeDisplay = displays.first else {
                return [:]
            }

            if let existing = previous[activeDisplay.id] {
                return [activeDisplay.id: existing]
            }

            return [activeDisplay.id: backend]
        }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        provider.displays = []
        controller.refresh()

        XCTAssertEqual(backend.cleanupCount, 1)
        XCTAssertTrue(controller.snapshot().displays.isEmpty)
    }

    func testDDCBackendMapsPercentageToRawValueUsingDisplayMaximum() throws {
        let display = makeTestDisplay(id: 8, name: "LG UltraFine")
        let transport = MockDDCTransport(
            initialBrightness: DDCBrightnessValue(current: 40, maximum: 80)
        )

        let backend = try XCTUnwrap(
            DDCBrightnessBackend(display: display, transport: transport)
        )

        XCTAssertEqual(try backend.readBrightness(), 0.5, accuracy: 0.0001)

        try backend.writeBrightness(0.25)

        XCTAssertEqual(transport.recordedWrites, [20])
    }

    func testDDCBackendStillWritesWhenInitialReadFails() throws {
        let display = makeTestDisplay(id: 8, name: "LG UltraFine")
        let transport = MockDDCTransport(
            initialBrightness: DDCBrightnessValue(current: 40, maximum: 80)
        )
        transport.enqueueReadError(DisplayBrightnessControllerError.i2cUnavailable(displayName: display.name))

        let backend = try XCTUnwrap(
            DDCBrightnessBackend(display: display, transport: transport)
        )

        try backend.writeBrightness(0.25)

        XCTAssertEqual(transport.recordedWrites, [25])
    }

    func testBackendBuilderPrefersDDCForNonAppleExternalDisplay() {
        let display = makeTestDisplay(id: 11, name: "U27N3R", vendorNumber: 1507)
        var attempts: [String] = []
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { _ in [:] },
            appleFactory: { currentDisplay in
                attempts.append("apple:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .appleNative, display: currentDisplay, brightness: 0.7)
            },
            ddcFactory: { currentDisplay, _ in
                attempts.append("ddc:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .ddc, display: currentDisplay, brightness: 0.7)
            },
            gammaFactory: { currentDisplay in
                attempts.append("gamma:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .gamma, display: currentDisplay, brightness: 0.7)
            },
            shadeFactory: { currentDisplay in
                attempts.append("shade:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .shade, display: currentDisplay, brightness: 0.7)
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertEqual(attempts, ["ddc:11"])
        XCTAssertEqual(backends[display.id]?.kind, .ddc)
    }

    func testBackendBuilderFallsBackToGammaForNonAppleExternalDisplayWhenDDCUnavailable() {
        let display = makeTestDisplay(id: 16, name: "Projector", vendorNumber: 1507)
        var attempts: [String] = []
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { _ in [:] },
            appleFactory: { currentDisplay in
                attempts.append("apple:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .appleNative, display: currentDisplay, brightness: 0.7)
            },
            ddcFactory: { currentDisplay, _ in
                attempts.append("ddc:\(currentDisplay.id)")
                return nil
            },
            gammaFactory: { currentDisplay in
                attempts.append("gamma:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .gamma, display: currentDisplay, brightness: 0.7)
            },
            shadeFactory: { currentDisplay in
                attempts.append("shade:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .shade, display: currentDisplay, brightness: 0.7)
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertEqual(attempts, ["ddc:16", "gamma:16"])
        XCTAssertEqual(backends[display.id]?.kind, .gamma)
    }

    func testBackendBuilderPrefersAppleNativeForBuiltInDisplay() {
        let display = makeTestDisplay(id: 14, name: "Built-in Display", isBuiltin: true)
        var attempts: [String] = []
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { _ in [:] },
            appleFactory: { currentDisplay in
                attempts.append("apple:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .appleNative, display: currentDisplay, brightness: 0.7)
            },
            ddcFactory: { currentDisplay, _ in
                attempts.append("ddc:\(currentDisplay.id)")
                XCTFail("Built-in displays should not be probed through DDC")
                return nil
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertEqual(attempts, ["apple:14"])
        XCTAssertEqual(backends[display.id]?.kind, .appleNative)
    }

    func testBackendBuilderPrefersAppleNativeForAppleExternalDisplay() {
        let display = makeTestDisplay(id: 15, name: "Studio Display", vendorNumber: 610)
        var attempts: [String] = []
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { _ in [:] },
            appleFactory: { currentDisplay in
                attempts.append("apple:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .appleNative, display: currentDisplay, brightness: 0.7)
            },
            ddcFactory: { currentDisplay, _ in
                attempts.append("ddc:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .ddc, display: currentDisplay, brightness: 0.7)
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertEqual(attempts, ["apple:15"])
        XCTAssertEqual(backends[display.id]?.kind, .appleNative)
    }

    func testBackendBuilderFallsBackToDDCForAppleExternalDisplayWhenAppleNativeUnavailable() {
        let display = makeTestDisplay(id: 17, name: "LG UltraFine")
        var attempts: [String] = []
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { _ in [:] },
            appleFactory: { currentDisplay in
                attempts.append("apple:\(currentDisplay.id)")
                return nil
            },
            ddcFactory: { currentDisplay, _ in
                attempts.append("ddc:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .ddc, display: currentDisplay, brightness: 0.7)
            },
            gammaFactory: { currentDisplay in
                attempts.append("gamma:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .gamma, display: currentDisplay, brightness: 0.7)
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertEqual(attempts, ["apple:17", "ddc:17"])
        XCTAssertEqual(backends[display.id]?.kind, .ddc)
    }

    func testBackendBuilderSkipsArm64ServiceScanWhenExistingDDCBackendCanBeReused() {
        let display = makeTestDisplay(id: 12, name: "Reusable Display")
        let previousBackend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.7)
        var arm64ResolveCount = 0
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { _ in
                arm64ResolveCount += 1
                return [:]
            },
            appleFactory: { _ in nil },
            ddcFactory: { _, _ in
                XCTFail("Expected reusable DDC backend")
                return nil
            }
        )

        let backends = builder.backends(for: [display], previous: [display.id: previousBackend])

        XCTAssertTrue(backends[display.id] === previousBackend)
        XCTAssertEqual(arm64ResolveCount, 0)
    }

    func testBackendBuilderResolvesArm64ServicesOnlyWhenCreatingNewDDCBackend() {
        let display = makeTestDisplay(id: 13, name: "New DDC Display")
        let newBackend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.7)
        var arm64ResolveCount = 0
        var receivedService: CFTypeRef?
        let service = "matched-service" as CFString
        let builder = SystemDisplayBrightnessBackendBuilder(
            resolveArm64Services: { displays in
                arm64ResolveCount += 1
                XCTAssertEqual(displays.map(\.id), [display.id])
                return [display.id: service]
            },
            appleFactory: { _ in nil },
            ddcFactory: { _, matchedService in
                receivedService = matchedService
                return newBackend
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertTrue(backends[display.id] === newBackend)
        XCTAssertEqual(arm64ResolveCount, 1)
        XCTAssertTrue(receivedService === service)
    }

    func testArm64ServiceMatcherAssignsRemainingExternalServicesWhenCountsMatch() {
        let firstDisplay = makeTestDisplay(id: 21, name: "U27N3R")
        let secondDisplay = makeTestDisplay(id: 22, name: "U27N3R")
        let firstService = "first-service" as CFString
        let secondService = "second-service" as CFString

        let matches = Arm64DDCServiceMatcher.resolveServices(
            for: [secondDisplay, firstDisplay],
            candidates: [
                .init(service: secondService, location: "External", serviceLocation: 2),
                .init(service: firstService, location: "External", serviceLocation: 1)
            ]
        )

        XCTAssertTrue(matches[firstDisplay.id] === firstService)
        XCTAssertTrue(matches[secondDisplay.id] === secondService)
    }

    func testArm64ServiceMatcherDoesNotAssignRemainingServicesWhenCountsDiffer() {
        let firstDisplay = makeTestDisplay(id: 21, name: "U27N3R")
        let secondDisplay = makeTestDisplay(id: 22, name: "U27N3R")
        let onlyService = "only-service" as CFString

        let matches = Arm64DDCServiceMatcher.resolveServices(
            for: [firstDisplay, secondDisplay],
            candidates: [
                .init(service: onlyService, location: "External", serviceLocation: 1)
            ]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testArm64ServiceMatcherDoesNotAssignNonExternalServicesByFallback() {
        let display = makeTestDisplay(id: 21, name: "U27N3R")
        let embeddedService = "embedded-service" as CFString

        let matches = Arm64DDCServiceMatcher.resolveServices(
            for: [display],
            candidates: [
                .init(service: embeddedService, location: "Embedded", serviceLocation: 1)
            ]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testArm64ServiceMatcherUsesStrongSerialMatchesForDistinctDisplays() {
        let firstDisplay = makeTestDisplay(
            id: 31,
            name: "DELL U2720QM",
            serialNumber: 1001
        )
        let secondDisplay = makeTestDisplay(
            id: 32,
            name: "DELL U3225QE",
            isMain: true,
            serialNumber: 2002
        )
        let firstService = "first-service" as CFString
        let secondService = "second-service" as CFString

        let matches = Arm64DDCServiceMatcher.resolveServices(
            for: [firstDisplay, secondDisplay],
            candidates: [
                .init(service: secondService, serialNumber: 2002, location: "External", serviceLocation: 1),
                .init(service: firstService, serialNumber: 1001, location: "External", serviceLocation: 2)
            ]
        )

        XCTAssertTrue(matches[firstDisplay.id] === firstService)
        XCTAssertTrue(matches[secondDisplay.id] === secondService)
    }

    func testArm64ServiceMatcherUsesProductAndSerialForIdenticalNames() {
        let firstDisplay = makeTestDisplay(
            id: 51,
            name: "U27N3R",
            vendorNumber: 1507,
            modelNumber: 9987,
            serialNumber: 998
        )
        let secondDisplay = makeTestDisplay(
            id: 52,
            name: "U27N3R",
            vendorNumber: 1507,
            modelNumber: 9987,
            serialNumber: 960178
        )
        let firstService = "first-service" as CFString
        let secondService = "second-service" as CFString

        let matches = Arm64DDCServiceMatcher.resolveServices(
            for: [firstDisplay, secondDisplay],
            candidates: [
                .init(
                    service: secondService,
                    name: "U27N3R",
                    vendorNumber: 1507,
                    serialNumber: 960178,
                    productID: 9987,
                    location: "External",
                    edidUUID: "05E30327-0000-0000-0F23-0104B53C2278",
                    serviceLocation: 1
                ),
                .init(
                    service: firstService,
                    name: "U27N3R",
                    vendorNumber: 1507,
                    serialNumber: 998,
                    productID: 9987,
                    location: "External",
                    edidUUID: "05E30327-0000-0000-1022-0104B53C2278",
                    serviceLocation: 2
                )
            ]
        )

        XCTAssertTrue(matches[firstDisplay.id] === firstService)
        XCTAssertTrue(matches[secondDisplay.id] === secondService)
    }

    func testArm64ServiceMatcherCanUseVendorAndNameWhenSerialIsMissing() {
        let display = makeTestDisplay(
            id: 41,
            name: "DELL U3225QE",
            vendorNumber: 4268
        )
        let matchedService = "matched-service" as CFString
        let otherService = "other-service" as CFString

        let matches = Arm64DDCServiceMatcher.resolveServices(
            for: [display],
            candidates: [
                .init(service: otherService, name: "DELL U2720QM", vendorNumber: 4268, location: "External"),
                .init(service: matchedService, name: "DELL U3225QE", vendorNumber: 4268, location: "External")
            ]
        )

        XCTAssertTrue(matches[display.id] === matchedService)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTFail("Condition was not satisfied before timeout", file: file, line: line)
    }
}

private final class MockDDCTransport: DDCBrightnessTransport {
    private var brightness: DDCBrightnessValue
    private var readErrors: [Error] = []
    private(set) var recordedWrites: [UInt16] = []

    init(initialBrightness: DDCBrightnessValue) {
        self.brightness = initialBrightness
    }

    func enqueueReadError(_ error: Error) {
        readErrors.append(error)
    }

    func readBrightness() throws -> DDCBrightnessValue {
        if !readErrors.isEmpty {
            throw readErrors.removeFirst()
        }

        return brightness
    }

    func writeBrightness(_ value: UInt16) throws {
        recordedWrites.append(value)
    }
}
