import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class MiddleClickPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        MiddleClickPluginProvider(context: context)
    }
}

@MainActor
private struct MiddleClickPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [MiddleClickPlugin(context: context)]
    }
}

/// 触控板三指点击模拟鼠标中键插件。
///
/// 开启后，在触控板上用三根手指轻点（不是按下），会在当前光标位置发送一次鼠标中键事件。
/// 常见用途：
/// - 浏览器中间键点击链接，在后台新标签页打开
/// - 关闭浏览器标签页
/// - 终端中粘贴选中文本
///
/// 需要辅助功能（Accessibility）权限才能向其他应用发送鼠标事件。
@MainActor
final class MiddleClickPlugin: MacToolsPlugin, PluginPrimaryPanel, AccessibilityPermissionRefreshing {

    // MARK: - IDs

    private enum StorageKey {
        static let isEnabled = "middle-click.enabled"
        static let requiredFingerCount = "middle-click.required-finger-count"
    }

    private enum PermissionID {
        static let accessibility = "accessibility"
    }

    private enum ControlID {
        static let fingerCount = "finger-count"
    }

    // 支持的手指数量
    private enum FingerCountOption: Int, CaseIterable {
        case three = 3
        case four = 4
        case five = 5

        var label: String {
            "\(self.rawValue) 指"
        }
    }

    // MARK: - Plugin Metadata

    let metadata = PluginMetadata(
        id: "middle-click",
        title: "模拟鼠标中键",
        iconName: "hand.tap",
        iconTint: Color(nsColor: .systemIndigo),
        order: 55,
        defaultDescription: "触控板轻点 → 模拟鼠标中键"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    // MARK: - Plugin Wiring

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    // MARK: - State

    private let storage: PluginStorage
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "MiddleClickPlugin")
    private var isAccessibilityGranted: Bool
    private var session: MiddleClickSession?
    private var lastErrorMessage: String?
    private var requiredFingerCount: Int

