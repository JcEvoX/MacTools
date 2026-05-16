import Foundation
import AppKit
import SwiftUI
import OSLog

/// 剪贴板清空插件
@MainActor
final class ClipboardClearPlugin: FeaturePlugin {
    static let pluginID = "ClipboardClear"
    static let pluginOrder: Int = 120

    private let pasteboard = NSPasteboard.general
    private var canClearClipboard = false

    let manifest: PluginManifest = .init(
        id: ClipboardClearPlugin.pluginID,
        title: "清空剪贴板",
        iconName: "trash",
        iconTint: .accentColor,
        controlStyle: .button,
        menuActionBehavior: .dismissBeforeHandling,
        order: ClipboardClearPlugin.pluginOrder,
        defaultDescription: "一键清空当前剪贴板内容",
        buttonTitle: "清空"
    )

    init() {
        canClearClipboard = Self.hasClipboardContents(in: pasteboard)
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }
    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    var panelState: PluginPanelState {
        PluginPanelState(
            subtitle: manifest.defaultDescription,
            isOn: false,
            isExpanded: false,
            isEnabled: canClearClipboard,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    func handlePanelAction(_ action: PluginPanelAction) {
        if case .invokeAction(let controlID) = action, controlID == "execute" {
            pasteboard.clearContents()
            syncPasteboardState(forceNotify: true)
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.mactools", category: "ClipboardClearPlugin").info("剪贴板已清空")
        }
    }

    func refresh() {
        syncPasteboardState(forceNotify: false)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState { PluginPermissionState(isGranted: false, footnote: nil) }
    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    private func syncPasteboardState(forceNotify: Bool) {
        let hasContents = Self.hasClipboardContents(in: pasteboard)
        let didChange = canClearClipboard != hasContents
        canClearClipboard = hasContents

        if forceNotify || didChange {
            onStateChange?()
        }
    }

    nonisolated private static func hasClipboardContents(in pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return false
        }

        return items.contains { !$0.types.isEmpty }
    }
}




