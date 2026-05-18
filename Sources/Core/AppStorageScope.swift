import Foundation

enum AppStorageScope {
    static var applicationSupportDirectoryName: String {
        #if DEBUG
        return "MacTools Dev"
        #else
        return "MacTools"
        #endif
    }

    static func applicationSupportRoot(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseURL.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }
}
