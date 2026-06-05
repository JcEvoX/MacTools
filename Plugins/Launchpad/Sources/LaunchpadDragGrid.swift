import AppKit
import SwiftUI

/// Fixed cell geometry — mirrors the previous SwiftUI cell so the AppKit grid looks the
/// same when not dragging.
struct LaunchpadGridMetrics: Equatable {
    var cellWidth: CGFloat = 116
    var cellHeight: CGFloat = 124
    var iconSide: CGFloat = 72
    var columnSpacing: CGFloat = 8
    var rowSpacing: CGFloat = 16
}

/// Where a dragged app should land, expressed as a *relative* position (never an absolute
/// index) so hidden/uninstalled drift can't pollute the persisted order (design §5.1).
enum LaunchpadDropTarget {
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

extension NSPasteboard.PasteboardType {
    static let launchpadAppItem = NSPasteboard.PasteboardType("cc.ggbond.mactools.launchpad.app-id")
}

/// One page of the launcher grid, rendered as a pure-AppKit subtree so per-item drag
/// (`NSDraggingSource`) and click/right-click are arbitrated by AppKit mouse events instead
/// of fighting SwiftUI gestures (design §5.1, mirroring `MenuBarHiddenLayoutStripView`).
/// Paging/selection/search stay in SwiftUI; this view only renders one page's items.
struct LaunchpadDragGrid: NSViewRepresentable {
    var items: [LaunchpadAppItem]
    var columns: Int
    var selectedID: String?
    var isCompact: Bool
    var metrics = LaunchpadGridMetrics()
    var iconProvider: (LaunchpadAppItem) -> NSImage
    var onActivate: (LaunchpadAppItem) -> Void
    var onReveal: (LaunchpadAppItem) -> Void
    var onCopyPath: (LaunchpadAppItem) -> Void
    var onHide: (LaunchpadAppItem) -> Void
    var onMoveToFront: (LaunchpadAppItem) -> Void
    var onMoveToEnd: (LaunchpadAppItem) -> Void
    var onSelect: (LaunchpadAppItem) -> Void
    var onReorder: (String, LaunchpadDropTarget) -> Void
    var onDragBegan: () -> Void
    var onPageSwipe: (Int) -> Void
    var onPageDrag: (CGFloat, CGFloat, Bool) -> Void   // translationX, pageWidth, ended
    var onDismiss: () -> Void

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

