import AppKit
import Foundation
@preconcurrency import IOKit.hid
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class MouseScrollReverserPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        MouseScrollReverserPluginProvider(context: context)
    }
}

@MainActor
private struct MouseScrollReverserPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [
            MouseScrollReverserPlugin(
                context: context,
                localization: PluginLocalization(bundle: context.resourceBundle)
            ),
        ]
    }
}

enum MouseScrollReverserInputMonitoringAuthorizationStatus {
    case granted
    case denied
    case unknown
}

@MainActor
final class MouseScrollReverserPlugin: MacToolsPlugin, PluginPrimaryPanel, AccessibilityPermissionRefreshing {
    private enum PermissionID {
        static let accessibility = "accessibility"
        static let inputMonitoring = "input-monitoring"
    }

    let metadata: PluginMetadata

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    let store: MouseScrollReverserStore

    private let localization: PluginLocalization
    private let session: any MouseScrollReverserSessionManaging
    private let accessibilityTrusted: @MainActor () -> Bool
    private let requestAccessibilityTrust: @MainActor (Bool) -> Bool
    private let inputMonitoringAuthorizationStatus: @MainActor () -> MouseScrollReverserInputMonitoringAuthorizationStatus
    private let openURL: (URL) -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "MouseScrollReverserPlugin"
    )

    private var isAccessibilityGranted: Bool
    private var lastErrorMessage: String?

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "mouse-scroll-reverser"),
        session: (any MouseScrollReverserSessionManaging)? = nil,
        localization: PluginLocalization = PluginLocalization(bundle: .main),
        accessibilityTrusted: @escaping @MainActor () -> Bool = MouseScrollReverserAccessibilityCheck.isTrusted,
        requestAccessibilityTrust: @escaping @MainActor (Bool) -> Bool = MouseScrollReverserAccessibilityCheck.requestTrust(prompt:),
        inputMonitoringAuthorizationStatus: @escaping @MainActor () -> MouseScrollReverserInputMonitoringAuthorizationStatus = MouseScrollReverserPlugin.currentInputMonitoringAuthorizationStatus,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.localization = localization
        self.store = MouseScrollReverserStore(storage: context.storage)
        self.session = session ?? MouseScrollReverserSession()
        self.accessibilityTrusted = accessibilityTrusted
        self.requestAccessibilityTrust = requestAccessibilityTrust
        self.inputMonitoringAuthorizationStatus = inputMonitoringAuthorizationStatus
        self.openURL = openURL
        self.isAccessibilityGranted = accessibilityTrusted()
        self.metadata = PluginMetadata(
            id: "mouse-scroll-reverser",
            title: localization.string("metadata.title", defaultValue: "鼠标滚动翻转"),
            iconName: "computermouse",
            iconTint: Color(nsColor: .systemTeal),
            order: 56,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "按设备和方向反转滚动"
            )
        )
    }

    func activate(context: PluginRuntimeContext) {
        refreshAccessibilityPermission()
        applyCurrentConfiguration()
    }

    func deactivate(reason: PluginDeactivationReason) {
        guard reason.requiresStateCleanup else {
            return
        }

        session.deactivate()
        onStateChange?()
    }

    func refresh() {
        refreshAccessibilityPermission()
        applyCurrentConfiguration()
        onStateChange?()
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: session.state.scrollTapInstalled,
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
                title: localization.string("permission.accessibility.title", defaultValue: "辅助功能授权"),
                description: localization.string(
                    "permission.accessibility.description",
                    defaultValue: "修改系统滚动事件需要辅助功能权限。"
                )
            ),
            PluginPermissionRequirement(
                id: PermissionID.inputMonitoring,
                kind: .inputMonitoring,
                title: localization.string("permission.inputMonitoring.title", defaultValue: "输入监控授权"),
                description: localization.string(
                    "permission.inputMonitoring.description",
                    defaultValue: "用于区分鼠标滚轮和触控板手势，减少误判。"
                )
            ),
        ]
    }

    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    var configuration: PluginConfiguration? {
        PluginConfiguration(description: metadata.defaultDescription) { [weak self] _ in
            guard let self else {
                return AnyView(EmptyView())
            }

            return AnyView(
                MouseScrollReverserSettingsView(
                    store: self.store,
                    localization: self.localization,
                    onChange: { [weak self] in
                        self?.configurationDidChange()
                    }
                )
            )
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(enabled) = action else {
            return
        }

        setEnabled(enabled)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        switch permissionID {
        case PermissionID.accessibility:
            return PluginPermissionState(
                isGranted: isAccessibilityGranted,
                footnote: isAccessibilityGranted
                    ? nil
                    : localization.string(
                        "permission.accessibility.footnote",
                        defaultValue: "前往系统设置 → 隐私与安全性 → 辅助功能，允许 MacTools。"
                    )
            )
        case PermissionID.inputMonitoring:
            return inputMonitoringPermissionState
        default:
            return PluginPermissionState(isGranted: true, footnote: nil)
        }
    }

    func handlePermissionAction(id: String) {
        switch id {
        case PermissionID.accessibility:
            handleAccessibilityPermissionAction()
        case PermissionID.inputMonitoring:
            openInputMonitoringSettings()
        default:
            return
        }
    }

    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    func refreshAccessibilityPermission() {
        let previous = isAccessibilityGranted
        isAccessibilityGranted = accessibilityTrusted()

        if previous && !isAccessibilityGranted {
            session.deactivate()
            lastErrorMessage = localization.string(
                "error.accessibilityRevoked",
                defaultValue: "辅助功能权限已关闭，滚动翻转已暂停。"
            )
        } else if !previous && isAccessibilityGranted {
            lastErrorMessage = nil
            applyCurrentConfiguration()
        }

        if previous != isAccessibilityGranted {
            onStateChange?()
        }
    }

    private func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil

        if enabled {
            isAccessibilityGranted = accessibilityTrusted()
            if !isAccessibilityGranted {
                isAccessibilityGranted = requestAccessibilityTrust(true)
            }

            guard isAccessibilityGranted else {
                store.setEnabled(false)
                lastErrorMessage = localization.string(
                    "error.accessibilityRequired",
                    defaultValue: "滚动翻转需要辅助功能权限，请先前往设置完成授权。"
                )
                requestPermissionGuidance?(PermissionID.accessibility)
                onStateChange?()
                return
            }
        }

        store.setEnabled(enabled)
        applyCurrentConfiguration()
        onStateChange?()
    }

    private func configurationDidChange() {
        lastErrorMessage = nil
        applyCurrentConfiguration()
        onStateChange?()
    }

    private func applyCurrentConfiguration() {
        let configuration = store.configuration

        guard configuration.shouldInstallEventTap else {
            session.deactivate()
            return
        }

        guard isAccessibilityGranted else {
            session.deactivate()
            return
        }

        if session.state.scrollTapInstalled {
            session.update(configuration: configuration)
            return
        }

        guard session.activate(configuration: configuration) else {
            store.setEnabled(false)
            lastErrorMessage = localization.string(
                "error.tapUnavailable",
                defaultValue: "无法启动滚动事件监听，请确认辅助功能授权后重试。"
            )
            logger.error("failed to install scroll event tap")
            return
        }
    }

    private func handleAccessibilityPermissionAction() {
        if isAccessibilityGranted {
            refreshAccessibilityPermission()
            return
        }

        isAccessibilityGranted = requestAccessibilityTrust(true)
        if isAccessibilityGranted {
            lastErrorMessage = nil
            applyCurrentConfiguration()
        } else {
            lastErrorMessage = localization.string(
                "error.accessibilityRequired",
                defaultValue: "滚动翻转需要辅助功能权限，请先前往设置完成授权。"
            )
        }
        onStateChange?()
    }

    private var panelSubtitle: String {
        let configuration = store.configuration

        if session.state.scrollTapInstalled {
            return localization.format(
                "panel.subtitle.enabledFormat",
                defaultValue: "已开启 · %@ · %@",
                deviceSummary(configuration),
                axisSummary(configuration)
            )
        }

        if configuration.isEnabled, !isAccessibilityGranted {
            return localization.string("panel.subtitle.needsAccessibility", defaultValue: "启用前需要辅助功能授权")
        }

        if configuration.isEnabled, !configuration.hasSelectedAxis {
            return localization.string("panel.subtitle.noAxis", defaultValue: "请选择水平或垂直方向")
        }

        if configuration.isEnabled, !configuration.hasSelectedDevice {
            return localization.string("panel.subtitle.noDevice", defaultValue: "请选择鼠标或触控板")
        }

        return metadata.defaultDescription
    }

    private func deviceSummary(_ configuration: MouseScrollReverserConfiguration) -> String {
        switch (configuration.reverseMouse, configuration.reverseTrackpad) {
        case (true, true):
            return localization.string("summary.device.all", defaultValue: "鼠标和触控板")
        case (true, false):
            return localization.string("summary.device.mouse", defaultValue: "鼠标")
        case (false, true):
            return localization.string("summary.device.trackpad", defaultValue: "触控板")
        case (false, false):
            return localization.string("summary.device.none", defaultValue: "未选设备")
        }
    }

    private func axisSummary(_ configuration: MouseScrollReverserConfiguration) -> String {
        switch (configuration.reverseVertical, configuration.reverseHorizontal) {
        case (true, true):
            return localization.string("summary.axis.all", defaultValue: "水平和垂直")
        case (true, false):
            return localization.string("summary.axis.vertical", defaultValue: "垂直")
        case (false, true):
            return localization.string("summary.axis.horizontal", defaultValue: "水平")
        case (false, false):
            return localization.string("summary.axis.none", defaultValue: "未选方向")
        }
    }

    private var inputMonitoringPermissionState: PluginPermissionState {
        switch inputMonitoringAuthorizationStatus() {
        case .granted:
            return PluginPermissionState(
                isGranted: true,
                footnote: localization.string(
                    "permission.inputMonitoring.granted",
                    defaultValue: "已允许 MacTools 使用输入监控，可更可靠地区分鼠标和触控板。"
                )
            )
        case .denied, .unknown:
            return PluginPermissionState(
                isGranted: false,
                footnote: localization.string(
                    "permission.inputMonitoring.footnote",
                    defaultValue: "前往系统设置 → 隐私与安全性 → 输入监控，允许 MacTools。未授权时会保守处理连续滚动，避免误伤触控板。"
                )
            )
        }
    }

    private static func currentInputMonitoringAuthorizationStatus() -> MouseScrollReverserInputMonitoringAuthorizationStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        case kIOHIDAccessTypeUnknown:
            return .unknown
        default:
            return .unknown
        }
    }

    private func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        openURL(url)
    }
}
