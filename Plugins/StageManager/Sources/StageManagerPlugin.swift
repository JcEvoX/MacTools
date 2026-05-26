import AppKit
import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

enum StageManagerDefaults {
    static let windowManagerDomain = "com.apple.WindowManager"
    static let globallyEnabledKey = "GloballyEnabled"
}

protocol StageManagerCommandRunning {
    func setStageManagerEnabled(_ isEnabled: Bool) throws
}

struct DefaultsStageManagerCommandRunner: StageManagerCommandRunning {
    func setStageManagerEnabled(_ isEnabled: Bool) throws {
        guard let defaults = UserDefaults(suiteName: StageManagerDefaults.windowManagerDomain) else {
            throw NSError(
                domain: "StageManagerPlugin",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法访问台前调度偏好设置"]
            )
        }

        defaults.set(isEnabled, forKey: StageManagerDefaults.globallyEnabledKey)

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.WindowManager.GloballyEnabled.changed"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

public final class StageManagerPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        StageManagerPluginProvider()
    }
}

@MainActor
private struct StageManagerPluginProvider: PluginProvider {
    func makePlugins() -> [any MacToolsPlugin] {
        [StageManagerPlugin()]
    }
}

@MainActor
final class StageManagerPlugin: MacToolsPlugin, PluginPrimaryPanel {
    let metadata = PluginMetadata(
        id: "stage-manager",
        title: "台前调度",
        iconName: "sidebar.squares.leading",
        iconTint: Color(nsColor: .systemTeal),
        order: 48,
        defaultDescription: "开启台前调度，集中显示当前窗口并把其他窗口收纳到侧边"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "StageManagerPlugin")
    private let commandRunner: any StageManagerCommandRunning
    private let stateReader: () -> Bool

    private var isStageManagerEnabled: Bool
    private var lastErrorMessage: String?

    init(
        commandRunner: any StageManagerCommandRunning = DefaultsStageManagerCommandRunner(),
        stateReader: @escaping () -> Bool = { StageManagerPlugin.readStageManagerState() }
    ) {
        self.commandRunner = commandRunner
        self.stateReader = stateReader
        self.isStageManagerEnabled = stateReader()
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: isStageManagerEnabled ? "已开启" : "已关闭",
            isOn: isStageManagerEnabled,
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
        let latestState = stateReader()
        if latestState != isStageManagerEnabled {
            isStageManagerEnabled = latestState
            onStateChange?()
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(isEnabled) = action else {
            return
        }

        setStageManagerEnabled(isEnabled)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    private func setStageManagerEnabled(_ isEnabled: Bool) {
        do {
            try commandRunner.setStageManagerEnabled(isEnabled)
            isStageManagerEnabled = isEnabled
            lastErrorMessage = nil
            onStateChange?()
        } catch {
            logger.error("Failed to update Stage Manager state: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            refresh()
            onStateChange?()
        }
    }

    private nonisolated static func readStageManagerState() -> Bool {
        let defaults = UserDefaults(suiteName: StageManagerDefaults.windowManagerDomain)
        return defaults?.object(forKey: StageManagerDefaults.globallyEnabledKey) as? Bool ?? false
    }
}