    // Empty-space drag (follow-cursor paging) + click (dismiss) tracking, plus scroll paging.
    private var gapDownPoint: NSPoint?
    private var gapMoved = false
    private var pageDragActive = false
    private var scrollAccum: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NOT layer-backed: SwiftUI's `.offset` moving a layer-backed AppKit subtree during
        // follow-cursor paging leaves CA presentation-layer ghost trails. The reorder shuffle
        // still animates via the NSView animator proxy (no layer needed).
        registerForDraggedTypes([.launchpadAppItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }   // top-left origin → natural grid math

    var callbacks: LaunchpadDragGrid? { grid }

    func apply(grid: LaunchpadDragGrid) {
        guard !isDragging else { pendingGrid = grid; return }
        let sameItems = cells.map(\.app.id) == grid.items.map(\.id)
        let sameColumns = columns == max(1, grid.columns)
        self.grid = grid
        self.columns = max(1, grid.columns)
        self.metrics = grid.metrics
        // Fast path: when only the page offset / selection changed (the common case during
        // follow-the-cursor paging), skip the full rebuild + relayout so paging stays smooth.
        if sameItems {
            for cell in cells { cell.isSelected = (cell.app.id == grid.selectedID) }
            if !sameColumns { needsLayout = true }
        } else {
            rebuildCells(items: grid.items, selectedID: grid.selectedID)
            needsLayout = true
        }
    }

    private func rebuildCells(items: [LaunchpadAppItem], selectedID: String?) {
        var reused: [LaunchpadGridCellView] = []
        for app in items {
            let cell = cells.first(where: { $0.app.id == app.id })
                ?? LaunchpadGridCellView(app: app, metrics: metrics)
            cell.container = self
            cell.update(icon: grid?.iconProvider(app) ?? NSImage(), metrics: metrics)
            cell.isSelected = (app.id == selectedID)
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
        layoutCells(order: dragOrder ?? cells, animated: false)
    }

    /// Position cells by their index in `order` — the live `dragOrder` while reordering (so
    /// the gap opens at the hover slot), otherwise the committed `cells`.
    private func layoutCells(order: [LaunchpadGridCellView], animated: Bool) {
        guard !order.isEmpty else { return }
        let gridWidth = CGFloat(columns) * metrics.cellWidth + CGFloat(max(0, columns - 1)) * metrics.columnSpacing
        let leftInset = max(0, (bounds.width - gridWidth) / 2).rounded(.down)
        func frame(forSlot index: Int) -> CGRect {
            let col = index % columns, row = index / columns
            return CGRect(
                x: leftInset + CGFloat(col) * (metrics.cellWidth + metrics.columnSpacing),
                y: CGFloat(row) * (metrics.cellHeight + metrics.rowSpacing),
                width: metrics.cellWidth, height: metrics.cellHeight
            )
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.13
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                // Skip the lifted (hidden) source cell — it follows the cursor, not the grid.
                for (index, cell) in order.enumerated() where cell !== draggedCell {
                    cell.animator().frame = frame(forSlot: index)
                }
            }
        } else {
            for (index, cell) in order.enumerated() { cell.frame = frame(forSlot: index) }
        }
    }

    // MARK: Cell callbacks

    func activate(_ cell: LaunchpadGridCellView) { grid?.onActivate(cell.app) }
    func select(_ cell: LaunchpadGridCellView) { grid?.onSelect(cell.app) }

    func contextMenu(for cell: LaunchpadGridCellView) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = cell.app
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
    @objc private func menuOpen(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onActivate($0) } }
    @objc private func menuReveal(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onReveal($0) } }
    @objc private func menuCopy(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onCopyPath($0) } }
    @objc private func menuMoveFront(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onMoveToFront($0) } }
    @objc private func menuMoveEnd(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onMoveToEnd($0) } }
    @objc private func menuHide(_ sender: NSMenuItem) { menuApp(sender).map { grid?.onHide($0) } }

    // MARK: Drag source lifecycle (from cells)

    func beginDrag(_ cell: LaunchpadGridCellView) {
        isDragging = true
        draggedCell = cell
        dragOrder = cells
        cell.isDragSource = true            // lift off (hidden) so its slot opens up
        grid?.onDragBegan()                 // host freezes the visible order for this drag (§5.3)
    }

    func endDrag(_ cell: LaunchpadGridCellView) {
        draggedCell = nil
        dragOrder = nil
        isDragging = false
        if let pending = pendingGrid {
            pendingGrid = nil
            apply(grid: pending)                       // commit reorder → new cell order
        }
        layoutCells(order: cells, animated: false)     // settle every cell (incl. the lifted one) to its slot
        cell.isDragSource = false                      // reveal the source now it's at the right place (no flash)
        refocusSearchField()                           // so arrow-key navigation keeps working after a drag
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

    // MARK: Drop target — live reorder shuffle (NSDraggingDestination)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { shuffle(toward: sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { shuffle(toward: sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Keep the open gap where it is. A drop inside commits it; a drop outside is undone by
        // endDrag. (Closing the gap on every transient boundary cross caused flicker.)
    }

    /// Open the gap at the slot under the cursor, animating the other cells aside.
    private func shuffle(toward sender: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = draggedCell, var order = dragOrder, sender.draggingSource is LaunchpadGridCellView
        else { return .move }
        let point = convert(sender.draggingLocation, from: nil)
        let target = slotIndex(at: point, count: order.count)
        guard let current = order.firstIndex(of: dragged), current != target else { return .move }
        order.remove(at: current)
        order.insert(dragged, at: min(target, order.count))
        dragOrder = order
        layoutCells(order: order, animated: true)
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let dragged = sender.draggingSource as? LaunchpadGridCellView,
              let order = dragOrder, let index = order.firstIndex(of: dragged)
        else { return false }
        // The dragged app lands at `index` in the new order → after the cell before it,
        // or before the next cell when dropped at the very front.
        let target: LaunchpadDropTarget
        if index > 0 { target = .after(order[index - 1].app.id) }
        else if order.count > 1 { target = .before(order[index + 1].app.id) }
        else { return false }
        grid?.onReorder(dragged.app.id, target)
        return true
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
            switch event.phase {
            case .began:
                scrollAccum = 0
            case .changed:
                scrollAccum += event.scrollingDeltaX
                grid?.onPageDrag(scrollAccum, bounds.width, false)
            case .ended, .cancelled:
                grid?.onPageDrag(scrollAccum, bounds.width, true)
                scrollAccum = 0
            default:
                break
            }
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

final class LaunchpadGridCellView: NSView, NSDraggingSource {
    private(set) var app: LaunchpadAppItem
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var metrics: LaunchpadGridMetrics
    weak var container: LaunchpadGridContainerView?

    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    /// While dragging, the source cell lifts off (hidden) so its grid slot opens up and the
    /// drag image carries the icon under the cursor.
    var isDragSource = false { didSet { isHidden = isDragSource } }

    private var mouseDownPoint: NSPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 8

    init(app: LaunchpadAppItem, metrics: LaunchpadGridMetrics) {
        self.app = app
        self.metrics = metrics
        super.init(frame: CGRect(x: 0, y: 0, width: metrics.cellWidth, height: metrics.cellHeight))

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = CGRect(
            x: (metrics.cellWidth - metrics.iconSide) / 2, y: 8,
            width: metrics.iconSide, height: metrics.iconSide
        )
        addSubview(imageView)

        label.frame = CGRect(x: 2, y: 8 + metrics.iconSide + 8, width: metrics.cellWidth - 4, height: 32)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        label.stringValue = app.name
        addSubview(label)

        toolTip = app.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(app.name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(icon: NSImage, metrics: LaunchpadGridMetrics) {
        imageView.image = icon
        if app.name != label.stringValue { label.stringValue = app.name }
        self.metrics = metrics
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        path.fill()
    }

    // MARK: Click vs drag

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        container?.select(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > dragThreshold else { return }
        didDrag = true
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !didDrag else { return }
        container?.activate(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        container?.select(self)   // highlight which app the menu targets (user feedback)
        guard let menu = container?.contextMenu(for: self) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        container?.refocusSearchField()   // keep arrow-key nav working after the menu closes
    }

    /// Claim mouse events only over the icon itself (+ its label band); the generous side
    /// padding that *looks* empty falls through to the container so a drag there pages
    /// instead of grabbing the app — much closer to native Launchpad hit areas (user feedback).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let icon = imageView.frame
        let active = NSRect(
            x: icon.minX - 4, y: icon.minY - 2,
            width: icon.width + 8, height: bounds.maxY - icon.minY
        )
        return active.contains(local) ? self : nil
    }

    override func accessibilityPerformPress() -> Bool {
        container?.activate(self)
        return true
    }

    // MARK: NSDraggingSource

    private func beginDrag(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(app.id, forType: .launchpadAppItem)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation { .move }

    func draggingSession(_ session: NSDraggingSession, willBeginAt _: NSPoint) {
        session.animatesToStartingPositionsOnCancelOrFail = true
        container?.beginDrag(self)
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        container?.endDrag(self)
    }

    private func dragImage() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return imageView.image ?? NSImage() }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
