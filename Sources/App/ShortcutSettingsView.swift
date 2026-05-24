import AppKit
import SwiftUI
import MacToolsPluginKit

private enum ShortcutSettingsLayout {
    static let controlColumnWidth: CGFloat = 128
    static let controlHeight: CGFloat = 48
}

@MainActor
final class ShortcutCaptureController: ObservableObject {
    @Published private(set) var recordingShortcutID: String?

    private var localMonitor: Any?
    private var onCapture: ((ShortcutBinding) -> Void)?

    func toggleRecording(for shortcutID: String, onCapture: @escaping (ShortcutBinding) -> Void) {
        if recordingShortcutID == shortcutID {
            stopRecording()
            return
        }

        startRecording(for: shortcutID, onCapture: onCapture)
    }

    func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        localMonitor = nil
        onCapture = nil
        recordingShortcutID = nil
    }

    private func startRecording(for shortcutID: String, onCapture: @escaping (ShortcutBinding) -> Void) {
        stopRecording()
        recordingShortcutID = shortcutID
        self.onCapture = onCapture

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recordingShortcutID != nil else {
            return event
        }

        let modifiers = ShortcutModifiers.from(event.modifierFlags)

        if event.keyCode == ShortcutKeyCode.escape, modifiers.isEmpty {
            stopRecording()
            return nil
        }

        if let binding = event.shortcutBindingCandidate {
            onCapture?(binding)
        }

        stopRecording()
        return nil
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var pluginHost: PluginHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("键盘快捷键", systemImage: "command")
                        .font(PluginSettingsTheme.Typography.pageTitle)

                    Text("为常用动作配置全局快捷键。编辑后立即生效，必要项不可删除。")
                        .font(PluginSettingsTheme.Typography.pageDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(PluginSettingsTheme.Spacing.cardContent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pluginSettingsCardBackground(.host)

                ShortcutSettingsRowsView(pluginHost: pluginHost, items: pluginHost.shortcutItems)
                .pluginSettingsCardBackground(.host)
            }
            .padding(PluginSettingsTheme.Spacing.pagePadding)
        }
        .background(SettingsStyle.contentBackground)
    }
}

struct ShortcutSettingsRowsView: View {
    @ObservedObject var pluginHost: PluginHost
    let items: [ShortcutSettingsItem]
    @StateObject private var captureController = ShortcutCaptureController()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ShortcutSettingsRow(
                    item: item,
                    isRecording: captureController.recordingShortcutID == item.id,
                    onConfigure: {
                        pluginHost.clearShortcutError(for: item.id)
                        captureController.toggleRecording(for: item.id) { binding in
                            pluginHost.setShortcutBinding(binding, for: item.id)
                        }
                    },
                    onClear: {
                        captureController.stopRecording()
                        pluginHost.clearShortcutError(for: item.id)
                        pluginHost.clearShortcut(for: item.id)
                    },
                    onReset: {
                        captureController.stopRecording()
                        pluginHost.clearShortcutError(for: item.id)
                        pluginHost.resetShortcut(for: item.id)
                    }
                )

                if index < items.count - 1 {
                    PluginSettingsListDivider()
                }
            }
        }
        .onDisappear {
            captureController.stopRecording()
        }
    }
}

private struct ShortcutSettingsRow: View {
    let item: ShortcutSettingsItem
    let isRecording: Bool
    let onConfigure: () -> Void
    let onClear: () -> Void
    let onReset: () -> Void

    private var supportingText: String {
        item.errorMessage ?? item.description
    }

    private var supportingColor: Color {
        item.errorMessage == nil ? .secondary : .red
    }

    private var rowHelpText: String {
        [item.title, supportingText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.title)

                    if item.isRequired {
                        ShortcutStatusBadge(text: "必填")
                    }
                }

                Text(supportingText)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(supportingColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(supportingText)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .help(rowHelpText)

            HStack(alignment: .center, spacing: 10) {
                ShortcutBindingBadge(
                    text: isRecording ? "请按下快捷键" : item.bindingText,
                    isRecording: isRecording
                )
                .frame(width: ShortcutSettingsLayout.controlColumnWidth)

                ShortcutActionGroup(
                    isRecording: isRecording,
                    canClear: item.canClear,
                    canReset: !item.usesDefaultValue,
                    onConfigure: onConfigure,
                    onReset: onReset,
                    onClear: onClear,
                    clearHelp: item.canClear
                        ? "清除快捷键"
                        : (item.isRequired ? "该快捷键不能为空" : "当前没有可清除的快捷键")
                )
                .frame(width: ShortcutSettingsLayout.controlColumnWidth)
            }
        }
        .pluginSettingsListRowPadding(interactive: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShortcutStatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PluginSettingsTheme.Typography.statusBadge)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(SettingsStyle.activeControlBackground)
            )
    }
}

private struct ShortcutActionGroup: View {
    let isRecording: Bool
    let canClear: Bool
    let canReset: Bool
    let onConfigure: () -> Void
    let onReset: () -> Void
    let onClear: () -> Void
    let clearHelp: String

