import AppKit
import SwiftUI

public enum PluginSettingsTheme {
    public enum Typography {
        public static var pageTitle: Font {
            .title2.weight(.semibold)
        }

        public static var pageDescription: Font {
            .subheadline
        }

        public static var sectionTitle: Font {
            .body.weight(.semibold)
        }

        public static var rowTitle: Font {
            .body.weight(.medium)
        }

        public static var emphasizedRowTitle: Font {
            .body.weight(.semibold)
        }

        public static var rowDescription: Font {
            .subheadline
        }

        public static var secondaryLabel: Font {
            .subheadline.weight(.medium)
        }

        public static var statusBadge: Font {
            .caption2.weight(.medium)
        }

        public static var rowIcon: Font {
            .caption.weight(.semibold)
        }

        public static var controlLabel: Font {
            .callout
        }

        public static var monospacedValue: Font {
            .system(size: 12, design: .monospaced)
        }
    }

    public enum Spacing {
        public static let pagePadding: CGFloat = 24
        public static let section: CGFloat = 18
        public static let sectionHeaderContent: CGFloat = 10
        public static let cardContent: CGFloat = 16
        public static let rowHorizontal: CGFloat = 16
        public static let rowVertical: CGFloat = 10
        public static let interactiveRowVertical: CGFloat = 12
        public static let rowTitleDescription: CGFloat = 3
        public static let rowContentControl: CGFloat = 12
        public static let controlCluster: CGFloat = 8
    }

    public enum Radius {
        public static let card: CGFloat = 10
        public static let hostCard: CGFloat = 12
        public static let control: CGFloat = 8
        public static let field: CGFloat = 6
    }

    public enum Stroke {
        public static let hairline: CGFloat = 0.5
        public static let standard: CGFloat = 1
    }

    public enum Size {
        public static let pageIcon: CGFloat = 42
        public static let rowIcon: CGFloat = 18
        public static let controlHeight: CGFloat = 30
        public static let metricIcon: CGFloat = 36
        public static let emptyStateIcon: CGFloat = 28
    }

    public enum Palette {
        public static var windowBackground: Color {
            dynamic(light: 0xF4F5F7, dark: 0x1E1F22)
        }

        public static var sidebarBackground: Color {
            dynamic(light: 0xEEF0F3, dark: 0x25262A)
        }

        public static var contentBackground: Color {
            dynamic(light: 0xF7F8FA, dark: 0x1F2023)
        }

        public static var cardBackground: Color {
            dynamic(light: 0xFFFFFF, dark: 0x2A2B2F)
        }

        public static var recessedControlBackground: Color {
            dynamic(light: 0xF1F3F6, dark: 0x222327)
        }

        public static var fieldBackground: Color {
            dynamic(light: 0xFFFFFF, dark: 0x1C1D20)
        }

        public static var keycapBackground: Color {
            dynamic(light: 0xF8F9FB, dark: 0x2F3035)
        }

        public static var separator: Color {
            dynamic(light: 0xD9DDE4, dark: 0x3A3B40)
        }

        public static var cardBorder: Color {
            dynamic(light: 0xDDE1E7, dark: 0x3B3C42)
        }

        public static var sidebarHoverBackground: Color {
            Color.primary.opacity(0.05)
        }

        public static var sidebarSelectionBackground: Color {
            Color.accentColor.opacity(0.12)
        }

        public static var activeControlBackground: Color {
            Color.accentColor.opacity(0.12)
        }

        public static var recordingBackground: Color {
            Color.accentColor.opacity(0.08)
        }

        public static var nativeCardBackground: Color {
            Color(nsColor: .controlBackgroundColor)
        }

        public static var nativeFieldBackground: Color {
            Color(nsColor: .textBackgroundColor)
        }

        public static var nativeSeparator: Color {
            Color(nsColor: .separatorColor)
        }

        private static func dynamic(light lightHex: UInt32, dark darkHex: UInt32) -> Color {
            Color(
                nsColor: NSColor(
                    name: nil,
                    dynamicProvider: { appearance in
                        appearance.pluginSettingsThemeIsDark
                            ? .pluginSettingsThemeRGB(darkHex)
                            : .pluginSettingsThemeRGB(lightHex)
                    }
                )
            )
        }
    }
}

public enum PluginSettingsCardBackgroundStyle {
    case host
    case plugin
    case recessed
}

public enum PluginSettingsListDividerStyle {
    case horizontal
    case vertical
}

public struct PluginSettingsCardBackground: ViewModifier {
    private let style: PluginSettingsCardBackgroundStyle

    public init(_ style: PluginSettingsCardBackgroundStyle = .host) {
        self.style = style
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
    }

    private var radius: CGFloat {
        switch style {
        case .host:
            return PluginSettingsTheme.Radius.hostCard
        case .plugin, .recessed:
            return PluginSettingsTheme.Radius.card
        }
    }

    private var background: Color {
        switch style {
        case .host:
            return PluginSettingsTheme.Palette.cardBackground
        case .plugin:
            return PluginSettingsTheme.Palette.nativeCardBackground
        case .recessed:
            return PluginSettingsTheme.Palette.recessedControlBackground
        }
    }

}

public struct PluginSettingsListDivider: View {
    private let style: PluginSettingsListDividerStyle
    private let leadingInset: CGFloat
    private let trailingInset: CGFloat

