import AppKit
import Carbon
import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class PhysicalCleanModePluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        PhysicalCleanModePluginProvider(context: context)
    }
}

@MainActor
private struct PhysicalCleanModePluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [PhysicalCleanModePlugin(context: context)]
    }
}

@MainActor
final class PhysicalCleanModePlugin: MacToolsPlugin, PluginPrimaryPanel, AccessibilityPermissionRefreshing {
    private enum StorageKey {
        static let legacyEnabledState = "feature.cleanModeEnabled"
    }

    private enum ActionID {
        static let exitPhysicalCleanMode = "exitPhysicalCleanMode"
    }

    private enum PermissionID {
        static let accessibility = "accessibility"
    }

    private enum ShortcutID {
        static let exitPhysicalCleanMode = "exit-physical-clean-mode"
    }

    private enum ShortcutSettingsGroupID {
        static let exitPhysicalCleanMode = "physical-clean-mode.exit"
    }

    let metadata = PluginMetadata(
        id: "physical-clean-mode",
        title: "清洁模式",
        iconName: "sparkles",
        iconTint: Color(nsColor: .systemCyan),
        order: 100,
        defaultDescription: "屏幕全黑并临时禁用键盘输入"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .dismissBeforeHandling
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let storage: PluginStorage
    private let logger = PhysicalCleanModeLog.plugin
    private var isAccessibilityGranted: Bool
    private var lastErrorMessage: String?
    private var session: PhysicalCleanModeSession?

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "physical-clean-mode"),
        userDefaults: UserDefaults? = nil
    ) {
        self.storage = userDefaults.map {
            UserDefaultsPluginStorage(pluginID: context.pluginID, userDefaults: $0)
        } ?? context.storage
        self.isAccessibilityGranted = AccessibilityCheck.isTrusted()

        storage.migrateValueIfNeeded(
            fromLegacyKey: StorageKey.legacyEnabledState,
            to: StorageKey.legacyEnabledState
        )
        storage.removeObject(forKey: StorageKey.legacyEnabledState)
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: session != nil,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: lastErrorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] {
        [
            PluginPermissionRequirement(
                id: PermissionID.accessibility,
                kind: .accessibility,
                title: "辅助功能授权",
                description: "辅助功能权限是清洁模式运行所需的必要权限。"
            )
        ]
    }

    var settingsSections: [PluginSettingsSection] { [] }

    var shortcutDefinitions: [PluginShortcutDefinition] {
        [
            PluginShortcutDefinition(
                id: ShortcutID.exitPhysicalCleanMode,
                title: "退出清洁模式",
                description: "清洁模式启用时用于恢复输入和关闭黑屏覆盖的快捷键。",
                actionID: ActionID.exitPhysicalCleanMode,
                scope: .whilePluginActive,
                defaultBinding: ShortcutBinding(
                    keyCode: UInt16(kVK_Escape),
                    modifiers: [.control, .command]
                ),
                isRequired: true,
                settingsGroupID: ShortcutSettingsGroupID.exitPhysicalCleanMode,
                settingsGroupTitle: "退出快捷键",
                settingsGroupDescription: "清洁模式启用时恢复输入并关闭黑屏覆盖。",
                settingsControlTitle: "退出",
                settingsControlSystemImage: "keyboard"
            )
        ]
    }

    func refresh() {
        let previousAccessState = isAccessibilityGranted
        isAccessibilityGranted = AccessibilityCheck.isTrusted()

        if isAccessibilityGranted {
            if lastErrorMessage == "请先完成辅助功能授权。" {
                lastErrorMessage = nil
            }
        } else if session != nil {
            session?.requestEmergencyExit(message: "辅助功能授权已失效，已自动退出清洁模式。")
        }

        if previousAccessState != isAccessibilityGranted {
            notifyChange()
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setSwitch(isEnabled):
            if PhysicalCleanModeLog.isVerboseLoggingEnabled {
                logger.debug("panel action setSwitch isEnabled=\(isEnabled, privacy: .public)")
            }
            setPhysicalCleanModeEnabled(isEnabled)
        case .setDisclosureExpanded,
             .setSelection,
             .setNavigationSelection,
             .clearNavigationSelection,
             .setDate,
             .setSlider,
             .invokeAction:
            break
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        switch permissionID {
        case PermissionID.accessibility:
            return PluginPermissionState(
                isGranted: isAccessibilityGranted,
                footnote: lastErrorMessage
            )
        default:
            return PluginPermissionState(isGranted: true, footnote: nil)
        }
    }

    func handlePermissionAction(id: String) {
        guard id == PermissionID.accessibility else {
            return
        }

        if isAccessibilityGranted {
            refresh()
        } else {
            requestAccessibilityPermission(showSettingsGuidance: false)
        }
    }

    func handleSettingsAction(id: String) {}

    func handleShortcutAction(id: String) {
        guard id == ActionID.exitPhysicalCleanMode else {
            return
        }

        session?.requestStop(reason: .userRequested)
    }

    private var panelSubtitle: String {
        if let session {
            return "已启用，使用 \(ShortcutFormatter.displayString(for: session.exitBinding)) 退出"
        }

        if isAccessibilityGranted {
            return metadata.defaultDescription
        }

        return "启用前需要辅助功能授权"
    }

    private func requestAccessibilityPermission(showSettingsGuidance: Bool) {
        if PhysicalCleanModeLog.isVerboseLoggingEnabled {
            logger.debug("request accessibility permission showSettingsGuidance=\(showSettingsGuidance, privacy: .public)")
        }
        isAccessibilityGranted = AccessibilityCheck.requestTrust(prompt: true)

        if isAccessibilityGranted {
            lastErrorMessage = nil
        } else {
            logger.notice("accessibility permission is required before entering physical clean mode")
            lastErrorMessage = "清洁模式需要辅助功能权限，请先前往设置完成授权。"

            if showSettingsGuidance {
                requestPermissionGuidance?(PermissionID.accessibility)
            }
        }

        notifyChange()
    }

    private func setPhysicalCleanModeEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            lastErrorMessage = nil
            if let session {
                session.requestStop(reason: .userRequested)
            } else {
                notifyChange()
            }
            return
        }

        enablePhysicalCleanModeIfPossible()
    }

    private func enablePhysicalCleanModeIfPossible() {
        isAccessibilityGranted = AccessibilityCheck.isTrusted()

        guard isAccessibilityGranted else {
            requestAccessibilityPermission(showSettingsGuidance: true)
            return
        }

        guard let exitBinding = shortcutBindingResolver?(ShortcutID.exitPhysicalCleanMode), exitBinding.isValid else {
            logger.error("enable aborted because exit shortcut is missing or invalid")
            lastErrorMessage = "请先在功能中设置有效的退出快捷键。"
            notifyChange()
            return
        }

        if session != nil {
            return
        }

        let session = PhysicalCleanModeSession(
            exitBinding: exitBinding,
            onEnd: { [weak self] reason in
                self?.handleSessionEnd(reason)
            }
        )

        do {
            self.session = session
            if PhysicalCleanModeLog.isVerboseLoggingEnabled {
                logger.debug("starting physical clean mode session exitBinding=\(ShortcutFormatter.displayString(for: exitBinding), privacy: .public)")
            }
            try session.start()

            guard self.session === session else {
                logger.error("session ended during startup sequence before completion")
                return
            }

            lastErrorMessage = nil
            notifyChange()
        } catch {
            if self.session === session {
                self.session = nil
            }
            logger.error("physical clean mode session start failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            notifyChange()
        }
    }

    private func handleSessionEnd(_ reason: PhysicalCleanModeSession.EndReason) {
        switch reason {
        case .userRequested:
            break
        case .emergency:
            logger.error("physical clean mode session ended unexpectedly reason=\(String(describing: reason), privacy: .public)")
        }

        session = nil

        switch reason {
        case .userRequested:
            lastErrorMessage = nil
        case let .emergency(message):
            lastErrorMessage = message
        }

        notifyChange()
    }

    private func notifyChange() {
        onStateChange?()
    }

    // MARK: - AccessibilityPermissionRefreshing

    func refreshAccessibilityPermission() {
        refresh()
    }
}
