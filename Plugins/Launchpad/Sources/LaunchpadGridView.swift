import AppKit
import SwiftUI

/// The launcher content: a focused search field over a horizontally **paged** app grid
/// (classic Launchpad layout).
///
/// Input model (Codex P0 #2/#3): the `NSSearchField` is first responder, so typing /
/// IME composition just works while the grid stays visible ("grid-first, type to
/// search"). Arrow keys move the grid selection and Return launches — routed through
/// the field's `doCommandBySelector`, which the system does NOT call during IME
/// composition, so a candidate-selecting Return never launches an app.
///
/// Paging (LP4b): macOS SwiftUI has no `PageTabViewStyle`, so pages are laid out in a
/// single clipped `HStack` and slid by an `offset`. `selectedIndex` is the source of
/// truth; the visible page is derived from it (`selectedIndex / perPage`), so keyboard
/// navigation, page dots and drag all stay consistent.
struct LaunchpadGridView: View {
    @ObservedObject var catalog: LaunchpadAppCatalog
    /// Custom-order layout. Observed so a reorder / reset (which mutates `@Published layout`)
    /// re-evaluates `filtered` and re-renders — the overlay grid does NOT observe
    /// `onStateChange`, so this injection is the only reorder-refresh path (design §5.5 / R1).
    @ObservedObject var layoutStore: LaunchpadLayoutStore
    /// Fixed column count, or `LaunchpadPreferences.autoColumns` (0) to fit to width.
    var columns: Int = LaunchpadPreferences.autoColumns
    /// Compact (centered panel) vs fullscreen — tightens padding and, since a small
    /// panel dismisses by clicking *outside* it (→ app resigns active), drops the
    /// inside-the-panel click-to-dismiss that fullscreen Launchpad uses.
    var isCompact: Bool = false
    /// Ids hidden from the grid (snapshot at open; the live set below seeds from it).
    var hiddenAppIDs: Set<String> = []
    var onActivate: (LaunchpadAppItem) -> Void
    var onReveal: (LaunchpadAppItem) -> Void
    var onHide: (LaunchpadAppItem) -> Void
    var onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var currentPage = 0
    /// Hiding an app removes it from the grid immediately (live), while `onHide`
    /// persists it; seeded from `hiddenAppIDs` on appear.
    @State private var sessionHidden: Set<String> = []
    @State private var columnCount = 7
    @State private var rowCount = 5
    /// Visible order frozen at drag start, so a drop reorders against exactly what the user
    /// dragged — even if an async catalog reload lands mid-drag (design §5.3 / Codex P2).
    @State private var dragOrderSnapshot: [LaunchpadAppItem]?
    /// Live horizontal offset while an empty-space drag pages the grid (follow-the-cursor).
    @State private var pageDragTranslation: CGFloat = 0

    // Must match `LaunchpadGridMetrics` defaults so paging math agrees with the AppKit grid.
    private let cellWidth: CGFloat = 116
    private let cellHeight: CGFloat = 124
    private let columnSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 16

    private var filtered: [LaunchpadAppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty else { return searchResults(query: query) }
        // Layout state: custom order via the pure reconcile projection. `layout == nil` →
        // alphabetical, byte-for-byte the previous behaviour. 19a only yields `.app` cells,
        // so the grid stays a flat `[LaunchpadAppItem]` and every paging / selection path
        // below is untouched (design §5.2: output set == visible, only order differs).
        return LaunchpadLayoutReconciler
            .reconcile(apps: catalog.apps, layout: layoutStore.layout, hidden: sessionHidden)
            .compactMap { cell -> LaunchpadAppItem? in
                guard case .app(let item) = cell else { return nil }
                return item
            }
    }

