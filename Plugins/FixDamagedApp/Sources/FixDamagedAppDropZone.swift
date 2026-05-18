import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - View Model

@MainActor
final class DropZoneViewModel: ObservableObject {

    enum Phase: Equatable {
        case waiting
        case running
        case success(appName: String)
        case failure(message: String)
    }

    @Published private(set) var phase: Phase = .waiting

    /// drop 已被接受但 URL 异步加载还未完成时为 true，防止 dismissIfIdle 提前关闭
    private var isDropPending = false

    private let onComplete: (String, Bool, String?) -> Void
    private let onDismiss: () -> Void

    init(
        onComplete: @escaping (String, Bool, String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    func beginDrop() {
        isDropPending = true
    }

    func cancelDropPending() {
        isDropPending = false
    }

    func dropApp(url: URL) {
        isDropPending = false
        guard phase == .waiting else { return }
        let appName = url.deletingPathExtension().lastPathComponent
        let appPath = url.path
        phase = .running
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try runQuarantineRemoval(appPath: appPath)
                }.value
                phase = .success(appName: appName)
                onComplete(appName, true, nil)
                try? await Task.sleep(for: .seconds(1.5))
                onDismiss()
            } catch {
                let msg = error.localizedDescription
                phase = .failure(message: msg)
                onComplete(appName, false, msg)
            }
        }
    }

    func dismissIfIdle() {
        guard phase == .waiting, !isDropPending else { return }
        onDismiss()
    }

    func dismiss() {
        onDismiss()
    }
}

// MARK: - Drop Zone View

struct FixDropZoneView: View {
    @ObservedObject var viewModel: DropZoneViewModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                    lineWidth: isTargeted ? 2 : 1
                )

            content
                .padding(20)
        }
        .frame(width: 280, height: 160)
        .background(Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .waiting:
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .scaleEffect(isTargeted ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isTargeted)

                Text("将 .app 文件拖到此处以修复")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .running:
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("修复中…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        case .success(let name):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)

                Text("已修复：\(name)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

        case .failure(let message):
            VStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.red)

                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Button("关闭") {
                    viewModel.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        // 在异步 URL 加载完成前先标记 pending，防止 mouseUp 监听器误判为空闲并关闭面板
        // SwiftUI drop 回调在主线程触发，可安全使用 assumeIsolated
        MainActor.assumeIsolated { viewModel.beginDrop() }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard
                let data,
                let url = URL(dataRepresentation: data, relativeTo: nil),
                url.pathExtension.lowercased() == "app"
            else {
                Task { @MainActor in viewModel.cancelDropPending() }
                return
            }
            Task { @MainActor in
                viewModel.dropApp(url: url)
            }
        }
        return true
    }
}

// MARK: - Panel

@MainActor
final class FixDamagedAppDropZonePanel: NSPanel {

    private let viewModel: DropZoneViewModel

    init(viewModel: DropZoneViewModel) {
        self.viewModel = viewModel
        let size = NSSize(width: 280, height: 160)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true

        // NSVisualEffectView 是磨砂玻璃效果的正确载体：
        // .behindWindow 混合模式 + maskImage 圆角遮罩（比 layer.cornerRadius 更可靠）。
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.makeRoundedMaskImage(size: size, cornerRadius: 20)

        // SwiftUI 层只负责边框和内容，背景透明叠在 effectView 上方。
        let hostingView = NSHostingView(rootView: FixDropZoneView(viewModel: viewModel))
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        contentView = effectView
        setContentSize(size)
    }

    func dismissIfIdle() {
        viewModel.dismissIfIdle()
    }

    /// NSVisualEffectView.maskImage 专用：黑色填充圆角矩形，alpha 通道控制可见区域。
    private static func makeRoundedMaskImage(size: NSSize, cornerRadius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius, left: cornerRadius,
            bottom: cornerRadius, right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }
}
