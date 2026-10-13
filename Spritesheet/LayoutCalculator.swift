import Foundation

enum LayoutError: LocalizedError, Equatable {
    case noFrames
    case invalidColumns
    case invalidRows
    case negativeSpacing
    case cellTooSmall(requiredWidth: Int, requiredHeight: Int)
    case manualRowsTooSmall(required: Int)
    case arithmeticOverflow

    var errorDescription: String? {
        switch self {
        case .noFrames: "Add at least one frame before exporting."
        case .invalidColumns: "Columns must be at least 1."
        case .invalidRows: "Rows must be at least 1."
        case .negativeSpacing: "Spacing and margins cannot be negative."
        case let .cellTooSmall(width, height): "The cell must be at least \(width) × \(height) pixels."
        case let .manualRowsTooSmall(required): "The layout needs at least \(required) rows."
        case .arithmeticOverflow: "The requested dimensions exceed integer arithmetic limits."
        }
    }
}

struct CalculatedLayout: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let cellWidth: Int
    let cellHeight: Int
    let outputWidth: Int
    let outputHeight: Int

    func cellOrigin(for index: Int) -> (x: Int, y: Int) {
        let column = index % columns
        let row = index / columns
        return (
            x: column * (cellWidth),
            y: row * (cellHeight)
        )
    }
}

enum LayoutCalculator {
    static func calculate(frameRects: [PixelRect], layout: SheetLayout) throws -> CalculatedLayout {
        guard !frameRects.isEmpty else { throw LayoutError.noFrames }
        guard layout.columns >= 1 else { throw LayoutError.invalidColumns }
        guard layout.horizontalSpacing >= 0, layout.verticalSpacing >= 0, layout.margin >= 0 else {
            throw LayoutError.negativeSpacing
        }

        let maxWidth = frameRects.map(\.width).max() ?? 0
        let maxHeight = frameRects.map(\.height).max() ?? 0
        guard frameRects.allSatisfy({ $0.width > 0 && $0.height > 0 && $0.x >= 0 && $0.y >= 0 }) else {
            throw LayoutError.cellTooSmall(requiredWidth: maxWidth, requiredHeight: maxHeight)
        }

        let cellWidth = layout.cellWidth ?? maxWidth
        let cellHeight = layout.cellHeight ?? maxHeight
        guard cellWidth >= maxWidth, cellHeight >= maxHeight else {
            throw LayoutError.cellTooSmall(requiredWidth: maxWidth, requiredHeight: maxHeight)
        }

        let automaticRows = frameRects.count / layout.columns + (frameRects.count % layout.columns == 0 ? 0 : 1)
        let rows = layout.manualRows ?? automaticRows
        guard rows >= 1 else { throw LayoutError.invalidRows }
        guard rows >= automaticRows else { throw LayoutError.manualRowsTooSmall(required: automaticRows) }

        let width = try checkedDimension(
            cells: layout.columns,
            cellSize: cellWidth,
            spacing: layout.horizontalSpacing,
            margin: layout.margin
        )
        let height = try checkedDimension(
            cells: rows,
            cellSize: cellHeight,
            spacing: layout.verticalSpacing,
            margin: layout.margin
        )

        return CalculatedLayout(
            columns: layout.columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            outputWidth: width,
            outputHeight: height
        )
    }

    private static func checkedDimension(cells: Int, cellSize: Int, spacing: Int, margin: Int) throws -> Int {
        let (cellPixels, cellOverflow) = cells.multipliedReportingOverflow(by: cellSize)
        let (gapPixels, gapOverflow) = max(0, cells - 1).multipliedReportingOverflow(by: spacing)
        let (margins, marginOverflow) = margin.multipliedReportingOverflow(by: 2)
        let (partial, partialOverflow) = cellPixels.addingReportingOverflow(gapPixels)
        let (result, resultOverflow) = partial.addingReportingOverflow(margins)
        guard !cellOverflow, !gapOverflow, !marginOverflow, !partialOverflow, !resultOverflow else {
            throw LayoutError.arithmeticOverflow
        }
        return result
    }

    static func frameOrigin(
        index: Int,
        frame: PixelRect,
        calculated: CalculatedLayout,
        layout: SheetLayout
    ) -> (x: Int, y: Int) {
        let column = index % calculated.columns
        let row = index / calculated.columns
        let cellX = layout.margin + column * (calculated.cellWidth + layout.horizontalSpacing)
        let cellY = layout.margin + row * (calculated.cellHeight + layout.verticalSpacing)

        let xOffset: Int
        switch layout.horizontalAlignment {
        case .leading: xOffset = 0
        case .center: xOffset = (calculated.cellWidth - frame.width) / 2
        case .trailing: xOffset = calculated.cellWidth - frame.width
        }

        let yOffset: Int
        switch layout.verticalAlignment {
        case .top: yOffset = 0
        case .center: yOffset = (calculated.cellHeight - frame.height) / 2
        case .bottom: yOffset = calculated.cellHeight - frame.height
        }

        return (cellX + xOffset, cellY + yOffset)
    }
}
