//
//  FrameExtractor.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import Foundation

enum ExtractionOrder: String, Codable, CaseIterable, Sendable {
    case rowMajor
    case columnMajor
}

struct ExtractionSettings: Equatable, Sendable {
    var columns = 1
    var rows = 1
    var frameCount = 1
    var frameWidth: Int?
    var frameHeight: Int?
    var horizontalSpacing = 0
    var verticalSpacing = 0
    var margin = 0
    var order = ExtractionOrder.rowMajor
}

struct ExtractionMismatch: Equatable, Sendable {
    let horizontalPixels: Int
    let verticalPixels: Int
}

enum ExtractionError: LocalizedError, Equatable {
    case invalidGrid
    case invalidFrameCount(capacity: Int)
    case invalidGeometry
    case mismatch(ExtractionMismatch)

    var errorDescription: String? {
        switch self {
        case .invalidGrid: "Columns and rows must each be at least 1."
        case .invalidFrameCount(let capacity):
            "Frame count must be between 1 and the grid capacity of \(capacity)."
        case .invalidGeometry:
            "Frame size, spacing, and margin values are invalid."
        case .mismatch(let value):
            "The grid differs from the source by \(value.horizontalPixels) horizontal and \(value.verticalPixels) vertical pixels."
        }
    }
}

enum FrameExtractor {
    static func extract(source: SpriteSource, settings: ExtractionSettings)
        throws -> [SpriteFrame]
    {
        guard settings.columns > 0, settings.rows > 0 else {
            throw ExtractionError.invalidGrid
        }
        let (capacity, overflow) = settings.columns.multipliedReportingOverflow(
            by: settings.rows
        )
        guard !overflow else { throw LayoutError.arithmeticOverflow }
        guard settings.frameCount > 0, settings.frameCount <= capacity else {
            throw ExtractionError.invalidFrameCount(capacity: capacity)
        }
        guard settings.margin >= 0, settings.horizontalSpacing >= 0,
            settings.verticalSpacing >= 0
        else {
            throw ExtractionError.invalidGeometry
        }

        let availableWidth =
            source.pixelWidth - 2 * settings.margin - (settings.columns - 1)
            * settings.horizontalSpacing
        let availableHeight =
            source.pixelHeight - 2 * settings.margin - (settings.rows - 1)
            * settings.verticalSpacing
        guard availableWidth > 0, availableHeight > 0 else {
            throw ExtractionError.invalidGeometry
        }

        let frameWidth =
            settings.frameWidth ?? availableWidth / settings.columns
        let frameHeight =
            settings.frameHeight ?? availableHeight / settings.rows
        guard frameWidth > 0, frameHeight > 0 else {
            throw ExtractionError.invalidGeometry
        }

        let usedWidth =
            frameWidth * settings.columns
            + settings.horizontalSpacing * (settings.columns - 1)
            + 2 * settings.margin
        let usedHeight =
            frameHeight * settings.rows
            + settings.verticalSpacing * (settings.rows - 1)
            + 2 * settings.margin
        let mismatch = ExtractionMismatch(
            horizontalPixels: source.pixelWidth - usedWidth,
            verticalPixels: source.pixelHeight - usedHeight
        )
        guard mismatch.horizontalPixels == 0, mismatch.verticalPixels == 0
        else {
            throw ExtractionError.mismatch(mismatch)
        }

        return (0..<settings.frameCount).map { index in
            let column: Int
            let row: Int
            switch settings.order {
            case .rowMajor:
                column = index % settings.columns
                row = index / settings.columns
            case .columnMajor:
                column = index / settings.rows
                row = index % settings.rows
            }
            return SpriteFrame(
                id: UUID(),
                sourceID: source.id,
                pixelRect: PixelRect(
                    x: settings.margin + column
                        * (frameWidth + settings.horizontalSpacing),
                    y: settings.margin + row
                        * (frameHeight + settings.verticalSpacing),
                    width: frameWidth,
                    height: frameHeight
                )
            )
        }
    }
}
