import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MacToolsPluginKit

// MARK: - Shortcut Recorder Display State

@MainActor
final class ShortcutRecorderDisplayState: ObservableObject {
    @Published var previewText = "按下录制快捷键"
    @Published private(set) var showEscHint = false
    @Published private(set) var conflictMessage: String? = nil
    @Published private(set) var shakeOffset: CGFloat = 0
    @Published private(set) var isShaking = false

    func triggerShake(conflict: String? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            showEscHint = true
            if let conflict { conflictMessage = conflict }
        }
        isShaking = true
        let steps: [(CGFloat, Double)] = [
            (10, 0.00), (-8, 0.06), (7, 0.12), (-5, 0.18), (3, 0.24), (0, 0.30)
        ]
        for (offset, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(.linear(duration: 0.05)) {
                    self?.shakeOffset = offset
                }
            }
        }
        // 晃动动画结束后恢复背景色
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
            self?.isShaking = false
        }
    }
}

// MARK: - Shortcut Recorder Popover View

private struct ShortcutRecorderPopoverView: View {
    @ObservedObject var displayState: ShortcutRecorderDisplayState

    var body: some View {
        VStack(spacing: 0) {
            Text(displayState.previewText)
                .font(PluginSettingsTheme.Typography.secondaryLabel)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, PluginSettingsTheme.Spacing.rowContentControl)
                .padding(.vertical, PluginSettingsTheme.Spacing.controlCluster)
                .frame(minWidth: 130, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous)
                        .fill(displayState.isShaking
                              ? Color.red.opacity(0.18)
                              : PluginSettingsTheme.Palette.recordingBackground)
                )
                .offset(x: displayState.shakeOffset)

            if displayState.conflictMessage != nil || displayState.showEscHint {
                Group {
                    if let msg = displayState.conflictMessage {
                        Text(msg)
                            .foregroundStyle(.red)
                    } else {
                        Text("按下 ESC 退出录制")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(PluginSettingsTheme.Typography.statusBadge)
                .padding(.top, PluginSettingsTheme.Spacing.controlCluster)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -6)),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
        .padding(.vertical, PluginSettingsTheme.Spacing.rowContentControl)
        .frame(minWidth: 160)
    }
}

// MARK: - Shortcut Recorder Presenter (NSViewRepresentable)

