import AppKit
import FinderSync
import Foundation
import OSLog

final class RightClickFinderSync: FIFinderSync {
    private enum ActionID {
        static let newFolder = "new-folder"
        static let copyFileName = "copy-file-name"
        static let copyAbsolutePath = "copy-absolute-path"
        static let copyRelativePath = "copy-relative-path"
    }

    private final class MenuActionContext: NSObject {
        let actionID: String
        let directory: URL?

        init(actionID: String, directory: URL? = nil) {
            self.actionID = actionID
            self.directory = directory
        }
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools.right-click.finder-sync",
        category: "RightClickFinderSync"
    )
    private var titleToActionContext: [String: MenuActionContext] = [:]
    private var lastSelectedURLs: [URL] = []
    private var lastTargetedURL: URL?

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = Self.monitoredDirectories()
        let monitoredPaths = FIFinderSyncController.default().directoryURLs.map(\.path).joined(separator: ", ")
        logger.info("RightClick Finder Sync loaded. Monitoring: \(monitoredPaths, privacy: .public)")
    }

    override var toolbarItemName: String {
        "MacTools"
    }

    override var toolbarItemToolTip: String {
        "MacTools 右键工具"
    }

    override var toolbarItemImage: NSImage {
        let image = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "MacTools")
            ?? NSImage()
        image.isTemplate = true
        return image
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetedURL = controller.targetedURL()

        lastSelectedURLs = selectedURLs
        lastTargetedURL = targetedURL
        titleToActionContext.removeAll()

        let menu = NSMenu(title: "MacTools")

        switch menuKind {
        case .contextualMenuForContainer:
            if let directory = RightClickTargetResolver.targetDirectory(
                selectedURLs: [],
                targetedURL: targetedURL
            ) {
                addNewFolderItem(to: menu, directory: directory)
            }
        case .contextualMenuForItems, .contextualMenuForSidebar, .toolbarItemMenu:
            addMenuItemsForSelection(selectedURLs, targetedURL: targetedURL, to: menu)
        @unknown default:
            break
        }

        return menu
    }

    override func beginObservingDirectory(at url: URL) {
        logger.debug("Begin observing directory: \(url.path, privacy: .public)")
    }

    override func endObservingDirectory(at url: URL) {
        logger.debug("End observing directory: \(url.path, privacy: .public)")
    }

    private func addMenuItemsForSelection(_ selectedURLs: [URL], targetedURL: URL?, to menu: NSMenu) {
        if let directory = RightClickTargetResolver.targetDirectory(
            selectedURLs: selectedURLs,
            targetedURL: targetedURL
        ) {
            addNewFolderItem(to: menu, directory: directory)
        }

        guard !selectedURLs.isEmpty else {
            return
        }

        addCopyItem(
            title: "复制文件名",
            actionID: ActionID.copyFileName,
            to: menu
        )
        addCopyItem(
            title: "复制绝对路径",
            actionID: ActionID.copyAbsolutePath,
            to: menu
        )
        addCopyItem(
            title: "复制相对路径",
            actionID: ActionID.copyRelativePath,
            to: menu
        )
    }

    private func addNewFolderItem(to menu: NSMenu, directory: URL) {
        let item = actionItem(title: "新建文件夹", context: MenuActionContext(
            actionID: ActionID.newFolder,
            directory: directory
        ))
        menu.addItem(item)
    }

    private func addCopyItem(
        title: String,
        actionID: String,
        to menu: NSMenu
    ) {
        menu.addItem(actionItem(title: title, actionID: actionID))
    }

    private func actionItem(title: String, actionID: String) -> NSMenuItem {
        actionItem(title: title, context: MenuActionContext(actionID: actionID))
    }

    private func actionItem(title: String, context: MenuActionContext) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(handleMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = context
        titleToActionContext[title] = context
        return item
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let context = menuActionContext(for: sender) else {
            logger.error("Missing action context for menu item: \(sender.title, privacy: .public)")
            return
        }

        if context.actionID == ActionID.newFolder,
           let directory = context.directory {
            openHostURL(path: "/new-folder", queryItems: [
                URLQueryItem(name: "directory", value: directory.path)
            ])
            return
        }

        switch context.actionID {
        case ActionID.copyFileName:
            copyToPasteboard(RightClickPathFormatter.joinedFileNames(currentSelectedURLs()))
        case ActionID.copyAbsolutePath:
            copyToPasteboard(RightClickPathFormatter.joinedPaths(currentSelectedURLs()))
        case ActionID.copyRelativePath:
            copyToPasteboard(
                RightClickPathFormatter.joinedRelativePaths(
                    currentSelectedURLs(),
                    base: currentTargetedURL()
                )
            )
        default:
            logger.error("Unknown action: \(context.actionID, privacy: .public)")
        }
    }

    private func menuActionContext(for item: NSMenuItem) -> MenuActionContext? {
        if let context = item.representedObject as? MenuActionContext {
            return context
        }

        // macOS can strip representedObject from Finder Sync menu items. Keep a
        // title fallback, mirroring SuperRClick's approach.
        return titleToActionContext[item.title]
    }

    private func currentSelectedURLs() -> [URL] {
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        return selectedURLs.isEmpty ? lastSelectedURLs : selectedURLs
    }

    private func currentTargetedURL() -> URL? {
        FIFinderSyncController.default().targetedURL() ?? lastTargetedURL
    }

    private func copyToPasteboard(_ value: String) {
        guard !value.isEmpty else {
            logger.error("Copy action skipped because selected URLs are empty")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        guard pasteboard.setString(value, forType: .string) else {
            logger.error("Failed to write right-click value to pasteboard")
            return
        }
    }

    private func openHostURL(path: String, queryItems: [URLQueryItem]) {
        var components = URLComponents()
        components.scheme = "mactools"
        components.host = "right-click"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            logger.error("Failed to build host URL for \(path, privacy: .public)")
            return
        }

        NSWorkspace.shared.open(url)
    }

    private static func monitoredDirectories() -> Set<URL> {
        // Finder Sync only asks for menus inside monitored directories. A right-click
        // utility is expected to work from arbitrary Finder locations, so monitor the
        // filesystem root and let the menu builder stay lightweight.
        [URL(fileURLWithPath: "/", isDirectory: true)]
    }
}
