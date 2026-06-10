import AppKit
import SwiftUI

/// Fixed cell geometry — mirrors the previous SwiftUI cell so the AppKit grid looks the
/// same when not dragging.
struct LaunchpadGridMetrics: Equatable {
    var cellWidth: CGFloat = 116
    var cellHeight: CGFloat = 124
    var iconSide: CGFloat = 64        // smaller, airier icons (closer to iOS) inside the same pitch
    var columnSpacing: CGFloat = 8
    var rowSpacing: CGFloat = 16
}

/// Where a dragged app should land, expressed as a *relative* position (never an absolute
/// index) so hidden/uninstalled drift can't pollute the persisted order (design §5.1).
enum LaunchpadDropTarget: Equatable {
    case before(String)
    case after(String)

    /// True when dropping `dragged` at this target leaves the visible `order` unchanged —
    /// dropping on itself, or onto the side it already neighbours. Lets the caller skip a
    /// reorder that would otherwise flip alphabetical → custom mode for no visible gain.
    func isNoOp(dragged: String, in order: [String]) -> Bool {
        guard let from = order.firstIndex(of: dragged) else { return true }
        switch self {
        case .before(let id):
            if dragged == id { return true }
            guard let to = order.firstIndex(of: id) else { return false }
            return from + 1 == to
        case .after(let id):
            if dragged == id { return true }
            guard let to = order.firstIndex(of: id) else { return false }
            return from == to + 1
        }
    }
}

/// Outcome of releasing an externally-carried (folder-ejected) app over the root grid. Mirrors
/// `commitDrop`'s three branches, but as DATA the coordinator/view maps to store ops — the carried
/// app has no cell in this grid, so the container can't fire onReorder/onMakeFolder itself.
enum LaunchpadExternalDropResult: Equatable {
    case makeFolder(targetAppID: String)
    case addToFolder(folderID: String)
    case reorder(LaunchpadDropTarget?)
}

/// One page of the launcher grid, rendered as a pure-AppKit subtree so per-item drag is tracked
/// directly via mouse events (the cell follows the cursor 1:1, like iOS — not NSDraggingSession)
/// and click/right-click are arbitrated by AppKit instead of fighting SwiftUI gestures.
/// Paging/selection/search stay in SwiftUI; this view only renders one page's items.
struct LaunchpadDragGrid: NSViewRepresentable {
    var items: [LaunchpadDisplayCell]
    var columns: Int
    var selectedID: String?                            // the selected cell's layoutID
    var isCompact: Bool
    var interactionEnabled: Bool = true                // false while a folder overlay is up
    var metrics = LaunchpadGridMetrics()
    var iconProvider: (LaunchpadAppItem) -> NSImage
    var onActivate: (LaunchpadDisplayCell) -> Void     // app → launch, folder → open
    var onReveal: (LaunchpadAppItem) -> Void
    var onCopyPath: (LaunchpadAppItem) -> Void
    var onHide: (LaunchpadAppItem) -> Void
    var onMoveToFront: (LaunchpadAppItem) -> Void
    var onMoveToEnd: (LaunchpadAppItem) -> Void
    var onSelect: (String) -> Void                     // layoutID
    var onReorder: (String, LaunchpadDropTarget) -> Void
    var onMakeFolder: (String, String) -> Void         // (targetAppID, draggedAppID) → new folder
    var onAddToFolder: (String, String) -> Void        // (folderID, draggedAppID)
    var onDragBegan: () -> Void
    var onPageSwipe: (Int) -> Void
    var onPageDrag: (CGFloat, CGFloat, Bool) -> Void   // translationX, pageWidth, ended (empty-space mouse drag)
    var onPageScroll: (CGFloat, CGFloat) -> Void       // trackpad two-finger: raw deltaX, pageWidth — accumulated SHARED in SwiftUI (per-page containers must NOT each accumulate, or the offset oscillates)
    var onDismiss: () -> Void
    var allowFolderCreation: Bool = true               // false inside an open folder (no nested folders → never arm a merge)
    var coordinator: LaunchpadDragCoordinator? = nil   // shared across root pages + the open folder; owns the finger-bound folder-exit handoff
    var folderContextID: String? = nil                 // non-nil only on the open folder's grid → its id, so an ejected app knows its source folder
    var isCurrentRootPage: Bool = false                // true on the visible root page → registers with the coordinator as the eject drop target

    func makeNSView(context _: Context) -> LaunchpadGridContainerView {
        let view = LaunchpadGridContainerView()
        view.apply(grid: self)
        return view
    }

    func updateNSView(_ view: LaunchpadGridContainerView, context _: Context) {
        view.apply(grid: self)
    }
}

// MARK: - Container

final class LaunchpadGridContainerView: NSView {
    private var grid: LaunchpadDragGrid?
    private var cells: [LaunchpadGridCellView] = []
    private var columns = 7
    private var metrics = LaunchpadGridMetrics()

    /// While a drag session is live, defer rebuilding the cell views (so the dragged view
    /// isn't destroyed mid-flight) and remember the latest model to apply on drag end —
    /// the `canSetItemViews` discipline from `MenuBarHiddenLayoutStripView`.
    private var isDragging = false
    private var pendingGrid: LaunchpadDragGrid?

    /// Live visual order while a reorder drag hovers — cells animate aside so a gap opens at
    /// the slot under the cursor (Apple-style live reorder). `nil` when not dragging.
    private var dragOrder: [LaunchpadGridCellView]?
    private weak var draggedCell: LaunchpadGridCellView?

