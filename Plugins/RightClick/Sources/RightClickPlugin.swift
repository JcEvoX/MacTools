import AppKit
import FinderSync
import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class RightClickPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        RightClickPluginProvider(context: context)
    }
}

@MainActor
private struct RightClickPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [RightClickPlugin(localization: PluginLocalization(bundle: context.resourceBundle))]
    }
}

private enum RightClickControlID {
    static let openExtensionSettings = "open-extension-settings"
}

@MainActor
final class RightClickPlugin: MacToolsPlugin, PluginPrimaryPanel {
    let metadata: PluginMetadata
    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .button,
        menuActionBehavior: .dismissBeforeHandling,
        buttonTitle: "启用"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let localization: PluginLocalization
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "RightClickPlugin"
    )

    init(localization: PluginLocalization = PluginLocalization(bundle: .main)) {
        self.localization = localization
        self.metadata = PluginMetadata(
            id: "right-click",
            title: localization.string("metadata.title", defaultValue: "右键工具"),
            iconName: "contextualmenu.and.cursorarrow",
            iconTint: Color(nsColor: .systemTeal),
            order: 74,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "在 Finder 右键菜单中快速新建文件夹和复制路径"
            )
        )
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: localization.string("panel.subtitle", defaultValue: "打开扩展管理里的 MacTools 开关后即可使用"),
            isOn: true,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    var settingsSections: [PluginSettingsSection] {
        [
            PluginSettingsSection(
                id: "finder-extension",
                title: localization.string("settings.extension.title", defaultValue: "Finder 扩展"),
                description: localization.string(
                    "settings.extension.description",
                    defaultValue: "在系统设置的扩展管理中打开 MacTools 开关；调试版显示为 MacTools Dev。"
                ),
                status: PluginSettingsSection.Status(
                    text: localization.string("settings.extension.status", defaultValue: "需要打开系统开关"),
                    systemImage: "puzzlepiece.extension",
                    tone: .neutral
                ),
                footnote: localization.string(
                    "settings.extension.footnote",
                    defaultValue: "启用后，Finder 右键菜单会显示「新建文件夹」「复制文件名」「复制绝对路径」「复制相对路径」。"
                ),
                buttonTitle: localization.string("settings.extension.button", defaultValue: "打开扩展管理"),
                actionID: RightClickControlID.openExtensionSettings
            )
        ]
    }

    func handleAction(_ action: PluginPanelAction) {
        if case .invokeAction = action {
            openExtensionManagementInterface()
        }
    }

    func handleSettingsAction(id: String) {
        guard id == RightClickControlID.openExtensionSettings else {
            return
        }

        openExtensionManagementInterface()
    }

    private func openExtensionManagementInterface() {
        logger.info("Opening Finder extension management interface")
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
