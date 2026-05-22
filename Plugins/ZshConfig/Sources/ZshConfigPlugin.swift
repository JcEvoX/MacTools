import AppKit
import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

// MARK: - Bundle Factory

public final class ZshConfigPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        ZshConfigPluginProvider(context: context)
    }
}

@MainActor
private struct ZshConfigPluginProvider: PluginProvider {
    let context: PluginRuntimeContext
    func makePlugins() -> [any MacToolsPlugin] {
        [ZshConfigPlugin(context: context)]
    }
}

// MARK: - Control IDs

private enum ControlID {
    static let openSettings = "zsh-open-config"
}

// MARK: - Plugin

@MainActor
final class ZshConfigPlugin: MacToolsPlugin, PluginPrimaryPanel {

    // MARK: Metadata

    let metadata = PluginMetadata(
        id: "zsh-config",
        title: "zsh 配置",
        iconName: "curlybraces",
        iconTint: Color(nsColor: .systemGreen),
        order: 72,
        defaultDescription: "快速编辑 zsh 配置文件"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .button,
        menuActionBehavior: .dismissBeforeHandling,
        buttonTitle: "编辑"
    )

    // MARK: Callbacks

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    // MARK: Private

    private let store: ZshConfigStore
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "ZshConfigPlugin"
    )

    // MARK: Init

    init(context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "zsh-config")) {
        self.store = ZshConfigStore()
    }

    // MARK: - MacToolsPlugin

    func activate(context: PluginRuntimeContext) {
        store.refreshStatusMap()
    }

    func refresh() {
        store.refreshStatusMap()
        onStateChange?()
    }

    // MARK: - PluginPrimaryPanel

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: false,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    func handleAction(_ action: PluginPanelAction) {
        // 「编辑」按钮由宿主拦截并导航到设置页，插件无需额外处理。
    }

    // MARK: - Configuration

    var configuration: PluginConfiguration? {
        PluginConfiguration(
            description: "在应用内直接查看和编辑 zsh 配置文件，支持常用片段快速插入。",
            prefersFullHeight: true
        ) { [self] _ in
            ZshConfigEditorView(store: self.store)
        }
    }

    // MARK: - Private Helpers

    private var panelSubtitle: String {
        let existing = ZshConfigFileType.allCases.filter {
            store.statusMap[$0]?.exists == true
        }
        if existing.isEmpty {
            return "未找到配置文件，点击设置创建"
        }
        return metadata.defaultDescription
    }
}
