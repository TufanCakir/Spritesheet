import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportFailure: LocalizedError {
    case missingSource(String)
    case invalidFrame(String)
    case unsupportedPixelFormat(String)
    case insufficientMemory(estimatedBytes: Int)
    case contextCreation
    case destinationCreation
    case encoding
    case verification

    var errorDescription: String? {
        switch self {
        case let .missingSource(name): "The source file “\(name)” is missing."
        case let .invalidFrame(name): "A frame rectangle is outside “\(name)”."
        case let .unsupportedPixelFormat(message): message
        case let .insufficientMemory(bytes): "The export needs at least about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)) for its destination buffer."
        case .contextCreation: "The destination pixel buffer could not be created."
        case .destinationCreation: "The PNG encoder could not be created."
        case .encoding: "The PNG encoder could not finish the file."
        case .verification: "The created PNG failed verification."
        }
    }
}

struct ExportResult: Sendable {
    let url: URL
    let width: Int
    let height: Int
    let frameCount: Int
}

actor ExportService {
    private let storage = ProjectStorage()

    func export(snapshot: ProjectSnapshot) throws -> ExportResult {
        let calculated = try LayoutCalculator.calculate(
            frameRects: snapshot.frames.map(\.pixelRect),
            layout: snapshot.layout
        )

        let bytesPerPixel = 4
        let (minimumBytes, overflow) = calculated.outputWidth
            .multipliedReportingOverflow(by: calculated.outputHeight)
        guard !overflow else { throw LayoutError.arithmeticOverflow }
        let (estimatedBytes, byteOverflow) = minimumBytes.multipliedReportingOverflow(by: bytesPerPixel)
        guard !byteOverflow else { throw LayoutError.arithmeticOverflow }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ExportFailure.contextCreation
        }
        guard let context = CGContext(
            data: nil,
            width: calculated.outputWidth,
            height: calculated.outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ExportFailure.insufficientMemory(estimatedBytes: estimatedBytes)
        }

        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.clear(CGRect(x: 0, y: 0, width: calculated.outputWidth, height: calculated.outputHeight))

        let sourcesByID = Dictionary(uniqueKeysWithValues: snapshot.sources.map { ($0.id, $0) })
        for (index, frame) in snapshot.frames.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            guard let source = sourcesByID[frame.sourceID] else {
                throw ExportFailure.missingSource(frame.sourceID.uuidString)
            }
            let sourceURL = try storage.sourceURL(projectID: snapshot.projectID, relativePath: source.relativePath)
            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(
                    imageSource,
                    0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                  ) else {
                throw ExportFailure.missingSource(source.originalFilename)
            }

            let rect = frame.pixelRect
            guard rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
                  rect.x <= image.width - rect.width,
                  rect.y <= image.height - rect.height else {
                throw ExportFailure.invalidFrame(source.originalFilename)
            }

            let cropRect = CGRect(
                x: rect.x,
                y: image.height - rect.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            guard let cropped = image.cropping(to: cropRect) else {
                throw ExportFailure.invalidFrame(source.originalFilename)
            }

            let origin = LayoutCalculator.frameOrigin(
                index: index,
                frame: rect,
                calculated: calculated,
                layout: snapshot.layout
            )
            let destinationRect = CGRect(
                x: origin.x,
                y: calculated.outputHeight - origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            context.draw(cropped, in: destinationRect)
        }

        guard let outputImage = context.makeImage() else { throw ExportFailure.contextCreation }
        let exportsDirectory = try storage.projectDirectory(for: snapshot.projectID)
            .appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        let safeBase = sanitizedFilename(snapshot.exportSettings.filename)
        let outputURL = exportsDirectory.appending(path: "\(safeBase)-\(UUID().uuidString).png")

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportFailure.destinationCreation
        }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportFailure.encoding
        }

        guard let verificationSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(verificationSource, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == calculated.outputWidth,
              properties[kCGImagePropertyPixelHeight] as? Int == calculated.outputHeight else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportFailure.verification
        }

        return ExportResult(
            url: outputURL,
            width: calculated.outputWidth,
            height: calculated.outputHeight,
            frameCount: snapshot.frames.count
        )
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = filename.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "spritesheet" : cleaned
    }
}
