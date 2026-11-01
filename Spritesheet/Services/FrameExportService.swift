import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGFrameCodec {
    static let maximumDecodedBytes = 256 * 1_024 * 1_024

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImportFailure.corrupt(url.lastPathComponent)
        }
        try validateSize(width: width, height: height)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw ImportFailure.corrupt(url.lastPathComponent)
        }
        return image
    }

    static func validateSize(width: Int, height: Int) throws {
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        // Budget for up to 16-bit RGBA without allocating first.
        guard width > 0, height > 0, !overflow, pixels <= maximumDecodedBytes / 8 else {
            throw RecoveryFailure.imageTooLarge
        }
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil) else { throw RecoveryFailure.exportFailed }
        // Direct encoding preserves the source color space, depth and alpha; no drawing context.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RecoveryFailure.exportFailed }
    }
}

enum RecoveryFailure: LocalizedError {
    case imageTooLarge
    case exportFailed
    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            String(localized: "This image is too large to process safely. Use a sheet with at most 33 million pixels.")
        case .exportFailed:
            String(localized: "The frames could not be exported. Check the destination and available storage, then try again.")
        }
    }
}

actor FrameExportService {
    private let storage: ProjectStorage
    init(storage: ProjectStorage = ProjectStorage()) { self.storage = storage }

    /// Each batch gets a new directory, so existing user files are never overwritten.
    func export(project: SpriteProject, frames: [SpriteFrame], prefix: String, folder: URL) throws -> URL {
        guard !frames.isEmpty else { throw LayoutError.noFrames }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let batch = folder.appending(path: "Frames-\(UUID().uuidString)", directoryHint: .isDirectory)
        let safe = String(prefix.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }.prefix(80))
        let base = safe.isEmpty ? "frame" : safe
        do {
            try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: false)
            var currentID: UUID?
            var image: CGImage?
            for (index, frame) in frames.enumerated() {
                try Task.checkCancellation()
                if currentID != frame.sourceID {
                    guard let source = project.sources.first(where: { $0.id == frame.sourceID }) else {
                        throw RecoveryFailure.exportFailed
                    }
                    image = nil
                    image = try PNGFrameCodec.load(storage.sourceURL(projectID: project.id, relativePath: source.relativePath))
                    currentID = source.id
                }
                guard let image else { throw RecoveryFailure.exportFailed }
                try autoreleasepool {
                    let crop = try FrameExtractor.crop(image, rect: frame.pixelRect)
                    let name = String(format: "%@_%03d.png", base, index + 1)
                    try PNGFrameCodec.write(crop, to: batch.appending(path: name))
                }
            }
            return batch
        } catch {
            try? FileManager.default.removeItem(at: batch)
            if error is CancellationError { throw error }
            throw RecoveryFailure.exportFailed
        }
    }
}
