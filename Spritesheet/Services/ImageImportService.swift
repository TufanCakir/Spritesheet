//
//  ImageImportService.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

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
        case .accessDenied(let name):
            String(localized: "Access to “\(name)” was denied.")
        case .unsupported(let name):
            String(localized: "“\(name)” is not a supported PNG file.")
        case .corrupt(let name):
            String(localized: "“\(name)” is damaged or cannot be decoded.")
        case .copyFailed(let name):
            String(localized: "“\(name)” could not be copied into the project.")
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
    private let storage: ProjectStorage

    init(storage: ProjectStorage = ProjectStorage()) {
        self.storage = storage
    }

    /// Imports sequentially so the provider's delivered order is preserved.
    func importPNGs(_ urls: [URL], projectID: UUID) async -> ImportBatchResult {
        var imported: [ImportedImage] = []
        var failures: [ImportFailure] = []

        for url in urls {
            if Task.isCancelled { break }
            let name = url.lastPathComponent
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                imported.append(
                    try importPNGData(
                        data,
                        filename: name,
                        projectID: projectID
                    )
                )
            } catch let failure as ImportFailure {
                failures.append(failure)
            } catch {
                failures.append(
                    scoped || url.isFileURL
                        ? .copyFailed(name) : .accessDenied(name)
                )
            }
        }
        return ImportBatchResult(imported: imported, failures: failures)
    }

    func importPNGData(_ data: Data, filename: String, projectID: UUID) throws
        -> ImportedImage
    {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(imageSource),
            UTType(type as String) == .png
        else {
            throw ImportFailure.unsupported(filename)
        }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw ImportFailure.corrupt(filename)
        }

        let sourceID = UUID()
        let storedName = "\(sourceID.uuidString).png"
        let destination = try storage.sourcesDirectory(for: projectID)
            .appending(path: storedName)
        do {
            try data.write(
                to: destination,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
        } catch {
            throw ImportFailure.copyFailed(filename)
        }

        let depth = (properties[kCGImagePropertyDepth] as? Int) ?? 8
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) ?? true
        let source = SpriteSource(
            id: sourceID,
            relativePath: "Sources/\(storedName)",
            originalFilename: filename,
            pixelWidth: width,
            pixelHeight: height,
            bitsPerComponent: depth,
            bitsPerPixel: depth * (hasAlpha ? 4 : 3),
            colorSpaceName: properties[kCGImagePropertyColorModel] as? String,
            hasAlpha: hasAlpha
        )
        let frame = SpriteFrame(
            id: UUID(),
            sourceID: sourceID,
            pixelRect: PixelRect(width: width, height: height)
        )
        return ImportedImage(source: source, frame: frame)
    }
}
