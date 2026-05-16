import SwiftUI

@MainActor
protocol MacToolsPlugin: AnyObject {
    var metadata: PluginMetadata { get }
    var primaryPanel: (any PluginPrimaryPanel)? { get }
    var componentPanel: (any PluginComponentPanel)? { get }
    var permissionRequirements: [PluginPermissionRequirement] { get }
    var settingsSections: [PluginSettingsSection] { get }
    var shortcutDefinitions: [PluginShortcutDefinition] { get }
    var configuration: PluginConfiguration? { get }
    var onStateChange: (() -> Void)? { get set }
    var requestPermissionGuidance: ((String) -> Void)? { get set }
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)? { get set }

    func refresh()
    func permissionState(for permissionID: String) -> PluginPermissionState
    func handlePermissionAction(id: String)
    func handleSettingsAction(id: String)
    func handleShortcutAction(id: String)
}

@MainActor
protocol PluginPrimaryPanel: AnyObject {
    var primaryPanelDescriptor: PluginPrimaryPanelDescriptor { get }
    var primaryPanelState: PluginPanelState { get }

    func handleAction(_ action: PluginPanelAction)
}

extension MacToolsPlugin {
    var primaryPanel: (any PluginPrimaryPanel)? {
        nil
    }

    var componentPanel: (any PluginComponentPanel)? {
        nil
    }

    var permissionRequirements: [PluginPermissionRequirement] {
        []
    }

    var settingsSections: [PluginSettingsSection] {
        []
    }

    var shortcutDefinitions: [PluginShortcutDefinition] {
        []
    }

    var configuration: PluginConfiguration? {
        nil
    }

    func refresh() {}

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}
}

extension MacToolsPlugin where Self: PluginPrimaryPanel {
    var primaryPanel: (any PluginPrimaryPanel)? {
        self
    }
}

@MainActor
protocol PluginComponentPanel: AnyObject {
    var descriptor: PluginComponentDescriptor { get }
    var componentPanelState: PluginComponentState { get }

    func makeView(context: PluginComponentContext) -> AnyView
}

extension MacToolsPlugin where Self: PluginComponentPanel {
    var componentPanel: (any PluginComponentPanel)? {
        self
    }
}

@MainActor
protocol PluginProvider {
    func makePlugins() -> [any MacToolsPlugin]
}
