import SwiftUI

struct DeviceBatteryComponentView: View {
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
                    DeviceBatteryNativeList(
                        items: gridItems,
                        totalCount: viewModel.snapshot.visibleItems.count,
                        rowHeight: DeviceBatteryLayout.nativeRowHeight(for: gridItems.count),
                        showsDetail: gridItems.count == 1,
                        featuredSingle: gridItems.count == 1
                    )
                case .list:
                    DeviceBatteryNativeList(
                        items: Array(viewModel.snapshot.visibleItems.prefix(5)),
                        totalCount: viewModel.snapshot.visibleItems.count,
                        rowHeight: 34,
                        showsDetail: true
                    )
                case .showcase:
                    DeviceBatteryFeaturedList(
                        items: Array(viewModel.snapshot.visibleItems.prefix(4)),
                        totalCount: viewModel.snapshot.visibleItems.count
                    )
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

    private var gridItems: [DeviceBatteryItem] {
        Array(viewModel.snapshot.visibleItems.prefix(3))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.snapshot.accessState.isError ? "exclamationmark.triangle" : "battery.0percent")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.snapshot.accessState.isError ? Color(nsColor: .systemOrange) : Color.secondary)

            Text(emptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(emptySubtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

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
        .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
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
}

private enum DeviceBatteryLayout {
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let rowIconWidth: CGFloat = 34
    static let percentWidth: CGFloat = 48
    static let batteryWidth: CGFloat = 34

    static func nativeRowHeight(for itemCount: Int) -> CGFloat {
        switch itemCount {
        case 1:
            return 164
        case 2:
            return 84
        default:
            return 54
        }
    }

    static func showcasePrimaryHeight(for itemCount: Int) -> CGFloat {
        itemCount == 1 ? 164 : 72
    }
}

private struct DeviceBatteryNativeList: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int
    let rowHeight: CGFloat
    let showsDetail: Bool
    var featuredSingle = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                DeviceBatteryNativeRow(
                    item: item,
                    rowHeight: rowHeight,
                    showsDetail: showsDetail,
                    isFeatured: featuredSingle
                )

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, DeviceBatteryLayout.horizontalPadding + DeviceBatteryLayout.rowIconWidth + 12)
                }
            }

            if totalCount > items.count {
                Divider()
                    .padding(.leading, DeviceBatteryLayout.horizontalPadding + DeviceBatteryLayout.rowIconWidth + 12)
                Text("还有 \(totalCount - items.count) 台设备")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
            }
        }
        .padding(.vertical, DeviceBatteryLayout.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
    }
}

private struct DeviceBatteryFeaturedList: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int

    var body: some View {
        VStack(spacing: 0) {
            if let primary = items.first {
                DeviceBatteryNativeRow(
                    item: primary,
                    rowHeight: DeviceBatteryLayout.showcasePrimaryHeight(for: items.count),
                    showsDetail: items.count == 1,
                    isFeatured: true
                )
            }

            ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { index, item in
                Divider()
                    .padding(.leading, DeviceBatteryLayout.horizontalPadding + DeviceBatteryLayout.rowIconWidth + 12)
                DeviceBatteryNativeRow(item: item, rowHeight: 36, showsDetail: true)

                if index == items.dropFirst().count - 1, totalCount > items.count {
                    Divider()
                        .padding(.leading, DeviceBatteryLayout.horizontalPadding + DeviceBatteryLayout.rowIconWidth + 12)
                    Text("还有 \(totalCount - items.count) 台设备")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                }
            }
        }
        .padding(.vertical, DeviceBatteryLayout.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
    }
}

private struct DeviceBatteryNativeRow: View {
    let item: DeviceBatteryItem
    let rowHeight: CGFloat
    var showsDetail = false
    var isFeatured = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceSymbolName(for: item))
                .font(.system(size: usesProminentMetrics ? 24 : 21, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: DeviceBatteryLayout.rowIconWidth, height: rowHeight)

            VStack(alignment: .leading, spacing: usesProminentMetrics ? 3 : 1) {
                Text(item.name)
                    .font(.system(size: usesProminentMetrics ? 14.5 : 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(rowHeight >= 110 ? 2 : 1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)

                if showsDetail {
                    Text(deviceDetailText(for: item))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                .font(.system(size: usesProminentMetrics ? 14.5 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: DeviceBatteryLayout.percentWidth, alignment: .trailing)

            DeviceBatterySystemBattery(item: item)
                .frame(width: DeviceBatteryLayout.batteryWidth, height: 16)
        }
        .padding(.horizontal, DeviceBatteryLayout.horizontalPadding)
        .frame(height: rowHeight)
        .help(helpText(for: item))
    }

    private var usesProminentMetrics: Bool {
        isFeatured || rowHeight >= 70
    }
}

private struct DeviceBatterySystemBattery: View {
    let item: DeviceBatteryItem

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(0.36), lineWidth: 1.1)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(batteryTint(for: item))
                    .frame(width: fillWidth, height: 9)
                    .padding(.leading, 2)
                    .opacity(item.clampedLevel == nil ? 0.2 : 0.92)

                if let symbolName = chargingSymbolName(for: item) {
                    Image(systemName: symbolName)
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 28, height: 14)

            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .fill(Color.primary.opacity(0.36))
                .frame(width: 2.4, height: 6)
        }
    }

    private var fillWidth: CGFloat {
        guard let level = item.clampedLevel else {
            return 3
        }
        return max(3, 24 * CGFloat(level) / 100)
    }
}

private struct DeviceBatteryCardBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.045))
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

private func chargingSymbolName(for item: DeviceBatteryItem) -> String? {
    switch item.chargeState {
    case .charging, .charged:
        return "bolt.fill"
    case .plugged:
        return "powerplug.fill"
    case .unknown, .normal, .invalid:
        return nil
    }
}

private func deviceDetailText(for item: DeviceBatteryItem) -> String {
    if let detail = item.detail, !detail.isEmpty {
        return detail
    }
    if let model = item.model, !model.isEmpty, model != item.name {
        return model
    }
    return item.chargeState.title == "正常" ? "已连接" : item.chargeState.title
}

private func deviceSymbolName(for item: DeviceBatteryItem) -> String {
    let haystack = [
        item.name,
        item.model,
        item.detail,
        item.parentName,
        item.kind.title
    ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

    switch item.kind {
    case .internalBattery:
        return "laptopcomputer"
    case .rapooMouse:
        return "computermouse.fill"
    case .airPodsPart:
        if haystack.contains("case") || haystack.contains("充电盒") {
            return "airpods.chargingcase"
        }
        return "airpodspro"
    case .bluetooth, .magicAccessory, .other:
        if haystack.contains("mouse") || haystack.contains("鼠标") || haystack.contains("mx anywhere") || haystack.contains("mx master") {
            return "computermouse.fill"
        }
        if haystack.contains("keyboard") || haystack.contains("键盘") {
            return "keyboard"
        }
        if haystack.contains("trackpad") || haystack.contains("触控板") {
            return "rectangle.and.hand.point.up.left.fill"
        }
        if haystack.contains("airpods") {
            return "airpodspro"
        }
        if haystack.contains("beats") || haystack.contains("headphone") || haystack.contains("耳机") {
            return "headphones"
        }
        return item.kind.iconName
    }
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