private struct ShortcutRecorderPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    /// 录制成功时调用；返回 nil 表示提交成功，返回字符串表示冲突原因。
    let validateAndCommit: (ShortcutBinding) -> String?
    var onBeginRecording: (() -> Void)? = nil
    var onEndRecording: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            sourceView: nsView,
            validateAndCommit: validateAndCommit,
            onDismiss: { isPresented = false },
            onBeginRecording: onBeginRecording,
            onEndRecording: onEndRecording
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?
        private var displayState: ShortcutRecorderDisplayState?
        private var keyMonitor: Any?
        private var committed = false
        private var validateAndCommit: ((ShortcutBinding) -> String?)?
        private var onDismiss: (() -> Void)?
        private var onBeginRecording: (() -> Void)?
        private var onEndRecording: (() -> Void)?

        func update(
            isPresented: Bool,
            sourceView: NSView,
            validateAndCommit: @escaping (ShortcutBinding) -> String?,
            onDismiss: @escaping () -> Void,
            onBeginRecording: (() -> Void)?,
            onEndRecording: (() -> Void)?
        ) {
            self.validateAndCommit = validateAndCommit
            self.onDismiss = onDismiss
            self.onBeginRecording = onBeginRecording
            self.onEndRecording = onEndRecording

            if isPresented, popover == nil {
                guard sourceView.window != nil else { return }
                present(from: sourceView)
            } else if !isPresented, popover != nil {
                close()
            }
        }

        func close() {
            guard let pop = popover else { return }
            let dismiss = onDismiss
            let endRecording = onEndRecording
            let wasRecording = displayState != nil
            pop.delegate = nil
            popover = nil
            pop.close()
            cleanup()
            dismiss?()
            if wasRecording { endRecording?() }
        }

        // MARK: NSPopoverDelegate

        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            guard !committed else { return true }
            displayState?.triggerShake()
            return false
        }

        // MARK: Private

        private func present(from sourceView: NSView) {
            committed = false
            let state = ShortcutRecorderDisplayState()
            displayState = state

            onBeginRecording?()

            let content = ShortcutRecorderPopoverView(displayState: state)
            let vc = NSHostingController(rootView: content)
            let pop = NSPopover()
            pop.contentViewController = vc
            pop.behavior = .transient
            pop.animates = true
            pop.delegate = self
            popover = pop

            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: NSEvent.EventTypeMask.keyDown
                    .union(.flagsChanged)
                    .union(.leftMouseDown)
                    .union(.rightMouseDown)
                    .union(.otherMouseDown)
                    .union(.leftMouseUp)
                    .union(.rightMouseUp)
                    .union(.otherMouseUp)
                    .union(.scrollWheel)
                    .union(.mouseEntered)
                    .union(.mouseExited)
                    .union(.mouseMoved)
            ) { [weak self] event in
                // 注意：不能用 self?.handleEvent(event) ?? event
                // 因为当 handleEvent 返回 nil（吞掉事件）时，
                // 可选链同样得到 nil，?? event 会把事件放回去，导致永远无法拦截。
                guard let self else { return event }
                return self.handleEvent(event)
            }

            // 延迟一帧，确保 SwiftUI layout pass 完成后 sourceView.bounds 已正确更新
            DispatchQueue.main.async { [weak self, weak sourceView] in
                guard let self, let sourceView, self.popover === pop else { return }
                pop.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
            }
        }

        private func handleEvent(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .flagsChanged:
                handleFlagsChanged(event)
                return event
            case .keyDown:
                return handleKey(event)
            case .leftMouseDown, .rightMouseDown, .otherMouseDown,
                 .leftMouseUp, .rightMouseUp, .otherMouseUp,
                 .scrollWheel, .mouseEntered, .mouseExited, .mouseMoved:
                // 录制期间吞掉本 App 内的所有鼠标事件，防止点击其他元素
                return nil
            default:
                return event
            }
        }

        private func handleFlagsChanged(_ event: NSEvent) {
            guard popover?.isShown == true else { return }
            let modifiers = ShortcutModifiers.from(event.modifierFlags)
            if modifiers.isEmpty {
                displayState?.previewText = "按下录制快捷键"
            } else {
                var tokens: [String] = []
                if modifiers.contains(.control) { tokens.append("⌃") }
                if modifiers.contains(.option)  { tokens.append("⌥") }
                if modifiers.contains(.shift)   { tokens.append("⇧") }
                if modifiers.contains(.command) { tokens.append("⌘") }
                displayState?.previewText = tokens.joined(separator: " + ")
            }
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            guard popover?.isShown == true else { return event }

            let modifiers = ShortcutModifiers.from(event.modifierFlags)

            if event.keyCode == ShortcutKeyCode.escape, modifiers.isEmpty {
                close()
                return nil
            }

            let binding = ShortcutBinding(keyCode: event.keyCode, modifiers: modifiers)
            guard binding.isValid else { return nil }

            if let conflict = validateAndCommit?(binding) {
                displayState?.triggerShake(conflict: conflict)
            } else {
                committed = true
                close()
            }

            return nil
        }

        private func cleanup() {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
            displayState = nil
            committed = false
            validateAndCommit = nil
            onDismiss = nil
            onBeginRecording = nil
            onEndRecording = nil
        }
    }
}

// MARK: - Manager View