    public init(
        _ style: PluginSettingsListDividerStyle = .horizontal,
        leadingInset: CGFloat = PluginSettingsTheme.Spacing.rowHorizontal,
        trailingInset: CGFloat = PluginSettingsTheme.Spacing.rowHorizontal
    ) {
        self.style = style
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }

    public var body: some View {
        switch style {
        case .horizontal:
            Rectangle()
                .fill(PluginSettingsTheme.Palette.separator)
                .frame(height: PluginSettingsTheme.Stroke.standard)
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
        case .vertical:
            Rectangle()
                .fill(PluginSettingsTheme.Palette.separator)
                .frame(width: PluginSettingsTheme.Stroke.standard)
        }
    }
}

@MainActor
final class PluginShortcutRecorderDisplayState: ObservableObject {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
            self?.isShaking = false
        }
    }
}

public struct PluginShortcutRecorderField: View {
    public let text: String
    public let isRecording: Bool
    public let minWidth: CGFloat

    private var displayText: String {
        text == "None" ? "未设置" : text
    }

    public init(
        text: String,
        isRecording: Bool,
        minWidth: CGFloat = 90
    ) {
        self.text = text
        self.isRecording = isRecording
        self.minWidth = minWidth
    }

    public var body: some View {
        Text(displayText)
            .font(PluginSettingsTheme.Typography.monospacedValue)
            .foregroundStyle(displayText == "未设置" ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, PluginSettingsTheme.Spacing.sectionHeaderContent)
            .padding(.vertical, PluginSettingsTheme.Spacing.controlCluster - 3)
            .frame(minWidth: minWidth, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous)
                    .fill(PluginSettingsTheme.Palette.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor : PluginSettingsTheme.Palette.cardBorder,
                        lineWidth: isRecording ? 1.5 : PluginSettingsTheme.Stroke.standard
                    )
            )
    }
}

public struct PluginShortcutRecorder: View {
    public let text: String
    public let minWidth: CGFloat
    public let validateAndCommit: (ShortcutBinding) -> String?
    public let onBeginRecording: (() -> Void)?
    public let onEndRecording: (() -> Void)?

    @State private var isPresented = false

    public init(
        text: String,
        minWidth: CGFloat = 90,
        validateAndCommit: @escaping (ShortcutBinding) -> String?,
        onBeginRecording: (() -> Void)? = nil,
        onEndRecording: (() -> Void)? = nil
    ) {
        self.text = text
        self.minWidth = minWidth
        self.validateAndCommit = validateAndCommit
        self.onBeginRecording = onBeginRecording
        self.onEndRecording = onEndRecording
    }

    public var body: some View {
        Button { isPresented = true } label: {
            PluginShortcutRecorderField(
                text: text,
                isRecording: isPresented,
                minWidth: minWidth
            )
        }
        .buttonStyle(.plain)
        .help("点击录制快捷键")
        .overlay(
            PluginShortcutRecorderPresenter(
                isPresented: $isPresented,
                validateAndCommit: validateAndCommit,
                onBeginRecording: onBeginRecording,
                onEndRecording: onEndRecording
            )
            .allowsHitTesting(false)
        )
    }
}

private struct PluginShortcutRecorderPopoverView: View {
    @ObservedObject var displayState: PluginShortcutRecorderDisplayState

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
                        .fill(
                            displayState.isShaking
                                ? Color.red.opacity(0.18)
                                : PluginSettingsTheme.Palette.recordingBackground
                        )
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

private struct PluginShortcutRecorderPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
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

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?
        private var displayState: PluginShortcutRecorderDisplayState?
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

        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            guard !committed else { return true }
            displayState?.triggerShake()
            return false
        }

        private func present(from sourceView: NSView) {
            committed = false
            let state = PluginShortcutRecorderDisplayState()
            displayState = state

            onBeginRecording?()

            let content = PluginShortcutRecorderPopoverView(displayState: state)
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
                guard let self else { return event }
                return self.handleEvent(event)
            }

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
                if modifiers.contains(.option) { tokens.append("⌥") }
                if modifiers.contains(.shift) { tokens.append("⇧") }
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
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }

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

public extension View {
    func pluginSettingsCardBackground(
        _ style: PluginSettingsCardBackgroundStyle = .host
    ) -> some View {
        modifier(PluginSettingsCardBackground(style))
    }

    func pluginSettingsRowIconStyle(visualScale: CGFloat = 1) -> some View {
        pluginSettingsRowIconStyle(
            HierarchicalShapeStyle.secondary,
            visualScale: visualScale
        )
    }

    func pluginSettingsRowIconStyle<S: ShapeStyle>(
        _ foregroundStyle: S,
        visualScale: CGFloat = 1
    ) -> some View {
        self
            .font(PluginSettingsTheme.Typography.rowIcon)
            .foregroundStyle(foregroundStyle)
            .symbolRenderingMode(.monochrome)
            .scaleEffect(visualScale)
            .frame(
                width: PluginSettingsTheme.Size.rowIcon,
                height: PluginSettingsTheme.Size.rowIcon
            )
    }

    func pluginSettingsListRowPadding(interactive: Bool = false) -> some View {
        self
            .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
            .padding(
                .vertical,
                interactive
                    ? PluginSettingsTheme.Spacing.interactiveRowVertical
                    : PluginSettingsTheme.Spacing.rowVertical
            )
    }
}

private extension NSAppearance {
    var pluginSettingsThemeIsDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSColor {
    static func pluginSettingsThemeRGB(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}