    /// Drag-to-stack (iOS folders): when the cursor moves into a cell's CENTRE zone the cell is
    /// armed as a stack target (create / join a folder on drop); the cell's outer EDGE zone stays
    /// reorder. This is driven purely by the movement `draggingUpdated` callbacks — never by a
    /// timer or AppKit's periodic updates, which a live drag session starves. Arming on entry
    /// means it survives the cursor then holding perfectly still (nothing disarms it), and the
    /// drop commits it. The armed target is read by the cell's `draw` to paint the merge cue.
    private(set) weak var stackTargetCell: LaunchpadGridCellView?

    /// External drag (an app ejected from a folder, carried over THIS root grid). The carried app is
    /// NOT among `cells` — it lives in its source folder until commit — so make-way opens a GAP by
    /// index and merge arms a real `cells` target. No phantom cell view, no `dragOrder` mutation.
    private var externalDragActive = false
    private(set) var externalGapIndex: Int?       // slot the carried app would occupy (make-way gap)
    private var externalDragAppID: String?

    // Empty-space drag (follow-cursor paging) + click (dismiss) tracking, plus scroll paging.
    private var gapDownPoint: NSPoint?
    private var gapMoved = false
    private var pageDragActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NOT layer-backed: SwiftUI's `.offset` moving a layer-backed AppKit subtree during
        // follow-cursor paging leaves CA presentation-layer ghost trails. The reorder shuffle
        // still animates via the NSView animator proxy (no layer needed).
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }   // top-left origin → natural grid math

    var callbacks: LaunchpadDragGrid? { grid }

    /// The laid-out cell views, in committed order. Exposed for drag-to-stack unit tests.
    var cellViews: [LaunchpadGridCellView] { cells }

    /// True while any cell is being dragged — cells read this to suppress hover magnification so the
    /// lifted icon passing over neighbours doesn't make them twitch.
    var hasActiveDrag: Bool { draggedCell != nil }

    /// While a folder overlay is up, the grid is inert: returning `nil` lets the click fall
    /// through to the SwiftUI scrim (which closes the folder) instead of being grabbed by a
    /// cell or the empty-space pager underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard grid?.interactionEnabled != false else { return nil }
        return super.hitTest(point)
    }

    func apply(grid: LaunchpadDragGrid) {
        guard !isDragging else { pendingGrid = grid; return }
        // Compare the full display cells (Equatable) so a folder rename / contents change still
        // rebuilds, whilst an offset/selection-only change during paging takes the fast path.
        let sameItems = cells.map(\.cell) == grid.items
        let sameColumns = columns == max(1, grid.columns)
        self.grid = grid
        self.columns = max(1, grid.columns)
        self.metrics = grid.metrics
        // The visible root page is the drop target for an app ejected from a folder.
        if grid.isCurrentRootPage { grid.coordinator?.registerRootContainer(self) }
        if sameItems {
            for cell in cells { cell.isSelected = (cell.layoutID == grid.selectedID) }
            if !sameColumns { needsLayout = true }
        } else {
            rebuildCells(items: grid.items, selectedID: grid.selectedID)
            needsLayout = true
        }
    }

    private func icons(for cell: LaunchpadDisplayCell) -> [NSImage] {
        guard let provider = grid?.iconProvider else { return [] }
        switch cell {
        case .app(let item): return [provider(item)]
        case .folder(_, _, let items): return items.prefix(9).map(provider)
        }
    }

    private func rebuildCells(items: [LaunchpadDisplayCell], selectedID: String?) {
        var reused: [LaunchpadGridCellView] = []
        for item in items {
            let cell = cells.first(where: { $0.layoutID == item.layoutID })
                ?? LaunchpadGridCellView(cell: item, icons: icons(for: item), metrics: metrics)
            cell.container = self
            cell.update(cell: item, icons: icons(for: item), metrics: metrics)
            cell.isSelected = (item.layoutID == selectedID)
            if cell.superview !== self { addSubview(cell) }
            reused.append(cell)
        }
        for stale in cells where !reused.contains(where: { $0 === stale }) {
            stale.removeFromSuperview()
        }
        cells = reused
    }

    override func layout() {
        super.layout()
        // While an app is being carried over this grid (folder eject), preserve the make-way GAP —
        // a plain re-layout (e.g. triggered by the folder-close animation's re-render) would snap the
        // cells back to their committed slots and the make-way would "spring back".
        if externalDragActive {
            layoutCellsWithGap(animated: false)
        } else {
            layoutCells(order: dragOrder ?? cells, animated: false)
        }
    }

    /// The frame of grid slot `index` (row-major), in container coordinates.
    private func slotRect(_ index: Int) -> CGRect {
        let gridWidth = CGFloat(columns) * metrics.cellWidth + CGFloat(max(0, columns - 1)) * metrics.columnSpacing
        let leftInset = max(0, (bounds.width - gridWidth) / 2).rounded(.down)
        let col = index % columns, row = index / columns
        return CGRect(
            x: leftInset + CGFloat(col) * (metrics.cellWidth + metrics.columnSpacing),
            y: CGFloat(row) * (metrics.cellHeight + metrics.rowSpacing),
            width: metrics.cellWidth, height: metrics.cellHeight
        )
    }

    /// Position cells by their index in `order` — the live `dragOrder` while reordering (so
    /// the gap opens at the hover slot), otherwise the committed `cells`.
    private func layoutCells(order: [LaunchpadGridCellView], animated: Bool, settle: Bool = false) {
        guard !order.isEmpty else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                // Make-way (cells flowing aside as you drag): a smooth, slightly slower ease so it
                // reads as elegant, not a snap. Settle (the drop landing): a touch longer with a
                // gentle overshoot for a satisfying, iOS-like land.
                ctx.duration = settle ? 0.30 : 0.20
                ctx.timingFunction = settle
                    ? CAMediaTimingFunction(controlPoints: 0.34, 1.18, 0.5, 1)
                    : CAMediaTimingFunction(name: .easeInEaseOut)
                // Skip the lifted source cell — it follows the cursor (setFrameOrigin), not the grid.
                for (index, cell) in order.enumerated() where cell !== draggedCell {
                    cell.animator().frame = slotRect(index)
                }
            }
        } else {
            // MUST also skip the dragged cell here — `layout()` uses this path during a drag, and
            // writing the dragged cell back to its slot fights `updateDirectDrag`'s 1:1 follow
            // (that tug-of-war was a source of the every-frame reorder flicker).
            for (index, cell) in order.enumerated() where cell !== draggedCell {
                cell.frame = slotRect(index)
            }
        }
    }

    // MARK: Cell callbacks

    func activate(_ cell: LaunchpadGridCellView) { grid?.onActivate(cell.cell) }
    func select(_ cell: LaunchpadGridCellView) { grid?.onSelect(cell.layoutID) }

    /// App context menu. Folders carry a different menu (rename / dissolve, 19b-4); returning
    /// `nil` suppresses the menu on a folder cell for now.
    func contextMenu(for cell: LaunchpadGridCellView) -> NSMenu? {
        guard case .app(let app) = cell.cell else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = app
            menu.addItem(item)
        }
        add("打开", #selector(menuOpen(_:)))
        menu.addItem(.separator())
        add("在 Finder 中显示", #selector(menuReveal(_:)))
        add("拷贝路径", #selector(menuCopy(_:)))
        menu.addItem(.separator())
        add("移到最前", #selector(menuMoveFront(_:)))
        add("移到最后", #selector(menuMoveEnd(_:)))
        menu.addItem(.separator())
        add("隐藏", #selector(menuHide(_:)))
        return menu
    }

    private func menuApp(_ sender: NSMenuItem) -> LaunchpadAppItem? { sender.representedObject as? LaunchpadAppItem }
    @objc private func menuOpen(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onActivate(.app($0)) } }
    @objc private func menuReveal(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onReveal($0) } }
    @objc private func menuCopy(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onCopyPath($0) } }
    @objc private func menuMoveFront(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onMoveToFront($0) } }
    @objc private func menuMoveEnd(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onMoveToEnd($0) } }
    @objc private func menuHide(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onHide($0) } }

    // MARK: Direct drag (mouse-tracked, like iOS — NOT NSDraggingSession)
    //
    // The system drag (NSDraggingSession) is the laggy "long-press / .onDrag" model: a separate
    // system-managed drag image, input latency, and a modal drag loop that starves timers. iOS
    // SpringBoard and the smooth SwiftUI reorder libraries instead track the pointer DIRECTLY and
    // move the real view 1:1. So the cell forwards its own mouse-drag here: the lifted cell follows
    // the cursor, the others spring aside, and a normal-run-loop dwell can drive pause-to-stack.

    /// Cursor offset within the dragged cell, so it follows the pointer keeping the grab point.
    private var dragGrabOffset = NSPoint.zero
    /// Last drag point in local coords — used on drop to detect an "escape" (dragged clearly out of
    /// the grid bounds → leave the folder).
    private var lastDragPoint: NSPoint?
    /// Last drag point in WINDOW coords — the coordinate space that survives the folder closing, so
    /// the eject commit can resolve the root drop slot.
    private var lastWindowDragPoint: NSPoint?

    func beginDirectDrag(_ cell: LaunchpadGridCellView, atWindowPoint windowPoint: NSPoint) {
        isDragging = true
        draggedCell = cell
        dragOrder = cells
        lastDragPoint = nil
        lastWindowDragPoint = nil
        disarmStackTarget()
        let p = convert(windowPoint, from: nil)
        dragGrabOffset = NSPoint(x: p.x - cell.frame.minX, y: p.y - cell.frame.minY)
        cell.isLifted = true                                   // picked-up look (scales the icon up)
        addSubview(cell, positioned: .above, relativeTo: nil)  // draw on top of its neighbours
        grid?.onDragBegan()                                    // freeze the visible order (§5.3)
    }

    func updateDirectDrag(atWindowPoint windowPoint: NSPoint) {
        guard isDragging, let cell = draggedCell else { return }
        lastWindowDragPoint = windowPoint
        // Eject in progress (folder is zooming closed): the floating window IS the icon now; just
        // follow the cursor in screen space, leave this (closing) grid alone.
        if let coord = grid?.coordinator, coord.ejectActive {
            if let screen = window?.convertPoint(toScreen: windowPoint) {
                coord.moveEject(atScreenPoint: screen, atWindowPoint: windowPoint)
            }
            return
        }
        let p = convert(windowPoint, from: nil)
        lastDragPoint = p
        var origin = NSPoint(x: p.x - dragGrabOffset.x, y: p.y - dragGrabOffset.y)
        // Main grid: keep the lifted icon within the page so it can't be dragged off-screen / under
        // the launcher edge (iOS keeps the dragged icon on-screen). The OPEN FOLDER grid is exempt —
        // its cell must be free to leave the grid to trigger the eject.
        if grid?.folderContextID == nil {
            origin.x = min(max(origin.x, 0), max(0, bounds.width - cell.frame.width))
            origin.y = min(max(origin.y, 0), max(0, bounds.height - cell.frame.height))
        }
        cell.setFrameOrigin(origin)                           // 1:1 follow (clamped on the main grid)
        updateDrag(at: p)                                     // reflow the others / arm a merge target
        // Inside a folder: the moment the cell clearly leaves, begin the finger-bound eject — the
        // folder zooms closed and a floating icon takes over (see LaunchpadDragCoordinator).
        if let folderID = grid?.folderContextID, let coord = grid?.coordinator, draggedClearlyOutsideFolder(cell),
           let screen = window?.convertPoint(toScreen: windowPoint) {
            coord.beginEject(appID: cell.layoutID, sourceFolderID: folderID, icon: cell.primaryIcon,
                             iconSide: metrics.iconSide, atScreenPoint: screen, aboveLevel: window?.level ?? .popUpMenu)
        }
    }

    /// True when the DRAGGED CELL has clearly left the folder's cell cluster. Decided entirely in the
    /// container's OWN coordinate space — the cell's laid-out frame vs the union of the grid slots —
    /// never via a window→view conversion. `convert(_:from:)` is unreliable through the folder
    /// overlay's SwiftUI `scaleEffect`/centering, which made small in-folder reorders falsely eject;
    /// the cell frame and the slots share one coordinate system, so this matches what the user sees.
    /// The zone grows the slot union generously (most on top) to cover the panel's title + padding.
    private func draggedClearlyOutsideFolder(_ cell: LaunchpadGridCellView) -> Bool {
        let union = (0..<cells.count).map(slotRect).reduce(CGRect.null) { $0.union($1) }
        let base = union.isNull ? bounds : union
        let region = CGRect(x: base.minX - 60, y: base.minY - 110,
                            width: base.width + 120, height: base.height + 170)
        return !region.contains(NSPoint(x: cell.frame.midX, y: cell.frame.midY))
    }

    /// Tear down the local drag state after an in-folder app is ejected to the root — no in-folder
    /// reorder is committed (the app left the folder).
    private func teardownDragState(_ cell: LaunchpadGridCellView) {
        disarmStackTarget()
        draggedCell = nil
        dragOrder = nil
        pendingGrid = nil           // an eject closes the folder; drop any deferred apply so the next drag starts clean
        isDragging = false
        cell.isLifted = false
        lastDragPoint = nil
        lastWindowDragPoint = nil
    }

    func endDirectDrag() { endDirectDrag(atWindowPoint: lastWindowDragPoint ?? .zero) }

    func endDirectDrag(atWindowPoint windowPoint: NSPoint) {
        guard let cell = draggedCell else { return }
        lastWindowDragPoint = windowPoint

        // Finger-bound folder exit: if the eject is in flight (folder already closing) OR the cell is
        // released clearly outside, drop the app at the cursor's ROOT slot (not the tail). Releasing
        // INSIDE falls through to a normal in-folder reorder (the revert).
        if let coordinator = grid?.coordinator, let folderID = grid?.folderContextID,
           coordinator.ejectActive || draggedClearlyOutsideFolder(cell) {
            coordinator.commitOut(folderID: folderID, appID: cell.layoutID, atWindowPoint: windowPoint)
            teardownDragState(cell)
            refocusSearchField()
            return
        }

        let settleOrder = dragOrder ?? cells
        let wasMerge = stackTargetCell != nil
        commitDrop(dragged: cell)                              // reorder or make/join folder (disarms)
        draggedCell = nil
        dragOrder = nil
        isDragging = false
        cell.isLifted = false
        lastDragPoint = nil
        if let pending = pendingGrid {
            pendingGrid = nil
            apply(grid: pending)                              // committed order already includes the move
            layoutCells(order: cells, animated: true, settle: true)
        } else {
            // Reorder: adopt the reflowed order as the committed `cells` NOW, so the async SwiftUI
            // apply finds `sameItems` and is a no-op — no instant snap/flicker after the glide.
            // (Merge changes the visible set, so let its apply rebuild into the new folder cell.)
            if !wasMerge { cells = settleOrder }
            layoutCells(order: settleOrder, animated: true, settle: true)   // elegant glide to the drop slot
        }
        refocusSearchField()
    }

    /// Return first-responder focus to the search field after a grid interaction, so typing
    /// and arrow-key navigation keep working (the field is the keyboard handler).
    func refocusSearchField() {
        guard let window, let field = Self.searchField(in: window.contentView) else { return }
        window.makeFirstResponder(field)
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = searchField(in: subview) { return field }
        }
        return nil
    }

    /// iOS folders, movement-driven + STABLE grid: reorder opens a gap only at the seam BETWEEN
    /// two icons; moving onto an icon's CENTRE keeps the grid exactly where it is and just
    /// highlights that icon as a merge target (release = create / join a folder). Arming never
    /// touches the layout, so the target stays put under the cursor.
    ///
    /// Classify the cursor against the cell currently under it: inside that cell's central icon
    /// rect → merge intent (arm it, leave the grid untouched); otherwise → reorder (slide the
    /// dragged gap to that cell's near side — one local shift, never a full-grid reset). Exposed
    /// so unit tests can drive it directly instead of a real `NSDraggingInfo`.
    func updateDrag(at point: NSPoint) {
        guard let dragged = draggedCell else { return }

        // Anti-jitter #1: keep an armed merge target while the cursor stays over its cell (+ a
        // little), so hovering near the merge-zone edge can't toggle merge↔reorder every frame.
        if let armed = stackTargetCell, armed.frame.insetBy(dx: -6, dy: -6).contains(point) { return }

        let slot = slotIndex(at: point, count: cells.count)
        guard cells.indices.contains(slot) else { return }

        // MERGE — classify against the COMMITTED layout (`cells`), NOT the reflowed `dragOrder`.
        // While reordering, the dragged's own gap can occupy this slot in `dragOrder`, so detecting
        // there makes the target read as "self" and silently kills merge (the regression). The
        // committed cell at this geometric slot is the real icon under the cursor. On arm, settle the
        // grid back to committed so that target sits exactly under the cursor and gets the highlight.
        let target = cells[slot]
        if grid?.allowFolderCreation != false, target !== dragged, dragged.cell.folderID == nil, mergeRect(forSlot: slot).contains(point) {
            if stackTargetCell !== target {
                setStackTarget(target)
                if dragOrder != cells {
                    dragOrder = cells
                    layoutCells(order: cells, animated: true)
                }
            }
            return
        }
        clearStackTarget()

        // REORDER — slide the dragged to the hovered cell's NEAR side (before / after). Inserting
        // *beside* the hovered cell (rather than absorbing its slot) keeps that cell where it is, so
        // the next frame can still detect a merge on it. The central merge rect is the dead-band
        // between "before" and "after", so a cursor sitting on the seam can't flap the order.
        guard var order = dragOrder else { return }
        let hovered = order[slot]
        if hovered === dragged { return }
        let m = mergeRect(forSlot: slot)
        let before: Bool
        if point.x < m.minX { before = true }
        else if point.x > m.maxX { before = false }
        else { return }                                   // central band → reserved for merge
        guard let cur = order.firstIndex(of: dragged) else { return }
        order.remove(at: cur)
        guard let hIdx = order.firstIndex(of: hovered) else { return }
        order.insert(dragged, at: before ? hIdx : hIdx + 1)
        if order != dragOrder {
            dragOrder = order
            // Animate the OTHER cells flowing aside (elegant make-way). This is safe — it fires only
            // on an order CHANGE (not every frame) and animates non-dragged cells to FIXED slots; the
            // earlier flicker was the *dragged* cell being re-targeted to a moving point each frame,
            // which `layoutCells` excludes (`where cell !== draggedCell`).
            layoutCells(order: order, animated: true)
        }
    }

    /// The central icon rect of a slot — the merge "hot zone" (icon-centred ~52×52); the seams
    /// to either side stay reorder.
    private func mergeRect(forSlot slot: Int) -> CGRect {
        let s = slotRect(slot)
        let inset: CGFloat = 8
        return CGRect(
            x: s.minX + (metrics.cellWidth - metrics.iconSide) / 2 + inset,
            y: s.minY + 8 + inset,
            width: metrics.iconSide - inset * 2,
            height: metrics.iconSide - inset * 2
        )
    }

    private func setStackTarget(_ cell: LaunchpadGridCellView) {
        guard stackTargetCell !== cell else { return }
        stackTargetCell?.isMergeTarget = false
        stackTargetCell = cell
        cell.isMergeTarget = true
    }

    private func disarmStackTarget() { clearStackTarget() }

    private func clearStackTarget() {
        guard let target = stackTargetCell else { return }
        stackTargetCell = nil
        target.isMergeTarget = false
    }

    /// Resolve a drop: a dwelled-over target makes (app→app) or joins (app→folder) a folder;
    /// otherwise reorder against the live order. Called by `endDirectDrag`; also unit-tested
    /// directly (no real drag session needed).
    @discardableResult
    func commitDrop(dragged: LaunchpadGridCellView) -> Bool {
        let armed = stackTargetCell
        defer { disarmStackTarget() }

        if let target = armed, target !== dragged, dragged.cell.folderID == nil {
            if target.cell.folderID != nil {
                grid?.onAddToFolder(target.layoutID, dragged.layoutID)
            } else {
                grid?.onMakeFolder(target.layoutID, dragged.layoutID)
            }
            return true
        }

        // Otherwise reorder: the dragged app lands at `index` → after the cell before it, or
        // before the next cell when dropped at the very front.
        guard let order = dragOrder, let index = order.firstIndex(of: dragged) else { return false }
        let target: LaunchpadDropTarget
        if index > 0 { target = .after(order[index - 1].layoutID) }
        else if order.count > 1 { target = .before(order[index + 1].layoutID) }
        else { return false }
        grid?.onReorder(dragged.layoutID, target)
        return true
    }

    /// Resolve a root drop target from a WINDOW point using THIS container's live geometry — used
    /// when an app is ejected from a folder and dropped onto the root grid, so it lands at the slot
    /// under the cursor (not the tail). The cursor's side of the slot midline picks before/after.
    /// The ejected app is not among `cells` (it's still in the folder), so no self-exclusion.
    func rootDropTarget(atWindowPoint windowPoint: NSPoint) -> LaunchpadDropTarget? {
        guard !cells.isEmpty else { return nil }
        let p = convert(windowPoint, from: nil)
        let slot = slotIndex(at: p, count: cells.count)
        guard cells.indices.contains(slot) else { return nil }
        let id = cells[slot].layoutID
        return p.x < slotRect(slot).midX ? .before(id) : .after(id)
    }

    // MARK: External drag (an app carried over this root grid after being ejected from a folder)

    /// Begin carrying an external app over this grid. Mutually exclusive with a real in-grid drag.
    func beginExternalDrag(appID: String) {
        guard draggedCell == nil, !externalDragActive else { return }
        externalDragActive = true
        externalDragAppID = appID
        externalGapIndex = nil
        clearStackTarget()
    }

    /// Run the SAME make-way + merge classification an in-grid reorder uses (`updateDrag`), but for a
    /// phantom carried item: merge arms a real `cells` target (app → makeFolder, folder → addToFolder);
    /// otherwise a make-way GAP opens on the hovered cell's near side. Reuses mergeRect/slotIndex and
    /// the same central dead-band + sticky hysteresis so it can't flicker.
    func updateExternalDrag(atWindowPoint windowPoint: NSPoint) {
        guard externalDragActive, draggedCell == nil, !cells.isEmpty else { return }
        // With a window, map window→container (flips y for this flipped view). Windowless (unit tests),
        // `convert(_:from: nil)` would mis-flip, so treat the point as already container-local.
        let point = window != nil ? convert(windowPoint, from: nil) : windowPoint
        if let armed = stackTargetCell, armed.frame.insetBy(dx: -6, dy: -6).contains(point) { return }
        let slot = slotIndex(at: point, count: cells.count)
        guard cells.indices.contains(slot) else { return }
        let target = cells[slot]
        if mergeRect(forSlot: slot).contains(point) {
            if stackTargetCell !== target {
                setStackTarget(target)
                if externalGapIndex != nil { externalGapIndex = nil; layoutCellsWithGap(animated: true) }
            }
            return
        }
        clearStackTarget()
        let m = mergeRect(forSlot: slot)
        let gap: Int
        if point.x < m.minX { gap = slot }
        else if point.x > m.maxX { gap = slot + 1 }
        else { return }                                    // central band → reserved for merge
        if gap != externalGapIndex {
            externalGapIndex = gap
            layoutCellsWithGap(animated: true)
        }
    }

    /// Make-way for the phantom carried item: lay cell `i` at `slotRect(i)`, shifted one slot forward
    /// once past `externalGapIndex`, leaving an empty slot under the cursor. (When the gap is nil this
    /// is the identity layout — i.e. the settle.)
    private func layoutCellsWithGap(animated: Bool) {
        func slot(for index: Int) -> Int {
            guard let gap = externalGapIndex, index >= gap else { return index }
            return index + 1
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.20
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (i, cell) in cells.enumerated() { cell.animator().frame = slotRect(slot(for: i)) }
            }
        } else {
            for (i, cell) in cells.enumerated() { cell.frame = slotRect(slot(for: i)) }
        }
    }

    /// Resolve the release into a store action (merge or reorder). Tears the external drag down.
    func commitExternalDrag() -> LaunchpadExternalDropResult {
        let armed = stackTargetCell
        let gap = externalGapIndex
        defer { endExternalDrag() }
        if let target = armed {
            if let fid = target.cell.folderID { return .addToFolder(folderID: fid) }
            return .makeFolder(targetAppID: target.layoutID)
        }
        guard let gap, !cells.isEmpty else { return .reorder(nil) }
        if gap <= 0 { return .reorder(.before(cells[0].layoutID)) }
        if gap >= cells.count { return .reorder(.after(cells[cells.count - 1].layoutID)) }
        return .reorder(.after(cells[gap - 1].layoutID))
    }

    /// Clear external-drag state and settle the make-way gap closed.
    func endExternalDrag() {
        externalDragActive = false
        externalDragAppID = nil
        externalGapIndex = nil
        clearStackTarget()
        layoutCellsWithGap(animated: true)
    }

    /// Grid slot (row-major index) under a point, clamped to the current item range.
    private func slotIndex(at point: NSPoint, count: Int) -> Int {
        let gridWidth = CGFloat(columns) * metrics.cellWidth + CGFloat(max(0, columns - 1)) * metrics.columnSpacing
        let leftInset = max(0, (bounds.width - gridWidth) / 2)
        let col = min(max(Int((point.x - leftInset) / (metrics.cellWidth + metrics.columnSpacing)), 0), columns - 1)
        let maxRow = max(0, (count - 1) / columns)
        let row = min(max(Int(point.y / (metrics.cellHeight + metrics.rowSpacing)), 0), maxRow)
        return min(max(row * columns + col, 0), max(0, count - 1))
    }

    // MARK: Scroll paging + gap click-to-dismiss

    /// Two-finger horizontal swipe pages the grid — the native Launchpad gesture. Paging is
    /// a scroll gesture (no mouse button), kept entirely separate from per-item click-drag,
    /// so swiping to page can never grab an app. Cells don't override `scrollWheel`, so a
    /// swipe over an icon bubbles up to here.
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            // Trackpad two-finger swipe: follow-the-finger paging — the SAME live-track + snap
            // as the empty-space mouse drag, so the two gestures feel identical.
            guard event.momentumPhase == [] else { return }      // ignore the inertial tail
            // Forward the RAW delta only — accumulation + end-debounce live in SwiftUI so they're
            // SHARED across all per-page containers. (Each page is a separate container; if each
            // kept its own running total, the sliding grid would feed two different totals into the
            // shared offset on alternating frames → the every-frame flicker.)
            grid?.onPageScroll(event.scrollingDeltaX, bounds.width)
        } else {
            // Mouse wheel (discrete notches): one notch → one page, on whichever axis moved.
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard delta != 0 else { return }
            grid?.onPageSwipe(delta < 0 ? 1 : -1)
        }
    }

    override func mouseDown(with event: NSEvent) {
        gapDownPoint = event.locationInWindow   // window coords — stable while the page offsets
        gapMoved = false
        pageDragActive = false
    }

    /// A horizontal drag that starts on *empty space* (margins / gaps / below the grid —
    /// cells handle their own drags) pages the grid, follow-the-cursor: the page tracks the
    /// drag live and snaps once past a threshold on release. Can't grab an app because the
    /// press never landed on a cell.
    ///
    /// The delta is measured in WINDOW coordinates: the container itself slides via the SwiftUI
    /// page offset, so converting the point into its (moving) coordinate space would feed the
    /// offset back into the delta — an oscillation that shows up as ghosting. Window space is
    /// stable, so the drag tracks the real cursor displacement.
    override func mouseDragged(with event: NSEvent) {
        guard let start = gapDownPoint else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if hypot(dx, dy) > 6 { gapMoved = true }
        if !pageDragActive {
            guard abs(dx) > 8, abs(dx) > abs(dy) else { return }   // commit to a horizontal page drag
            pageDragActive = true
        }
        grid?.onPageDrag(dx, bounds.width, false)                   // live: page follows the cursor
    }

    override func mouseUp(with event: NSEvent) {
        let start = gapDownPoint
        gapDownPoint = nil
        if pageDragActive {
            let dx = event.locationInWindow.x - (start?.x ?? 0)
            grid?.onPageDrag(dx, bounds.width, true)                // release: snap or spring back
            pageDragActive = false
        } else if !gapMoved, grid?.isCompact == false {
            // A click (no drag) on empty space dismisses in fullscreen.
            grid?.onDismiss()
        }
    }
}

