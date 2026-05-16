import Foundation

@MainActor
struct BuiltInPluginRegistry: PluginProvider {
    private enum PluginID {
        static let appearance = "appearance"
        static let nightShift = "night-shift"
        static let displayBrightness = "display-brightness"
        static let displayTrueColor = "display-true-color"
        static let displayResolution = "display-resolution"
        static let hideNotch = "hide-notch"
        static let hideDock = "hide-dock"
        static let keepAwake = "keep-awake"
        static let middleClick = "middle-click"
        static let diskClean = "disk-clean"
        static let launchControl = "launch-control"
        static let ejectDisk = "eject-disk"
        static let emptyTrash = "empty-trash"
        static let physicalCleanMode = "physical-clean-mode"
        static let clipboardClear = "clipboard-clear"
        static let systemStatus = "system-status"
        static let calendar = "calendar"
    }

    func makePlugins() -> [any MacToolsPlugin] {
        [
            AppearancePlugin(),
            NightShiftPlugin(),
            DisplayBrightnessPlugin(),
            DisplayTrueColorPlugin(),
            DisplayResolutionPlugin(),
            HideNotchPlugin(context: context(for: PluginID.hideNotch)),
            HideDockPlugin(),
            KeepAwakePlugin(),
            MiddleClickPlugin(context: context(for: PluginID.middleClick)),
            DiskCleanFeature.shared.makePlugin(),
            LaunchControlFeature.shared.makePlugin(context: context(for: PluginID.launchControl)),
            EjectDiskPlugin(),
            EmptyTrashPlugin(),
            PhysicalCleanModePlugin(context: context(for: PluginID.physicalCleanMode)),
            ClipboardClearPlugin(),
            SystemStatusPlugin(),
            CalendarPlugin(context: context(for: PluginID.calendar, resourceSubdirectory: "CalendarPluginResources"))
        ]
    }

    private func context(for pluginID: String, resourceSubdirectory: String? = nil) -> PluginRuntimeContext {
        PluginRuntimeContext(pluginID: pluginID, resourceSubdirectory: resourceSubdirectory)
    }
}
