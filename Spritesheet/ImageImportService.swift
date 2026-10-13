import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImportFailure: LocalizedError, Sendable {
    case accessDenied(String)
    case unsupported(String)
    case corrupt(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case let .accessDenied(name): "Access to “\(name)” was denied."
        case let .unsupported(name): "“\(name)” is not a supported PNG file."
        case let .corrupt(name): "“\(name)” is damaged or cannot be decoded."
        case let .copyFailed(name): "“\(name)” could not be copied into the project."
        }
    }
}

struct ImportedImage: Sendable {
    let source: SpriteSource
    let frame: SpriteFrame
}

struct ImportBatchResult: Sendable {
    let imported: [ImportedImage]
    let failures: [ImportFailure]
}

actor ImageImportService {
    private let storage = ProjectStorage()

    /// Imports sequentially so the provider's delivered URL order is preserved.
    func importPNGs(_ urls: [URL], projectID: UUID) async -> ImportBatchResult {
        var imported: [ImportedImage] = []
        var failures: [ImportFailure] = []

        for url in urls {
            if Task.isCancelled { break }
            do {
                imported.append(try importPNG(url, projectID: projectID))
            } catch let failure as ImportFailure {
                failures.append(failure)
            } catch {
                failures.append(.copyFailed(url.lastPathComponent))
            }
        }
        return ImportBatchResult(imported: imported, failures: failures)
    }

    private func importPNG(_ url: URL, projectID: UUID) throws -> ImportedImage {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        guard scoped || url.isFileURL else { throw ImportFailure.accessDenied(name) }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(imageSource),
              UTType(type as String) == .png else {
            throw ImportFailure.unsupported(name)
        }
        guard let image = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImportFailure.corrupt(name)
        }

        let sourceID = UUID()
        let sourcesDirectory = try storage.sourcesDirectory(for: projectID)
        let storedName = "\(sourceID.uuidString).png"
        let destination = sourcesDirectory.appending(path: storedName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw ImportFailure.copyFailed(name)
        }

        let alpha = image.alphaInfo
        let hasAlpha = alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast
        let source = SpriteSource(
            id: sourceID,
            relativePath: "Sources/\(storedName)",
            originalFilename: name,
            pixelWidth: image.width,
            pixelHeight: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            colorSpaceName: image.colorSpace?.name as String?,
            hasAlpha: hasAlpha
        )
        let frame = SpriteFrame(
            id: UUID(),
            sourceID: sourceID,
            pixelRect: PixelRect(width: image.width, height: image.height)
        )
        return ImportedImage(source: source, frame: frame)
    }
}