// MARK: - Cell

final class LaunchpadGridCellView: NSView {
    private(set) var cell: LaunchpadDisplayCell
    /// The store-facing id (app path / folder uuid) for drag payload + reorder.
    var layoutID: String { cell.layoutID }
    /// The app icon, for the window-level floating view when this cell is ejected from a folder.
    var primaryIcon: NSImage? { imageView.image }

    private let imageView = NSImageView()        // single icon — apps only (hidden for folders)
    private let label = NSTextField(labelWithString: "")
    private var folderIcons: [NSImage] = []      // up to 9 child icons (3×3 preview), drawn for a folder cell
    private var metrics: LaunchpadGridMetrics
    weak var container: LaunchpadGridContainerView?

    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    /// While being directly dragged, the cell follows the cursor and its icon scales up (the
    /// iOS pick-up). It stays VISIBLE (unlike the old system-drag, which hid the source).
    var isLifted = false { didSet { if isLifted != oldValue { syncIconScale() } } }
    /// Armed as a folder merge target during a drag: the icon blooms slightly larger and a soft
    /// accent well is drawn behind it (iOS pre-merge feel).
    var isMergeTarget = false { didSet { if isMergeTarget != oldValue { syncIconScale(); needsDisplay = true } } }
    /// Cursor is over this cell → magnify the icon (macOS Dock-style). Suppressed while ANY cell is
    /// being dragged so passing the lifted icon over others doesn't make them twitch.
    var isHovered = false { didSet { if isHovered != oldValue { syncIconScale() } } }
    private var hoverTracking: NSTrackingArea?

