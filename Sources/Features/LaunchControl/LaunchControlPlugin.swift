import Foundation
import SwiftUI

@MainActor
final class LaunchControlPlugin: FeaturePlugin {
    enum ControlID {
        static let refresh = "launch-control-refresh"
        static let openManager = "launch-control-open-manager"
    }

    let manifest = PluginManifest(
        id: "launch-control",
        title: "启动项",
        iconName: "powerplug",
        iconTint: Color(nsColor: .systemOrange),
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented,
        order: 95,
        defaultDescription: "查看和管理 launchctl 启动项"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let controller: LaunchControlController
    private var isExpanded = false

    init(controller: LaunchControlController = LaunchControlFeature.shared.controller) {
        self.controller = controller
        self.controller.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
    }

    var panelState: PluginPanelState {
        let snapshot = controller.snapshot
        return PluginPanelState(
            subtitle: subtitle(for: snapshot),
            isOn: snapshot.isRefreshing,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? buildDetail(for: snapshot) : nil,
            errorMessage: snapshot.errorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }
    var configuration: PluginConfiguration? {
        PluginConfiguration(description: manifest.defaultDescription) { _ in
            LaunchControlManagerView(controller: self.controller)
        }
    }

    func refresh() {
        if controller.snapshot.items.isEmpty {
            controller.refresh()
        }
    }

    func handlePanelAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID):
            if controlID == ControlID.refresh {
                controller.refresh()
            }
        case .setSwitch,
             .setSelection,
             .setNavigationSelection,
             .clearNavigationSelection,
             .setDate,
             .setSlider:
            break
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    private func buildDetail(for snapshot: LaunchControlSnapshot) -> PluginPanelDetail {
        let refreshControl = PluginPanelControl(
            id: ControlID.refresh,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: snapshot.isRefreshing ? "正在刷新" : "刷新列表",
            actionIconSystemName: "arrow.clockwise",
            isEnabled: !snapshot.isRefreshing
        )

        let openManagerControl = PluginPanelControl(
            id: ControlID.openManager,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: "打开管理器",
            actionIconSystemName: "arrow.up.right.square",
            actionBehavior: .dismissBeforeHandling,
            showsLeadingDivider: true,
            isEnabled: true
        )

        return PluginPanelDetail(primaryControls: [refreshControl, openManagerControl], secondaryPanel: nil)
    }

    private func subtitle(for snapshot: LaunchControlSnapshot) -> String {
        if snapshot.isRefreshing {
            return "正在扫描 LaunchAgent 与 LaunchDaemon"
        }

        if snapshot.items.isEmpty {
            return "打开管理器或刷新后查看启动项"
        }

        let userCreatedCount = snapshot.items.filter { $0.origin == .userCreated }.count
        let runningCount = snapshot.items.filter { $0.state == .running }.count
        return "\(snapshot.items.count) 项 · \(runningCount) 运行中 · \(userCreatedCount) 用户创建"
    }
}
