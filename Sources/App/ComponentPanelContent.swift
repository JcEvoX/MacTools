import AppKit
import SwiftUI
import MacToolsPluginKit

struct ComponentGridPlacement: Identifiable, Equatable {
    let id: String
    let row: Int
    let column: Int
    let span: PluginComponentSpan
    let yOffset: CGFloat
}

enum ComponentPanelLayout {
    static let metrics = PluginComponentPanelLayoutMetrics.default
    static let columns = metrics.columns
    static let cellWidth = metrics.cellWidth
    static let horizontalSpacing = metrics.horizontalSpacing
    static let originalCellHeight = metrics.originalCellHeight
    static let cellHeight = metrics.cellHeight
    static let spacing = horizontalSpacing
    static let horizontalPadding = MenuBarPanelLayout.outerPadding
    static let verticalPadding = MenuBarPanelLayout.outerPadding
    static let verticalSpacing = horizontalPadding
    static let emptyContentHeight: CGFloat = 164
    static let maximumPanelHeight = MenuBarPanelLayout.maximumPanelHeight
    static let minimumPanelHeight = MenuBarPanelLayout.minimumPanelHeight

    static var gridWidth: CGFloat {
        metrics.gridWidth
    }

    static var panelWidth: CGFloat {
        gridWidth + horizontalPadding * 2
    }

    static var contentVerticalPadding: CGFloat {
        verticalPadding * 2
    }

    static var scrollClipCornerRadius: CGFloat {
        MenuBarPanelLayout.cornerRadius
    }

    static func itemWidth(for span: PluginComponentSpan) -> CGFloat {
        metrics.itemWidth(forSpanWidth: span.width)
    }

    static func itemHeight(for span: PluginComponentSpan) -> CGFloat {
        metrics.itemHeight(forSpanHeight: span.height)
    }

    static func xOffset(for placement: ComponentGridPlacement) -> CGFloat {
        metrics.offsetX(forColumn: placement.column)
    }

    static func yOffset(for placement: ComponentGridPlacement) -> CGFloat {
        placement.yOffset
    }

    static func gridContentHeight(for placements: [ComponentGridPlacement]) -> CGFloat {
        guard let maximumBottom = placements.map({
            $0.yOffset + itemHeight(for: $0.span)
        }).max() else {
            return emptyContentHeight
        }

        return maximumBottom
    }

    static func preferredPanelHeight(for items: [PluginComponentItem], screen: NSScreen?) -> CGFloat {
        let rawContentHeight: CGFloat

        if items.isEmpty {
            rawContentHeight = emptyContentHeight
        } else {
            let placements = ComponentGridPlacementEngine.placements(for: items, columns: columns)
            rawContentHeight = gridContentHeight(for: placements)
        }

        let contentHeight = rawContentHeight + contentVerticalPadding
        let minimumHeight = items.isEmpty ? minimumPanelHeight : contentHeight
        return min(
            max(contentHeight, minimumHeight),
            MenuBarPanelLayout.maximumPanelHeight(for: screen)
        )
    }
}

enum ComponentGridPlacementEngine {
    static func placements(
        for items: [PluginComponentItem],
        columns: Int = ComponentPanelLayout.columns
    ) -> [ComponentGridPlacement] {
        var occupiedCells: Set<GridCell> = []
        var placements: [ComponentGridPlacement] = []
        var columnBottoms = Array(repeating: CGFloat(0), count: columns)

        for item in items {
            let span = item.span
            var row = 0

            while true {
                var didPlace = false

                for column in 0..<columns where canPlace(
                    span: span,
                    row: row,
                    column: column,
                    columns: columns,
                    occupiedCells: occupiedCells
                ) {
                    placements.append(
                        ComponentGridPlacement(
                            id: item.id,
                            row: row,
                            column: column,
                            span: span,
                            yOffset: yOffset(
                                column: column,
                                span: span,
                                columnBottoms: columnBottoms
                            )
                        )
                    )
                    markOccupied(
                        span: span,
                        row: row,
                        column: column,
                        occupiedCells: &occupiedCells
                    )
                    updateColumnBottoms(
                        span: span,
                        column: column,
                        yOffset: placements[placements.count - 1].yOffset,
                        columnBottoms: &columnBottoms
                    )
                    didPlace = true
                    break
                }

                if didPlace {
                    break
                }

                row += 1
            }
        }

        return placements
    }

    private static func yOffset(
        column: Int,
        span: PluginComponentSpan,
        columnBottoms: [CGFloat]
    ) -> CGFloat {
        let coveredColumns = column..<(column + span.width)
        let previousBottom = coveredColumns
            .map { columnBottoms[$0] }
            .max() ?? 0

        return previousBottom == 0
            ? 0
            : previousBottom + ComponentPanelLayout.verticalSpacing
    }

