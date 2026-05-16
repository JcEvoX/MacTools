import AppKit
import SwiftUI

enum MenuBarPanelWindowRegistry {
    private static let secondaryPanelIdentifier = NSUserInterfaceItemIdentifier(
        "MacTools.MenuBarSecondaryPanel"
    )

    @MainActor
    static func markSecondaryPanel(_ window: NSWindow) {
        window.identifier = secondaryPanelIdentifier
    }

    @MainActor
    static func containsAuxiliaryPanelWindow(_ window: NSWindow) -> Bool {
        window.identifier == secondaryPanelIdentifier
    }
}

@MainActor
final class MenuBarPanelPresenter: NSObject {
    static let popoverBehavior: NSPopover.Behavior = .applicationDefined

    private let pluginHost: PluginHost
    private let onDismiss: () -> Void
    private let onAllPanelsClosed: () -> Void

    private let featurePopover = NSPopover()
    private let componentPopover = NSPopover()
    private let featureHostingController: NSHostingController<MenuBarContent>
    private let componentHostingController: NSHostingController<ComponentPanelContent>
    private var appearanceObserver: NSObjectProtocol?

    init(
        pluginHost: PluginHost,
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onPresentDiskCleanConfiguration: @escaping () -> Void,
        onPresentLaunchControlConfiguration: @escaping () -> Void,
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
                onPresentDiskCleanConfiguration: onPresentDiskCleanConfiguration,
                onPresentLaunchControlConfiguration: onPresentLaunchControlConfiguration
            )
        )
        self.componentHostingController = NSHostingController(
            rootView: ComponentPanelContent(
                pluginHost: pluginHost,
                panelHeight: ComponentPanelLayout.minimumPanelHeight,
                isPanelVisible: false,
                onDismiss: onDismiss
            )
        )

        super.init()

        configure(featurePopover, contentViewController: featureHostingController)
        configure(componentPopover, contentViewController: componentHostingController)
        observeAppearancePreference()
        applyCurrentAppearance()
        prewarm()
    }

    deinit {
        MainActor.assumeIsolated {
            if let appearanceObserver {
                NotificationCenter.default.removeObserver(appearanceObserver)
            }
        }
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
            isPanelVisible: true,
            onDismiss: onDismiss
        )
        applyCurrentAppearance()
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

    func containsPresentedWindow(_ window: NSWindow) -> Bool {
        window === featurePopover.contentViewController?.view.window
            || window === componentPopover.contentViewController?.view.window
            || MenuBarPanelWindowRegistry.containsAuxiliaryPanelWindow(window)
    }

    private func configure(
        _ popover: NSPopover,
        contentViewController: NSViewController
    ) {
        // Dismissal is coordinated by MenuBarStatusItemController so sibling
        // panels can receive clicks without AppKit closing the popover first.
        popover.behavior = Self.popoverBehavior
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = contentViewController
        AppAppearancePreference.stored().apply(to: contentViewController.view)
    }

    private func prewarm() {
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
        applyCurrentAppearance()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        applyCurrentAppearance()
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

    private func observeAppearancePreference() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: AppAppearancePreference.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyCurrentAppearance()
            }
        }
    }

    private func applyCurrentAppearance() {
        let preference = AppAppearancePreference.stored()
        preference.apply(to: featureHostingController.view)
        preference.apply(to: componentHostingController.view)
        preference.apply(to: featurePopover)
        preference.apply(to: componentPopover)
    }
}

extension MenuBarPanelPresenter: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if let popover = notification.object as? NSPopover, popover === componentPopover {
            componentHostingController.rootView = ComponentPanelContent(
                pluginHost: pluginHost,
                panelHeight: ComponentPanelLayout.minimumPanelHeight,
                isPanelVisible: false,
                onDismiss: onDismiss
            )
            pluginHost.discardComponentViews()
        }

        guard !featurePopover.isShown, !componentPopover.isShown else {
            return
        }

        onAllPanelsClosed()
    }
}