    var body: some View {
        HStack(spacing: 0) {
            ShortcutActionButton(
                systemName: isRecording ? "xmark" : "pencil",
                helpText: isRecording ? "取消录制快捷键" : "编辑快捷键",
                tint: isRecording ? .accentColor : .primary,
                isActive: isRecording,
                action: onConfigure
            )

            ShortcutActionDivider()

            ShortcutActionButton(
                systemName: "arrow.counterclockwise",
                helpText: canReset ? "重置为默认快捷键" : "已是默认快捷键",
                tint: .secondary,
                isDisabled: !canReset,
                action: onReset
            )

            ShortcutActionDivider()

            ShortcutActionButton(
                systemName: "trash",
                helpText: clearHelp,
                tint: .red,
                isDisabled: !canClear,
                action: onClear
            )
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: ShortcutSettingsLayout.controlHeight)
        .pluginSettingsCardBackground(.recessed)
    }
}

private struct ShortcutActionDivider: View {
    var body: some View {
        PluginSettingsListDivider(.vertical)
            .frame(height: 18)
            .padding(.vertical, 5)
    }
}

private struct ShortcutActionButton: View {
    let systemName: String
    let helpText: String
    let tint: Color
    var isDisabled: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(PluginSettingsTheme.Typography.sectionTitle)
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? SettingsStyle.activeControlBackground : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.35) : tint)
        .disabled(isDisabled)
        .help(helpText)
    }
}

private struct ShortcutBindingBadge: View {
    let text: String
    let isRecording: Bool

    private var displayText: String {
        text == "None" ? "未设置" : text
    }

    private var tokens: [String] {
        guard !isRecording, displayText != "未设置" else {
            return []
        }

        return Self.keycapTokens(from: displayText)
    }

    var body: some View {
        badgeContent
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: ShortcutSettingsLayout.controlHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.hostCard, style: .continuous)
                .fill(
                    isRecording
                        ? PluginSettingsTheme.Palette.recordingBackground
                        : PluginSettingsTheme.Palette.fieldBackground
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.hostCard, style: .continuous)
                .strokeBorder(
                    isRecording ? Color.accentColor : PluginSettingsTheme.Palette.cardBorder,
                    lineWidth: isRecording ? 1.5 : PluginSettingsTheme.Stroke.standard
                )
        )
    }

    @ViewBuilder
    private var badgeContent: some View {
        if isRecording {
            Label("请按下快捷键", systemImage: "record.circle.fill")
                .font(PluginSettingsTheme.Typography.controlLabel.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        } else if displayText == "未设置" {
            Text(displayText)
                .font(PluginSettingsTheme.Typography.controlLabel.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            ViewThatFits(in: .horizontal) {
                ShortcutKeycapRow(tokens: tokens, metrics: .regular)
                ShortcutKeycapRow(tokens: tokens, metrics: .compact)
                ShortcutKeycapRow(tokens: tokens, metrics: .compressed)
            }
        }
    }

    private static func keycapTokens(from text: String) -> [String] {
        let separator = " + "
        if text.contains(separator) {
            let components = text
                .components(separatedBy: separator)
                .filter { !$0.isEmpty }
            if !components.isEmpty {
                return components
            }
        }

        let modifierSymbols: Set<Character> = ["⌘", "⌥", "⌃", "⇧"]
        var tokens: [String] = []
        var keyToken = ""

        for character in text {
            if modifierSymbols.contains(character), keyToken.isEmpty {
                tokens.append(String(character))
            } else {
                keyToken.append(character)
            }
        }

        if !keyToken.isEmpty {
            tokens.append(keyToken)
        }

        return tokens.isEmpty ? [text] : tokens
    }
}

private struct ShortcutKeycapRow: View {
    let tokens: [String]
    let metrics: ShortcutKeycapMetrics

    var body: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                ShortcutKeycap(text: token, metrics: metrics)
            }
        }
    }
}

private struct ShortcutKeycapMetrics {
    let singleCharacterFontSize: CGFloat
    let multiCharacterFontSize: CGFloat
    let horizontalPadding: CGFloat
    let multiCharacterHorizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat

    static let regular = ShortcutKeycapMetrics(
        singleCharacterFontSize: 13,
        multiCharacterFontSize: 12,
        horizontalPadding: 8,
        multiCharacterHorizontalPadding: 9,
        verticalPadding: 5,
        cornerRadius: 8,
        spacing: 6
    )

    static let compact = ShortcutKeycapMetrics(
        singleCharacterFontSize: 12,
        multiCharacterFontSize: 11,
        horizontalPadding: 7,
        multiCharacterHorizontalPadding: 7,
        verticalPadding: 4,
        cornerRadius: 7,
        spacing: 5
    )

    static let compressed = ShortcutKeycapMetrics(
        singleCharacterFontSize: 11,
        multiCharacterFontSize: 10,
        horizontalPadding: 6,
        multiCharacterHorizontalPadding: 6,
        verticalPadding: 4,
        cornerRadius: 7,
        spacing: 4
    )
}

private struct ShortcutKeycap: View {
    let text: String
    let metrics: ShortcutKeycapMetrics

    var body: some View {
        Text(text)
            .font(
                .system(
                    size: text.count > 1 ? metrics.multiCharacterFontSize : metrics.singleCharacterFontSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, text.count > 1 ? metrics.multiCharacterHorizontalPadding : metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(PluginSettingsTheme.Palette.keycapBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        PluginSettingsTheme.Palette.cardBorder,
                        lineWidth: PluginSettingsTheme.Stroke.standard
                    )
            )
    }
}
