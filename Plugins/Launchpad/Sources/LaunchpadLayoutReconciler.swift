import Foundation

/// Display-time expansion of one root grid slot (computed, never persisted).
///
/// 19a only ever produces `.app`; the `.folder` case is added in 19b (design §3 / §8). When
/// app and folder cells eventually share one render sequence, `id` is the cross-type stable
/// key that `ForEach` / AppKit diffing must use to avoid drag/animation misplacement.
enum LaunchpadDisplayCell: Identifiable, Equatable {
    case app(LaunchpadAppItem)

    var id: String {
        switch self {
        case .app(let item): return item.id
        }
    }
}

/// Pure projection: alphabetical `catalog.apps` (the truth source) + an optional custom
/// `layout` + `hidden` ids → the ordered cells to render.
///
/// This is the whole "safe downstream projection" idea: the output element *set* always
/// equals `visible` — only the order differs — so the grid's paging / `selectedIndex`
/// clamping downstream needs zero changes (design §5.2). The function is pure and never
/// writes persistence; only explicit user actions mutate the layout.
enum LaunchpadLayoutReconciler {
    static func reconcile(
        apps: [LaunchpadAppItem],
        layout: LaunchpadLayout?,
        hidden: Set<String>
    ) -> [LaunchpadDisplayCell] {
        // 1. Hidden filtered first, prior to and independent of ordering (invariant 4).
        let visible = apps.filter { !hidden.contains($0.id) }

        // 2. No custom layout → alphabetical passthrough (default behaviour unchanged).
        guard let layout else { return visible.map(LaunchpadDisplayCell.app) }

        // 3. Emit in layout order; silently skip ids that are missing / hidden / uninstalled.
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cells: [LaunchpadDisplayCell] = []
        var referenced = Set<String>()
        cells.reserveCapacity(visible.count)

        for node in layout.nodes {
            switch node {
            case .app(let ref):
                // `referenced.insert(...).inserted` also collapses any accidental duplicate
                // ref so each id is emitted at most once (set stays == visible).
                guard let item = byID[ref.id], referenced.insert(ref.id).inserted else { continue }
                cells.append(.app(item))
            case .folder:
                // 19a never produces folders; 19b extends reconcile to render folder cells.
                continue
            }
        }

        // 4. Newly-installed apps (in `visible`, not referenced by the layout) append at the
        //    root tail. `visible` is already alphabetical, so iterating it keeps the tail
        //    alphabetical too (invariant 2).
        for item in visible where !referenced.contains(item.id) {
            cells.append(.app(item))
        }

        return cells
    }
}
