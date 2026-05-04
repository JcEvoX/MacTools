import AppKit
import SwiftUI

@MainActor
final class MenuBarPanelPresenter: NSObject {
    private let pluginHost: PluginHost
    private let onDismiss: () -> Void
    private let onAllPanelsClosed: () -> Void

    private let featurePopover = NSPopover()
    private let componentPopover = NSPopover()
    private let featureHostingController: NSHostingController<MenuBarContent>
    private let componentHostingController: NSHostingController<ComponentPanelContent>

    init(
        pluginHost: PluginHost,
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onPresentDiskCleanConfiguration: @escaping () -> Void,
        onAllPanelsClosed: @escaping () -> Void
    ) {
        self.pluginHost = pluginHost
        self.onDismiss = onDismiss
        self.onAllPanelsClosed = onAllPanelsClosed

        self.featureHostingController = NSHostingController(
            rootView: MenuBarContent(
                pluginHost: pluginHost,
                onDismiss: onDismiss,
                onOpenSettings: onOpenSettings,
                onPresentDiskCleanConfiguration: onPresentDiskCleanConfiguration
            )
        )
        self.componentHostingController = NSHostingController(
            rootView: ComponentPanelContent(
                pluginHost: pluginHost,
                panelHeight: ComponentPanelLayout.minimumPanelHeight,
                onDismiss: onDismiss
            )
        )

        super.init()

        configure(featurePopover, contentViewController: featureHostingController)
        configure(componentPopover, contentViewController: componentHostingController)
        prewarm()
    }

    var isAnyPanelShown: Bool {
        featurePopover.isShown || componentPopover.isShown
    }

    func toggleFeaturePanel(relativeTo button: NSStatusBarButton) {
        if featurePopover.isShown {
            featurePopover.performClose(nil)
            return
        }

        componentPopover.performClose(nil)
        featurePopover.contentSize = MenuBarPanelLayout.contentSize(for: pluginHost.panelItems)
        show(featurePopover, relativeTo: button)
    }

    func toggleComponentPanel(relativeTo button: NSStatusBarButton) {
        if componentPopover.isShown {
            componentPopover.performClose(nil)
            return
        }

        featurePopover.performClose(nil)
        let panelHeight = ComponentPanelLayout.preferredPanelHeight(
            for: pluginHost.componentItems,
            screen: button.window?.screen ?? NSScreen.main
        )
        componentHostingController.rootView = ComponentPanelContent(
            pluginHost: pluginHost,
            panelHeight: panelHeight,
            onDismiss: onDismiss
        )
        componentPopover.contentSize = NSSize(
            width: ComponentPanelLayout.panelWidth,
            height: panelHeight
        )
        show(componentPopover, relativeTo: button)
    }

    func dismissPanels() {
        featurePopover.performClose(nil)
        componentPopover.performClose(nil)
    }

    func containsPopoverWindow(_ window: NSWindow) -> Bool {
        window === featurePopover.contentViewController?.view.window
            || window === componentPopover.contentViewController?.view.window
    }

    private func configure(
        _ popover: NSPopover,
        contentViewController: NSViewController
    ) {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = contentViewController
    }

    private func prewarm() {
        pluginHost.warmComponentViews(dismiss: onDismiss)
        featurePopover.contentSize = MenuBarPanelLayout.contentSize(for: pluginHost.panelItems)
        componentPopover.contentSize = NSSize(
            width: ComponentPanelLayout.panelWidth,
            height: ComponentPanelLayout.preferredPanelHeight(
                for: pluginHost.componentItems,
                screen: NSScreen.main
            )
        )
    }

    private func show(_ popover: NSPopover, relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        focus(popover)
    }

    private func focus(_ popover: NSPopover) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()

        Task { @MainActor [weak popover] in
            await Task.yield()
            guard let popover, popover.isShown else {
                return
            }

            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension MenuBarPanelPresenter: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        guard !featurePopover.isShown, !componentPopover.isShown else {
            return
        }

        onAllPanelsClosed()
    }
}
