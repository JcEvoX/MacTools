import AppKit
import SwiftUI

struct ActivityBarComponentView: View {
    private enum Layout {
        static let cornerRadius: CGFloat = 10
        static let cardCornerRadius: CGFloat = 8
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 10
        static let sectionSpacing: CGFloat = 8
        static let iconSize: CGFloat = 26
        static let accentBlue = Color(nsColor: .systemBlue)
        static let aiGreen = Color(red: 0x10 / 255.0, green: 0xA3 / 255.0, blue: 0x7F / 255.0)
    }

    @ObservedObject var controller: ActivityBarController
    @State private var expandedAppName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            inputStatsSection
            divider
            aiSection
            divider
            topAppsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: ActivityBarPanelShape(cornerRadius: Layout.cornerRadius))
        .overlay {
            ActivityBarPanelShape(cornerRadius: Layout.cornerRadius)
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onAppear { controller.refresh() }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("Activity Bar")
                .font(.title3.bold())
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.2))
                    .frame(width: 22, height: 22)

                Text("Today")
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.55))
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.2))
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var inputStatsSection: some View {
        VStack(spacing: Layout.sectionSpacing) {
            HStack(spacing: 10) {
                statCell(
                    icon: "keyboard",
                    value: ActivityBarFormatting.decimal(controller.todayInputStats.keystrokes),
                    label: "Keystrokes"
                )
                statCell(
                    icon: "cursorarrow.click.2",
                    value: ActivityBarFormatting.decimal(controller.todayInputStats.pointerClicks),
                    label: "Clicks"
                )
            }

            HStack(spacing: 10) {
                statCell(
                    icon: "scroll",
                    value: ActivityBarFormatting.decimal(controller.todayInputStats.scrollEvents),
                    label: "Scrolls"
                )
                statCell(
                    icon: "macwindow.on.rectangle",
                    value: ActivityBarFormatting.duration(controller.todayInputStats.screenTimeSeconds),
                    label: "Screen Time"
                )
            }

            if let insightText {
                Text(insightText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Layout.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
    }

    private func statCell(icon: String, value: String, label: String, tint: Color = Layout.accentBlue) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
    }

    private var insightText: String? {
        let stats = controller.todayInputStats

        if stats.keystrokes >= 550 {
            let pages = max(Int((Double(stats.keystrokes) / 550.0).rounded()), 1)
            return "✍️ You typed \(ActivityBarFormatting.decimal(stats.keystrokes)) keys today. That's about writing \(pages) full page\(pages == 1 ? "" : "s")."
        }

        if stats.pointerClicks >= 120 {
            let minutes = max(Int((Double(stats.pointerClicks) * 0.5 / 60.0).rounded()), 1)
            return "🥁 You clicked \(ActivityBarFormatting.decimal(stats.pointerClicks)) times. That's like tapping your desk for about \(minutes) minute\(minutes == 1 ? "" : "s")."
        }

        if !controller.isTrackingEnabled {
            return "Grant Input Monitoring and turn this on to start collecting local stats."
        }

        return nil
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time AI Worked for You")
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.bottom, 2)

            codingToolRow(
                name: "Claude / Cursor / Codex",
                detail: aiDetailText,
                duration: controller.todayCodingStats.durationSeconds,
                tint: Layout.aiGreen
            )
        }
        .padding(.vertical, 8)
    }

    private var aiDetailText: String {
        let wordCount = ActivityBarFormatting.decimal(controller.todayCodingStats.wordCount)
        let toolCount = ActivityBarFormatting.decimal(controller.todayCodingStats.toolCallCount)

        if controller.codingStats.activeSessionCount > 0 {
            return "\(controller.codingStats.activeSessionCount) active · \(wordCount) words · \(toolCount) tools"
        }

        return "\(wordCount) words · \(toolCount) tools"
    }

    private func codingToolRow(name: String, detail: String, duration: TimeInterval, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            Text(ActivityBarFormatting.duration(duration))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Apps by Screen Time")
                .font(.headline)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            let apps = Array(controller.todayInputStats.topApps.prefix(5))
            if apps.isEmpty {
                Text(controller.isTrackingEnabled ? "No activity yet" : "Turn on tracking to rank your apps")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
            } else {
                let maxTime = apps.first?.stats.screenTimeSeconds ?? 1
                ForEach(apps, id: \.name) { app in
                    topAppRow(name: app.name, stats: app.stats, maxScreenTime: maxTime)
                }
                .onAppear {
                    if expandedAppName == nil {
                        expandedAppName = apps.first?.name
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func topAppRow(name: String, stats: ActivityBarAppStats, maxScreenTime: Double) -> some View {
        let isExpanded = expandedAppName == name

        return VStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedAppName = isExpanded ? nil : name
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(ActivityBarFormatting.duration(stats.screenTimeSeconds))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            GeometryReader { geometry in
                let ratio = CGFloat(stats.screenTimeSeconds) / CGFloat(Swift.max(maxScreenTime, 1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Layout.accentBlue.opacity(0.25))
                    .frame(width: geometry.size.width * ratio, height: 3)
            }
            .frame(height: 3)

            if isExpanded {
                HStack(spacing: 16) {
                    appDetailItem(icon: "keyboard", value: ActivityBarFormatting.decimal(stats.keystrokes))
                    appDetailItem(icon: "cursorarrow.click.2", value: ActivityBarFormatting.decimal(stats.pointerClicks))
                    appDetailItem(icon: "scroll", value: ActivityBarFormatting.decimal(stats.scrollEvents))
                }
                .padding(.top, 4)
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func appDetailItem(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.primary.opacity(0.55))
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
                .lineLimit(1)
        }
    }

    private var divider: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}

private struct ActivityBarPanelShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }
}
