import AppKit
import SwiftUI

@MainActor
final class TranslatorPanelController: TranslatorPanelControlling {
    private static let panelSize = NSSize(width: 520, height: 520)
    private static let screenPadding: CGFloat = 16

    private var panelWindow: TranslatorPanelWindow?
    private var lastFrame: NSRect?
    private let model = TranslatorPanelModel()

    var onAction: ((TranslatorPanelAction) -> Void)?

    func show(snapshot: TranslatorPanelSnapshot) {
        model.snapshot = snapshot
        let panel = panelWindow ?? makePanel()
        panelWindow = panel

        panel.orderFrontRegardless()

        // 取词阶段保持非 key，避免抢走前台 App 的键盘焦点而影响 AX 取词与模拟 ⌘C；
        // 结果态才成为 key 以支持按钮点击、文本选择与 Esc 关闭。不调用 NSApp.activate，
        // 与仓库内其他 .nonactivatingPanel 浮窗保持一致，不让整个 App 抢占前台。
        if snapshot.phase != .capturing {
            panel.makeKey()
        }
    }

    func update(snapshot: TranslatorPanelSnapshot) {
        model.snapshot = snapshot
    }

    func close() {
        guard let panelWindow else { return }

        lastFrame = panelWindow.frame
        panelWindow.performProgrammaticClose {
            panelWindow.orderOut(nil)
        }
    }

    private func makePanel() -> TranslatorPanelWindow {
        let panel = TranslatorPanelWindow(size: Self.panelSize)
        panel.onCloseRequest = { [weak self] in
            self?.onAction?(.close)
        }

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMaskImage(size: Self.panelSize, cornerRadius: 18)

        let rootView = TranslatorPanelHostView(model: model) { [weak self] action in
            self?.onAction?(action)
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        panel.contentView = effectView
        panel.setContentSize(Self.panelSize)
        panel.setFrame(lastFrame ?? defaultFrame(for: panel), display: true)
        return panel
    }

    private func defaultFrame(for panel: NSPanel) -> NSRect {
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = visibleFrame.maxX - Self.panelSize.width - Self.screenPadding
        let y = visibleFrame.maxY - Self.panelSize.height - Self.screenPadding
        return clampedFrame(
            NSRect(origin: CGPoint(x: x, y: y), size: Self.panelSize),
            within: visibleFrame
        )
    }

    private func clampedFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        guard !visibleFrame.isEmpty else { return frame }

        let minX = visibleFrame.minX + Self.screenPadding
        let maxX = visibleFrame.maxX - frame.width - Self.screenPadding
        let minY = visibleFrame.minY + Self.screenPadding
        let maxY = visibleFrame.maxY - frame.height - Self.screenPadding
        let x = maxX >= minX ? min(max(frame.minX, minX), maxX) : visibleFrame.midX - frame.width / 2
        let y = maxY >= minY ? min(max(frame.minY, minY), maxY) : visibleFrame.midY - frame.height / 2
        return NSRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }

    private static func roundedMaskImage(size: NSSize, cornerRadius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }
}
