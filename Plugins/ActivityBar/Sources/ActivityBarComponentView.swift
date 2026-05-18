import SwiftUI

struct ActivityBarComponentView: View {
    @ObservedObject var controller: ActivityBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(spacing: 8) {
                metricCard(
                    title: "按键",
                    value: ActivityBarFormatting.count(controller.todayInputStats.keystrokes),
                    systemImage: "keyboard"
                )
                metricCard(
                    title: "点击",
                    value: ActivityBarFormatting.count(controller.todayInputStats.pointerClicks),
                    systemImage: "cursorarrow.click"
                )
                metricCard(
                    title: "滚动",
                    value: ActivityBarFormatting.count(controller.todayInputStats.scrollEvents),
                    systemImage: "scroll"
                )
                metricCard(
                    title: "前台",
                    value: ActivityBarFormatting.duration(controller.todayInputStats.screenTimeSeconds),
                    systemImage: "macwindow"
                )
            }

            HStack(spacing: 8) {
                summaryCard(
                    title: "AI 活动",
                    primary: ActivityBarFormatting.duration(controller.todayCodingStats.durationSeconds),
                    secondary: "\(ActivityBarFormatting.count(controller.todayCodingStats.wordCount)) 词 · \(ActivityBarFormatting.count(controller.todayCodingStats.toolCallCount)) 工具"
                )
                summaryCard(
                    title: "最活跃应用",
                    primary: controller.todayInputStats.topApps.first?.name ?? "暂无",
                    secondary: topAppSecondaryText
                )
            }
        }
        .padding(10)
        .onAppear {
            controller.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("活动统计")
                    .font(.headline)
                    .lineLimit(1)
                Text(controller.isTrackingEnabled ? "今日概览" : "未开启统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Circle()
                .fill(controller.isTrackingEnabled ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
    }

    private var topAppSecondaryText: String {
        guard let topApp = controller.todayInputStats.topApps.first else {
            return "开启后自动记录"
        }

        return "\(ActivityBarFormatting.duration(topApp.stats.screenTimeSeconds)) · \(ActivityBarFormatting.count(topApp.stats.totalInputs)) 次输入"
    }

    private func metricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 12)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func summaryCard(title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(primary)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
