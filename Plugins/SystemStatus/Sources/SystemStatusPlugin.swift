import AppKit
import SwiftUI
import MacToolsPluginKit

public final class SystemStatusPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        SystemStatusPluginProvider(context: context)
    }
}

@MainActor
private struct SystemStatusPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [SystemStatusPlugin(localization: PluginLocalization(bundle: context.resourceBundle))]
    }
}

@MainActor
final class SystemStatusPlugin: MacToolsPlugin, PluginComponentPanel {
    let metadata: PluginMetadata

    let descriptor = PluginComponentDescriptor(
        span: PluginComponentSpan(
            width: 4,
            height: PluginComponentPanelLayoutMetrics.default.heightSpan(closestToOriginalSpanHeight: 2)
        )!
    )

    private let viewModel: SystemStatusViewModel
    private let localization: PluginLocalization

    init(
        viewModel: SystemStatusViewModel? = nil,
        localization: PluginLocalization = PluginLocalization(bundle: .main)
    ) {
        self.viewModel = viewModel
            ?? SystemStatusViewModel(sampler: SystemStatusSampler(localization: localization))
        self.localization = localization
        self.metadata = PluginMetadata(
            id: "system-status",
            title: localization.string("metadata.title", defaultValue: "系统状态"),
            iconName: "gauge.with.dots.needle.67percent",
            iconTint: Color(nsColor: .systemTeal),
            order: 10,
            defaultDescription: localization.string("metadata.description", defaultValue: "实时查看系统状态")
        )
    }

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    var componentPanelState: PluginComponentState {
        PluginComponentState(
            subtitle: metadata.defaultDescription,
            isActive: false,
            isEnabled: true,
            isVisible: true,
            errorMessage: nil
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func makeView(context: PluginComponentContext) -> AnyView {
        AnyView(
            SystemStatusComponentView(
                viewModel: viewModel,
                isPanelVisible: context.isPanelVisible,
                localization: localization
            )
        )
    }

    func refresh() {}

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}
}

@MainActor
final class SystemStatusViewModel: ObservableObject {
    @Published private(set) var snapshot = SystemStatusSnapshot.empty

    private let sampler: any SystemStatusSampling
    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    private var publicIPTask: Task<Void, Never>?
    private var publicIPAddress: String?

    init(sampler: any SystemStatusSampling = SystemStatusSampler()) {
        self.sampler = sampler
    }

    func start() {
        guard fastTask == nil, slowTask == nil, processTask == nil, publicIPTask == nil else {
            return
        }

        fastTask = Task { @MainActor [weak self] in
            await self?.runFastSamplingLoop()
        }
        slowTask = Task { @MainActor [weak self] in
            await self?.runSlowSamplingLoop()
        }
        processTask = Task { @MainActor [weak self] in
            await self?.runProcessSamplingLoop()
        }
        publicIPTask = Task { @MainActor [weak self] in
            await self?.runPublicIPSamplingLoop()
        }
    }

    func stop() {
        fastTask?.cancel()
        slowTask?.cancel()
        processTask?.cancel()
        publicIPTask?.cancel()
        fastTask = nil
        slowTask = nil
        processTask = nil
        publicIPTask = nil
    }

