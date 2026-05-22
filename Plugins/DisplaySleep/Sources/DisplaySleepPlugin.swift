import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class DisplaySleepPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        DisplaySleepPluginProvider()
    }
}

@MainActor
private struct DisplaySleepPluginProvider: PluginProvider {
    func makePlugins() -> [any MacToolsPlugin] {
        [DisplaySleepPlugin()]
    }
}

@MainActor
final class DisplaySleepPlugin: MacToolsPlugin, PluginPrimaryPanel {
    let metadata = PluginMetadata(
        id: "display-sleep",
        title: "显示器休眠",
        iconName: "display",
        iconTint: Color(nsColor: .systemIndigo),
        order: 97,
        defaultDescription: "立即让显示器休眠"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .button,
        menuActionBehavior: .dismissBeforeHandling,
        buttonTitle: "休眠"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "DisplaySleepPlugin"
    )

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

    func handleAction(_ action: PluginPanelAction) {
        guard case let .invokeAction(controlID) = action, controlID == "execute" else {
            return
        }

        sleepDisplays()
    }

    private func sleepDisplays() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]

        do {
            try task.run()
            logger.info("Requested display sleep via pmset")
        } catch {
            logger.error("Failed to invoke pmset displaysleepnow: \(error.localizedDescription)")
        }
    }
}
