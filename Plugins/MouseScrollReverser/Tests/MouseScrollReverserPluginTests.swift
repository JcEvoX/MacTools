import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import MouseScrollReverserPlugin

@MainActor
private final class MouseScrollReverserMemoryStorage: PluginStorage {
    var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func stringArray(forKey key: String) -> [String]? {
        values[key] as? [String]
    }

    func integer(forKey key: String) -> Int {
        values[key] as? Int ?? 0
    }

    func bool(forKey key: String) -> Bool {
        values[key] as? Bool ?? false
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String) {
        guard values[key] == nil, let value = values[legacyKey] else {
            return
        }

        values[key] = value
        values.removeValue(forKey: legacyKey)
    }
}

@MainActor
private final class MockMouseScrollReverserSession: MouseScrollReverserSessionManaging {
    private(set) var state: MouseScrollReverserSessionState = .inactive
    private(set) var activatedConfigurations: [MouseScrollReverserConfiguration] = []
    private(set) var updatedConfigurations: [MouseScrollReverserConfiguration] = []
    private(set) var deactivateCallCount = 0
    var activationSucceeds = true

    @discardableResult
    func activate(configuration: MouseScrollReverserConfiguration) -> Bool {
        activatedConfigurations.append(configuration)
        state.scrollTapInstalled = activationSucceeds
        state.gestureTapInstalled = activationSucceeds
        return activationSucceeds
    }

    func update(configuration: MouseScrollReverserConfiguration) {
        updatedConfigurations.append(configuration)
    }

    func deactivate() {
        deactivateCallCount += 1
        state = .inactive
    }
}

