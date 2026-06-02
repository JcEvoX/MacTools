import AppKit
import SwiftUI

@MainActor
final class TranslatorPanelController: TranslatorPanelControlling {
    private static let panelSize = NSSize(width: 520, height: 520)
    private static let screenPadding: CGFloat = 16

    private var panelWindow: TranslatorPanelWindow?
    private var lastFrame: NSRect?

    var onAction: ((TranslatorPanelAction) -> Void)?

    func show(snapshot: TranslatorPanelSnapshot) {
        let panel = panelWindow ?? makePanel()
        panelWindow = panel

        update(snapshot: snapshot)

        if lastFrame == nil {
            panel.setFrame(defaultFrame(for: panel), display: true)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func update(snapshot: TranslatorPanelSnapshot) {
        let panel = panelWindow ?? makePanel()
        panelWindow = panel

        let currentFrame = panel.frame
        let size = currentFrame.size == .zero ? Self.panelSize : currentFrame.size
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMaskImage(size: size, cornerRadius: 18)

        let rootView = TranslatorPanelView(snapshot: snapshot) { [weak self] action in
            self?.onAction?(action)
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        panel.contentView = effectView
        panel.setContentSize(size)
        if currentFrame != .zero {
            panel.setFrame(currentFrame, display: true)
        }
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
