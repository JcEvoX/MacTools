import AppKit
import CoreGraphics
import Foundation
import MacToolsPluginKit
@testable import MacTools
@testable import DisplayBrightnessPlugin

func makeTestDisplay(
    id: CGDirectDisplayID,
    name: String,
    isBuiltin: Bool = false,
    isMain: Bool = false,
    vendorNumber: UInt32? = nil,
    modelNumber: UInt32? = nil,
    serialNumber: UInt32? = nil
) -> DisplayInfo {
    DisplayInfo(
        id: id,
        name: name,
        isBuiltin: isBuiltin,
        isMain: isMain,
        vendorNumber: vendorNumber,
        modelNumber: modelNumber,
        serialNumber: serialNumber
    )
}

func makeBrightnessDisplay(
    id: CGDirectDisplayID,
    name: String,
    brightness: Double,
    isPendingWrite: Bool = false,
    vendorNumber: UInt32? = nil,
    modelNumber: UInt32? = nil,
    serialNumber: UInt32? = nil
) -> DisplayBrightnessDisplay {
    DisplayBrightnessDisplay(
        display: makeTestDisplay(
            id: id,
            name: name,
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            serialNumber: serialNumber
        ),
        brightness: brightness,
        isPendingWrite: isPendingWrite
    )
}

@MainActor
final class MockDisplayBrightnessController: DisplayBrightnessControlling {
    struct SetBrightnessCall: Equatable {
        let value: Double
        let displayID: CGDirectDisplayID
        let phase: PluginPanelAction.SliderPhase
    }

    var onStateChange: (() -> Void)?
    var snapshotValue = DisplayBrightnessSnapshot(
        displays: [],
        errorMessage: nil
    )
    var refreshCount = 0
    var setBrightnessCalls: [SetBrightnessCall] = []

    func refresh() {
        refreshCount += 1
    }

    func snapshot() -> DisplayBrightnessSnapshot {
        snapshotValue
    }

    func setBrightness(
        _ value: Double,
        for displayID: CGDirectDisplayID,
        phase: PluginPanelAction.SliderPhase
    ) {
        setBrightnessCalls.append(
            SetBrightnessCall(value: value, displayID: displayID, phase: phase)
        )
        snapshotValue = DisplayBrightnessSnapshot(
            displays: snapshotValue.displays.map { display in
                guard display.id == displayID else {
                    return display
                }

                return DisplayBrightnessDisplay(
                    display: display.display,
                    brightness: min(max(value, 0), 1),
                    isPendingWrite: phase != .ended
                )
            },
            errorMessage: snapshotValue.errorMessage
        )
    }
}

final class StubDisplayProvider: DisplayProviding {
    var displays: [DisplayInfo]

    init(displays: [DisplayInfo] = []) {
        self.displays = displays
    }

    func listConnectedDisplays() -> [DisplayInfo] {
        displays
    }

    func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        nil
    }
}

final class StubBrightnessBackendBuilder: DisplayBrightnessBackendBuilding {
    typealias BuildHandler = (
        [DisplayInfo],
        [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> [CGDirectDisplayID: any DisplayBrightnessBackend]
    typealias FallbackHandler = (
        any DisplayBrightnessBackend,
        DisplayInfo,
        [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> (any DisplayBrightnessBackend)?

    var handler: BuildHandler
    var fallbackHandler: FallbackHandler
    private(set) var calls: [[DisplayInfo]] = []
    private(set) var fallbackCalls: [(DisplayBrightnessBackendKind, DisplayInfo)] = []

    init(
        handler: @escaping BuildHandler = { _, _ in [:] },
        fallbackHandler: @escaping FallbackHandler = { _, _, _ in nil }
    ) {
        self.handler = handler
        self.fallbackHandler = fallbackHandler
    }

    func backends(
        for displays: [DisplayInfo],
        previous: [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> [CGDirectDisplayID: any DisplayBrightnessBackend] {
        calls.append(displays)
        return handler(displays, previous)
    }

    func fallbackBackend(
        after failedBackend: any DisplayBrightnessBackend,
        for display: DisplayInfo,
        previous: [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> (any DisplayBrightnessBackend)? {
        fallbackCalls.append((failedBackend.kind, display))
        return fallbackHandler(failedBackend, display, previous)
    }
}

final class TestBrightnessBackend: DisplayBrightnessBackend, @unchecked Sendable {
    let kind: DisplayBrightnessBackendKind
    var display: DisplayInfo

    var writeDelay: TimeInterval = 0
    var blockFirstWrite = false
    let allowFirstWriteToFinish = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var storedBrightness: Double
    private var pendingWriteErrors: [Error] = []
    private var recordedWritesStorage: [Double] = []
    private var cleanupCountStorage = 0
    private var writeCountStorage = 0
    private var readCountStorage = 0
    private var activeWrites = 0
    private var maxConcurrentWritesStorage = 0
    private var storedBrightnessAfterWrite: Double?

    init(
        kind: DisplayBrightnessBackendKind,
        display: DisplayInfo,
        brightness: Double = 1
    ) {
        self.kind = kind
        self.display = display
        self.storedBrightness = brightness
    }

    var recordedWrites: [Double] {
        lock.withLock { recordedWritesStorage }
    }

    var cleanupCount: Int {
        lock.withLock { cleanupCountStorage }
    }

    var writeCount: Int {
        lock.withLock { writeCountStorage }
    }

    var readCount: Int {
        lock.withLock { readCountStorage }
    }

    var maxConcurrentWrites: Int {
        lock.withLock { maxConcurrentWritesStorage }
    }

    func enqueueWriteError(_ error: Error) {
        lock.withLock {
            pendingWriteErrors.append(error)
        }
    }

    func setStoredBrightnessAfterWrite(_ value: Double?) {
        lock.withLock {
            storedBrightnessAfterWrite = value
        }
    }

    func readBrightness() throws -> Double {
        lock.withLock {
            readCountStorage += 1
            return storedBrightness
        }
    }

    func writeBrightness(_ value: Double) throws {
        let shouldBlock = lock.withLock { () -> Bool in
            writeCountStorage += 1
            recordedWritesStorage.append(value)
            activeWrites += 1
            maxConcurrentWritesStorage = max(maxConcurrentWritesStorage, activeWrites)
            return blockFirstWrite && writeCountStorage == 1
        }

        defer {
            lock.withLock {
                activeWrites -= 1
            }
        }

        if shouldBlock {
            allowFirstWriteToFinish.wait()
        }

        if writeDelay > 0 {
            Thread.sleep(forTimeInterval: writeDelay)
        }

        if let error = lock.withLock({
            pendingWriteErrors.isEmpty ? nil : pendingWriteErrors.removeFirst()
        }) {
            throw error
        }

        lock.withLock {
            storedBrightness = storedBrightnessAfterWrite ?? value
        }
    }

    func cleanup() {
        lock.withLock {
            cleanupCountStorage += 1
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
