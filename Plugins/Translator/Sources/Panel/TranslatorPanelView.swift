import SwiftUI
import MacToolsPluginKit

@MainActor
final class TranslatorPanelModel: ObservableObject {
    @Published var snapshot: TranslatorPanelSnapshot = .idle
}

/// 长期承载 SwiftUI 视图树，仅在 `model.snapshot` 变化时由 SwiftUI 差量更新，
/// 避免每次快照都重建 NSHostingView 而丢失滚动位置与文本选择。
struct TranslatorPanelHostView: View {
    @ObservedObject var model: TranslatorPanelModel
    let localization: PluginLocalization
    let onAction: (TranslatorPanelAction) -> Void

    var body: some View {
        TranslatorPanelView(snapshot: model.snapshot, localization: localization, onAction: onAction)
    }
}

struct TranslatorPanelView: View {
    let snapshot: TranslatorPanelSnapshot
    let localization: PluginLocalization
    let onAction: (TranslatorPanelAction) -> Void

    init(
        snapshot: TranslatorPanelSnapshot,
        localization: PluginLocalization = PluginLocalization(bundle: .main),
        onAction: @escaping (TranslatorPanelAction) -> Void
    ) {
        self.snapshot = snapshot
        self.localization = localization
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 14) {
            sourceCard
            languageRow
            resultCards
        }
        .padding(16)
        .frame(width: 560, height: 560)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(localization.string("panel.source.title", defaultValue: "原文"))
                    .font(.headline)
                Spacer()
                iconButton(
                    "speaker.wave.2",
                    help: localization.string("panel.source.speakHelp", defaultValue: "朗读原文"),
                    action: .speakSource
                )
                    .disabled(sourceTextForDisplay.isEmpty)
                iconButton(
                    "doc.on.doc",
                    help: localization.string("panel.source.copyHelp", defaultValue: "复制原文"),
                    action: .copySource
                )
                    .disabled(sourceTextForDisplay.isEmpty)
                iconButton("xmark", help: localization.string("panel.closeHelp", defaultValue: "关闭"), action: .close)
            }

            ScrollView {
                Text(sourceTextForDisplay.isEmpty ? sourcePlaceholder : sourceTextForDisplay)
                    .font(.body)
                    .foregroundStyle(sourceTextForDisplay.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var languageRow: some View {
        HStack(spacing: 12) {
            languagePill(
                flag: snapshot.languageSelection?.source?.flag ?? "🌐",
                title: snapshot.languageSelection?.source?.displayName(localization: localization)
                    ?? localization.string("language.automatic", defaultValue: "自动检测")
            )

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            languagePill(
                flag: snapshot.languageSelection?.target.flag ?? "🇨🇳",
                title: snapshot.languageSelection?.target.displayName(localization: localization)
                    ?? TranslatorLanguage.simplifiedChinese.displayName(localization: localization)
            )
        }
    }

    private var resultCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(localization.string("panel.result.title", defaultValue: "译文"))
                    .font(.headline)
                if case .translating = snapshot.phase {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                iconButton(
                    "speaker.wave.2",
                    help: localization.string("panel.result.speakHelp", defaultValue: "朗读译文"),
                    action: .speakTranslation
                )
                    .disabled(resultTextForDisplay.isEmpty)
                iconButton(
                    "doc.on.doc",
                    help: localization.string("panel.result.copyHelp", defaultValue: "复制首个译文"),
                    action: .copyTranslation
                )
                    .disabled(resultTextForDisplay.isEmpty)
                iconButton("arrow.clockwise", help: localization.string("panel.retryHelp", defaultValue: "重试"), action: .retry)
                iconButton("gearshape", help: localization.string("panel.settingsHelp", defaultValue: "设置"), action: .openSettings)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let results = providerResultsForDisplay
                    ForEach(results) { result in
                        providerResultCard(result)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, minHeight: 222, maxHeight: 222, alignment: .topLeading)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func providerResultCard(_ result: TranslatorProviderResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(result.providerTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if result.phase == .translating || result.phase == .waiting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                iconButton(
                    "doc.on.doc",
                    help: localization.format(
                        "panel.result.copyProviderHelpFormat",
                        defaultValue: "复制%@译文",
                        result.providerTitle
                    ),
                    action: .copyProviderTranslation(result.id)
                )
                .disabled((result.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(providerResultBodyText(result))
                .font(.body)
                .foregroundStyle(providerResultTextColor(result))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func languagePill(flag: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(flag)
                .font(.title3)
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        action: TranslatorPanelAction
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var sourceTextForDisplay: String {
        snapshot.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var resultTextForDisplay: String {
        snapshot.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var providerResultsForDisplay: [TranslatorProviderResult] {
        if !snapshot.providerResults.isEmpty {
            return snapshot.providerResults
        }

        return [
            TranslatorProviderResult(
                id: "placeholder",
                providerTitle: snapshot.translation?.providerTitle
                    ?? localization.string("openAIClient.providerTitle", defaultValue: "OpenAI 翻译"),
                phase: placeholderProviderPhase,
                translation: snapshot.translation,
                errorMessage: snapshot.errorMessage
            ),
        ]
    }

    private var placeholderProviderPhase: TranslatorProviderResultPhase {
        switch snapshot.phase {
        case .translating:
            return .translating
        case .success:
            return .success
        case .error:
            return .error
        case .idle, .capturing:
            return .waiting
        }
    }

    private var sourcePlaceholder: String {
        switch snapshot.phase {
        case .capturing:
            if let captureStage = snapshot.captureStage {
                switch captureStage {
                case .selectedText:
                    return localization.string("panel.sourcePlaceholder.capturing", defaultValue: "正在读取选中文本...")
                case .screenshotRegion:
                    return localization.string("panel.sourcePlaceholder.screenshotRegion", defaultValue: "正在选择截图区域...")
                case .ocr:
                    return localization.string("panel.sourcePlaceholder.ocr", defaultValue: "正在识别截图文字...")
                }
            }
            return localization.string("panel.sourcePlaceholder.capturing", defaultValue: "正在读取选中文本...")
        case .error(.missingSelection):
            return localization.string("panelError.missingSelection", defaultValue: "未找到选中文本")
        case .error(.missingOCRText):
            return localization.string("panelError.missingOCRText", defaultValue: "截图中没有识别到文字")
        case .error(.permissionRequired):
            return localization.string("panelError.permissionRequired", defaultValue: "需要辅助功能授权")
        case .error(.screenRecordingPermissionRequired):
            return localization.string("panelError.screenRecordingPermissionRequired", defaultValue: "需要屏幕录制授权")
        case .error(.screenshotCancelled):
            return localization.string("panelError.screenshotCancelled", defaultValue: "已取消截图")
        case .error(.screenshotRegionTooSmall):
            return localization.string("panelError.screenshotRegionTooSmall", defaultValue: "截图区域太小")
        case .error(.screenshotFailed):
            return localization.string("panelError.screenshotFailed", defaultValue: "截图失败")
        default:
            return localization.string("panel.sourcePlaceholder.idle", defaultValue: "等待选中文本")
        }
    }

    private func providerResultBodyText(_ result: TranslatorProviderResult) -> String {
        let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }

        switch result.phase {
        case .translating:
            return localization.string("panel.resultPlaceholder.translating", defaultValue: "正在翻译...")
        case .error:
            return result.errorMessage
                ?? localization.string("openAIClient.error.requestFailed", defaultValue: "请求失败，请稍后重试")
        case .waiting:
            return localization.string("panel.resultPlaceholder.idle", defaultValue: "等待翻译")
        case .success:
            return localization.string("panel.resultPlaceholder.emptyResponse", defaultValue: "响应为空")
        }
    }

    private func providerResultTextColor(_ result: TranslatorProviderResult) -> Color {
        if result.phase == .error {
            return .red
        }

        let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? .secondary : .primary
    }
}
