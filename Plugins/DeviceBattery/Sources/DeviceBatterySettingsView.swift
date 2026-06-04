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

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                    ForEach(DeviceBatteryLayoutMode.allCases, id: \.self) { mode in
                        DeviceBatteryLayoutModeButton(
                            mode: mode,
                            isSelected: store.layoutMode == mode,
                            iconSystemName: iconName(for: mode),
                            action: {
                                store.setLayoutMode(mode)
                                onChange()
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PluginSettingsTheme.Spacing.cardContent)
            .pluginSettingsCardBackground(.host)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(systemName: "bolt.horizontal.circle", title: "显示内容")

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
                    title: "厂商 HID 鼠标",
                    description: "读取已适配鼠标的电量、充电状态、设备型号和名称。",
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
            return "list.bullet.rectangle"
        case .list:
            return "gauge.with.dots.needle.67percent"
        }
    }
}

private struct DeviceBatteryLayoutModeButton: View {
    let mode: DeviceBatteryLayoutMode
    let isSelected: Bool
    let iconSystemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                Image(systemName: iconSystemName)
                    .pluginSettingsRowIconStyle(isSelected ? Color.accentColor : Color.primary)

                VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                    Text(mode.title)
                        .font(PluginSettingsTheme.Typography.secondaryLabel.weight(.semibold))
                        .lineLimit(1)

                    Text(mode.subtitle)
                        .font(PluginSettingsTheme.Typography.statusBadge)
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.78) : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PluginSettingsTheme.Size.controlHeight * 2)
            .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.control, style: .continuous)
                .fill(
                    isSelected
                        ? PluginSettingsTheme.Palette.activeControlBackground
                        : PluginSettingsTheme.Palette.recessedControlBackground
                )
        )
    }
}
