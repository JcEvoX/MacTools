import Foundation

@MainActor
struct BuiltInPluginRegistry: PluginProvider {
    func makePlugins() -> [any MacToolsPlugin] {
        [
            AppearancePlugin(),
            NightShiftPlugin(),
            DisplayBrightnessPlugin(),
            DisplayTrueColorPlugin(),
            DisplayResolutionPlugin(),
            HideNotchPlugin(),
            HideDockPlugin(),
            KeepAwakePlugin(),
            MiddleClickPlugin(),
            DiskCleanFeature.shared.makePlugin(),
            LaunchControlFeature.shared.makePlugin(),
            EjectDiskPlugin(),
            EmptyTrashPlugin(),
            PhysicalCleanModePlugin(),
            ClipboardClearPlugin(),
            SystemStatusPlugin(),
            CalendarPlugin()
        ]
    }
}
