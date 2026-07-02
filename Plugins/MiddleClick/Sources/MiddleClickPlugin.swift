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

/// Simulates a mouse middle-click from a trackpad tap with the configured finger count.
///
/// When enabled, tapping the trackpad with the configured number of fingers converts the system
/// click at the current pointer location into a middle-click. Typical uses include:
/// - Opening browser links in background tabs
/// - Closing browser tabs
/// - Pasting selected text in terminal apps
///
/// Accessibility permission is required to deliver mouse events to other apps.
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

    // MARK: - Plugin Metadata

    let metadata: PluginMetadata

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
    private let localization: PluginLocalization
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
        let localization = PluginLocalization(bundle: context.resourceBundle)
        self.localization = localization
        self.storage = userDefaults.map {
            UserDefaultsPluginStorage(pluginID: context.pluginID, userDefaults: $0)
        } ?? context.storage
        self.metadata = PluginMetadata(
            id: "middle-click",
            title: localization.string("metadata.title", defaultValue: "模拟鼠标中键"),
            iconName: "hand.tap",
            iconTint: Color(nsColor: .systemIndigo),
            order: 55,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "触控板轻点 → 模拟鼠标中键"
            )
        )
        self.isAccessibilityGranted = AccessibilityCheck.isTrusted()
        storage.migrateValueIfNeeded(fromLegacyKey: StorageKey.isEnabled, to: StorageKey.isEnabled)
        storage.migrateValueIfNeeded(
            fromLegacyKey: StorageKey.requiredFingerCount,
            to: StorageKey.requiredFingerCount
        )
        self.requiredFingerCount = storage.integer(forKey: StorageKey.requiredFingerCount)
        
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
            ? localization.format(
                "panel.subtitle.enabledFingerCountFormat",
                defaultValue: "触控板%d指轻点 → 鼠标中键",
                self.requiredFingerCount
            )
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
                    localization: self.localization,
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
                title: localization.string("permission.accessibility.title", defaultValue: "辅助功能授权"),
                description: localization.string(
                    "permission.accessibility.description",
                    defaultValue: "模拟鼠标中键需要辅助功能权限才能正常工作。"
                )
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
                footnote: isAccessibilityGranted
                    ? nil
                    : localization.string(
                        "permission.accessibility.footnote",
                        defaultValue: "前往系统设置 → 隐私与安全性 → 辅助功能，授权 MacTools。"
                    )
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
                lastErrorMessage = localization.string(
                    "error.accessibilityRequired",
                    defaultValue: "模拟鼠标中键需要辅助功能权限，请先前往设置完成授权。"
                )
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

        // Keep the session running; `touchCallback` reads the latest value every frame.
        session?.requiredFingerCount = count

        onStateChange?()
    }

    // MARK: - Private

    private var panelSubtitle: String {
        if session != nil {
            return localization.string("panel.subtitle.enabledDefault", defaultValue: "触控板三指轻点 → 鼠标中键")
        }

        if isAccessibilityGranted {
            return metadata.defaultDescription
        }

        return localization.string("panel.subtitle.needsAccessibility", defaultValue: "启用前需要辅助功能授权")
    }

    private func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil

        if enabled {
            isAccessibilityGranted = AccessibilityCheck.isTrusted()

            if !isAccessibilityGranted {
                isAccessibilityGranted = AccessibilityCheck.requestTrust(prompt: true)
            }

            guard isAccessibilityGranted else {
                lastErrorMessage = localization.string(
                    "error.accessibilityRequired",
                    defaultValue: "模拟鼠标中键需要辅助功能权限，请先前往设置完成授权。"
                )
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
        logger.info("middle click enabled requiredFingerCount=\(self.requiredFingerCount, privacy: .public)")
    }

    private func stopSession() {
        session?.deactivate()
        session = nil
        logger.info("middle click disabled")
    }

    // MARK: - AccessibilityPermissionRefreshing

    func refreshAccessibilityPermission() {
        let previous = isAccessibilityGranted
        isAccessibilityGranted = AccessibilityCheck.isTrusted()

        if previous && !isAccessibilityGranted {
            stopSession()
            storage.set(false, forKey: StorageKey.isEnabled)
        } else if !previous && isAccessibilityGranted {
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