    private static func updateColumnBottoms(
        span: PluginComponentSpan,
        column: Int,
        yOffset: CGFloat,
        columnBottoms: inout [CGFloat]
    ) {
        let bottom = yOffset + ComponentPanelLayout.itemHeight(for: span)
        for occupiedColumn in column..<(column + span.width) {
            columnBottoms[occupiedColumn] = bottom
        }
    }

    private static func canPlace(
        span: PluginComponentSpan,
        row: Int,
        column: Int,
        columns: Int,
        occupiedCells: Set<GridCell>
    ) -> Bool {
        guard column + span.width <= columns else {
            return false
        }

        for occupiedRow in row..<(row + span.height) {
            for occupiedColumn in column..<(column + span.width) {
                if occupiedCells.contains(GridCell(row: occupiedRow, column: occupiedColumn)) {
                    return false
                }
            }
        }

        return true
    }

    private static func markOccupied(
        span: PluginComponentSpan,
        row: Int,
        column: Int,
        occupiedCells: inout Set<GridCell>
    ) {
        for occupiedRow in row..<(row + span.height) {
            for occupiedColumn in column..<(column + span.width) {
                occupiedCells.insert(GridCell(row: occupiedRow, column: occupiedColumn))
            }
        }
    }

    private struct GridCell: Hashable {
        let row: Int
        let column: Int
    }
}

struct ComponentPanelContent: View {
    @ObservedObject var pluginHost: PluginHost
    let panelHeight: CGFloat
    let isPanelVisible: Bool
    let onPreferredHeightChange: () -> Void
    let onDismiss: () -> Void

    private var placements: [ComponentGridPlacement] {
        ComponentGridPlacementEngine.placements(for: pluginHost.componentItems)
    }

    private var componentLayoutSignature: String {
        pluginHost.componentItems
            .map { "\($0.id):\($0.span.width)x\($0.span.height)" }
            .joined(separator: "|")
    }

    var body: some View {
        Group {
            if !isPanelVisible {
                Color.clear
            } else if pluginHost.componentItems.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    ComponentGridView(
                        pluginHost: pluginHost,
                        items: pluginHost.componentItems,
                        placements: placements,
                        isPanelVisible: isPanelVisible,
                        onDismiss: onDismiss
                    )
                }
                .background(ScrollViewScrollerVisibilityConfigurator())
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ComponentPanelLayout.scrollClipCornerRadius,
                        style: .continuous
                    )
                )
            }
        }
        .padding(.horizontal, ComponentPanelLayout.horizontalPadding)
        .padding(.vertical, ComponentPanelLayout.verticalPadding)
        .frame(width: ComponentPanelLayout.panelWidth, height: panelHeight, alignment: .topLeading)
        .onAppear {
            guard isPanelVisible else {
                return
            }

            onPreferredHeightChange()
        }
        .onChange(of: componentLayoutSignature) {
            guard isPanelVisible else {
                return
            }

            onPreferredHeightChange()
        }
    }

    private var emptyState: some View {
        PanelPluginEmptyState(
            title: "暂无组件",
            systemImage: "square.grid.2x2",
            iconTint: .purple,
            onInstall: {
                pluginHost.presentPluginMarketplace()
            },
            onEnable: {
                pluginHost.presentInstalledPlugins()
            }
        )
        .frame(minHeight: ComponentPanelLayout.emptyContentHeight)
        .frame(maxWidth: .infinity)
    }
}

private struct ComponentGridView: View {
    @ObservedObject var pluginHost: PluginHost
    let items: [PluginComponentItem]
    let placements: [ComponentGridPlacement]
    let isPanelVisible: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(placements) { placement in
                if let item = items.first(where: { $0.id == placement.id }) {
                    ComponentCardContainer(
                        pluginHost: pluginHost,
                        item: item,
                        isPanelVisible: isPanelVisible,
                        onDismiss: onDismiss
                    )
                    .frame(
                        width: ComponentPanelLayout.itemWidth(for: placement.span),
                        height: ComponentPanelLayout.itemHeight(for: placement.span)
                    )
                    .offset(
                        x: ComponentPanelLayout.xOffset(for: placement),
                        y: ComponentPanelLayout.yOffset(for: placement)
                    )
                }
            }
        }
        .frame(
            width: ComponentPanelLayout.gridWidth,
            height: ComponentPanelLayout.gridContentHeight(for: placements),
            alignment: .topLeading
        )
    }
}

private struct ComponentCardContainer: View {
    @ObservedObject var pluginHost: PluginHost
    let item: PluginComponentItem
    let isPanelVisible: Bool
    let onDismiss: () -> Void

    var body: some View {
        pluginHost.componentViewItem(
            for: item.id,
            dismiss: onDismiss,
            isPanelVisible: isPanelVisible
        ).content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .disabled(!item.isEnabled)
            .opacity(item.isEnabled ? 1 : 0.55)
    }
}
