import AppKit
import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

protocol DockCommandRunning {
    func setDockAutohide(_ isEnabled: Bool) throws
}

struct ProcessDockCommandRunner: DockCommandRunning {
    func setDockAutohide(_ isEnabled: Bool) throws {
        let script = """
        tell application "System Events"
            tell dock preferences
                set autohide to \(isEnabled ? "true" : "false")
            end tell
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "HideDockPlugin",
                code: (error[NSAppleScript.errorNumber] as? Int) ?? 1,
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "切换 Dock 自动隐藏失败"]
            )
        }
    }
}

public final class HideDockPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        HideDockPluginProvider()
    }
}

@MainActor
private struct HideDockPluginProvider: PluginProvider {
    func makePlugins() -> [any MacToolsPlugin] {
        [HideDockPlugin()]
    }
}

@MainActor
final class HideDockPlugin: MacToolsPlugin, PluginPrimaryPanel {
    let metadata = PluginMetadata(
        id: "hide-dock",
        title: "自动隐藏程序坞",
        iconName: "rectangle.bottomthird.inset.filled",
        iconTint: Color(nsColor: .systemBlue),
        order: 45,
        defaultDescription: "自动隐藏程序坞，提供更干净的桌面环境"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "HideDockPlugin")
    private let commandRunner: any DockCommandRunning
    private let stateReader: () -> Bool

    private var isDockHidden: Bool
    private var lastErrorMessage: String?

    init(
        commandRunner: any DockCommandRunning = ProcessDockCommandRunner(),
        stateReader: @escaping () -> Bool = { HideDockPlugin.readDockAutohideState() }
    ) {
        self.commandRunner = commandRunner
        self.stateReader = stateReader
        self.isDockHidden = stateReader()
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: isDockHidden ? "已开启" : "已关闭",
            isOn: isDockHidden,
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
        if latestState != isDockHidden {
            isDockHidden = latestState
            onStateChange?()
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(isEnabled) = action else {
            return
        }

        setDockHidden(isEnabled)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    private func setDockHidden(_ isEnabled: Bool) {
        do {
            try commandRunner.setDockAutohide(isEnabled)
            isDockHidden = isEnabled
            lastErrorMessage = nil
            onStateChange?()
        } catch {
            logger.error("Failed to update Dock auto-hide: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            refresh()
            onStateChange?()
        }
    }

    private nonisolated static func readDockAutohideState() -> Bool {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        return defaults?.object(forKey: "autohide") as? Bool ?? false
    }
}
