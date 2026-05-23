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
final class IPOverviewPlugin: MacToolsPlugin, PluginPrimaryPanel {
    enum ControlID {
        static let refresh = "ip-overview-refresh"
        static let copyIP = "ip-overview-copy-ip"
        static let copyReport = "ip-overview-copy-report"
        static let openDetails = "ip-overview-open-details"
    }

    let metadata = PluginMetadata(
        id: "ip-overview",
        title: "IP 概览",
        iconName: "network",
        iconTint: Color(nsColor: .systemBlue),
        order: 12,
        defaultDescription: "查看公网 IP、本地地址和归属地"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    private let viewModel: IPOverviewViewModel
    private var isExpanded = false

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

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: viewModel.isRefreshingAll,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? panelDetail : nil,
            errorMessage: viewModel.snapshot.errorMessage
        )
    }

    var configuration: PluginConfiguration? {
        PluginConfiguration(
            description: metadata.defaultDescription,
            prefersFullHeight: true
        ) { _ in
            IPOverviewComponentView(
                viewModel: self.viewModel,
                startsInDetails: true,
                showsBackButton: false
            )
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID):
            handleInvoke(controlID: controlID)
        case .setSwitch,
             .setSelection,
             .setNavigationSelection,
             .clearNavigationSelection,
             .setDate,
             .setSlider:
            break
        }
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

    private var panelDetail: PluginPanelDetail {
        PluginPanelDetail(primaryControls: [
            PluginPanelControl(
                id: ControlID.refresh,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: viewModel.isRefreshingAll ? "刷新中..." : "刷新全部检测",
                actionIconSystemName: "arrow.clockwise",
                isEnabled: !viewModel.isRefreshingAll
            ),
            PluginPanelControl(
                id: ControlID.copyIP,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: "复制公网 IP",
                actionIconSystemName: "doc.on.doc",
                showsLeadingDivider: true,
                isEnabled: viewModel.snapshot.preferredPublicIP != nil
            ),
            PluginPanelControl(
                id: ControlID.copyReport,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: "复制完整结果",
                actionIconSystemName: "doc.on.clipboard",
                isEnabled: viewModel.snapshot.lastUpdated != nil
            ),
            PluginPanelControl(
                id: ControlID.openDetails,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: "打开详情",
                actionIconSystemName: "arrow.up.right.square",
                actionBehavior: .dismissBeforeHandling,
                showsLeadingDivider: true,
                isEnabled: true
            )
        ], secondaryPanel: nil)
    }

    private func handleInvoke(controlID: String) {
        switch controlID {
        case ControlID.refresh:
            viewModel.refreshAll()
        case ControlID.copyIP:
            viewModel.copy(viewModel.snapshot.preferredPublicIP?.ip)
        case ControlID.copyReport:
            viewModel.copy(viewModel.snapshot.reportText)
        default:
            break
        }
    }
}
