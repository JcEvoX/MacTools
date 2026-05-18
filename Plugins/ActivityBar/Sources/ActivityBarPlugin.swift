import AppKit
import SwiftUI
import MacToolsPluginKit

public final class ActivityBarPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        ActivityBarPluginProvider(context: context)
    }
}

@MainActor
private struct ActivityBarPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [ActivityBarPlugin(context: context)]
    }
}

@MainActor
final class ActivityBarPlugin: MacToolsPlugin, PluginPrimaryPanel, PluginComponentPanel {
    private enum ControlID {
        static let installHooks = "install-hooks"
        static let resetToday = "reset-today"
        static let openInputMonitoring = "open-input-monitoring"
    }

    let metadata = PluginMetadata(
        id: ActivityBarController.pluginID,
        title: "活动统计",
        iconName: "chart.bar.xaxis",
        iconTint: Color(nsColor: .systemGreen),
        order: 18,
        defaultDescription: "统计输入、前台应用使用时长和 AI 编程活动"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    let descriptor = PluginComponentDescriptor(span: .fourByTwo)

    private let controller: ActivityBarController

    var onStateChange: (() -> Void)? {
        didSet {
            controller.onStateChange = onStateChange
        }
    }
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    init(
        context: PluginRuntimeContext,
        controller: ActivityBarController? = nil
    ) {
        self.controller = controller ?? ActivityBarController(context: context)
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: controller.panelSubtitle,
            isOn: controller.isTrackingEnabled,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: panelDetail,
            errorMessage: controller.lastErrorMessage
        )
    }

    var componentPanelState: PluginComponentState {
        PluginComponentState(
            subtitle: controller.componentSubtitle,
            isActive: controller.isTrackingEnabled,
            isEnabled: true,
            isVisible: true,
            errorMessage: controller.lastErrorMessage
        )
    }

    var settingsSections: [PluginSettingsSection] {
        [
            PluginSettingsSection(
                id: "input-monitoring",
                title: "输入监控",
                description: "用于统计键盘、鼠标点击和滚动事件。",
                status: inputMonitoringSettingsStatus,
                footnote: controller.inputMonitoringFootnote,
                buttonTitle: "打开系统设置",
                actionID: ControlID.openInputMonitoring
            ),
            PluginSettingsSection(
                id: "ai-hooks",
                title: "AI 工具 Hook",
                description: "记录 Claude Code、Cursor 和 Codex 的提示、工具调用与执行时长。",
                status: hookSettingsStatus,
                footnote: controller.hookInstallFootnote,
                buttonTitle: "安装或更新 Hook",
                actionID: ControlID.installHooks
            )
        ]
    }

    func activate(context: PluginRuntimeContext) {
        controller.activate(context: context)
    }

    func deactivate(reason: PluginDeactivationReason) {
        controller.deactivate(reason: reason)
    }

    func refresh() {
        controller.refresh()
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setSwitch(isEnabled):
            controller.setTrackingEnabled(isEnabled)
        case let .invokeAction(controlID):
            handleAction(controlID: controlID)
        case .setDisclosureExpanded, .setSelection, .setNavigationSelection,
             .clearNavigationSelection, .setDate, .setSlider:
            return
        }
    }

    func makeView(context: PluginComponentContext) -> AnyView {
        AnyView(ActivityBarComponentView(controller: controller))
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}

    func handleSettingsAction(id: String) {
        handleAction(controlID: id)
    }

    func handleShortcutAction(id: String) {}

    private var panelDetail: PluginPanelDetail {
        let openSettingsControl = PluginPanelControl(
            id: ControlID.openInputMonitoring,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: "打开输入监控设置",
            actionIconSystemName: "keyboard.badge.eye",
            isEnabled: true
        )

        let installHooksControl = PluginPanelControl(
            id: ControlID.installHooks,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: "安装或更新 AI Hook",
            actionIconSystemName: "terminal",
            isEnabled: true
        )

        let resetControl = PluginPanelControl(
            id: ControlID.resetToday,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: "清空今日统计",
            actionIconSystemName: "arrow.counterclockwise",
            showsLeadingDivider: true,
            isEnabled: true
        )

        return PluginPanelDetail(
            primaryControls: [openSettingsControl, installHooksControl, resetControl],
            secondaryPanel: nil
        )
    }

    private var inputMonitoringSettingsStatus: PluginSettingsSection.Status {
        switch controller.monitorStatus {
        case .running:
            return PluginSettingsSection.Status(
                text: "运行中",
                systemImage: "checkmark.circle.fill",
                tone: .positive
            )
        case .inputMonitoringDenied:
            return PluginSettingsSection.Status(
                text: "需要授权",
                systemImage: "exclamationmark.triangle.fill",
                tone: .caution
            )
        case .idle:
            return PluginSettingsSection.Status(
                text: "未开启",
                systemImage: "pause.circle",
                tone: .neutral
            )
        }
    }

    private var hookSettingsStatus: PluginSettingsSection.Status {
        if controller.hookStatusMessage?.hasPrefix("已安装") == true {
            return PluginSettingsSection.Status(
                text: "已安装",
                systemImage: "checkmark.circle.fill",
                tone: .positive
            )
        }

        if controller.hookStatusMessage == "安装失败" {
            return PluginSettingsSection.Status(
                text: "安装失败",
                systemImage: "exclamationmark.triangle.fill",
                tone: .caution
            )
        }

        return PluginSettingsSection.Status(
            text: "未安装",
            systemImage: "terminal",
            tone: .neutral
        )
    }

    private func handleAction(controlID: String) {
        switch controlID {
        case ControlID.installHooks:
            controller.installHooks()
        case ControlID.resetToday:
            controller.resetToday()
        case ControlID.openInputMonitoring:
            controller.openInputMonitoringSettings()
        default:
            break
        }
    }
}
