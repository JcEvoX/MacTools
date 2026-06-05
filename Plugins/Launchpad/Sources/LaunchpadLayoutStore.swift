import Combine
import Foundation
import OSLog
import MacToolsPluginKit

/// Owns the persisted custom layout and republishes it so the (otherwise non-reactive)
/// overlay grid re-renders on change.
///
/// `ObservableObject` is load-bearing: the overlay grid's only other reactive source is the
/// catalog, and it does NOT observe `onStateChange`, so the grid must inject this store as
/// `@ObservedObject` to ever see a reorder (design §5.5 / risk R1). Persistence mirrors
/// `AppHotkeyStore`'s `JSONEncoder` + `data(forKey:)` write-through; decode failures fall
/// back to alphabetical (`nil`) and never crash.
@MainActor
final class LaunchpadLayoutStore: ObservableObject {
    private enum Keys {
        static let customLayout = "customLayout"
    }

    /// `nil` == no custom layout == alphabetical order. Non-nil == custom-sort mode.
    @Published private(set) var layout: LaunchpadLayout?

    private let storage: PluginStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "LaunchpadLayoutStore"
    )

    init(storage: PluginStorage) {
        self.storage = storage
        self.layout = Self.loadLayout(from: storage, decoder: decoder, logger: logger)
    }

    /// On the first user reorder, freeze the current alphabetical sequence into an all-`.app`
    /// layout so subsequent moves are relative to a stable snapshot. No-op once a layout
    /// exists (design §5.3). The caller must pass the frozen drag-session snapshot, NOT a live
    /// `filtered` read, to avoid racing an async catalog reload.
    func materializeIfNeeded(from apps: [LaunchpadAppItem]) {
        guard layout == nil else { return }
        setLayout(LaunchpadLayout(nodes: apps.map(Self.node(for:))))
    }

    /// Ensure the layout exists and references every currently-visible app, so a following
    /// `move` can target any of them — including reconcile-appended new installs that aren't
    /// yet in the layout (Codex P2). Materializes the full snapshot when none exists;
    /// otherwise appends the missing visible apps at the tail, preserving existing order and
    /// any offscreen/orphan entries (the tolerance window).
    func captureVisibleOrder(_ apps: [LaunchpadAppItem]) {
        materializeIfNeeded(from: apps)
        guard let current = layout else { return }
        let present = Set(current.nodes.flatMap(\.appIDs))
        let missing = apps.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return }
        setLayout(LaunchpadLayout(version: current.version, nodes: current.nodes + missing.map(Self.node(for:))))
    }

    private static func node(for app: LaunchpadAppItem) -> LaunchpadLayoutNode {
        .app(LaunchpadAppRef(id: app.id, name: app.name))
    }

    /// Move `id` to immediately before `targetID` in the root node order.
    func move(id: String, before targetID: String) {
        reorder(id: id, relativeTo: targetID, placeAfter: false)
    }

    /// Move `id` to immediately after `targetID` in the root node order.
    func move(id: String, after targetID: String) {
        reorder(id: id, relativeTo: targetID, placeAfter: true)
    }

    /// Drop the custom layout entirely → back to alphabetical (design §5.4). No-op (and no
    /// write) when already alphabetical.
    func resetToAlphabetical() {
        guard layout != nil else { return }
        layout = nil
        storage.removeObject(forKey: Keys.customLayout)
    }

    // MARK: - Folders (19b)

    /// Stack two root apps into a new folder occupying `targetID`'s slot, carrying both apps;
    /// the dragged app is removed from the root. The apps must already be root nodes (the
    /// caller captures the visible order first, exactly as for a reorder). `id` is injectable
    /// for deterministic tests; production passes a fresh UUID.
    func makeFolder(target targetID: String, dragged draggedID: String,
                    name: String, id: String = UUID().uuidString) {
        guard let current = layout, targetID != draggedID else { return }
        var nodes = current.nodes
        guard let targetIndex = nodes.firstIndex(where: { $0.rootID == targetID }),
              case .app(let targetRef) = nodes[targetIndex],
              let draggedNode = nodes.first(where: { $0.rootID == draggedID }),
              case .app(let draggedRef) = draggedNode
        else { return }
        nodes[targetIndex] = .folder(id: id, name: name, children: [targetRef, draggedRef])
        nodes.removeAll { $0.rootID == draggedID }   // drop the now-foldered dragged app from root
        setLayout(LaunchpadLayout(version: current.version, nodes: nodes))
    }

    /// Move a root app into an existing folder (appended to its children, removed from root).
    func addToFolder(_ folderID: String, app appID: String) {
        guard let current = layout else { return }
        var nodes = current.nodes
        guard let folderIndex = nodes.firstIndex(where: { $0.rootID == folderID }),
              case .folder(let fid, let fname, var children) = nodes[folderIndex],
              let appNode = nodes.first(where: { $0.rootID == appID }),
              case .app(let appRef) = appNode,
              !children.contains(where: { $0.id == appID })
        else { return }
        children.append(appRef)
        nodes[folderIndex] = .folder(id: fid, name: fname, children: children)
        nodes.removeAll { $0.rootID == appID }
        setLayout(LaunchpadLayout(version: current.version, nodes: nodes))
    }

    /// Remove an app from a folder back to the root tail. Dropping to a single remaining child
    /// auto-dissolves the folder, lifting the survivor back into the folder's slot (design §7).
    func removeFromFolder(_ folderID: String, app appID: String) {
        guard let current = layout else { return }
        var nodes = current.nodes
        guard let folderIndex = nodes.firstIndex(where: { $0.rootID == folderID }),
              case .folder(let fid, let fname, var children) = nodes[folderIndex],
              let childIndex = children.firstIndex(where: { $0.id == appID })
        else { return }
        let removed = children.remove(at: childIndex)
        if children.count <= 1 {
            // Auto-dissolve: survivor(s) take the folder's slot, removed app goes to the tail.
            nodes.replaceSubrange(folderIndex...folderIndex, with: children.map(LaunchpadLayoutNode.app))
        } else {
            nodes[folderIndex] = .folder(id: fid, name: fname, children: children)
        }
        nodes.append(.app(removed))
        setLayout(LaunchpadLayout(version: current.version, nodes: nodes))
    }

    /// Rename a folder. An empty name falls back to a default so a folder is never nameless.
    func renameFolder(_ folderID: String, name: String) {
        guard let current = layout else { return }
        var nodes = current.nodes
        guard let folderIndex = nodes.firstIndex(where: { $0.rootID == folderID }),
              case .folder(let fid, _, let children) = nodes[folderIndex]
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nodes[folderIndex] = .folder(id: fid, name: trimmed.isEmpty ? "未命名" : trimmed, children: children)
        setLayout(LaunchpadLayout(version: current.version, nodes: nodes))
    }

    /// Explicitly dissolve a folder: release all its children back to the root, in place.
    func dissolveFolder(_ folderID: String) {
        guard let current = layout else { return }
        var nodes = current.nodes
        guard let folderIndex = nodes.firstIndex(where: { $0.rootID == folderID }),
              case .folder(_, _, let children) = nodes[folderIndex]
        else { return }
        nodes.replaceSubrange(folderIndex...folderIndex, with: children.map(LaunchpadLayoutNode.app))
        setLayout(LaunchpadLayout(version: current.version, nodes: nodes))
    }

    // MARK: - Loading

    /// Decode the stored layout, tolerating absence and corruption.
    /// Missing key → `nil` (alphabetical — the zero-migration default for upgrading users).
    /// Decode failure or `version < currentVersion` → `nil` + a warning, never a crash.
    private static func loadLayout(
        from storage: PluginStorage,
        decoder: JSONDecoder,
        logger: Logger
    ) -> LaunchpadLayout? {
        guard let data = storage.data(forKey: Keys.customLayout) else { return nil }
        guard let decoded = try? decoder.decode(LaunchpadLayout.self, from: data) else {
            logger.warning("Failed to decode custom layout; falling back to alphabetical order.")
            return nil
        }
        guard decoded.version >= LaunchpadLayout.currentVersion else {
            logger.warning(
                "Custom layout version \(decoded.version, privacy: .public) below \(LaunchpadLayout.currentVersion, privacy: .public); falling back to alphabetical order."
            )
            return nil
        }
        return decoded
    }

    // MARK: - Mutation

    private func reorder(id: String, relativeTo targetID: String, placeAfter: Bool) {
        guard let current = layout,
              id != targetID,
              let sourceIndex = current.nodes.firstIndex(where: { $0.rootID == id })
        else { return }

        var nodes = current.nodes
        let moved = nodes.remove(at: sourceIndex)
        if let targetIndex = nodes.firstIndex(where: { $0.rootID == targetID }) {
            nodes.insert(moved, at: placeAfter ? targetIndex + 1 : targetIndex)
        } else {
            // Target not in the layout yet (e.g. a freshly-installed app rendered at the tail
            // but not yet persisted) → fall back to appending at the end.
            nodes.append(moved)
        }

        guard nodes != current.nodes else { return }   // dropping in place writes nothing (R8)
        setLayout(LaunchpadLayout(version: current.version, nodes: nodes))
    }

    private func setLayout(_ newLayout: LaunchpadLayout) {
        layout = newLayout
        persist(newLayout)
    }

    private func persist(_ layout: LaunchpadLayout) {
        guard let data = try? encoder.encode(layout) else {
            logger.error("Failed to encode custom layout; skipping persist.")
            return
        }
        storage.set(data, forKey: Keys.customLayout)
    }
}
