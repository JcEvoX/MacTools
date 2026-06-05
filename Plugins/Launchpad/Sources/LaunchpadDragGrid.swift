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

    /// Insertion indicator geometry while a drop is hovering.
    private var insertion: (x: CGFloat, yTop: CGFloat, yBottom: CGFloat)?

    // Empty-space drag (paging) + click (dismiss) tracking, plus scroll paging.
    private var gapDownPoint: NSPoint?
    private var gapMoved = false
    private var gapSwiped = false
    private var scrollAccum: CGFloat = 0
    private var scrollFired = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.launchpadAppItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }   // top-left origin → natural grid math

    var callbacks: LaunchpadDragGrid? { grid }

    func apply(grid: LaunchpadDragGrid) {
        guard !isDragging else { pendingGrid = grid; return }
        self.grid = grid
        self.columns = max(1, grid.columns)
        self.metrics = grid.metrics
        rebuildCells(items: grid.items, selectedID: grid.selectedID)
        needsLayout = true
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
        guard !cells.isEmpty else { return }
        let gridWidth = CGFloat(columns) * metrics.cellWidth + CGFloat(max(0, columns - 1)) * metrics.columnSpacing
        let leftInset = max(0, (bounds.width - gridWidth) / 2).rounded(.down)
        for (index, cell) in cells.enumerated() {
            let col = index % columns
            let row = index / columns
            let x = leftInset + CGFloat(col) * (metrics.cellWidth + metrics.columnSpacing)
            let y = CGFloat(row) * (metrics.cellHeight + metrics.rowSpacing)
            cell.frame = CGRect(x: x, y: y, width: metrics.cellWidth, height: metrics.cellHeight)
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
        cell.isDragSource = true
        grid?.onDragBegan()   // let the host freeze the visible order for this drag (design §5.3)
    }

    func endDrag(_ cell: LaunchpadGridCellView) {
        cell.isDragSource = false
        isDragging = false
        insertion = nil
        needsDisplay = true
        if let pending = pendingGrid {
            pendingGrid = nil
            apply(grid: pending)
        }
        refocusSearchField()   // so arrow-key navigation keeps working after a drag
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

    // MARK: Drop target (NSDraggingDestination)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateInsertion(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateInsertion(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        insertion = nil
        needsDisplay = true
    }

    private func updateInsertion(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource is LaunchpadGridCellView else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        if let resolved = resolveTarget(at: point) {
            insertion = resolved.indicator
            needsDisplay = true
            return .move
        }
        insertion = nil
        needsDisplay = true
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let source = sender.draggingSource as? LaunchpadGridCellView else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        guard let resolved = resolveTarget(at: point) else { return false }
        insertion = nil
        needsDisplay = true
        grid?.onReorder(source.app.id, resolved.target)
        return true
    }

    /// Map a drop point to a relative target (before/after the nearest cell) + the indicator
    /// line geometry. Uses the fixed cell frames, never the in-flight drag offset.
    private func resolveTarget(at point: NSPoint) -> (target: LaunchpadDropTarget, indicator: (x: CGFloat, yTop: CGFloat, yBottom: CGFloat))? {
        guard !cells.isEmpty else { return nil }
        // Prefer cells on the same row as the point; fall back to all cells.
        let sameRow = cells.filter { point.y >= $0.frame.minY && point.y <= $0.frame.maxY }
        let candidates = sameRow.isEmpty ? cells : sameRow
        guard let nearest = candidates.min(by: {
            hypot($0.frame.midX - point.x, $0.frame.midY - point.y) < hypot($1.frame.midX - point.x, $1.frame.midY - point.y)
        }) else { return nil }

        let before = point.x < nearest.frame.midX
        let target: LaunchpadDropTarget = before ? .before(nearest.app.id) : .after(nearest.app.id)
        let x = before ? nearest.frame.minX - metrics.columnSpacing / 2 : nearest.frame.maxX + metrics.columnSpacing / 2
        return (target, (x: x, yTop: nearest.frame.minY + 6, yBottom: nearest.frame.maxY - 6))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let insertion else { return }
        let line = NSBezierPath()
        line.move(to: NSPoint(x: insertion.x, y: insertion.yTop))
        line.line(to: NSPoint(x: insertion.x, y: insertion.yBottom))
        line.lineWidth = 2
        line.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        line.stroke()
    }

    // MARK: Scroll paging + gap click-to-dismiss

    /// Two-finger horizontal swipe pages the grid — the native Launchpad gesture. Paging is
    /// a scroll gesture (no mouse button), kept entirely separate from per-item click-drag,
    /// so swiping to page can never grab an app. Cells don't override `scrollWheel`, so a
    /// swipe over an icon bubbles up to here.
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            // Trackpad two-finger swipe: accumulate along the dominant axis, fire once.
            guard event.momentumPhase == [] else { return }      // ignore the inertial tail
            let dominant = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            if event.phase == .began { scrollAccum = 0; scrollFired = false }
            scrollAccum += dominant
            if !scrollFired, abs(scrollAccum) >= 40 {
                scrollFired = true
                grid?.onPageSwipe(scrollAccum < 0 ? 1 : -1)      // swipe left / up → next page
            }
            if event.phase == .ended || event.phase == .cancelled { scrollAccum = 0; scrollFired = false }
        } else {
            // Mouse wheel (discrete notches): one notch → one page, on whichever axis moved.
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard delta != 0 else { return }
            grid?.onPageSwipe(delta < 0 ? 1 : -1)
        }
    }

    override func mouseDown(with event: NSEvent) {
        gapDownPoint = convert(event.locationInWindow, from: nil)
        gapMoved = false
        gapSwiped = false
    }

    /// A horizontal drag that starts on *empty space* (margins / gaps / below the grid —
    /// cells handle their own drags) pages the grid. This is the user's preferred paging
    /// gesture; it can't grab an app because the press never landed on a cell.
    override func mouseDragged(with event: NSEvent) {
        guard let start = gapDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - start.x, dy = point.y - start.y
        if hypot(dx, dy) > 6 { gapMoved = true }
        guard !gapSwiped, abs(dx) > 36, abs(dx) > abs(dy) else { return }
        gapSwiped = true
        grid?.onPageSwipe(dx < 0 ? 1 : -1)          // drag left → next page
    }

    override func mouseUp(with event: NSEvent) {
        defer { gapDownPoint = nil }
        // A click (neither a swipe nor a drag) on empty space dismisses in fullscreen.
        guard !gapSwiped, !gapMoved, grid?.isCompact == false else { return }
        grid?.onDismiss()
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
    var isDragSource = false { didSet { alphaValue = isDragSource ? 0.35 : 1 } }

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