    private func runFastSamplingLoop() async {
        while !Task.isCancelled {
            let sample = await sampler.collectFast(referenceDate: Date())
            guard !Task.isCancelled else { return }
            snapshot.cpu = sample.cpu
            snapshot.memory = sample.memory
            snapshot.network = sample.network.replacingPublicIPAddress(publicIPAddress)

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    private func runSlowSamplingLoop() async {
        while !Task.isCancelled {
            let sample = await sampler.collectSlow()
            guard !Task.isCancelled else { return }
            snapshot.disk = sample.disk
            snapshot.battery = sample.battery

            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
        }
    }

    private func runProcessSamplingLoop() async {
        while !Task.isCancelled {
            let processes = await sampler.collectTopProcesses(limit: 3)
            guard !Task.isCancelled else { return }
            snapshot.topProcesses = await Self.resolveApplicationNames(for: processes)

            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
        }
    }

    private func runPublicIPSamplingLoop() async {
        while !Task.isCancelled {
            if let publicIPAddress = await sampler.collectPublicIPAddress() {
                guard !Task.isCancelled else { return }
                self.publicIPAddress = publicIPAddress
                snapshot.network = snapshot.network.replacingPublicIPAddress(publicIPAddress)
            }

            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        }
    }

    private static func resolveApplicationNames(for processes: [SystemStatusTopProcess]) async -> [SystemStatusTopProcess] {
        processes.map { process in
            guard
                let application = NSRunningApplication(processIdentifier: pid_t(process.pid)),
                let localizedName = application.localizedName,
                !localizedName.isEmpty
            else {
                return process
            }

            return process.replacingDisplayName(localizedName)
        }
    }
}

struct SystemStatusComponentView: View {
    private enum Layout {
        static let spacing = SystemStatusComponentLayout.cardSpacing
    }

    @ObservedObject var viewModel: SystemStatusViewModel
    let isPanelVisible: Bool
    let localization: PluginLocalization

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = max(0, (proxy.size.height - Layout.spacing) / 2)

            VStack(spacing: Layout.spacing) {
                HStack(spacing: Layout.spacing) {
                    compactCPUCard
                    compactMemoryCard
                    compactDiskCard
                    compactBatteryCard
                }
                .frame(height: rowHeight)

                HStack(spacing: Layout.spacing) {
                    networkCard
                    topProcessesCard
                }
                .frame(height: rowHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if isPanelVisible {
                viewModel.start()
            }
        }
        .onDisappear { viewModel.stop() }
    }

    private var compactCPUCard: some View {
        let cpu = viewModel.snapshot.cpu
        return SystemStatusCompactMetricCard(
            title: SystemStatusMetricKind.cpu.title(localization: localization),
            percentText: cpu.isCollecting ? "--" : SystemStatusFormatter.percent(cpu.usage),
            detailLines: [
                localization.format(
                    "metric.temperatureFormat",
                    defaultValue: "温度 %@",
                    SystemStatusFormatter.temperature(cpu.temperatureCelsius)
                ),
                localization.format(
                    "metric.powerFormat",
                    defaultValue: "功率 %@",
                    SystemStatusFormatter.power(cpu.systemPowerWatts)
                )
            ],
            progress: cpu.usage
        )
    }

    private var compactMemoryCard: some View {
        let memory = viewModel.snapshot.memory
        return SystemStatusCompactMetricCard(
            title: SystemStatusMetricKind.memory.title(localization: localization),
            percentText: SystemStatusFormatter.percent(memory.usage),
            detailLines: [
                localization.format(
                    "metric.usedFormat",
                    defaultValue: "已用 %@",
                    SystemStatusFormatter.bytes(memory.usedBytes)
                ),
                localization.format(
                    "metric.totalFormat",
                    defaultValue: "总量 %@",
                    SystemStatusFormatter.bytes(memory.totalBytes)
                )
            ],
            progress: memory.usage
        )
    }

    private var compactDiskCard: some View {
        let disk = viewModel.snapshot.disk
        return SystemStatusCompactMetricCard(
            title: SystemStatusMetricKind.disk.title(localization: localization),
            percentText: SystemStatusFormatter.percent(disk.usage),
            detailLines: [
                localization.format(
                    "metric.usedFormat",
                    defaultValue: "已用 %@",
                    SystemStatusFormatter.bytes(disk.usedBytes)
                ),
                localization.format(
                    "metric.totalFormat",
                    defaultValue: "总量 %@",
                    SystemStatusFormatter.bytes(disk.totalBytes)
                )
            ],
            progress: disk.usage
        )
    }

    private var compactBatteryCard: some View {
        let battery = viewModel.snapshot.battery
        return SystemStatusCompactMetricCard(
            title: SystemStatusMetricKind.battery.title(localization: localization),
            percentText: battery.isAvailable ? SystemStatusFormatter.percent(battery.level) : "--",
            detailLines: [
                localization.format(
                    "metric.temperatureFormat",
                    defaultValue: "温度 %@",
                    SystemStatusFormatter.temperature(battery.temperatureCelsius)
                ),
                batteryHealthText(for: battery)
            ],
            progress: battery.level,
            centerSubtext: batteryCircleStatusText(for: battery),
            centerHelpText: batteryShortText(for: battery)
        )
    }

    private var networkCard: some View {
        let network = viewModel.snapshot.network
        return SystemStatusWideInfoCard(
            title: SystemStatusMetricKind.network.title(localization: localization),
            iconName: "wifi",
            tint: Color(nsColor: .systemCyan),
            headerLeadingPadding: 4
        ) {
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 2) {
                    SystemStatusNetworkSpeedRow(
                        iconName: "arrow.down",
                        value: SystemStatusFormatter.speed(network.downloadBytesPerSecond),
                        tint: Color(nsColor: .systemBlue)
                    )
                    SystemStatusNetworkSpeedRow(
                        iconName: "arrow.up",
                        value: SystemStatusFormatter.speed(network.uploadBytesPerSecond),
                        tint: Color(nsColor: .systemGreen)
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    SystemStatusKeyValueLine(
                        label: localization.string("network.publicIP", defaultValue: "公网"),
                        value: network.publicIPAddress
                            ?? localization.string("network.publicIP.collecting", defaultValue: "获取中"),
                        copyValue: network.publicIPAddress,
                        localization: localization
                    )
                    SystemStatusKeyValueLine(
                        label: localization.string("network.localIP", defaultValue: "内网"),
                        value: network.ipAddress ?? "—",
                        copyValue: network.ipAddress,
                        localization: localization
                    )
                }
            }
        }
    }

    private var topProcessesCard: some View {
        SystemStatusTopProcessesCard(
            processes: Array(viewModel.snapshot.topProcesses.prefix(3)),
            localization: localization
        )
    }

    private func batteryShortText(for battery: SystemStatusBatterySnapshot) -> String {
        guard battery.isAvailable else {
            return battery.state.title(localization: localization)
        }

        if battery.state == .charged {
            return localization.string("battery.state.charged", defaultValue: "已充满")
        }

        if let adapterWatts = battery.adapterWatts, battery.state == .charging || battery.state == .acPower {
            return localization.format(
                "battery.stateWithWattsFormat",
                defaultValue: "%@ %dW",
                battery.state.title(localization: localization),
                adapterWatts
            )
        }

        return SystemStatusFormatter.timeRemaining(minutes: battery.timeRemainingMinutes, localization: localization)
    }

    private func batteryHealthText(for battery: SystemStatusBatterySnapshot) -> String {
        guard let healthPercent = battery.healthPercent else {
            return localization.string("battery.healthUnavailable", defaultValue: "健康度 —")
        }

        return localization.format("battery.healthFormat", defaultValue: "健康度 %d%%", healthPercent)
    }

    private func batteryCircleStatusText(for battery: SystemStatusBatterySnapshot) -> String? {
        guard battery.isAvailable else {
            return nil
        }

        switch battery.state {
        case .charging, .charged, .acPower, .unplugged:
            return battery.state.title(localization: localization)
        case .unavailable, .unknown:
            return nil
        }
    }
}

private enum SystemStatusCircleStyle {
    static let tint = Color(nsColor: .systemBlue)
}

private struct SystemStatusCompactMetricCard: View {
    let title: String
    let percentText: String
    let detailLines: [String]
    let progress: Double?
    var centerSubtext: String? = nil
    var centerHelpText: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SystemStatusCircularProgress(value: progress, tint: SystemStatusCircleStyle.tint)
                    .frame(width: 58, height: 58)

