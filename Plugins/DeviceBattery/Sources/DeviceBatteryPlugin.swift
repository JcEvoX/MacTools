import AppKit
import SwiftUI
import MacToolsPluginKit

public final class DeviceBatteryPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        DeviceBatteryPluginProvider(context: context)
    }
}

@MainActor
private struct DeviceBatteryPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [DeviceBatteryPlugin(context: context)]
    }
}

@MainActor
final class DeviceBatteryPlugin: MacToolsPlugin, PluginComponentPanel {
    private enum ControlID {
        static let openInputMonitoring = "open-input-monitoring"
    }

    let metadata = PluginMetadata(
        id: "device-battery",
        title: "设备电量",
        iconName: "battery.75percent",
        iconTint: Color(nsColor: .systemGreen),
        order: 20,
        defaultDescription: "查看 Mac、蓝牙外设和雷柏鼠标电量"
    )

    let descriptor = PluginComponentDescriptor(
        span: .fourByTwo
    )

    private let viewModel: DeviceBatteryViewModel
    private let store: DeviceBatteryStore

    convenience init(context: PluginRuntimeContext) {
        self.init(context: context, viewModel: DeviceBatteryViewModel())
    }

    init(
        context: PluginRuntimeContext,
        viewModel: DeviceBatteryViewModel
    ) {
        self.viewModel = viewModel
        self.store = DeviceBatteryStore(storage: context.storage)
    }

    var onStateChange: (() -> Void)? {
        didSet {
            viewModel.onSnapshotChange = onStateChange
        }
    }
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    var componentPanelState: PluginComponentState {
        PluginComponentState(
            subtitle: viewModel.snapshot.subtitle,
            isActive: !viewModel.snapshot.visibleItems.isEmpty,
            isEnabled: true,
            isVisible: true,
            errorMessage: viewModel.snapshot.errorMessage
        )
    }

    var settingsSections: [PluginSettingsSection] {
        [
            PluginSettingsSection(
                id: "sources",
                title: "电量来源",
                description: "读取 macOS 本地电源、蓝牙外设和雷柏 HID 上报。",
                status: sourceSettingsStatus,
                footnote: sourceSettingsFootnote,
                buttonTitle: "打开输入监控设置",
                actionID: ControlID.openInputMonitoring
            )
        ]
    }

    var configuration: PluginConfiguration? {
        PluginConfiguration(description: "选择组件面板布局和需要显示的电量来源。") { [store, viewModel] _ in
            DeviceBatterySettingsView(
                store: store,
                onChange: {
                    viewModel.refresh(
                        includeInternalBattery: store.showInternalBattery,
                        includeBluetoothDevices: store.showBluetoothDevices,
                        includeRapooDevices: store.showRapooDevices
                    )
                }
            )
        }
    }

    func activate(context: PluginRuntimeContext) {
        viewModel.start(
            includeInternalBattery: store.showInternalBattery,
            includeBluetoothDevices: store.showBluetoothDevices,
            includeRapooDevices: store.showRapooDevices
        )
        onStateChange?()
    }

    func deactivate(reason: PluginDeactivationReason) {
        viewModel.stop()
        onStateChange?()
    }

    func refresh() {
        viewModel.refresh(
            includeInternalBattery: store.showInternalBattery,
            includeBluetoothDevices: store.showBluetoothDevices,
            includeRapooDevices: store.showRapooDevices
        )
        onStateChange?()
    }

    func makeView(context: PluginComponentContext) -> AnyView {
        AnyView(
            DeviceBatteryComponentView(
                viewModel: viewModel,
                store: store,
                isPanelVisible: context.isPanelVisible,
                openSettings: openInputMonitoringSettings
            )
        )
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}

    func handleSettingsAction(id: String) {
        if id == ControlID.openInputMonitoring {
            openInputMonitoringSettings()
        }
    }

    func handleShortcutAction(id: String) {}

    private var sourceSettingsStatus: PluginSettingsSection.Status {
        let snapshot = viewModel.snapshot
        if snapshot.rapooState == .permissionDenied {
            return PluginSettingsSection.Status(
                text: "雷柏需授权",
                systemImage: "exclamationmark.triangle.fill",
                tone: .caution
            )
        }

        if snapshot.visibleItems.isEmpty {
            return PluginSettingsSection.Status(
                text: "未检测到",
                systemImage: "battery.0percent",
                tone: .neutral
            )
        }

        return PluginSettingsSection.Status(
            text: "\(snapshot.visibleItems.count) 台设备",
            systemImage: "checkmark.circle.fill",
            tone: .positive
        )
    }

    private var sourceSettingsFootnote: String {
        switch viewModel.snapshot.rapooState {
        case .permissionDenied:
            return "雷柏鼠标通过厂商 HID 接口读取，macOS 可能要求输入监控权限。"
        case .failed(let message):
            return message
        case .idle, .scanning, .waitingForReport, .connected, .noDevice:
            return "系统电池和蓝牙电量来自本机系统信息；雷柏 VT 系列使用专用 HID 监听，不访问网页。"
        }
    }

    private func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
