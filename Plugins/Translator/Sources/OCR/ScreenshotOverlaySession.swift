import AppKit
import SwiftUI

@MainActor
final class ScreenshotOverlaySession: ScreenshotOverlaySelecting {
    private var windows: [ScreenshotOverlayWindow] = []
    private var closingWindows: [ScreenshotOverlayWindow] = []
    private var continuation: CheckedContinuation<ScreenshotOverlaySelectionResult, Never>?

    func selectRegion() async -> ScreenshotOverlaySelectionResult {
        guard continuation == nil else {
            return .failure(.cancelled)
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return .failure(.noScreen)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showOverlayWindows(on: screens)
        }
    }

    private func showOverlayWindows(on screens: [NSScreen]) {
        NSApp.activate(ignoringOtherApps: true)

        windows = screens.map { screen in
            let window = ScreenshotOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.animationBehavior = .none
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary,
            ]
            window.onCancel = { [weak self] in
                self?.complete(.failure(.cancelled))
            }
            window.contentView = NSHostingView(
                rootView: ScreenshotOverlayView(
                    screen: screen,
                    onComplete: { [weak self] result in
                        self?.complete(result)
                    }
                )
            )
            return window
        }

        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    private func complete(_ result: ScreenshotOverlaySelectionResult) {
        guard let continuation else { return }

        self.continuation = nil
        let currentWindows = windows
        windows = []
        closingWindows.append(contentsOf: currentWindows)
        currentWindows.forEach { window in
            window.onCancel = nil
            window.contentView = nil
            window.orderOut(nil)
        }
        continuation.resume(returning: result)

        DispatchQueue.main.async { [weak self] in
            self?.closingWindows.removeAll()
        }
    }
}

private final class ScreenshotOverlayWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }
}

private struct ScreenshotOverlayView: View {
    let screen: NSScreen
    let onComplete: (ScreenshotOverlaySelectionResult) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            if let selectionRect {
                Rectangle()
                    .fill(Color.clear)
                    .background(.clear)
                    .overlay(
                        Rectangle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .background(Color.white.opacity(0.12))
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .offset(x: selectionRect.minX, y: selectionRect.minY)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = value.startLocation
                    }
                    dragCurrent = value.location
                }
                .onEnded { value in
                    let rect = normalizedRect(from: dragStart ?? value.startLocation, to: value.location)
                    dragStart = nil
                    dragCurrent = nil

                    guard rect.width >= 10, rect.height >= 10 else {
                        onComplete(.failure(.regionTooSmall))
                        return
                    }

                    onComplete(.success(ScreenshotOverlaySelection(screen: screen, selectedRect: rect)))
                }
        )
        .onAppear {
            NSCursor.crosshair.push()
        }
        .onDisappear {
            NSCursor.pop()
        }
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return normalizedRect(from: dragStart, to: dragCurrent)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }
}