    // MARK: - Init

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "middle-click"),
        userDefaults: UserDefaults? = nil
    ) {
        self.storage = userDefaults.map {
            UserDefaultsPluginStorage(pluginID: context.pluginID, userDefaults: $0)
        } ?? context.storage
        self.isAccessibilityGranted = AccessibilityCheck.isTrusted()
        storage.migrateValueIfNeeded(fromLegacyKey: StorageKey.isEnabled, to: StorageKey.isEnabled)
        storage.migrateValueIfNeeded(
            fromLegacyKey: StorageKey.requiredFingerCount,
            to: StorageKey.requiredFingerCount
        )
        self.requiredFingerCount = storage.integer(forKey: StorageKey.requiredFingerCount)
        
        // 如果没有存储的值，默认为 3 指
        if self.requiredFingerCount == 0 {
            self.requiredFingerCount = 3
        }

        if isAccessibilityGranted && storage.bool(forKey: StorageKey.isEnabled) {
            let s = MiddleClickSession()
            s.requiredFingerCount = self.requiredFingerCount
            s.activate()
            session = s
        }
    }

    func deactivate(reason: PluginDeactivationReason) {
        guard reason.requiresStateCleanup else { return }
        stopSession()
    }

    // MARK: - Primary Panel

    var primaryPanelState: PluginPanelState {
        let subtitle = session != nil 
            ? "触控板\(self.requiredFingerCount)指轻点 → 鼠标中键"
            : panelSubtitle
        
        return PluginPanelState(
            subtitle: subtitle,
            isOn: session != nil,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: lastErrorMessage
        )
    }

    var configuration: PluginConfiguration? {
        PluginConfiguration(description: metadata.defaultDescription) { [weak self] _ in
            guard let self = self else { return AnyView(EmptyView()) }
            let currentCount = self.storage.integer(forKey: StorageKey.requiredFingerCount)
            let displayCount = currentCount > 0 ? currentCount : self.requiredFingerCount
            return AnyView(
                MiddleClickSettingsView(
                    selectedCount: displayCount,
                    onCountChange: { newCount in
                        self.setFingerCount(newCount)
                    }
                )
            )
        }
    }

    var permissionRequirements: [PluginPermissionRequirement] {
        [
            PluginPermissionRequirement(
                id: PermissionID.accessibility,
                kind: .accessibility,
                title: "辅助功能授权",
                description: "模拟鼠标中键需要辅助功能权限才能正常工作。"
            )
        ]
    }

    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {
        refreshAccessibilityPermission()
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(enabled) = action else { return }
        setEnabled(enabled)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        switch permissionID {
        case PermissionID.accessibility:
            return PluginPermissionState(
                isGranted: isAccessibilityGranted,
                footnote: isAccessibilityGranted ? nil : "前往系统设置 → 隐私与安全性 → 辅助功能，授权 MacTools。"
            )
        default:
            return PluginPermissionState(isGranted: true, footnote: nil)
        }
    }

    func handlePermissionAction(id: String) {
        guard id == PermissionID.accessibility else { return }

        if isAccessibilityGranted {
            refresh()
        } else {
            isAccessibilityGranted = AccessibilityCheck.requestTrust(prompt: true)
            if !isAccessibilityGranted {
                lastErrorMessage = "模拟鼠标中键需要辅助功能权限，请先前往设置完成授权。"
            } else {
                lastErrorMessage = nil
            }
            onStateChange?()
        }
    }

    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    // MARK: - Settings

    private func setFingerCount(_ count: Int) {
        requiredFingerCount = count
        storage.set(count, forKey: StorageKey.requiredFingerCount)

        // session 持续运行；touchCallback 每帧都会读取最新值
        session?.requiredFingerCount = count

        onStateChange?()
    }

    // MARK: - Private

    private var panelSubtitle: String {
        if session != nil {
            return "触控板三指轻点 → 鼠标中键"
        }

        if isAccessibilityGranted {
            return metadata.defaultDescription
        }

        return "启用前需要辅助功能授权"
    }

    private func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil

        if enabled {
            isAccessibilityGranted = AccessibilityCheck.isTrusted()

            if !isAccessibilityGranted {
                isAccessibilityGranted = AccessibilityCheck.requestTrust(prompt: true)
            }

            guard isAccessibilityGranted else {
                lastErrorMessage = "模拟鼠标中键需要辅助功能权限，请先前往设置完成授权。"
                requestPermissionGuidance?(PermissionID.accessibility)
                onStateChange?()
                return
            }

            startSession()
            storage.set(true, forKey: StorageKey.isEnabled)
        } else {
            stopSession()
            storage.set(false, forKey: StorageKey.isEnabled)
        }
        onStateChange?()
    }

    private func startSession() {
        guard session == nil else { return }
        let newSession = MiddleClickSession()
        newSession.requiredFingerCount = requiredFingerCount
        newSession.activate()
        session = newSession
        logger.info("\(self.requiredFingerCount)指中键已启用")
    }

    private func stopSession() {
        session?.deactivate()
        session = nil
        logger.info("三指中键已停用")
    }

    // MARK: - AccessibilityPermissionRefreshing

    func refreshAccessibilityPermission() {
        let previous = isAccessibilityGranted
        isAccessibilityGranted = AccessibilityCheck.isTrusted()

        if previous && !isAccessibilityGranted {
            // 权限被撤销：停止 session，清除持久化
            stopSession()
            storage.set(false, forKey: StorageKey.isEnabled)
        } else if !previous && isAccessibilityGranted {
            // 权限新授予：清除错误，按需恢复 session
            lastErrorMessage = nil
            if storage.bool(forKey: StorageKey.isEnabled) {
                startSession()
            }
        }

        if previous != isAccessibilityGranted {
            onStateChange?()
        }
    }
}
