import CoreGraphics
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
    var marginX: Int?
    var marginY: Int?
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
        case .invalidGrid:
            String(localized: "Columns and rows must each be at least 1.")
        case .invalidFrameCount(let capacity):
            String(localized: "Frame count must be between 1 and \(capacity).")
        case .invalidGeometry:
            String(localized: "Frame size, spacing, or margins are invalid or too large.")
        case .mismatch:
            String(localized: "The grid does not fit the image exactly. Adjust the frame size, spacing, or margins.")
        }
    }
}

enum FrameExtractor {
    // Bound metadata allocation independently of image size.
    static let maximumFrameCount = 10_000

    static func extract(source: SpriteSource, settings: ExtractionSettings) throws -> [SpriteFrame] {
        guard settings.columns > 0, settings.rows > 0 else { throw ExtractionError.invalidGrid }
        let (capacity, overflow) = settings.columns.multipliedReportingOverflow(by: settings.rows)
        guard !overflow else { throw ExtractionError.invalidGeometry }
        guard settings.frameCount > 0, settings.frameCount <= min(capacity, maximumFrameCount) else {
            throw ExtractionError.invalidFrameCount(capacity: min(capacity, maximumFrameCount))
        }
        let x = settings.marginX ?? settings.margin
        let y = settings.marginY ?? settings.margin
        let width = try dimension(source.pixelWidth, cells: settings.columns,
                                  explicit: settings.frameWidth, spacing: settings.horizontalSpacing, margin: x)
        let height = try dimension(source.pixelHeight, cells: settings.rows,
                                   explicit: settings.frameHeight, spacing: settings.verticalSpacing, margin: y)
        let mismatch = ExtractionMismatch(horizontalPixels: width.remainder, verticalPixels: height.remainder)
        guard width.remainder == 0, height.remainder == 0 else { throw ExtractionError.mismatch(mismatch) }
        return (0..<settings.frameCount).map { index in
            let column = settings.order == .rowMajor ? index % settings.columns : index / settings.rows
            let row = settings.order == .rowMajor ? index / settings.columns : index % settings.rows
            return SpriteFrame(id: UUID(), sourceID: source.id, pixelRect: PixelRect(
                x: x + column * (width.size + settings.horizontalSpacing),
                y: y + row * (height.size + settings.verticalSpacing),
                width: width.size, height: height.size))
        }
    }

    private static func dimension(_ pixels: Int, cells: Int, explicit: Int?,
                                  spacing: Int, margin: Int) throws -> (size: Int, remainder: Int) {
        guard pixels > 0, spacing >= 0, margin >= 0 else { throw ExtractionError.invalidGeometry }
        let (margins, mo) = margin.multipliedReportingOverflow(by: 2)
        let (gaps, go) = (cells - 1).multipliedReportingOverflow(by: spacing)
        let (occupied, oo) = margins.addingReportingOverflow(gaps)
        guard !mo, !go, !oo, occupied < pixels else { throw ExtractionError.invalidGeometry }
        let available = pixels - occupied
        let size = explicit ?? available / cells
        guard size > 0, size <= available / cells,
              size <= Int.max - spacing else { throw ExtractionError.invalidGeometry }
        return (size, available - size * cells)
    }

    /// CGImage cropping uses image pixel coordinates, with the first scanline at y = 0.
    /// Do not apply the Quartz drawing-context Y flip here.
    static func crop(_ image: CGImage, rect: PixelRect) throws -> CGImage {
        guard rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
              rect.width <= image.width, rect.height <= image.height,
              rect.x <= image.width - rect.width, rect.y <= image.height - rect.height,
              let cropped = image.cropping(to: CGRect(x: rect.x, y: rect.y,
                                                      width: rect.width, height: rect.height)) else {
            throw ExtractionError.invalidGeometry
        }
        return cropped
    }

    static func suggestions(for source: SpriteSource) -> [ExtractionSettings] {
        [16, 32, 64, 128, 256].compactMap { size in
            guard source.pixelWidth > 0, source.pixelHeight > 0,
                  source.pixelWidth % size == 0, source.pixelHeight % size == 0 else { return nil }
            let columns = source.pixelWidth / size
            let rows = source.pixelHeight / size
            let (count, overflow) = columns.multipliedReportingOverflow(by: rows)
            guard !overflow, count <= maximumFrameCount else { return nil }
            return ExtractionSettings(columns: columns, rows: rows, frameCount: count,
                                      frameWidth: size, frameHeight: size)
        }
    }
}
