import Combine
import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class LaunchpadPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        LaunchpadPluginProvider(context: context)
    }
}

private struct LaunchpadPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [LaunchpadPlugin(context: context)]
    }
}

@MainActor
final class LaunchpadPlugin: MacToolsPlugin, PluginPrimaryPanel {
    private enum ControlID {
        static let execute = "execute"
    }
    private enum ActionID {
        static let toggle = "toggleLaunchpad"
    }
    private enum ShortcutID {
        static let toggle = "launchpad.toggle"
    }

    let metadata = PluginMetadata(
        id: "launchpad",
        title: "启动台",
        iconName: "square.grid.3x3.fill",
        iconTint: Color(nsColor: .systemBlue),
        order: 12,
        defaultDescription: "唤出应用网格，搜索并启动"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .button,
        menuActionBehavior: .dismissBeforeHandling,
        buttonTitle: "打开"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "LaunchpadPlugin"
    )

    private let preferences: LaunchpadPreferences
    private let layoutStore: LaunchpadLayoutStore
    private let overlay: LaunchpadOverlayController
    private let hotCornerMonitor = LaunchpadHotCornerMonitor()
    private var cancellables = Set<AnyCancellable>()

    init(context: PluginRuntimeContext) {
        let preferences = LaunchpadPreferences(storage: context.storage)
        // Same scoped storage as preferences; owned here so the layout (and its @Published
        // changes) outlives individual overlay sessions and drives grid re-renders.
        let layoutStore = LaunchpadLayoutStore(storage: context.storage)
        self.preferences = preferences
        self.layoutStore = layoutStore
        self.overlay = LaunchpadOverlayController(preferences: preferences, layoutStore: layoutStore)

        hotCornerMonitor.onTrigger = { [weak self] in self?.openLaunchpad() }
        // Apply the saved corner now and whenever the user changes it in settings.
        preferences.$hotCorner
            .sink { [weak hotCornerMonitor] corner in hotCornerMonitor?.update(corner: corner) }
            .store(in: &cancellables)
    }

    var configuration: PluginConfiguration? {
        PluginConfiguration(description: metadata.defaultDescription) { [preferences, layoutStore] _ in
            LaunchpadSettingsView(preferences: preferences, layoutStore: layoutStore)
        }
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: metadata.defaultDescription,
            isOn: false,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    var shortcutDefinitions: [PluginShortcutDefinition] {
        [
            PluginShortcutDefinition(
                id: ShortcutID.toggle,
                title: "打开启动台",
                description: "全局快捷键唤出或收起应用网格。默认未设置，可在此自定义。",
                actionID: ActionID.toggle,
                scope: .global,
                defaultBinding: nil,        // v1 决定：不抢占系统/用户已有热键
                isRequired: false
            )
        ]
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .invokeAction(controlID) = action, controlID == ControlID.execute else {
            return
        }
        openLaunchpad()
    }

    func handleShortcutAction(id: String) {
        guard id == ActionID.toggle else { return }
        openLaunchpad()
    }

    private func openLaunchpad() {
        overlay.toggle()
    }

    func activate(context: PluginRuntimeContext) {
        // Resume after a pause (插件隐藏/停用后重新启用): deactivate stopped the cursor poll but
        // the corner preference kept its value, so the `$hotCorner` sink (fires on CHANGE) never
        // re-arms it — re-apply explicitly here.
        hotCornerMonitor.update(corner: preferences.hotCorner)
    }

    func deactivate(reason: PluginDeactivationReason) {
        if reason.requiresStateCleanup {
            hotCornerMonitor.stop()      // stop the cursor poll; no runaway timer
            overlay.close()
        }
    }
}
