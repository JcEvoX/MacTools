import AppKit
import Combine
import SwiftUI

enum MenuBarStatusItemInvocation: Equatable {
    case featurePanel
    case componentPanel

    static func invocation(for event: NSEvent?) -> MenuBarStatusItemInvocation {
        guard let event else {
            return .componentPanel
        }

        if event.type == .rightMouseDown
            || event.type == .rightMouseUp
            || event.modifierFlags.contains(.control) {
            return .featurePanel
        }

        return .componentPanel
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    private static let statusIconName = NSImage.Name("MenuBarIcon")
    private static let statusIconSize = NSSize(width: 18, height: 18)

    private let pluginHost: PluginHost
    private let windowRouter: AppWindowRouter
    private let statusItem: NSStatusItem
    private var panelPresenter: MenuBarPanelPresenter!
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var refreshAfterPresentationTask: Task<Void, Never>?

    init(pluginHost: PluginHost, windowRouter: AppWindowRouter) {
        self.pluginHost = pluginHost
        self.windowRouter = windowRouter
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        panelPresenter = MenuBarPanelPresenter(
            pluginHost: pluginHost,
            onDismiss: { [weak self] in
                self?.dismissPanels()
            },
            onOpenSettings: { [weak self] in
                self?.windowRouter.showSettings()
            },
            onPresentDiskCleanConfiguration: { [weak self] in
                self?.pluginHost.presentPluginConfiguration(pluginID: "disk-clean")
            },
            onAllPanelsClosed: { [weak self] in
                self?.removeDismissMonitorsIfNeeded()
            }
        )
        configureStatusItem()
        observePluginHost()
        updateStatusIcon()
    }

    func dismissPanels() {
        refreshAfterPresentationTask?.cancel()
        refreshAfterPresentationTask = nil
        panelPresenter.dismissPanels()
        removeDismissMonitorsIfNeeded()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.toolTip = "MacTools"
    }

    private func observePluginHost() {
        pluginHost.$hasActivePlugin
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)

        pluginHost.$settingsPresentationRequestCount
            .dropFirst()
            .sink { [weak self] _ in
                self?.windowRouter.showSettings()
                self?.dismissPanels()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        let image = NSImage(named: Self.statusIconName)
        image?.size = Self.statusIconSize
        image?.isTemplate = true

        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
    }

    @objc
    private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        switch MenuBarStatusItemInvocation.invocation(for: NSApp.currentEvent) {
        case .featurePanel:
            toggleFeaturePanel(relativeTo: sender)
        case .componentPanel:
            toggleComponentPanel(relativeTo: sender)
        }
    }

    private func toggleFeaturePanel(relativeTo button: NSStatusBarButton) {
        panelPresenter.toggleFeaturePanel(relativeTo: button)
        handlePresentationResult()
    }

    private func toggleComponentPanel(relativeTo button: NSStatusBarButton) {
        panelPresenter.toggleComponentPanel(relativeTo: button)
        handlePresentationResult()
    }

    private func handlePresentationResult() {
        guard panelPresenter.isAnyPanelShown else {
            refreshAfterPresentationTask?.cancel()
            refreshAfterPresentationTask = nil
            return
        }

        installDismissMonitorsIfNeeded()
        refreshAfterPresentation()
    }

    private func installDismissMonitorsIfNeeded() {
        let mouseEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
                self?.handleLocalMouseEvent(event) ?? event
            }
        }

        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
                Task { @MainActor in
                    self?.dismissPanels()
                }
            }
        }

        if appActivationObserver == nil {
            appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard !Self.isCurrentApplicationActivationNotification(notification) else {
                    return
                }

                Task { @MainActor in
                    self?.dismissPanels()
                }
            }
        }
    }

    private func removeDismissMonitorsIfNeeded() {
        refreshAfterPresentationTask?.cancel()
        refreshAfterPresentationTask = nil

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    private func handleLocalMouseEvent(_ event: NSEvent) -> NSEvent {
        guard panelPresenter.isAnyPanelShown else {
            removeDismissMonitorsIfNeeded()
            return event
        }

        guard !isEventInsidePopover(event), !isEventInsideStatusButton(event) else {
            return event
        }

        dismissPanels()
        return event
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window else {
            return false
        }

        return panelPresenter.containsPopoverWindow(eventWindow)
    }

    private func isEventInsideStatusButton(_ event: NSEvent) -> Bool {
        guard
            let button = statusItem.button,
            event.window === button.window
        else {
            return false
        }

        let pointInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(pointInButton)
    }

    nonisolated private static func isCurrentApplicationActivationNotification(_ notification: Notification) -> Bool {
        guard
            let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return false
        }

        return activatedApplication.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func refreshAfterPresentation() {
        refreshAfterPresentationTask?.cancel()
        refreshAfterPresentationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }

            guard
                !Task.isCancelled,
                self?.panelPresenter.isAnyPanelShown == true
            else {
                return
            }

            self?.pluginHost.refreshAll()
        }
    }
}
