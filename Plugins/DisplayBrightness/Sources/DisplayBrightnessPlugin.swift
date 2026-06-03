import CoreGraphics
import Foundation
import SwiftUI
import MacToolsPluginKit

public final class DisplayBrightnessPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        DisplayBrightnessPluginProvider()
    }
}

@MainActor
private struct DisplayBrightnessPluginProvider: PluginProvider {
    func makePlugins() -> [any MacToolsPlugin] {
        [DisplayBrightnessPlugin()]
    }
}

enum DisplayBrightnessShortcutDirection: Equatable {
    case decrease
    case increase

    var actionSuffix: String {
        switch self {
        case .decrease:
            return ".decrease"
        case .increase:
            return ".increase"
        }
    }

    var title: String {
        switch self {
        case .decrease:
            return "降低"
        case .increase:
            return "增加"
        }
    }

    var systemImage: String {
        switch self {
        case .decrease:
            return "sun.min.fill"
        case .increase:
            return "sun.max.fill"
        }
    }

    var sharedBindingGroupID: String {
        switch self {
        case .decrease:
            return "display-brightness.decrease"
        case .increase:
            return "display-brightness.increase"
        }
    }

    var multiplier: Double {
        switch self {
        case .decrease:
            return -1
        case .increase:
            return 1
        }
    }
}

struct DisplayBrightnessShortcutAction: Equatable {
    let id: String
    let displayKey: String
    let direction: DisplayBrightnessShortcutDirection
}

struct DisplayBrightnessShortcutAcceleration {
    private var lastPressDateByActionID: [String: Date] = [:]
    private var quickPressCountByActionID: [String: Int] = [:]

    mutating func stepForPress(actionID: String, now: Date, fastTapWindow: TimeInterval = 0.48) -> Int {
        let quickPressCount: Int
        if let lastPressDate = lastPressDateByActionID[actionID],
           now.timeIntervalSince(lastPressDate) <= fastTapWindow {
            quickPressCount = min((quickPressCountByActionID[actionID] ?? 0) + 1, 9)
        } else {
            quickPressCount = 0
        }

        quickPressCountByActionID[actionID] = quickPressCount
        lastPressDateByActionID[actionID] = now
        return min(10, 1 + quickPressCount)
    }

    static func stepForHold(elapsed: TimeInterval, baseline: Int) -> Int {
        let elapsedStep: Int
        switch elapsed {
        case ..<0.45:
            elapsedStep = 1
        case ..<0.9:
            elapsedStep = 2
        case ..<1.35:
            elapsedStep = 3
        case ..<1.8:
            elapsedStep = 4
        case ..<2.4:
            elapsedStep = 6
        case ..<3.2:
            elapsedStep = 8
        default:
            elapsedStep = 10
        }

        return min(10, max(baseline, elapsedStep))
    }
}

private struct DisplayBrightnessShortcutSession {
    let id: UUID
    let action: DisplayBrightnessShortcutAction
    let task: Task<Void, Never>
}

@MainActor
final class DisplayBrightnessPlugin: MacToolsPlugin, PluginPrimaryPanel, PluginShortcutEventHandling, DisplayTopologyRefreshing {
    private enum Constants {
        static let displayControlPrefix = "display."
        static let brightnessControlSuffix = ".brightness"
        static let shortcutActionPrefix = "display-brightness.display."
        static let shortcutDisplayGroupPrefix = "display-brightness.display-group."
    }

