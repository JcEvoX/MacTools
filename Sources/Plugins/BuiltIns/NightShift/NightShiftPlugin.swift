import CoreBrightness
import Foundation
import OSLog
import SwiftUI

protocol NightShiftControlling {
    func getStatus() -> Bool
    func setEnabled(_ enabled: Bool) -> Bool
}

struct CBNightShiftController: NightShiftControlling {
    private let client = CBBlueLightClient()

    func getStatus() -> Bool {
        var status = CBBlueLightStatus()
        guard client.getBlueLightStatus(&status) else { return false }
        return status.enabled.boolValue
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        client.setEnabled(enabled)
    }
}

@MainActor
final class NightShiftPlugin: MacToolsPlugin, PluginPrimaryPanel {
    let metadata = PluginMetadata(
        id: "night-shift",
        title: "夜览",
        iconName: "lamp.floor",
        iconTint: Color(nsColor: .systemOrange),
        order: 35,
        defaultDescription: "降低蓝光，使屏幕颜色更暖"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = AppLog.nightShiftPlugin
    private let controller: any NightShiftControlling
    private var isEnabled: Bool
    private var lastErrorMessage: String?

    init(controller: any NightShiftControlling = CBNightShiftController()) {
        self.controller = controller
        self.isEnabled = controller.getStatus()
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: isEnabled ? "已开启" : "已关闭",
            isOn: isEnabled,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: lastErrorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {
        let current = controller.getStatus()
        if current != isEnabled {
            isEnabled = current
            onStateChange?()
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(enable) = action else { return }
        setNightShift(enable)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    // MARK: - Private

    private func setNightShift(_ enable: Bool) {
        let success = controller.setEnabled(enable)
        if success {
            isEnabled = enable
            lastErrorMessage = nil
            onStateChange?()
        } else {
            logger.error("Failed to \(enable ? "enable" : "disable", privacy: .public) Night Shift")
            lastErrorMessage = "切换夜览失败"
            onStateChange?()
        }
    }
}