    /// Flat fuzzy search — ignores layout/folders entirely and never touches persistence
    /// (design §6); clearing the query returns to the reconciled layout for free.
    private func searchResults(query: String) -> [LaunchpadAppItem] {
        let visible = catalog.apps.filter { !sessionHidden.contains($0.id) }
        // Fuzzy (subsequence) match, ranked by relevance; ties keep alphabetical order.
        var scored: [(app: LaunchpadAppItem, score: Int)] = []
        for app in visible {
            if let s = LaunchpadFuzzy.score(name: app.name, query: query) {
                scored.append((app, s))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
        return scored.map(\.app)
    }

    private var perPage: Int { max(1, columnCount * rowCount) }

    private var pageCount: Int {
        max(1, Int(ceil(Double(filtered.count) / Double(perPage))))
    }

    var body: some View {
        ZStack {
            // Click-to-dismiss on empty space — the fullscreen Launchpad behaviour. Icons
            // and the search field (an AppKit NSView) hit-test first and swallow their own
            // clicks, so only genuine empty space (gaps/margins) reaches this layer. In
            // compact mode the panel itself is the content, so inside clicks must NOT
            // dismiss (outside clicks deactivate the app → close).
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !isCompact { onDismiss() } }

            VStack(spacing: isCompact ? 14 : 20) {
                searchBar
                content
            }
            .padding(.top, isCompact ? 24 : 60)
            .padding(.bottom, isCompact ? 20 : 32)
            .padding(.horizontal, isCompact ? 24 : 48)
        }
        .onAppear { selectedIndex = 0; currentPage = 0; sessionHidden = hiddenAppIDs }
        .onChange(of: searchText) { _, _ in selectedIndex = 0; currentPage = 0 }
    }

    private var searchBar: some View {
        LaunchpadSearchField(
            text: $searchText,
            onMove: handleMove,
            onLaunch: activateSelection,
            onCancel: onDismiss
        )
        .frame(width: 360, height: 28)
    }

    @ViewBuilder
    private var content: some View {
        if catalog.isLoading && catalog.apps.isEmpty {
            Spacer()
            ProgressView().controlSize(.large)
            Spacer()
        } else if filtered.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? "未找到应用" : "无匹配应用")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            pagedGrid
        }
    }

    private var pagedGrid: some View {
        GeometryReader { geo in
            let visiblePage = min(currentPage, pageCount - 1)
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        pageContent(page: page, columns: columnCount)
                            .frame(width: geo.size.width)
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .offset(x: -CGFloat(visiblePage) * geo.size.width + pageDragTranslation)
                .clipped()
                // Paging is handled inside the AppKit grid: `onPageDrag` tracks an empty-space
                // drag live (follow-the-cursor) and `onPageSwipe` handles scroll; both share one
                // event-arbitration tree with per-item drag (design §5.1). Page changes animate
                // via `withAnimation` in the handlers (not a value-keyed modifier) so the live
                // drag offset and the snap stay one continuous motion.

                if pageCount > 1 {
                    pageIndicator(current: visiblePage)
                }
            }
            .onAppear { updateLayout(size: geo.size) }
            .onChange(of: geo.size) { _, size in updateLayout(size: size) }
        }
    }

    /// One page rendered as an AppKit drag grid (per-item `NSDraggingSource`). Items are
    /// sliced from `filtered`; selection/activation/reorder use the global `filtered` order
    /// so navigation and ordering span the whole list.
    private func pageContent(page: Int, columns: Int) -> some View {
        let start = page * perPage
        let end = min(start + perPage, filtered.count)
        let items = start < end ? Array(filtered[start..<end]) : []
        return LaunchpadDragGrid(
            items: items,
            columns: columns,
            selectedID: selectedID,
            isCompact: isCompact,
            iconProvider: { catalog.icon(for: $0) },
            onActivate: activateApp,
            onReveal: onReveal,
            onCopyPath: copyPath,
            onHide: hideApp,
            onMoveToFront: moveAppToFront,
            onMoveToEnd: moveAppToEnd,
            onSelect: selectApp,
            onReorder: handleReorder,
            onDragBegan: { dragOrderSnapshot = filtered },
            onPageSwipe: { direction in goToPage(min(currentPage, pageCount - 1) + direction) },
            onPageDrag: handlePageDrag,
            onDismiss: onDismiss
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Selected app id for the AppKit cell highlight, derived from the global `selectedIndex`.
    private var selectedID: String? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex].id : nil
    }

    private func activateApp(_ app: LaunchpadAppItem) {
        if let index = filtered.firstIndex(where: { $0.id == app.id }) { selectedIndex = index }
        onActivate(app)
    }

    private func selectApp(_ app: LaunchpadAppItem) {
        if let index = filtered.firstIndex(where: { $0.id == app.id }) { selectedIndex = index }
    }

    private func copyPath(_ app: LaunchpadAppItem) {
        // Lightweight clipboard action — no lifecycle effect, so keep the launcher open.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.url.path, forType: .string)
    }

    private func hideApp(_ app: LaunchpadAppItem) {
        sessionHidden.insert(app.id)        // drop from this grid immediately
        selectedIndex = 0
        currentPage = 0
        onHide(app)                         // persist (settings page can restore)
    }

    /// First successful drop materialises the alphabetical snapshot into a layout, then
    /// applies the relative move; selection follows the dragged app by id to its new global
    /// index (design §5.3 / §5.5). Never writes while searching (search is read-only).
    private func handleReorder(_ draggedID: String, _ target: LaunchpadDropTarget) {
        // Reorder against the order frozen at drag start, not a list a mid-drag reload may
        // have changed (design §5.3 / Codex P2).
        let order = dragOrderSnapshot ?? filtered
        dragOrderSnapshot = nil
        // A drop that changes nothing visible must not flip alphabetical → custom mode (Codex P2).
        guard isLayoutEditable, !target.isNoOp(dragged: draggedID, in: order.map(\.id)) else { return }
        layoutStore.captureVisibleOrder(order)
        switch target {
        case .before(let id): layoutStore.move(id: draggedID, before: id)
        case .after(let id):  layoutStore.move(id: draggedID, after: id)
        }
        relocateSelection(to: draggedID)
    }

    private func moveAppToFront(_ app: LaunchpadAppItem) {
        guard isLayoutEditable, let first = filtered.first, first.id != app.id else { return }
        layoutStore.captureVisibleOrder(filtered)
        layoutStore.move(id: app.id, before: first.id)
        relocateSelection(to: app.id)
    }

    private func moveAppToEnd(_ app: LaunchpadAppItem) {
        guard isLayoutEditable, let last = filtered.last, last.id != app.id else { return }
        layoutStore.captureVisibleOrder(filtered)
        layoutStore.move(id: app.id, after: last.id)
        relocateSelection(to: app.id)
    }

    /// After a reorder, keep the selection on the moved app by id (not position) and bring its
    /// page on screen (design §5.5: selection is identity-, not index-, anchored).
    private func relocateSelection(to id: String) {
        guard let index = filtered.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        currentPage = perPage > 0 ? index / perPage : 0
    }

    /// Reorders only apply in the layout state; search is a read-only flat projection.
    private var isLayoutEditable: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pageIndicator(current: Int) -> some View {
        HStack(spacing: 9) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(Color.primary.opacity(page == current ? 0.55 : 0.18))
                    .frame(width: 7, height: 7)
                    .onTapGesture { goToPage(page) }
                    // Mirror the cell fix: `.onTapGesture` is mouse-only, so VoiceOver /
                    // AX press needs an explicit action to actually change page.
                    .accessibilityAction { goToPage(page) }
                    .accessibilityLabel("第 \(page + 1) 页")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Layout + navigation

    private func updateLayout(size: CGSize) {
        if columns != LaunchpadPreferences.autoColumns {
            columnCount = max(1, columns)                       // fixed count from preferences
        } else {
            let usable = max(size.width, cellWidth)
            columnCount = max(1, Int(usable / (cellWidth + columnSpacing)))
        }
        // Reserve ~26pt for the page indicator row below the grid.
        let usableHeight = max(cellHeight, size.height - 26)
        rowCount = max(1, Int((usableHeight + rowSpacing) / (cellHeight + rowSpacing)))
        // Layout (and thus perPage) changed: keep the selection valid and re-derive the
        // visible page *from it*, so the source-of-truth selection is always on screen —
        // not stranded on a now-wrong page (Codex P1).
        selectedIndex = min(max(selectedIndex, 0), max(0, filtered.count - 1))
        currentPage = filtered.isEmpty ? 0 : selectedIndex / perPage
    }

    /// Book-style paged navigation: arrows move within the current page; pressing past an
    /// edge turns the page keeping the cross-axis position (→ at the rightmost column jumps
    /// to the next page's same row, etc.).
    private func handleMove(_ direction: LaunchpadSearchField.MoveDirection) {
        guard !filtered.isEmpty else { return }
        let cols = max(1, columnCount)
        let rows = max(1, rowCount)
        let per = perPage
        let page = selectedIndex / per
        let local = selectedIndex % per
        let col = local % cols
        let row = local / cols
        let lastPage = max(0, (filtered.count - 1) / per)

        var target = selectedIndex
        switch direction {
        case .right:
            if col < cols - 1, selectedIndex + 1 < filtered.count { target = selectedIndex + 1 }
            else if page < lastPage { target = (page + 1) * per + row * cols }          // next page, same row
        case .left:
            if col > 0 { target = selectedIndex - 1 }
            else if page > 0 { target = (page - 1) * per + row * cols + (cols - 1) }     // prev page, same row, last col
        case .up:
            if row > 0 { target = selectedIndex - cols }
            else if page > 0 { target = (page - 1) * per + (rows - 1) * cols + col }     // prev page, bottom row, same col
        case .down:
            if row < rows - 1, selectedIndex + cols < filtered.count { target = selectedIndex + cols }
            else if page < lastPage { target = (page + 1) * per + col }                 // next page, top row, same col
        }

        selectedIndex = min(max(target, 0), filtered.count - 1)
        withAnimation(pageSnap) { currentPage = selectedIndex / per }   // bring the selection's page on screen
    }

    private func goToPage(_ page: Int) {
        // A stale gesture/dot closure could fire after an async catalog update emptied the
        // list; avoid `filtered.count - 1 == -1` (Codex P2).
        guard !filtered.isEmpty else { selectedIndex = 0; currentPage = 0; return }
        let target = min(max(page, 0), pageCount - 1)
        withAnimation(pageSnap) { currentPage = target }
        // Move selection onto the page so keyboard nav resumes from what's visible.
        selectedIndex = min(target * perPage, filtered.count - 1)
    }

    private var pageSnap: Animation { .spring(response: 0.34, dampingFraction: 0.86) }

    /// Follow-cursor paging: while dragging empty space the page tracks the cursor; on release
    /// it snaps to the adjacent page past a threshold, otherwise springs back.
    private func handlePageDrag(_ translationX: CGFloat, width: CGFloat, ended: Bool) {
        let pageW = max(1, width)                       // real page width from the AppKit grid (no @State race)
        let last = max(0, pageCount - 1)
        let cur = min(currentPage, last)
        var t = translationX
        // Rubber-band so you can't pull past the first / last page.
        if (cur == 0 && t > 0) || (cur == last && t < 0) { t *= 0.35 }
        t = min(max(t, -pageW), pageW)
        guard ended else { pageDragTranslation = t; return }
        let threshold = max(45, pageW * 0.18)
        withAnimation(pageSnap) {
            if t <= -threshold, cur < last { currentPage = cur + 1 }
            else if t >= threshold, cur > 0 { currentPage = cur - 1 }
            pageDragTranslation = 0
        }
        selectedIndex = min(currentPage * perPage, max(0, filtered.count - 1))
    }

    private func activateSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        onActivate(filtered[selectedIndex])
    }
}
