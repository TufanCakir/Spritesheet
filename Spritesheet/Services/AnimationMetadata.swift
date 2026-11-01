import Foundation

/// Optional fields allow future format adapters to map into the same recovery configuration.
struct AnimationMetadata: Codable, Sendable {
    var columns: Int?
    var rows: Int?
    var frameCount: Int?
    var fps: Double?
    var frameWidth: Int?
    var frameHeight: Int?
    var horizontalSpacing: Int?
    var verticalSpacing: Int?
    var marginX: Int?
    var marginY: Int?

    var hasCompleteGrid: Bool { columns != nil && rows != nil && frameCount != nil }

    static func decode(_ data: Data) throws -> AnimationMetadata {
        guard data.count <= 1_048_576 else { throw MetadataError.invalid }
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            let positive = [value.columns, value.rows, value.frameCount, value.frameWidth, value.frameHeight]
            let nonnegative = [value.horizontalSpacing, value.verticalSpacing, value.marginX, value.marginY]
            guard positive.compactMap({ $0 }).allSatisfy({ $0 > 0 }),
                  nonnegative.compactMap({ $0 }).allSatisfy({ $0 >= 0 }),
                  value.fps.map({ $0.isFinite && (1...60).contains($0) }) ?? true,
                  positive.contains(where: { $0 != nil }) || value.fps != nil ||
                    nonnegative.contains(where: { $0 != nil }) else { throw MetadataError.invalid }
            if let columns = value.columns, let rows = value.rows {
                let (capacity, overflow) = columns.multipliedReportingOverflow(by: rows)
                guard !overflow, value.frameCount.map({ $0 <= capacity }) ?? true else {
                    throw MetadataError.invalid
                }
            }
            guard value.frameCount.map({ $0 <= FrameExtractor.maximumFrameCount }) ?? true else {
                throw MetadataError.invalid
            }
            return value
        } catch { throw MetadataError.invalid }
    }

    func applying(to current: ExtractionSettings) -> ExtractionSettings {
        var result = current
        if let columns { result.columns = columns; result.frameWidth = nil }
        if let rows { result.rows = rows; result.frameHeight = nil }
        if let frameCount { result.frameCount = frameCount }
        if let frameWidth { result.frameWidth = frameWidth }
        if let frameHeight { result.frameHeight = frameHeight }
        if let horizontalSpacing { result.horizontalSpacing = horizontalSpacing }
        if let verticalSpacing { result.verticalSpacing = verticalSpacing }
        if let marginX { result.marginX = marginX }
        if let marginY { result.marginY = marginY }
        return result
    }
}

enum MetadataError: LocalizedError {
    case invalid
    var errorDescription: String? {
        String(localized: "The JSON metadata is invalid. Use positive grid values and FPS between 1 and 60.")
    }
}

actor AnimationMetadataImporter {
    func load(_ url: URL) throws -> AnimationMetadata {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw MetadataError.invalid }
        return try AnimationMetadata.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }
}
