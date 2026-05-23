import SwiftUI
import MacToolsPluginKit

struct XcodeCleanDetailView: View {
    @ObservedObject var controller: XcodeCleanController
    private let showsHeader: Bool
    private let contentPadding: CGFloat
    private let minimumContentHeight: CGFloat

    init(
        controller: XcodeCleanController,
        showsHeader: Bool = true,
        contentPadding: CGFloat = 20,
        minimumContentHeight: CGFloat = 420
    ) {
        self.controller = controller
        self.showsHeader = showsHeader
        self.contentPadding = contentPadding
        self.minimumContentHeight = minimumContentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            if showsHeader {
                header
            }

            if snapshot.isXcodeRunning {
                xcodeRunningBanner
            }

            categoryControls
            actionBar
            scanLog
            statusSummary
            candidateList
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, minHeight: minimumContentHeight, alignment: .topLeading)
    }

    private var snapshot: XcodeCleanSnapshot { controller.snapshot }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Xcode 清理")
                .font(PluginSettingsTheme.Typography.pageTitle)

            Text(snapshot.errorMessage ?? subtitleText)
                .font(PluginSettingsTheme.Typography.pageDescription.weight(.medium))
                .foregroundStyle(snapshot.errorMessage == nil ? Color.secondary : Color.red)
        }
    }

    private var subtitleText: String {
        if snapshot.isXcodeRunning {
            return "请先退出 Xcode，再进行扫描或清理"
        }
        switch snapshot.phase {
        case .idle:
            return "选择需要清理的分类，然后点击扫描"
        case .scanning:
            return "正在扫描…"
        case .scanned:
            if snapshot.isResultStale { return "勾选已更新，请重新扫描" }
            return snapshot.scanResult.map { "已找到 \($0.cleanableCandidates.count) 项可清理" } ?? "扫描完成"
        case .cleaning:
            return "正在清理…"
        case .completed:
            return snapshot.executionResult.map { "已释放 \(byteText($0.reclaimedBytes))" } ?? "清理完成"
        }
    }

    private var xcodeRunningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Xcode 当前正在运行")
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                Text("为避免破坏正在进行的构建或索引，请先退出 Xcode 再使用此功能。")
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
        .padding(.vertical, PluginSettingsTheme.Spacing.rowVertical)
        .pluginSettingsCardBackground(.recessed)
    }

    private var categoryControls: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            Label("清理分类", systemImage: "square.grid.2x2")
                .font(PluginSettingsTheme.Typography.sectionTitle)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(XcodeCleanCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
            .padding(.vertical, PluginSettingsTheme.Spacing.rowVertical)
            .pluginSettingsCardBackground(.host)
        }
    }

    private func categoryRow(_ category: XcodeCleanCategory) -> some View {
        let isSelected = snapshot.selectedCategories.contains(category)
        let summary = snapshot.scanResult?.summary(for: category)
        let sizeText = summary.map { byteText($0.totalBytes) } ?? "—"

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { controller.setCategory(category, isSelected: $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(category.title)
                            .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                        if category.risk == .medium {
                            Text("谨慎")
                                .font(PluginSettingsTheme.Typography.statusBadge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(category.summary)
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(snapshot.isBusy || snapshot.isXcodeRunning)

            Spacer(minLength: 12)

            Text(sizeText)
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                controller.scan()
            } label: {
                Label("扫描", systemImage: "magnifyingglass")
            }
            .disabled(!snapshot.canScan)

            Button {
                controller.cleanSelected(candidateIDs: cleanableCandidateIDs)
            } label: {
                Label("清理", systemImage: "trash")
            }
            .disabled(!snapshot.canClean)

            if snapshot.isBusy {
                Button {
                    controller.cancelCurrentOperation()
                } label: {
                    Label("停止", systemImage: "xmark.circle")
                }
            }

            Spacer()
        }
    }

    private var scanLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("扫描日志")
                    .font(PluginSettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.phase == .scanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if snapshot.scanLogEntries.isEmpty {
                            Text("扫描后这里会显示实时进度")
                                .font(PluginSettingsTheme.Typography.rowDescription)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(snapshot.scanLogEntries) { entry in
                                logRow(entry).id(entry.id)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 118, maxHeight: 160)
                .pluginSettingsCardBackground(.recessed)
                .onChange(of: snapshot.scanLogEntries.last?.id) {
                    guard let id = snapshot.scanLogEntries.last?.id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func logRow(_ entry: XcodeCleanScanLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: logIconName(entry.tone))
                .font(PluginSettingsTheme.Typography.statusBadge)
                .foregroundStyle(logColor(entry.tone))
                .frame(width: 14, height: 14)

            Text(entry.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusSummary: some View {
        if let scanResult = snapshot.scanResult {
            HStack(spacing: 16) {
                summaryTile(title: "可清理", value: "\(scanResult.cleanableCandidates.count) 项")
                summaryTile(title: "预计释放", value: byteText(scanResult.cleanableSizeBytes))
                summaryTile(title: "已保护", value: "\(scanResult.protectedCount) 项")
            }
        }

        if let executionResult = snapshot.executionResult {
            HStack(spacing: 16) {
                summaryTile(title: "已删除", value: "\(executionResult.removedCount) 项")
                summaryTile(title: "已跳过", value: "\(executionResult.skippedCount) 项")
                summaryTile(title: "失败", value: "\(executionResult.failedCount) 项")
                summaryTile(title: "已释放", value: byteText(executionResult.reclaimedBytes))
            }
        }
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
            Text(value)
                .font(PluginSettingsTheme.Typography.pageDescription.weight(.semibold))
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    @ViewBuilder
    private var candidateList: some View {
        if let scanResult = snapshot.scanResult, !scanResult.candidates.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(scanResult.candidates) { candidate in
                        candidateRow(candidate)
                        Divider()
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: XcodeCleanCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: candidate.safety.isCleanable ? "checkmark.circle.fill" : "shield.fill")
                .foregroundStyle(candidate.safety.isCleanable ? Color.green : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(candidate.category.title)
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                    Spacer(minLength: 12)
                    Text(byteText(candidate.sizeBytes))
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                }

                Text(candidate.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(safetyText(candidate.safety))
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(candidate.safety.isCleanable ? Color.green : Color.secondary)
            }
        }
        .padding(.vertical, 9)
    }

    // MARK: - Helpers

    private var cleanableCandidateIDs: Set<XcodeCleanCandidate.ID> {
        Set(snapshot.scanResult?.cleanableCandidates.map(\.id) ?? [])
    }

    private func safetyText(_ safety: XcodeCleanSafetyStatus) -> String {
        switch safety {
        case .allowed:
            return "允许清理"
        case .outsideAllowedRoot:
            return "路径越界保护"
        case .xcodeRunning:
            return "Xcode 运行中"
        case .missing:
            return "路径已不存在"
        }
    }

    private func byteText(_ bytes: Int64) -> String {
        XcodeCleanByteFormatter.string(fromByteCount: bytes)
    }

    private func logIconName(_ tone: XcodeCleanScanLogTone) -> String {
        switch tone {
        case .info: return "circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "shield.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func logColor(_ tone: XcodeCleanScanLogTone) -> Color {
        switch tone {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
