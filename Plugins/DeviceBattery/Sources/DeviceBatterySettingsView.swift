import SwiftUI
import MacToolsPluginKit

struct DeviceBatterySettingsView: View {
    @ObservedObject var store: DeviceBatteryStore
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            layoutSection
            sourceSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(systemName: "rectangle.grid.2x2", title: "组件布局")

            HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                ForEach(DeviceBatteryLayoutMode.allCases, id: \.self) { mode in
                    Button {
                        store.setLayoutMode(mode)
                        onChange()
                    } label: {
                        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                            HStack(spacing: 6) {
                                Image(systemName: iconName(for: mode))
                                    .frame(width: 16)
                                Text(mode.title)
                                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                            }
                            Text(mode.subtitle)
                                .font(PluginSettingsTheme.Typography.rowDescription)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
                        .padding(.vertical, PluginSettingsTheme.Spacing.interactiveRowVertical)
                        .contentShape(RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(store.layoutMode == mode ? Color.accentColor : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.card, style: .continuous)
                            .fill(store.layoutMode == mode ? Color.accentColor.opacity(0.12) : PluginSettingsTheme.Palette.recessedControlBackground)
                    )
                }
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(systemName: "bolt.horizontal.circle", title: "电量来源")

            VStack(spacing: 0) {
                sourceToggle(
                    title: "Mac 内置电池",
                    description: "显示本机电量、充电状态和剩余时间。",
                    isOn: store.showInternalBattery,
                    isFirst: true,
                    action: store.setShowInternalBattery
                )
                sourceToggle(
                    title: "蓝牙与 Apple 外设",
                    description: "读取系统可见的蓝牙设备、AirPods 分体电量和 Magic 外设。",
                    isOn: store.showBluetoothDevices,
                    action: store.setShowBluetoothDevices
                )
                sourceToggle(
                    title: "雷柏 VT 鼠标",
                    description: "监听雷柏厂商 HID 接口，支持已确认的 VT 系列 Product ID。",
                    isOn: store.showRapooDevices,
                    isLast: true,
                    action: store.setShowRapooDevices
                )
            }
            .pluginSettingsCardBackground(.plugin)
        }
    }

    private func sourceToggle(
        title: String,
        description: String,
        isOn: Bool,
        isFirst: Bool = false,
        isLast: Bool = false,
        action: @escaping (Bool) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            if !isFirst {
                Divider()
                    .padding(.leading, PluginSettingsTheme.Spacing.rowHorizontal)
            }

            HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                    Text(title)
                        .font(PluginSettingsTheme.Typography.rowTitle)
                    Text(description)
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: {
                        action($0)
                        onChange()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
            .padding(.vertical, PluginSettingsTheme.Spacing.interactiveRowVertical)
        }
    }

    private func sectionHeader(systemName: String, title: String) -> some View {
        Label {
            Text(title)
                .font(PluginSettingsTheme.Typography.sectionTitle)
        } icon: {
            Image(systemName: systemName)
        }
        .foregroundStyle(.secondary)
    }

    private func iconName(for mode: DeviceBatteryLayoutMode) -> String {
        switch mode {
        case .grid:
            return "square.grid.2x2"
        case .list:
            return "list.bullet"
        case .showcase:
            return "rectangle.inset.filled"
        }
    }
}