                VStack(spacing: centerSubtext == nil ? 1 : 0) {
                    Text(title)
                        .font(.system(size: centerSubtext == nil ? 9 : 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(percentText)
                        .font(.system(size: centerSubtext == nil ? 12 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let centerSubtext {
                        Text(centerSubtext)
                            .font(.system(size: 6.8, weight: .semibold, design: .rounded))
                            .foregroundStyle(SystemStatusCircleStyle.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                }
                .padding(.horizontal, 5)
                .help(centerHelpText ?? "")
            }

            Spacer(minLength: 5)

            VStack(spacing: 1) {
                ForEach(Array(detailLines.prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .help(detailLines.joined(separator: "\n"))
        }
        .padding(SystemStatusComponentLayout.cardContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SystemStatusCardBackground(cornerRadius: SystemStatusComponentLayout.cardCornerRadius))
    }
}
private struct SystemStatusWideInfoCard<Content: View>: View {
    let title: String
    let iconName: String
    let tint: Color
    var headerLeadingPadding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14, height: 14)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, headerLeadingPadding)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(SystemStatusComponentLayout.cardContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(SystemStatusCardBackground(cornerRadius: SystemStatusComponentLayout.cardCornerRadius))
    }
}

private enum SystemStatusNetworkRowLayout {
    static let leadingColumnWidth: CGFloat = 22
    static let columnSpacing: CGFloat = 5
}

private struct SystemStatusNetworkSpeedRow: View {
    let iconName: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: SystemStatusNetworkRowLayout.columnSpacing) {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: SystemStatusNetworkRowLayout.leadingColumnWidth, alignment: .center)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SystemStatusKeyValueLine: View {
    let label: String
    let value: String
    let copyValue: String?
    let localization: PluginLocalization

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: SystemStatusNetworkRowLayout.columnSpacing) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: SystemStatusNetworkRowLayout.leadingColumnWidth, alignment: .center)

            Text(value)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .help(value)
                .layoutPriority(1)

            if canCopy {
                Button(action: copyToPasteboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .disabled(!isHovering)
                .help(localization.format("network.copyIPHelpFormat", defaultValue: "复制%@ IP", label))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering = $0 }
    }

    private var canCopy: Bool {
        guard let copyValue else {
            return false
        }

        return !copyValue.isEmpty
    }

    private func copyToPasteboard() {
        guard let copyValue, !copyValue.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyValue, forType: .string)
    }
}

private struct SystemStatusTopProcessesCard: View {
    let processes: [SystemStatusTopProcess]
    let localization: PluginLocalization

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if processes.isEmpty {
                Text(localization.string("topProcesses.collecting", defaultValue: "采集中…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 4) {
                    ForEach(processes) { process in
                        SystemStatusProcessRow(process: process)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(SystemStatusComponentLayout.cardContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(SystemStatusCardBackground(cornerRadius: SystemStatusComponentLayout.cardCornerRadius))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemPink))
                .frame(width: 14, height: 14)

            Text(SystemStatusMetricKind.topProcesses.title(localization: localization))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            SystemStatusProcessMetricHeader()
                .layoutPriority(1)
        }
    }
}

private struct SystemStatusProcessMetricHeader: View {
    var body: some View {
        HStack(spacing: SystemStatusProcessRow.metricColumnSpacing) {
            Text("CPU")
                .frame(width: SystemStatusProcessRow.cpuColumnWidth, alignment: .trailing)
            Text("MEM")
                .frame(width: SystemStatusProcessRow.memoryColumnWidth, alignment: .trailing)
        }
        .font(.system(size: 7.5, weight: .bold, design: .rounded))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SystemStatusProcessRow: View {
    static let cpuColumnWidth: CGFloat = 28
    static let memoryColumnWidth: CGFloat = 26
    static let metricColumnSpacing: CGFloat = 1

    let process: SystemStatusTopProcess

    var body: some View {
        HStack(spacing: 4) {
            Text(process.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(process.displayName)

            Spacer(minLength: 1)

            HStack(spacing: Self.metricColumnSpacing) {
                metricText(SystemStatusFormatter.wholePercent(process.cpuPercent, fractionDigits: 0))
                    .frame(width: Self.cpuColumnWidth, alignment: .trailing)
                metricText(SystemStatusFormatter.wholePercent(process.memoryPercent, fractionDigits: 0))
                    .frame(width: Self.memoryColumnWidth, alignment: .trailing)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
private struct SystemStatusCircularProgress: View {
    let value: Double?
    let tint: Color

    private var clampedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 4)

            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(
                    tint.opacity(value == nil ? 0.22 : 0.86),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct SystemStatusCardBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.045))
    }
}
