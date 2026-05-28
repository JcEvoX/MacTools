import SwiftUI

struct DeviceBatteryComponentView: View {
    private enum Layout {
        static let cardRadius: CGFloat = 16
        static let spacing: CGFloat = 8
    }

    @ObservedObject var viewModel: DeviceBatteryViewModel
    @ObservedObject var store: DeviceBatteryStore
    let isPanelVisible: Bool
    let openSettings: () -> Void

    var body: some View {
        Group {
            if viewModel.snapshot.visibleItems.isEmpty {
                emptyState
            } else {
                switch store.layoutMode {
                case .grid:
                    gridLayout
                case .list:
                    listLayout
                case .showcase:
                    showcaseLayout
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if isPanelVisible {
                viewModel.start(
                    includeInternalBattery: store.showInternalBattery,
                    includeBluetoothDevices: store.showBluetoothDevices,
                    includeRapooDevices: store.showRapooDevices
                )
            }
        }
        .onDisappear { viewModel.stop() }
    }

    private var gridLayout: some View {
        let items = Array(viewModel.snapshot.visibleItems.prefix(6))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Layout.spacing), count: 3),
            spacing: Layout.spacing
        ) {
            ForEach(items) { item in
                DeviceBatteryGridCard(item: item)
                    .frame(minHeight: 84)
            }
        }
    }

    private var listLayout: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.snapshot.visibleItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                DeviceBatteryListRow(item: item)
                if index < min(viewModel.snapshot.visibleItems.count, 5) - 1 {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DeviceBatteryCardBackground(cornerRadius: Layout.cardRadius))
    }

    private var showcaseLayout: some View {
        let items = viewModel.snapshot.visibleItems
        let primaryItem = items.first
        let secondaryItems = Array(items.dropFirst().prefix(3))

        return HStack(spacing: Layout.spacing) {
            if let primaryItem {
                DeviceBatteryShowcaseCard(item: primaryItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: Layout.spacing) {
                ForEach(secondaryItems) { item in
                    DeviceBatteryMiniCard(item: item)
                }

                if secondaryItems.isEmpty {
                    DeviceBatteryMiniSummaryCard(snapshot: viewModel.snapshot)
                }
            }
            .frame(width: 130)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(batteryTint(for: nil).opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: emptyIconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(batteryTint(for: nil))
            }

            VStack(spacing: 3) {
                Text(emptyTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text(emptySubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if viewModel.snapshot.accessState == .permissionDenied {
                Button(action: openSettings) {
                    Label("打开系统设置", systemImage: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeviceBatteryCardBackground(cornerRadius: Layout.cardRadius))
    }

    private var emptyTitle: String {
        switch viewModel.snapshot.accessState {
        case .permissionDenied:
            return "需要输入监控权限"
        case .scanning:
            return "正在读取电量"
        case .failed:
            return "读取失败"
        case .idle, .ready, .noDevices:
            return "暂无设备电量"
        }
    }

    private var emptySubtitle: String {
        switch viewModel.snapshot.accessState {
        case .permissionDenied:
            return "授权后可读取雷柏 HID 上报"
        case .failed(let message):
            return message
        case .scanning:
            return "正在查询系统电源与蓝牙设备"
        case .idle, .ready, .noDevices:
            return "连接蓝牙设备或雷柏 VT 系列鼠标"
        }
    }

    private var emptyIconName: String {
        viewModel.snapshot.accessState.isError ? "exclamationmark.triangle.fill" : "battery.0percent"
    }
}

private struct DeviceBatteryGridCard: View {
    let item: DeviceBatteryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: item.kind.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(batteryTint(for: item))
                    .frame(width: 17, height: 17)

                Text(item.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if item.chargeState == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(batteryTint(for: item))
                }
            }

            Text(item.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(batteryTint(for: item))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                Text(item.chargeState.title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            DeviceBatteryBar(level: item.clampedLevel, tint: batteryTint(for: item))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeviceBatteryCardBackground(cornerRadius: 16))
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryListRow: View {
    let item: DeviceBatteryItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(batteryTint(for: item).opacity(0.12))
                Image(systemName: item.kind.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(batteryTint(for: item))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    Text(item.kind.title)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    DeviceBatteryBar(level: item.clampedLevel, tint: batteryTint(for: item))
                        .frame(maxWidth: 180)

                    Text(item.detail ?? item.chargeState.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(batteryTint(for: item))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: 40)
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryShowcaseCard: View {
    let item: DeviceBatteryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                ZStack {
                    Circle()
                        .fill(batteryTint(for: item).opacity(0.14))
                    Image(systemName: item.kind.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(batteryTint(for: item))
                }
                .frame(width: 44, height: 44)

                Spacer(minLength: 0)

                Text(item.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(item.model ?? item.detail ?? item.source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(batteryTint(for: item))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(item.chargeState.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            DeviceBatteryBar(level: item.clampedLevel, tint: batteryTint(for: item), height: 8)
        }
        .padding(14)
        .background(DeviceBatteryCardBackground(cornerRadius: 16))
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryMiniCard: View {
    let item: DeviceBatteryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(batteryTint(for: item))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                DeviceBatteryBar(level: item.clampedLevel, tint: batteryTint(for: item), height: 5)
            }

            Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(batteryTint(for: item))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeviceBatteryCardBackground(cornerRadius: 16))
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryMiniSummaryCard: View {
    let snapshot: DeviceBatterySnapshot

    var body: some View {
        VStack(spacing: 6) {
            Text("\(snapshot.visibleItems.count)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .monospacedDigit()

            Text("可显示设备")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeviceBatteryCardBackground(cornerRadius: 16))
    }
}

private struct DeviceBatteryBar: View {
    let level: Int?
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(tint.opacity(level == nil ? 0.18 : 0.86))
                    .frame(width: max(height, proxy.size.width * progress))
            }
        }
        .frame(height: height)
    }

    private var progress: CGFloat {
        guard let level else {
            return 0
        }

        return CGFloat(min(max(level, 0), 100)) / 100
    }
}

private struct DeviceBatteryCardBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.44))
    }
}

private func batteryTint(for item: DeviceBatteryItem?) -> Color {
    guard let item else {
        return Color(nsColor: .systemGreen)
    }

    if item.chargeState == .charging || item.chargeState == .charged {
        return Color(nsColor: .systemGreen)
    }

    guard let level = item.clampedLevel else {
        return Color(nsColor: .systemBlue)
    }

    if level <= 20 {
        return Color(nsColor: .systemRed)
    }
    if level <= 35 {
        return Color(nsColor: .systemOrange)
    }
    return Color(nsColor: .systemGreen)
}

private func helpText(for item: DeviceBatteryItem) -> String {
    var lines = [
        item.name,
        "\(DeviceBatteryFormatter.percent(item.clampedLevel)) · \(item.chargeState.title)",
        "来源：\(item.source)"
    ]
    if let parentName = item.parentName {
        lines.append("关联：\(parentName)")
    }
    if let lastUpdated = item.lastUpdated {
        lines.append("更新：\(DeviceBatteryFormatter.time(lastUpdated))")
    }
    return lines.joined(separator: "\n")
}