@MainActor
final class MouseScrollReverserPluginTests: XCTestCase {
    func testMetadataIdentifiesPlugin() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.metadata.id, "mouse-scroll-reverser")
        XCTAssertEqual(plugin.metadata.title, "鼠标滚动翻转")
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
    }

    func testDefaultConfigurationTargetsMouseVerticalOnlyAndStartsDisabled() {
        let store = MouseScrollReverserStore(storage: MouseScrollReverserMemoryStorage())

        XCTAssertFalse(store.configuration.isEnabled)
        XCTAssertTrue(store.configuration.reverseVertical)
        XCTAssertFalse(store.configuration.reverseHorizontal)
        XCTAssertTrue(store.configuration.reverseMouse)
        XCTAssertFalse(store.configuration.reverseTrackpad)
    }

    func testPanelSwitchEnablesSessionWhenAccessibilityGranted() {
        let session = MockMouseScrollReverserSession()
        let plugin = makePlugin(session: session, accessibilityTrusted: true)

        plugin.handleAction(.setSwitch(true))

        XCTAssertTrue(plugin.store.configuration.isEnabled)
        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertEqual(session.activatedConfigurations.count, 1)
        XCTAssertTrue(session.activatedConfigurations[0].reverseVertical)
        XCTAssertTrue(session.activatedConfigurations[0].reverseMouse)
    }

    func testPanelSwitchRequestsPermissionAndDoesNotPersistWhenAccessibilityDenied() {
        let session = MockMouseScrollReverserSession()
        var didRequestPermission = false
        let plugin = makePlugin(
            session: session,
            accessibilityTrusted: false,
            requestAccessibilityTrust: false
        )
        plugin.requestPermissionGuidance = { id in
            didRequestPermission = id == "accessibility"
        }

        plugin.handleAction(.setSwitch(true))

        XCTAssertFalse(plugin.store.configuration.isEnabled)
        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertTrue(didRequestPermission)
        XCTAssertTrue(session.activatedConfigurations.isEmpty)
        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)
    }

    func testDisablingStopsSessionAndPersistsOff() {
        let session = MockMouseScrollReverserSession()
        let plugin = makePlugin(session: session, accessibilityTrusted: true)

        plugin.handleAction(.setSwitch(true))
        plugin.handleAction(.setSwitch(false))

        XCTAssertFalse(plugin.store.configuration.isEnabled)
        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertGreaterThanOrEqual(session.deactivateCallCount, 1)
    }

    func testConfigurationChangeUpdatesRunningSession() {
        let session = MockMouseScrollReverserSession()
        let plugin = makePlugin(session: session, accessibilityTrusted: true)

        plugin.handleAction(.setSwitch(true))
        plugin.store.setReverseHorizontal(true)
        plugin.refresh()
        plugin.handleAction(.setSwitch(true))

        XCTAssertFalse(session.updatedConfigurations.isEmpty)
        XCTAssertTrue(session.updatedConfigurations.last?.reverseHorizontal == true)
    }

    func testTurningOffAllAxesStopsSession() {
        let session = MockMouseScrollReverserSession()
        let plugin = makePlugin(session: session, accessibilityTrusted: true)

        plugin.handleAction(.setSwitch(true))
        plugin.store.setReverseVertical(false)
        plugin.store.setReverseHorizontal(false)
        plugin.refresh()

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertGreaterThanOrEqual(session.deactivateCallCount, 1)
    }

    func testPermissionRequirementsIncludeAccessibilityAndInputMonitoring() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.permissionRequirements.map(\.id), ["accessibility", "input-monitoring"])
    }

    func testPluginHostIncludesMouseScrollReverserPlugin() {
        let host = makePluginHostForTests(plugins: [makePlugin(accessibilityTrusted: true)])

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "mouse-scroll-reverser" })
    }

    func testProcessorReversesDiscreteMouseVerticalDeltas() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: true,
                reverseTrackpad: false
            )
        )

        let result = processor.process(
            snapshot: .discreteWheel,
            deltas: MouseScrollDeltas(
                deltaAxis1: 3,
                deltaAxis2: 4,
                pointDeltaAxis1: 24,
                pointDeltaAxis2: 32,
                fixedPointDeltaAxis1: 3,
                fixedPointDeltaAxis2: 4
            )
        )

        XCTAssertEqual(result.source, .mouse)
        XCTAssertTrue(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, -3)
        XCTAssertEqual(result.deltas.pointDeltaAxis1, -24)
        XCTAssertEqual(result.deltas.fixedPointDeltaAxis1, -3)
        XCTAssertEqual(result.deltas.deltaAxis2, 4)
    }

    func testProcessorReversesHorizontalOnlyWhenConfigured() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: true,
                reverseVertical: false,
                reverseMouse: true,
                reverseTrackpad: false
            )
        )

        let result = processor.process(
            snapshot: .discreteWheel,
            deltas: MouseScrollDeltas(
                deltaAxis1: 3,
                deltaAxis2: 4,
                pointDeltaAxis1: 24,
                pointDeltaAxis2: 32,
                fixedPointDeltaAxis1: 3,
                fixedPointDeltaAxis2: 4
            )
        )

        XCTAssertEqual(result.deltas.deltaAxis1, 3)
        XCTAssertEqual(result.deltas.deltaAxis2, -4)
        XCTAssertEqual(result.deltas.pointDeltaAxis2, -32)
        XCTAssertEqual(result.deltas.fixedPointDeltaAxis2, -4)
    }

    func testProcessorClassifiesRecentGestureScrollAsTrackpad() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: false,
                reverseTrackpad: true
            )
        )

        processor.setGestureMonitoringAvailable(true)
        processor.recordGestureTouchingCount(2, timestamp: 1_000)
        let result = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 1,
                momentumPhase: 0
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 0,
                pointDeltaAxis1: 10,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 0
            ),
            timestamp: 1_000 + 10_000_000
        )

        XCTAssertEqual(result.source, .trackpad)
        XCTAssertTrue(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, -2)
    }

    func testProcessorTreatsPhaseLessContinuousScrollAsMouse() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: true,
                reverseTrackpad: false
            )
        )

        processor.setGestureMonitoringAvailable(false)
        let result = processor.process(
            snapshot: .phaseLessContinuousWheel,
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 0,
                pointDeltaAxis1: 10,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 0
            )
        )

        XCTAssertEqual(result.source, .mouse)
        XCTAssertTrue(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, -2)
    }

    func testProcessorConservativelyTreatsContinuousPhaseWithoutGestureAsTrackpad() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: true,
                reverseTrackpad: false
            )
        )

        let result = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 1,
                momentumPhase: 0
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 0,
                pointDeltaAxis1: 10,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 0
            )
        )

        XCTAssertEqual(result.source, .trackpad)
        XCTAssertFalse(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, 2)
    }

    func testProcessorClassifiesStaleNormalContinuousScrollAsMouseAfterGestureMonitoringStarts() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: true,
                reverseTrackpad: false
            )
        )

        processor.setGestureMonitoringAvailable(true)
        let result = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 1,
                momentumPhase: 0
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 0,
                pointDeltaAxis1: 10,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 0
            ),
            timestamp: 500_000_000
        )

        XCTAssertEqual(result.source, .mouse)
        XCTAssertTrue(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, -2)
    }

    func testProcessorDoesNotReverseWhenGlobalSwitchIsOff() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: false,
                reverseHorizontal: true,
                reverseVertical: true,
                reverseMouse: true,
                reverseTrackpad: true
            )
        )

        let result = processor.process(
            snapshot: .discreteWheel,
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 3,
                pointDeltaAxis1: 16,
                pointDeltaAxis2: 24,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 3
            )
        )

        XCTAssertEqual(result.source, .mouse)
        XCTAssertFalse(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, 2)
        XCTAssertEqual(result.deltas.deltaAxis2, 3)
    }

    func testProcessorKeepsTrackpadSourceForMomentumAfterTrackpadGesture() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: false,
                reverseTrackpad: true
            )
        )

        processor.setGestureMonitoringAvailable(true)
        processor.recordGestureTouchingCount(2, timestamp: 1_000)
        _ = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 1,
                momentumPhase: 0
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 0,
                pointDeltaAxis1: 10,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 0
            ),
            timestamp: 10_000_000
        )

        let result = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 0,
                momentumPhase: 1
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 1,
                deltaAxis2: 0,
                pointDeltaAxis1: 8,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 1,
                fixedPointDeltaAxis2: 0
            ),
            timestamp: 400_000_000
        )

        XCTAssertEqual(result.source, .trackpad)
        XCTAssertTrue(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, -1)
    }

    func testProcessorResetsClassificationStateWhenGestureMonitoringStops() {
        let processor = MouseScrollEventProcessor(
            configuration: MouseScrollReverserConfiguration(
                isEnabled: true,
                reverseHorizontal: false,
                reverseVertical: true,
                reverseMouse: true,
                reverseTrackpad: false
            )
        )

        processor.setGestureMonitoringAvailable(true)
        processor.recordGestureTouchingCount(2, timestamp: 1_000)
        _ = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 1,
                momentumPhase: 0
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 2,
                deltaAxis2: 0,
                pointDeltaAxis1: 10,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 2,
                fixedPointDeltaAxis2: 0
            ),
            timestamp: 10_000_000
        )

        processor.setGestureMonitoringAvailable(false)
        let result = processor.process(
            snapshot: MouseScrollEventSnapshot(
                isContinuous: true,
                scrollPhase: 0,
                momentumPhase: 1
            ),
            deltas: MouseScrollDeltas(
                deltaAxis1: 1,
                deltaAxis2: 0,
                pointDeltaAxis1: 8,
                pointDeltaAxis2: 0,
                fixedPointDeltaAxis1: 1,
                fixedPointDeltaAxis2: 0
            ),
            timestamp: 400_000_000
        )

        XCTAssertEqual(result.source, .trackpad)
        XCTAssertFalse(result.shouldReverse)
        XCTAssertEqual(result.deltas.deltaAxis1, 1)
    }

    private func makePlugin(
        session: MockMouseScrollReverserSession? = nil,
        accessibilityTrusted: Bool = true,
        requestAccessibilityTrust: Bool = true,
        inputMonitoringStatus: MouseScrollReverserInputMonitoringAuthorizationStatus = .granted
    ) -> MouseScrollReverserPlugin {
        let storage = MouseScrollReverserMemoryStorage()
        return MouseScrollReverserPlugin(
            context: PluginRuntimeContext(pluginID: "mouse-scroll-reverser", storage: storage),
            session: session ?? MockMouseScrollReverserSession(),
            accessibilityTrusted: { accessibilityTrusted },
            requestAccessibilityTrust: { _ in requestAccessibilityTrust },
            inputMonitoringAuthorizationStatus: { inputMonitoringStatus },
            openURL: { _ in }
        )
    }
}