struct AppHotkeyManagerView: View {
    @ObservedObject var store: AppHotkeyStore
    let onUpdate: () -> Void
    var onBeginRecording: ((UUID) -> Void)? = nil
    var onEndRecording: ((UUID) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            bindingSection
        }
    }

    // MARK: Binding Section

    private var bindingSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                Label("应用绑定", systemImage: "keyboard")
                    .font(PluginSettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: addApp) {
                    Label("添加", systemImage: "plus")
                        .font(PluginSettingsTheme.Typography.controlLabel)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if store.entries.isEmpty {
                emptyView
            } else {
                entryList
            }
        }
    }

    private var emptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: PluginSettingsTheme.Size.emptyStateIcon))
                    .foregroundStyle(.secondary)
                Text("点击「添加」选择应用并绑定快捷键")
                    .font(PluginSettingsTheme.Typography.pageDescription)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, PluginSettingsTheme.Spacing.pagePadding)
            Spacer()
        }
        .pluginSettingsCardBackground(.host)
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            ForEach(store.entries) { entry in
                AppShortcutEntryRow(
                    entry: entry,
                    onClearShortcut: {
                        store.updateShortcut(id: entry.id, shortcut: nil)
                        onUpdate()
                    },
                    onDelete: {
                        store.deleteEntry(id: entry.id)
                        onUpdate()
                    },
                    onBeginRecording: { onBeginRecording?(entry.id) },
                    onEndRecording: { onEndRecording?(entry.id) },
                    validateAndCommit: { binding in
                        if let conflict = store.conflictEntry(for: binding, excludingID: entry.id) {
                            return "与「\(conflict.displayName)」冲突"
                        }
                        store.updateShortcut(id: entry.id, shortcut: binding)
                        onUpdate()
                        return nil
                    }
                )
                if entry.id != store.entries.last?.id {
                    PluginSettingsListDivider()
                }
            }
        }
        .pluginSettingsCardBackground(.host)
    }

    // MARK: Actions

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.message = "选择要绑定快捷键的应用"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Bundle(url: url) != nil else { return }

        let displayName = url.deletingPathExtension().lastPathComponent
        let entry = AppShortcutEntry(bundleURL: url, displayName: displayName)
        store.addEntry(entry)
        onUpdate()
    }
}

// MARK: - Entry Row

private struct AppShortcutEntryRow: View {
    let entry: AppShortcutEntry
    let onClearShortcut: () -> Void
    let onDelete: () -> Void
    let onBeginRecording: () -> Void
    let onEndRecording: () -> Void
    /// 录制成功时调用；返回 nil 表示提交成功，返回字符串表示冲突原因。
    let validateAndCommit: (ShortcutBinding) -> String?

    @State private var showRecorder = false

    private var appIcon: NSImage {
        guard let url = entry.bundleURL else {
            return NSWorkspace.shared.icon(forFile: "/Applications")
        }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    private var shortcutText: String {
        ShortcutFormatter.displayString(for: entry.shortcut)
            .replacingOccurrences(of: "None", with: "未设置")
    }

    private var subtitle: String {
        guard let url = entry.bundleURL else {
            return "应用路径不可用"
        }

        return url.path(percentEncoded: false)
    }

    var body: some View {
        HStack(alignment: .center, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: PluginSettingsTheme.Size.rowIcon, height: PluginSettingsTheme.Size.rowIcon)

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(entry.displayName)
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                    .lineLimit(1)

                Text(subtitle)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderBadge(
                text: shortcutText,
                isPresented: $showRecorder,
                validateAndCommit: validateAndCommit,
                onBeginRecording: onBeginRecording,
                onEndRecording: onEndRecording
            )

            if entry.shortcut != nil {
                Button(action: onClearShortcut) {
                    Image(systemName: "xmark.circle.fill")
                        .pluginSettingsRowIconStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除快捷键")
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .pluginSettingsRowIconStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("删除此绑定")
        }
        .pluginSettingsListRowPadding()
    }
}

// MARK: - Shortcut Recorder Badge

private struct ShortcutRecorderBadge: View {
    let text: String
    @Binding var isPresented: Bool
    let validateAndCommit: (ShortcutBinding) -> String?
    var onBeginRecording: (() -> Void)? = nil
    var onEndRecording: (() -> Void)? = nil

    var body: some View {
        Button { isPresented = true } label: {
            Text(text)
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .foregroundStyle(text == "未设置" ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.horizontal, PluginSettingsTheme.Spacing.sectionHeaderContent)
                .padding(.vertical, PluginSettingsTheme.Spacing.controlCluster - 3)
                .frame(minWidth: 90, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous)
                        .fill(PluginSettingsTheme.Palette.fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous)
                        .strokeBorder(
                            isPresented ? Color.accentColor : PluginSettingsTheme.Palette.cardBorder,
                            lineWidth: isPresented ? 1.5 : PluginSettingsTheme.Stroke.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .help("点击录制快捷键")
        .overlay(
            ShortcutRecorderPresenter(
                isPresented: $isPresented,
                validateAndCommit: validateAndCommit,
                onBeginRecording: onBeginRecording,
                onEndRecording: onEndRecording
            )
            .allowsHitTesting(false)
        )
    }
}
