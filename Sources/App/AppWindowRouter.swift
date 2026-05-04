import AppKit
import SwiftUI

@MainActor
final class AppWindowRouter {
    private let pluginHost: PluginHost
    private let appUpdater: AppUpdater
    private var settingsWindow: NSWindow?

    init(pluginHost: PluginHost, appUpdater: AppUpdater) {
        self.pluginHost = pluginHost
        self.appUpdater = appUpdater
    }

    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        show(window)
        settingsWindow = window
    }

    private func show(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.contentView = NSHostingView(
            rootView: SettingsView(pluginHost: pluginHost, appUpdater: appUpdater)
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
