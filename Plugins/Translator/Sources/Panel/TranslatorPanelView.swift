import SwiftUI

@MainActor
final class TranslatorPanelModel: ObservableObject {
    @Published var snapshot: TranslatorPanelSnapshot = .idle
}

/// 长期承载 SwiftUI 视图树，仅在 `model.snapshot` 变化时由 SwiftUI 差量更新，
/// 避免每次快照都重建 NSHostingView 而丢失滚动位置与文本选择。
struct TranslatorPanelHostView: View {
    @ObservedObject var model: TranslatorPanelModel
    let onAction: (TranslatorPanelAction) -> Void

    var body: some View {
        TranslatorPanelView(snapshot: model.snapshot, onAction: onAction)
    }
}

struct TranslatorPanelView: View {
    let snapshot: TranslatorPanelSnapshot
    let onAction: (TranslatorPanelAction) -> Void

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
                Text("原文")
                    .font(.headline)
                Spacer()
                iconButton("speaker.wave.2", help: "朗读原文", action: .speakSource)
                    .disabled(sourceTextForDisplay.isEmpty)
                iconButton("doc.on.doc", help: "复制原文", action: .copySource)
                    .disabled(sourceTextForDisplay.isEmpty)
                iconButton("xmark", help: "关闭", action: .close)
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
                title: snapshot.languageSelection?.source?.displayName ?? "自动检测"
            )

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            languagePill(
                flag: snapshot.languageSelection?.target.flag ?? "🇨🇳",
                title: snapshot.languageSelection?.target.displayName ?? "简体中文"
            )
        }
    }

    private var resultCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("译文")
                    .font(.headline)
                if case .translating = snapshot.phase {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                iconButton("speaker.wave.2", help: "朗读译文", action: .speakTranslation)
                    .disabled(resultTextForDisplay.isEmpty)
                iconButton("doc.on.doc", help: "复制首个译文", action: .copyTranslation)
                    .disabled(resultTextForDisplay.isEmpty)
                iconButton("arrow.clockwise", help: "重试", action: .retry)
                iconButton("gearshape", help: "设置", action: .openSettings)
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
                    help: "复制\(result.providerTitle)译文",
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
                providerTitle: snapshot.translation?.providerTitle ?? "OpenAI 翻译",
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
            return "正在读取选中文本..."
        case .error(.missingSelection):
            return "未找到选中文本"
        case .error(.permissionRequired):
            return "需要辅助功能授权"
        default:
            return "等待选中文本"
        }
    }

    private func providerResultBodyText(_ result: TranslatorProviderResult) -> String {
        let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }

        switch result.phase {
        case .translating:
            return "正在翻译..."
        case .error:
            return result.errorMessage ?? "请求失败，请稍后重试"
        case .waiting:
            return "等待翻译"
        case .success:
            return "响应为空"
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
