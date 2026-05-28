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
                    DeviceBatteryRingGrid(items: Array(viewModel.snapshot.visibleItems.prefix(8)))
                case .list:
                    DeviceBatteryCompactList(
                        items: Array(viewModel.snapshot.visibleItems.prefix(6)),
                        totalCount: viewModel.snapshot.visibleItems.count,
                        snapshot: viewModel.snapshot
                    )
                case .showcase:
                    DeviceBatteryShowcaseLayout(
                        items: Array(viewModel.snapshot.visibleItems.prefix(6)),
                        totalCount: viewModel.snapshot.visibleItems.count,
                        snapshot: viewModel.snapshot
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            DeviceBatteryGauge(
                item: nil,
                size: 60,
                lineWidth: 7,
                showsPercentInside: false
            )

            VStack(spacing: 3) {
                Text(emptyTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(emptySubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
        .background(DeviceBatteryPanelBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
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
    static let padding: CGFloat = 10
    static let spacing: CGFloat = 8
    static let tightSpacing: CGFloat = 6
}

private struct DeviceBatteryRingGrid: View {
    let items: [DeviceBatteryItem]

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                DeviceBatterySingleOverview(item: item, compact: true)
            } else {
                GeometryReader { proxy in
                    let columns = columnCount(for: items.count)
                    let rows = rowCount(itemCount: items.count, columns: columns)
                    let compact = items.count > 4
                    let ringSize = ringSize(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        columns: columns,
                        rows: rows,
                        compact: compact
                    )

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 0), spacing: DeviceBatteryLayout.spacing),
                            count: columns
                        ),
                        spacing: compact ? DeviceBatteryLayout.tightSpacing : DeviceBatteryLayout.spacing
                    ) {
                        ForEach(items) { item in
                            DeviceBatteryRingTile(
                                item: item,
                                ringSize: ringSize,
                                compact: compact
                            )
                            .frame(maxWidth: .infinity, minHeight: compact ? 70 : 78)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .padding(DeviceBatteryLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeviceBatteryPanelBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
    }

    private func columnCount(for count: Int) -> Int {
        if count <= 2 {
            return max(count, 1)
        }
        if count <= 4 {
            return 2
        }
        return 4
    }

    private func rowCount(itemCount: Int, columns: Int) -> Int {
        max(1, (itemCount + columns - 1) / columns)
    }

    private func ringSize(width: CGFloat, height: CGFloat, columns: Int, rows: Int, compact: Bool) -> CGFloat {
        let horizontalSpace = CGFloat(max(columns - 1, 0)) * DeviceBatteryLayout.spacing
        let verticalSpace = CGFloat(max(rows - 1, 0)) * (compact ? DeviceBatteryLayout.tightSpacing : DeviceBatteryLayout.spacing)
        let cellWidth = (width - horizontalSpace) / CGFloat(max(columns, 1))
        let cellHeight = (height - verticalSpace) / CGFloat(max(rows, 1))
        let labelSpace: CGFloat = compact ? 18 : 34
        let maximum: CGFloat = compact ? 48 : (columns == 1 ? 92 : (columns == 2 && rows == 1 ? 78 : 62))
        let candidate = min(min(cellWidth * 0.72, cellHeight - labelSpace), maximum)
        return max(compact ? 38 : 48, candidate)
    }
}

private struct DeviceBatteryShowcaseLayout: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int
    let snapshot: DeviceBatterySnapshot

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                DeviceBatterySingleOverview(item: item, compact: false)
            } else if let primary = items.first {
                HStack(spacing: 10) {
                    DeviceBatteryPrimaryMeter(item: primary)
                        .frame(width: 112)

                    VStack(alignment: .leading, spacing: 4) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.dropFirst().prefix(5).enumerated()), id: \.element.id) { index, item in
                                DeviceBatteryCompactRow(item: item, rowHeight: 31, showsBatteryIcon: false, showsDetail: false)
                                if index < min(items.dropFirst().count, 5) - 1 {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }

                        if totalCount > items.count {
                            Text("还有 \(totalCount - items.count) 台设备")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(DeviceBatteryLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeviceBatteryPanelBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
    }
}

private struct DeviceBatteryCompactList: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int
    let snapshot: DeviceBatterySnapshot

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                DeviceBatterySingleOverview(item: item, compact: false)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(snapshot.subtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer(minLength: 0)

                        if let lastUpdated = snapshot.lastUpdated {
                            Text(DeviceBatteryFormatter.time(lastUpdated))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .frame(height: 16)

                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            DeviceBatteryCompactRow(item: item, rowHeight: 27, showsBatteryIcon: true, showsDetail: true)
                            if index < items.count - 1 {
                                Divider()
                                    .padding(.leading, 34)
                            }
                        }
                    }

                    if totalCount > items.count {
                        Text("还有 \(totalCount - items.count) 台设备")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .padding(DeviceBatteryLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeviceBatteryPanelBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
    }
}

private struct DeviceBatterySingleOverview: View {
    let item: DeviceBatteryItem
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 12 : 14) {
            DeviceBatteryGauge(
                item: item,
                size: compact ? 96 : 108,
                lineWidth: compact ? 9 : 10,
                showsPercentInside: false
            )
            .frame(width: compact ? 104 : 116)

            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                Text(item.name)
                    .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                        .font(.system(size: compact ? 35 : 40, weight: .bold, design: .rounded))
                        .foregroundStyle(batteryTint(for: item))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if chargingSymbolName(for: item) != nil {
                        Image(systemName: chargingSymbolName(for: item)!)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(batteryTint(for: item))
                    }
                }

                DeviceBatteryBar(level: item.clampedLevel, tint: batteryTint(for: item), height: 7)
                    .frame(maxWidth: 138)

                Text(deviceDetailText(for: item))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryPrimaryMeter: View {
    let item: DeviceBatteryItem

    var body: some View {
        VStack(spacing: 5) {
            DeviceBatteryGauge(item: item, size: 82, lineWidth: 8, showsPercentInside: false)

            Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(batteryTint(for: item))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(item.name)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryRingTile: View {
    let item: DeviceBatteryItem
    let ringSize: CGFloat
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            DeviceBatteryGauge(
                item: item,
                size: ringSize,
                lineWidth: compact ? 5.5 : 7,
                showsPercentInside: compact
            )

            if !compact {
                Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(batteryTint(for: item))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

            }

            Text(item.name)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryCompactRow: View {
    let item: DeviceBatteryItem
    let rowHeight: CGFloat
    let showsBatteryIcon: Bool
    let showsDetail: Bool

    var body: some View {
        HStack(spacing: 8) {
            DeviceBatteryIconBubble(item: item)
                .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)

                if showsDetail {
                    Text(deviceDetailText(for: item))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(batteryTint(for: item))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if showsBatteryIcon {
                DeviceBatteryInlineBattery(item: item)
                    .frame(width: 34, height: 15)
            }
        }
        .frame(height: rowHeight)
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryGauge: View {
    let item: DeviceBatteryItem?
    let size: CGFloat
    let lineWidth: CGFloat
    let showsPercentInside: Bool

    private let ringSpan: CGFloat = 0.78

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: ringSpan)
                .stroke(
                    Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(129))

            Circle()
                .trim(from: 0, to: ringSpan * progress)
                .stroke(
                    batteryTint(for: item).opacity(item?.clampedLevel == nil ? 0.24 : 0.95),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(129))

            VStack(spacing: max(1, size * 0.03)) {
                Image(systemName: item?.kind.iconName ?? "battery.0percent")
                    .font(.system(size: size * (showsPercentInside ? 0.26 : 0.34), weight: .semibold))
                    .foregroundStyle(item == nil ? Color.secondary : Color.primary.opacity(0.72))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: size * 0.48, height: size * 0.38)

                if showsPercentInside {
                    Text(DeviceBatteryFormatter.percent(item?.clampedLevel))
                        .font(.system(size: max(9, size * 0.2), weight: .bold, design: .rounded))
                        .foregroundStyle(batteryTint(for: item))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(width: size * 0.72)
                }
            }

            if let item,
               let symbolName = chargingSymbolName(for: item) {
                Image(systemName: symbolName)
                    .font(.system(size: max(10, size * 0.16), weight: .bold))
                    .foregroundStyle(batteryTint(for: item))
                    .padding(2)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor).opacity(0.9)))
                    .offset(x: size * 0.24, y: -size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(item.map { "\($0.name)，\(DeviceBatteryFormatter.percent($0.clampedLevel))" } ?? "暂无设备电量")
    }

    private var progress: CGFloat {
        guard let level = item?.clampedLevel else {
            return 0
        }
        return CGFloat(level) / 100
    }
}

private struct DeviceBatteryIconBubble: View {
    let item: DeviceBatteryItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(batteryTint(for: item).opacity(0.12))

            Image(systemName: item.kind.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(batteryTint(for: item))
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct DeviceBatteryInlineBattery: View {
    let item: DeviceBatteryItem

    var body: some View {
        HStack(spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.primary.opacity(0.28), lineWidth: 1.1)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(batteryTint(for: item))
                        .frame(
                            width: max(3, (proxy.size.width - 4) * progress),
                            height: max(4, proxy.size.height - 5)
                        )
                        .padding(.leading, 2)
                        .opacity(item.clampedLevel == nil ? 0.18 : 0.95)

                    if let symbolName = chargingSymbolName(for: item) {
                        Image(systemName: symbolName)
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: 29, height: 13)

            RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                .fill(Color.primary.opacity(0.28))
                .frame(width: 2.5, height: 6)
        }
    }

    private var progress: CGFloat {
        guard let level = item.clampedLevel else {
            return 0
        }
        return CGFloat(level) / 100
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
                    .fill(Color.primary.opacity(0.09))

                Capsule()
                    .fill(tint.opacity(level == nil ? 0.18 : 0.9))
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

private struct DeviceBatteryPanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.48))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 0.8)
            )
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
