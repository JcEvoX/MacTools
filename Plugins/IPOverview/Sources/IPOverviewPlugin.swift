import AppKit
import Foundation
import SwiftUI
import MacToolsPluginKit

public final class IPOverviewPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        IPOverviewPluginProvider(context: context)
    }
}

@MainActor
private struct IPOverviewPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [IPOverviewPlugin(context: context)]
    }
}

@MainActor
final class IPOverviewPlugin: MacToolsPlugin, PluginComponentPanel {
    let metadata = PluginMetadata(
        id: "ip-overview",
        title: "IP 概览",
        iconName: "network",
        iconTint: Color(nsColor: .systemBlue),
        order: 12,
        defaultDescription: "查看公网 IP、本地地址和归属地"
    )

    var descriptor: PluginComponentDescriptor {
        PluginComponentDescriptor(
            span: viewModel.isShowingDetails ? PluginComponentSpan(width: 4, height: 8)! : .fourByTwo
        )
    }

    private let viewModel: IPOverviewViewModel

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "ip-overview"),
        viewModel: IPOverviewViewModel? = nil
    ) {
        self.viewModel = viewModel ?? IPOverviewViewModel(storage: context.storage)
        self.viewModel.onSnapshotChange = { [weak self] in
            self?.onStateChange?()
        }
    }

    func activate(context: PluginRuntimeContext) {
        viewModel.refreshIfNeeded()
    }

    func deactivate(reason: PluginDeactivationReason) {
        viewModel.cancel()
    }

    func refresh() {
        viewModel.refreshAll()
    }

    var componentPanelState: PluginComponentState {
        PluginComponentState(
            subtitle: panelSubtitle,
            isActive: viewModel.snapshot.preferredPublicIP != nil,
            isEnabled: true,
            isVisible: true,
            errorMessage: viewModel.snapshot.errorMessage
        )
    }

    func makeView(context: PluginComponentContext) -> AnyView {
        AnyView(
            IPOverviewComponentView(viewModel: viewModel)
        )
    }

    private var panelSubtitle: String {
        let snapshot = viewModel.snapshot
        if snapshot.isRefreshing {
            return "正在检测公网 IP..."
        }

        if let ip = snapshot.preferredPublicIP?.ip {
            return ip
        }

        if let errorMessage = snapshot.errorMessage {
            return errorMessage
        }

        return metadata.defaultDescription
    }
}
