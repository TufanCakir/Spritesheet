import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Spritesheet

struct LayoutCalculatorTests {
    @Test func dhameystirRequiredLayout() throws {
        let frames = Array(repeating: PixelRect(width: 985, height: 1594), count: 10)
        let result = try LayoutCalculator.calculate(
            frameRects: frames,
            layout: SheetLayout(columns: 5)
        )

        #expect(result.rows == 2)
        #expect(result.outputWidth == 4925)
        #expect(result.outputHeight == 3188)
    }

    @Test(arguments: [
        (count: 100, expectedRows: 10, expectedHeight: 640),
        (count: 1001, expectedRows: 101, expectedHeight: 6464)
    ])
    func manyFrames(case input: (count: Int, expectedRows: Int, expectedHeight: Int)) throws {
        let frames = Array(repeating: PixelRect(width: 64, height: 64), count: input.count)
        let result = try LayoutCalculator.calculate(
            frameRects: frames,
            layout: SheetLayout(columns: 10)
        )

        #expect(result.outputWidth == 640)
        #expect(result.rows == input.expectedRows)
        #expect(result.outputHeight == input.expectedHeight)
    }

    @Test func exactGridExtraction() throws {
        let source = SpriteSource(
            id: UUID(),
            relativePath: "Sources/a.png",
            originalFilename: "a.png",
            pixelWidth: 2955,
            pixelHeight: 3188,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpaceName: nil,
            hasAlpha: true
        )
        let frames = try FrameExtractor.extract(
            source: source,
            settings: ExtractionSettings(columns: 3, rows: 2, frameCount: 6)
        )
        #expect(frames.count == 6)
        #expect(frames[0].pixelRect == PixelRect(x: 0, y: 0, width: 985, height: 1594))
        #expect(frames[5].pixelRect == PixelRect(x: 1970, y: 1594, width: 985, height: 1594))
    }

    @Test func incompleteGridIsReported() {
        let source = SpriteSource(
            id: UUID(),
            relativePath: "Sources/a.png",
            originalFilename: "a.png",
            pixelWidth: 10,
            pixelHeight: 10,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpaceName: nil,
            hasAlpha: true
        )
        #expect(throws: ExtractionError.mismatch(ExtractionMismatch(horizontalPixels: 1, verticalPixels: 0))) {
            try FrameExtractor.extract(
                source: source,
                settings: ExtractionSettings(columns: 3, rows: 2, frameCount: 6)
            )
        }
    }

    @Test func spacingMarginsAndAlignments() throws {
        let frames = [PixelRect(width: 2, height: 3), PixelRect(width: 1, height: 1)]
        let layout = SheetLayout(
            columns: 2,
            cellWidth: 4,
            cellHeight: 5,
            horizontalSpacing: 2,
            verticalSpacing: 3,
            margin: 7,
            horizontalAlignment: .trailing,
            verticalAlignment: .bottom
        )
        let result = try LayoutCalculator.calculate(frameRects: frames, layout: layout)

        #expect(result.outputWidth == 24)
        #expect(result.outputHeight == 19)
        let origin = LayoutCalculator.frameOrigin(index: 1, frame: frames[1], calculated: result, layout: layout)
        #expect(origin.x == 16)
        #expect(origin.y == 11)
    }

    @Test func tooSmallCellFails() {
        let layout = SheetLayout(columns: 1, cellWidth: 9, cellHeight: 20)
        #expect(throws: LayoutError.cellTooSmall(requiredWidth: 10, requiredHeight: 20)) {
            try LayoutCalculator.calculate(
                frameRects: [PixelRect(width: 10, height: 20)],
                layout: layout
            )
        }
    }

    @Test func overflowFailsWithoutAllocation() {
        let layout = SheetLayout(columns: Int.max, cellWidth: Int.max, cellHeight: 1)
        #expect(throws: LayoutError.arithmeticOverflow) {
            try LayoutCalculator.calculate(
                frameRects: [PixelRect(width: 1, height: 1)],
                layout: layout
            )
        }
    }
}

struct ImportExportWorkflowTests {
    @Test func orderedMultipleImportAndVerifiedExport() async throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let colors: [(UInt8, UInt8, UInt8, UInt8)] = [
            (255, 0, 0, 64),
            (0, 255, 0, 128),
            (0, 0, 255, 255)
        ]
        let urls = try colors.enumerated().map { index, color in
            let url = fixtureDirectory.appending(path: String(format: "frame_%02d.png", index))
            try writeFixture(url: url, width: 2, height: 2, color: color)
            return url
        }

        let projectID = UUID()
        let importResult = await ImageImportService().importPNGs(urls, projectID: projectID)
        #expect(importResult.failures.isEmpty)
        #expect(importResult.imported.map(\.source.originalFilename) == urls.map(\.lastPathComponent))

        var project = SpriteProject(id: projectID, name: "Workflow")
        project.sources = importResult.imported.map(\.source)
        project.frames = importResult.imported.map(\.frame)
        project.layout = SheetLayout(columns: 2)
        project.exportSettings.filename = "workflow"

        let result = try await ExportService().export(snapshot: ProjectSnapshot(project: project))
        #expect(result.width == 4)
        #expect(result.height == 4)
        #expect(result.frameCount == 3)

        guard let source = CGImageSourceCreateWithURL(result.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            Issue.record("Exported PNG could not be reopened")
            return
        }
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 4)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 4)
    }

    private func writeFixture(
        url: URL,
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8, UInt8)
    ) throws {
        let bytes = [UInt8](repeating: color.0, count: width * height * 4)
        var pixels = bytes
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = color.3
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
