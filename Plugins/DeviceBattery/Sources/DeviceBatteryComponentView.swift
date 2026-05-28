import SwiftUI

struct DeviceBatteryComponentView: View {
    @ObservedObject var viewModel: DeviceBatteryViewModel
    @ObservedObject var store: DeviceBatteryStore
    let isPanelVisible: Bool
    let openSettings: () -> Void

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                emptyState
            } else {
                switch store.layoutMode {
                case .grid:
                    DeviceBatteryListCard(
                        items: Array(visibleItems.prefix(5)),
                        totalCount: visibleItems.count,
                        rowHeight: DeviceBatteryLayout.listRowHeight(for: min(visibleItems.count, 5))
                    )
                case .list:
                    DeviceBatteryGaugeGrid(
                        items: Array(visibleItems.prefix(8)),
                        totalCount: visibleItems.count
                    )
                case .showcase:
                    DeviceBatteryShowcaseCard(
                        items: Array(visibleItems.prefix(4)),
                        totalCount: visibleItems.count
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var visibleItems: [DeviceBatteryItem] {
        viewModel.snapshot.visibleItems
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
        .frame(maxWidth: .infinity)
        .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    static let ringSpan: CGFloat = 0.78
    static let ringRotation: Double = 129.6

    static func listRowHeight(for itemCount: Int) -> CGFloat {
        switch itemCount {
        case 0...2:
            return 52
        case 3:
            return 46
        case 4:
            return 40
        default:
            return 34
        }
    }

    static func gaugeColumnCount(for itemCount: Int) -> Int {
        switch itemCount {
        case 0...1:
            return 1
        case 2:
            return 2
        case 3:
            return 3
        default:
            return 4
        }
    }

    static func gaugeTileSize(for itemCount: Int) -> CGFloat {
        switch itemCount {
        case 0...2:
            return 68
        case 3...4:
            return 58
        default:
            return 50
        }
    }

    static func gaugeLineWidth(for tileSize: CGFloat) -> CGFloat {
        max(5, tileSize * 0.105)
    }
}

private struct DeviceBatteryListCard: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                DeviceBatteryNativeRow(
                    item: item,
                    rowHeight: rowHeight,
                    showsDetail: rowHeight >= 44
                )

                if index < items.count - 1 {
                    DeviceBatteryDivider()
                }
            }

            if totalCount > items.count {
                DeviceBatteryDivider()
                Text("还有 \(totalCount - items.count) 台设备")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
            }
        }
        .padding(.vertical, DeviceBatteryLayout.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DeviceBatteryGaugeGrid: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                DeviceBatterySingleGaugeCard(item: item)
            } else {
                LazyVGrid(columns: columns, spacing: rowSpacing) {
                    ForEach(items) { item in
                        DeviceBatteryGaugeTile(
                            item: item,
                            tileSize: tileSize,
                            lineWidth: DeviceBatteryLayout.gaugeLineWidth(for: tileSize)
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if totalCount > items.count {
                        Text("+\(totalCount - items.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: tileSize, height: tileSize + 20)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tileSize: CGFloat {
        DeviceBatteryLayout.gaugeTileSize(for: items.count)
    }

    private var rowSpacing: CGFloat {
        items.count > 4 ? 14 : 10
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: tileSize), spacing: items.count > 4 ? 10 : 12),
            count: DeviceBatteryLayout.gaugeColumnCount(for: items.count)
        )
    }
}

private struct DeviceBatteryShowcaseCard: View {
    let items: [DeviceBatteryItem]
    let totalCount: Int

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                DeviceBatterySingleGaugeCard(item: item)
            } else if let primary = items.first {
                HStack(spacing: 12) {
                    DeviceBatteryFeaturedGauge(item: primary)
                        .frame(width: 124)

                    VStack(spacing: 0) {
                        ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { index, item in
                            DeviceBatteryNativeRow(item: item, rowHeight: 38, showsDetail: true, compact: true)

                            if index < items.dropFirst().count - 1 {
                                Divider()
                            }
                        }

                        if totalCount > items.count {
                            Divider()
                            Text("还有 \(totalCount - items.count) 台设备")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 22)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DeviceBatterySingleGaugeCard: View {
    let item: DeviceBatteryItem

    var body: some View {
        DeviceBatteryFeaturedGauge(item: item)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(DeviceBatteryCardBackground(cornerRadius: DeviceBatteryLayout.cornerRadius))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DeviceBatteryFeaturedGauge: View {
    let item: DeviceBatteryItem

    var body: some View {
        VStack(spacing: 6) {
            DeviceBatteryGaugeTile(
                item: item,
                tileSize: 104,
                lineWidth: 10,
                iconSize: 44,
                percentSize: 17
            )
            .frame(width: 114, height: 126)

            Text(item.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryGaugeTile: View {
    let item: DeviceBatteryItem
    let tileSize: CGFloat
    let lineWidth: CGFloat
    var iconSize: CGFloat? = nil
    var percentSize: CGFloat? = nil

    var body: some View {
        ZStack {
            DeviceBatteryRing(
                item: item,
                size: tileSize,
                lineWidth: lineWidth
            )

            Image(systemName: deviceSymbolName(for: item))
                .font(.system(size: iconSize ?? tileSize * 0.38, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: tileSize * 0.62, height: tileSize * 0.58)
                .offset(y: -tileSize * 0.06)

            if let symbolName = chargingSymbolName(for: item) {
                Image(systemName: symbolName)
                    .font(.system(size: max(11, tileSize * 0.18), weight: .bold))
                    .foregroundStyle(batteryTint(for: item))
                    .offset(y: -tileSize * 0.56)
            }

            Text(DeviceBatteryFormatter.percent(item.clampedLevel))
                .font(.system(size: percentSize ?? max(10, tileSize * 0.19), weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .offset(y: tileSize * 0.45)
        }
        .frame(width: tileSize, height: tileSize + 22)
        .compositingGroup()
        .help(helpText(for: item))
    }
}

private struct DeviceBatteryRing: View {
    let item: DeviceBatteryItem
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: DeviceBatteryLayout.ringSpan)
                .stroke(
                    Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

            Circle()
                .trim(from: 0, to: DeviceBatteryLayout.ringSpan * progress)
                .stroke(
                    batteryTint(for: item),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
        }
        .rotationEffect(.degrees(DeviceBatteryLayout.ringRotation))
        .frame(width: size, height: size)
        .accessibilityLabel("\(item.name)，\(DeviceBatteryFormatter.percent(item.clampedLevel))")
    }

    private var progress: CGFloat {
        CGFloat(item.clampedLevel ?? 0) / 100
    }
}

private struct DeviceBatteryDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, DeviceBatteryLayout.horizontalPadding + DeviceBatteryLayout.rowIconWidth + 12)
            .padding(.trailing, DeviceBatteryLayout.horizontalPadding)
    }
}

private struct DeviceBatteryNativeRow: View {
    let item: DeviceBatteryItem
    let rowHeight: CGFloat
    var showsDetail = false
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: deviceSymbolName(for: item))
                .font(.system(size: iconSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: DeviceBatteryLayout.rowIconWidth, height: rowHeight)

            VStack(alignment: .leading, spacing: showsDetail ? 1 : 0) {
                Text(item.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)

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
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(item.clampedLevel ?? 100 <= 10 ? Color(nsColor: .systemRed) : .primary)
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

    private var titleSize: CGFloat {
        rowHeight >= 44 ? 13.5 : 12.5
    }

    private var iconSize: CGFloat {
        rowHeight >= 44 ? 22 : 19
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
        if haystack.contains("iphone") || haystack.contains("手机") {
            return "iphone"
        }
        if haystack.contains("ipad") || haystack.contains("平板") {
            return "ipad"
        }
        if haystack.contains("watch") || haystack.contains("手表") {
            return "applewatch"
        }
        if haystack.contains("macbook") || haystack.contains("mac book") {
            return "laptopcomputer"
        }
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