    let metadata = PluginMetadata(
        id: "display-brightness",
        title: "显示器亮度",
        iconName: "sun.max",
        iconTint: Color(nsColor: .systemYellow),
        order: 20,
        defaultDescription: "快速调节每个显示器的亮度"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let controller: DisplayBrightnessControlling
    private var isExpanded = false
    private var shortcutAcceleration = DisplayBrightnessShortcutAcceleration()
    private var shortcutSessions: [String: DisplayBrightnessShortcutSession] = [:]

    init(controller: DisplayBrightnessControlling = DisplayBrightnessController()) {
        self.controller = controller
        self.controller.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
    }

    var primaryPanelState: PluginPanelState {
        let snapshot = controller.snapshot()

        guard !snapshot.displays.isEmpty else {
            isExpanded = false
            return PluginPanelState(
                subtitle: "未检测到可调节亮度的显示器",
                isOn: false,
                isExpanded: false,
                isEnabled: false,
                isVisible: true,
                detail: nil,
                errorMessage: snapshot.errorMessage
            )
        }

        return PluginPanelState(
            subtitle: subtitle(for: snapshot.displays),
            isOn: false,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? buildDetail(for: snapshot.displays) : nil,
            errorMessage: snapshot.errorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] {
        controller.snapshot().displays.flatMap { display in
            [
                shortcutDefinition(for: display.display, direction: .decrease),
                shortcutDefinition(for: display.display, direction: .increase)
            ]
        }
    }

    func refresh() {
        controller.refresh()
    }

    func refreshDisplayTopology() {
        controller.refresh()
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .setSlider(controlID, value, phase):
            guard let displayID = Self.parseDisplayID(from: controlID) else {
                DisplayBrightnessLog.plugin.error(
                    "invalid slider control id \(controlID, privacy: .public)"
                )
                return
            }

            controller.setBrightness(value, for: displayID, phase: phase)
            onStateChange?()
        case .setSwitch,
             .setSelection,
             .setNavigationSelection,
             .clearNavigationSelection,
             .setDate,
             .invokeAction:
            return
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {
        handleShortcutEvent(id: id, phase: .pressed)
    }

    func handleShortcutEvent(id: String, phase: PluginShortcutEventPhase) {
        switch phase {
        case .pressed:
            startShortcutAction(id: id)
        case .released:
            stopShortcutAction(id: id)
        }
    }

    func deactivate(reason: PluginDeactivationReason) {
        stopAllShortcutActions()
    }

    static func parseDisplayID(from controlID: String) -> CGDirectDisplayID? {
        guard
            controlID.hasPrefix(Constants.displayControlPrefix),
            controlID.hasSuffix(Constants.brightnessControlSuffix)
        else {
            return nil
        }

        let startIndex = controlID.index(
            controlID.startIndex,
            offsetBy: Constants.displayControlPrefix.count
        )
        let endIndex = controlID.index(
            controlID.endIndex,
            offsetBy: -Constants.brightnessControlSuffix.count
        )
        return CGDirectDisplayID(controlID[startIndex..<endIndex])
    }

    private func subtitle(for displays: [DisplayBrightnessDisplay]) -> String {
        if displays.count == 1, let display = displays.first {
            return "\(display.display.name) \(Self.percentText(for: display.brightness))"
        }

        return "\(displays.count) 个显示器"
    }

    private func buildDetail(for displays: [DisplayBrightnessDisplay]) -> PluginPanelDetail {
        PluginPanelDetail(
            primaryControls: displays.map { display in
                PluginPanelControl(
                    id: "\(Constants.displayControlPrefix)\(display.display.id)\(Constants.brightnessControlSuffix)",
                    kind: .slider,
                    options: [],
                    selectedOptionID: nil,
                    dateValue: nil,
                    minimumDate: nil,
                    displayedComponents: nil,
                    datePickerStyle: nil,
                    sectionTitle: display.display.name,
                    sliderValue: display.brightness,
                    sliderBounds: 0...1,
                    sliderStep: 0.01,
                    valueLabel: Self.percentText(for: display.brightness),
                    isEnabled: true
                )
            },
            secondaryPanel: nil
        )
    }

    private static func percentText(for brightness: Double) -> String {
        "\(Int((brightness * 100).rounded()))%"
    }

    private func shortcutDefinition(
        for display: DisplayInfo,
        direction: DisplayBrightnessShortcutDirection
    ) -> PluginShortcutDefinition {
        let displayKey = Self.shortcutDisplayKey(for: display)
        let actionID = Self.shortcutActionID(displayKey: displayKey, direction: direction)

        return PluginShortcutDefinition(
            id: actionID,
            title: "\(display.name) \(direction.title)亮度",
            description: "\(direction.title)\(display.name) 的亮度。",
            actionID: actionID,
            scope: .global,
            defaultBinding: nil,
            isRequired: false,
            sharedBindingGroupID: direction.sharedBindingGroupID,
            settingsGroupID: "\(Constants.shortcutDisplayGroupPrefix)\(displayKey)",
            settingsGroupTitle: display.name,
            settingsControlTitle: direction.title,
            settingsControlSystemImage: direction.systemImage
        )
    }

    private func startShortcutAction(id: String) {
        guard shortcutSessions[id] == nil,
              let action = Self.parseShortcutActionID(id)
        else {
            return
        }

        let now = Date()
        let initialStep = shortcutAcceleration.stepForPress(actionID: id, now: now)
        applyShortcutAction(action, step: initialStep, phase: .changed)
        scheduleShortcutRepeats(for: action, initialStep: initialStep, startDate: now)
    }

    private func stopShortcutAction(id: String) {
        guard let session = shortcutSessions.removeValue(forKey: id) else {
            return
        }

        session.task.cancel()
        commitShortcutAction(session.action)
    }

    private func stopAllShortcutActions() {
        for session in shortcutSessions.values {
            session.task.cancel()
        }
        shortcutSessions.removeAll()
    }

    private func scheduleShortcutRepeats(
        for action: DisplayBrightnessShortcutAction,
        initialStep: Int,
        startDate: Date
    ) {
        let sessionID = UUID()
        let task = Task { @MainActor [weak self] in
            await Self.sleep(seconds: Self.initialHoldDelay)
            var repeatCount = 0

            while !Task.isCancelled {
                guard let self,
                      self.shortcutSessions[action.id]?.id == sessionID
                else {
                    return
                }

                guard repeatCount < Self.maximumHoldRepeatCount else {
                    self.stopShortcutAction(id: action.id)
                    return
                }

                let elapsed = Date().timeIntervalSince(startDate)
                let step = DisplayBrightnessShortcutAcceleration.stepForHold(
                    elapsed: elapsed,
                    baseline: initialStep
                )
                self.applyShortcutAction(action, step: step, phase: .changed)
                repeatCount += 1
                await Self.sleep(seconds: Self.repeatDelay)
            }
        }

        shortcutSessions[action.id] = DisplayBrightnessShortcutSession(
            id: sessionID,
            action: action,
            task: task
        )
    }

    private func applyShortcutAction(
        _ action: DisplayBrightnessShortcutAction,
        step: Int,
        phase: PluginPanelAction.SliderPhase
    ) {
        guard let display = display(forShortcutKey: action.displayKey) else {
            return
        }

        let delta = Double(step) / 100 * action.direction.multiplier
        controller.setBrightness(display.brightness + delta, for: display.id, phase: phase)
    }

    private func commitShortcutAction(_ action: DisplayBrightnessShortcutAction) {
        guard let display = display(forShortcutKey: action.displayKey) else {
            return
        }

        controller.setBrightness(display.brightness, for: display.id, phase: .ended)
    }

    private func display(forShortcutKey displayKey: String) -> DisplayBrightnessDisplay? {
        controller.snapshot().displays.first {
            Self.shortcutDisplayKey(for: $0.display) == displayKey
        }
    }

    private static var initialHoldDelay: TimeInterval {
        systemKeyboardTiming(
            key: "InitialKeyRepeat",
            fallback: 25,
            minimum: 0.22,
            maximum: 0.55
        )
    }

    private static var repeatDelay: TimeInterval {
        systemKeyboardTiming(
            key: "KeyRepeat",
            fallback: 6,
            minimum: 0.075,
            maximum: 0.16
        )
    }

    private static var maximumHoldRepeatCount: Int { 100 }

    private static func systemKeyboardTiming(
        key: String,
        fallback: Double,
        minimum: TimeInterval,
        maximum: TimeInterval
    ) -> TimeInterval {
        let rawValue = UserDefaults.standard.object(forKey: key) as? Double ?? fallback
        return min(max(rawValue * 0.014, minimum), maximum)
    }

    private static func sleep(seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    static func shortcutActionID(
        displayKey: String,
        direction: DisplayBrightnessShortcutDirection
    ) -> String {
        "\(Constants.shortcutActionPrefix)\(displayKey)\(direction.actionSuffix)"
    }

    static func parseShortcutActionID(_ actionID: String) -> DisplayBrightnessShortcutAction? {
        guard actionID.hasPrefix(Constants.shortcutActionPrefix) else {
            return nil
        }

        let direction: DisplayBrightnessShortcutDirection
        if actionID.hasSuffix(DisplayBrightnessShortcutDirection.decrease.actionSuffix) {
            direction = .decrease
        } else if actionID.hasSuffix(DisplayBrightnessShortcutDirection.increase.actionSuffix) {
            direction = .increase
        } else {
            return nil
        }

        let startIndex = actionID.index(
            actionID.startIndex,
            offsetBy: Constants.shortcutActionPrefix.count
        )
        let endIndex = actionID.index(
            actionID.endIndex,
            offsetBy: -direction.actionSuffix.count
        )
        let displayKey = String(actionID[startIndex..<endIndex])

        guard !displayKey.isEmpty else {
            return nil
        }

        return DisplayBrightnessShortcutAction(
            id: actionID,
            displayKey: displayKey,
            direction: direction
        )
    }

    static func shortcutDisplayKey(for display: DisplayInfo) -> String {
        if let serialNumber = display.serialNumber {
            return "v\(display.vendorNumber ?? 0)-m\(display.modelNumber ?? 0)-s\(serialNumber)"
        }

        if display.isBuiltin {
            return "builtin-v\(display.vendorNumber ?? 0)-m\(display.modelNumber ?? 0)"
        }

        return "id\(display.id)"
    }
}
