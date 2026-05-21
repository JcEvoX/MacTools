import Foundation
import MacToolsPluginKit

/// 一条「应用 → 快捷键」绑定记录
struct AppShortcutEntry: Codable, Identifiable, Equatable {
    let id: UUID
    /// .app bundle 的 file:// URL 字符串
    var bundleURLString: String
    var displayName: String
    var shortcut: ShortcutBinding?

    var bundleURL: URL? { URL(string: bundleURLString) }

    init(
        id: UUID = UUID(),
        bundleURL: URL,
        displayName: String,
        shortcut: ShortcutBinding? = nil
    ) {
        self.id = id
        self.bundleURLString = bundleURL.absoluteString
        self.displayName = displayName
        self.shortcut = shortcut
    }
}