    /// The icon scales up ~1.1× while HOVERED (macOS Dock-style magnification), being dragged, or
    /// armed as a merge target — ANIMATED over a short ease so it grows smoothly. Folders scale the
    /// same way (the whole plate enlarges) so a folder and an app feel identical to point at.
    private func syncIconScale() {
        let big = isHovered || isLifted || isMergeTarget
        let target = big ? mergeIconFrame : iconFrame
        if imageView.isHidden { needsDisplay = true }   // folder: the plate is drawn, redraw at the new size
        guard imageView.frame != target else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 1.12, 0.42, 1)  // soft, slightly springy
            imageView.animator().frame = target
        }
    }

    private var mouseDownPoint: NSPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 6

    /// The icon area both the app image view and the folder thumbnail occupy.
    private var iconFrame: CGRect {
        CGRect(x: (metrics.cellWidth - metrics.iconSide) / 2, y: 8,
               width: metrics.iconSide, height: metrics.iconSide)
    }

    /// The icon area enlarged ~1.1× while armed as a merge target.
    private var mergeIconFrame: CGRect {
        iconFrame.insetBy(dx: -metrics.iconSide * 0.05, dy: -metrics.iconSide * 0.05)
    }

    init(cell: LaunchpadDisplayCell, icons: [NSImage], metrics: LaunchpadGridMetrics) {
        self.cell = cell
        self.metrics = metrics
        super.init(frame: CGRect(x: 0, y: 0, width: metrics.cellWidth, height: metrics.cellHeight))

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = iconFrame
        addSubview(imageView)

        label.frame = CGRect(x: 2, y: 8 + metrics.iconSide + 8, width: metrics.cellWidth - 4, height: 32)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        configure(cell: cell, icons: icons)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(cell: LaunchpadDisplayCell, icons: [NSImage], metrics: LaunchpadGridMetrics) {
        self.metrics = metrics
        imageView.frame = iconFrame
        configure(cell: cell, icons: icons)
    }

    /// Bind the view to a display cell: an app shows its single icon, a folder hides the image
    /// view and draws a 2×2 thumbnail of its first four children.
    private func configure(cell: LaunchpadDisplayCell, icons: [NSImage]) {
        self.cell = cell
        switch cell {
        case .app(let item):
            folderIcons = []
            imageView.isHidden = false
            imageView.image = icons.first
            if label.stringValue != item.name { label.stringValue = item.name }
            toolTip = item.name
        case .folder(_, let name, _):
            imageView.isHidden = true
            folderIcons = Array(icons.prefix(9))
            if label.stringValue != name { label.stringValue = name }
            toolTip = name
        }
        setAccessibilityLabel(label.stringValue)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isFolder: Bool = { if case .folder = cell { return true } else { return false } }()

        // App selection: a tight grey rounded square hugging the ICON (not the whole cell). Less
        // vertical inset than horizontal so the top stays inside the cell (the icon sits at y=8).
        if isSelected, !isFolder {
            let sel = iconFrame.insetBy(dx: -8, dy: -6)
            let path = NSBezierPath(roundedRect: sel, xRadius: sel.width * 0.24, yRadius: sel.width * 0.24)
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            path.fill()
        }
        if isMergeTarget { drawStackTargetCue() }       // behind the icon / thumbnail
        if isFolder { drawFolderThumbnail() }

        // Folder selection: a slim accent ring ON TOP of the plate — a grey fill behind the frosted
        // plate read as an ugly grey halo.
        if isSelected, isFolder {
            let ring = folderPlateRect.insetBy(dx: -3, dy: -3)
            let path = NSBezierPath(roundedRect: ring, xRadius: ring.width * 0.28, yRadius: ring.width * 0.28)
            path.lineWidth = 2.5
            NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
            path.stroke()
        }
    }

    /// iOS-style folder tile: a frosted rounded "squircle" plate carrying a 3×3 preview of the
    /// first nine child icons. Drawn (not subviews) so the cell stays non-layer-backed — see the
    /// container's `init` note on why layer-backing here would ghost during follow-cursor paging.
    /// The folder plate, inset to match an app icon's VISIBLE footprint (app icons carry ~10%
    /// transparent padding inside their frame, so an un-inset plate looks bigger than the apps).
    private var folderPlateRect: CGRect { iconFrame.insetBy(dx: 6, dy: 6) }

    private func drawFolderThumbnail() {
        // Hover / lift / merge enlarges the whole plate ~1.1× — same magnification an app icon gets.
        let big = isHovered || isLifted || isMergeTarget
        let plate = big
            ? folderPlateRect.insetBy(dx: -folderPlateRect.width * 0.05, dy: -folderPlateRect.height * 0.05)
            : folderPlateRect
        let radius = plate.width * 0.29          // iOS squircle proportion
        let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

        // Frosted plate: a translucent fill that reads in both light and dark, plus a thin top
        // highlight and bottom shade for a subtle "raised glass" depth.
        NSColor.white.withAlphaComponent(0.10).setFill()
        platePath.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        platePath.fill()
        do {
            let hl = NSRect(x: plate.minX + 1, y: plate.minY + 1, width: plate.width - 2, height: 1.5)
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: hl, xRadius: 1, yRadius: 1).fill()
            let sh = NSRect(x: plate.minX + 1, y: plate.maxY - 2.5, width: plate.width - 2, height: 1.5)
            NSColor.black.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: sh, xRadius: 1, yRadius: 1).fill()
        }

        // Mini-icon grid, CENTRED and filled top-left first. 2×2 for ≤4 apps (bigger icons that
        // fill the plate, like iOS) and 3×3 for 5–9, so a small folder doesn't look sparse/empty.
        let count = folderIcons.count
        let cols = count <= 4 ? 2 : 3
        let inset: CGFloat = plate.width * (cols == 2 ? 0.17 : 0.12)
        let gap: CGFloat = plate.width * (cols == 2 ? 0.11 : 0.08)
        let mini = ((plate.width - inset * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)).rounded(.down)
        let cornerR = mini * 0.24
        // Centre the actually-used rows/cols within the plate so 1–4 icons sit in the middle.
        let usedRows = Int((Double(min(count, cols * cols)) / Double(cols)).rounded(.up))
        let gridW = CGFloat(cols) * mini + CGFloat(cols - 1) * gap
        let gridH = CGFloat(usedRows) * mini + CGFloat(max(0, usedRows - 1)) * gap
        let originX = plate.minX + (plate.width - gridW) / 2
        let originY = plate.minY + (plate.height - gridH) / 2
        for (index, icon) in folderIcons.prefix(cols * cols).enumerated() {
            let col = index % cols, row = index / cols
            let rect = NSRect(
                x: originX + CGFloat(col) * (mini + gap),
                y: originY + CGFloat(row) * (mini + gap),
                width: mini, height: mini
            )
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: cornerR, yRadius: cornerR).addClip()
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// "Drop here to make / join a folder" cue on the armed merge target — a soft accent "well"
    /// (bloom) behind the enlarged icon, like iOS's pre-merge highlight. Light fill, no hard
    /// stroke, sized larger than the icon so it reads around a folder thumbnail too.
    private func drawStackTargetCue() {
        // Bloom around the (enlarged) icon, but keep the TOP inside the cell — `mergeIconFrame` sits
        // at y≈4.8, so a -6 vertical inset would push the cue above y=0 and clip on the first row.
        let zone = iconFrame.insetBy(dx: -6, dy: -4)
        let radius = zone.width * 0.30
        let path = NSBezierPath(roundedRect: zone, xRadius: radius, yRadius: radius)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()
        path.lineWidth = 1
        NSColor.controlAccentColor.withAlphaComponent(0.4).setStroke()
        path.stroke()
    }

    // MARK: Hover magnification (macOS Dock-style)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(ta)
        hoverTracking = ta
    }

    override func mouseEntered(with event: NSEvent) {
        guard container?.hasActiveDrag != true else { return }   // don't magnify while dragging
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    // MARK: Click vs direct drag (mouse-tracked — the cell receives all drag events itself)

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        container?.select(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        if !didDrag {
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - start.x, point.y - start.y) > dragThreshold else { return }
            didDrag = true
            container?.beginDirectDrag(self, atWindowPoint: event.locationInWindow)
        }
        container?.updateDirectDrag(atWindowPoint: event.locationInWindow)   // 1:1 follow
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        if didDrag {
            container?.endDirectDrag(atWindowPoint: event.locationInWindow)
        } else {
            container?.activate(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        container?.select(self)   // highlight which app the menu targets (user feedback)
        guard let menu = container?.contextMenu(for: self) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        container?.refocusSearchField()   // keep arrow-key nav working after the menu closes
    }

    /// Claim mouse events tightly: the icon itself (+2px) and a label strip the width of the
    /// icon — NOT the whole cell. The surrounding padding and the dead band below the label fall
    /// through to the container so a drag/click there pages instead of grabbing the app. Keeps
    /// the per-app hit footprint close to the icon, like iOS (user: the range felt too large).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let icon = iconFrame.insetBy(dx: -2, dy: -2)
        let labelHit = NSRect(x: icon.minX, y: label.frame.minY, width: icon.width, height: label.frame.height)
        return (icon.contains(local) || labelHit.contains(local)) ? self : nil
    }

    override func accessibilityPerformPress() -> Bool {
        container?.activate(self)
        return true
    }
}
