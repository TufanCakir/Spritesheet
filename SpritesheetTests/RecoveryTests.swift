import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Spritesheet

struct RecoveryTests {
    private func source(_ width: Int, _ height: Int) -> SpriteSource {
        SpriteSource(id: UUID(), relativePath: "Sources/test.png", originalFilename: "test.png",
                     pixelWidth: width, pixelHeight: height, bitsPerComponent: 8,
                     bitsPerPixel: 32, colorSpaceName: nil, hasAlpha: true)
    }

    // Non-premultiplied scanlines with distinct x/y colors, partial alpha and an empty bottom-right tile.
    private func fixture(_ width: Int, _ height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = UInt8(x % 256)
                bytes[index + 1] = UInt8(y % 256)
                bytes[index + 2] = 73
                bytes[index + 3] = x >= width - 64 && y >= height - 64 ? 0 : UInt8([64, 128, 255][x % 3])
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        let data = try #require(image.dataProvider?.data)
        let pointer = try #require(CFDataGetBytePtr(data))
        var result: [UInt8] = []
        for y in 0..<image.height {
            result.append(contentsOf: UnsafeBufferPointer(start: pointer + y * image.bytesPerRow, count: image.width * 4))
        }
        return result
    }

    @Test(arguments: [(256, 64, 4, 1), (256, 128, 4, 2), (128, 128, 2, 2), (64, 256, 1, 4)])
    func pngExtractionAndPixelRoundTrip(_ input: (Int, Int, Int, Int)) async throws {
        let (width, height, columns, rows) = input
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalURL = root.appending(path: "original.png")
        try PNGFrameCodec.write(fixture(width, height), to: originalURL)
        let originalBytes = try Data(contentsOf: originalURL)
        let storage = ProjectStorage(rootDirectory: root.appending(path: "Library"))
        var project = SpriteProject()
        let imported = await ImageImportService(storage: storage).importPNGs([originalURL], projectID: project.id)
        #expect(imported.failures.isEmpty)
        let item = try #require(imported.imported.first)
        project.sources = [item.source]
        project.frames = try FrameExtractor.extract(source: item.source,
            settings: ExtractionSettings(columns: columns, rows: rows, frameCount: columns * rows))
        #expect(project.frames.count == columns * rows)
        #expect(project.frames.allSatisfy { $0.pixelRect.width == 64 && $0.pixelRect.height == 64 })
        let original = try PNGFrameCodec.load(originalURL)
        let originalPixels = try rgba(original)
        let folder = try await FrameExportService(storage: storage).export(
            project: project, frames: project.frames, prefix: "frame", folder: root)
        for (index, frame) in project.frames.enumerated() {
            let url = folder.appending(path: String(format: "frame_%03d.png", index + 1))
            let reimport = await ImageImportService(storage: storage).importPNGs([url], projectID: UUID())
            #expect(reimport.imported.count == 1)
            let image = try PNGFrameCodec.load(url)
            #expect(image.width == 64 && image.height == 64)
            let actual = try rgba(image)
            var expected: [UInt8] = []
            for y in frame.pixelRect.y..<(frame.pixelRect.y + 64) {
                let start = (y * width + frame.pixelRect.x) * 4
                expected.append(contentsOf: originalPixels[start..<(start + 64 * 4)])
            }
            #expect(actual == expected)
            if index == project.frames.count - 1 {
                #expect(stride(from: 3, to: actual.count, by: 4).allSatisfy { actual[$0] == 0 })
            }
        }
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        let second = try await FrameExportService(storage: storage).export(
            project: project, frames: [project.frames[0]], prefix: "../frame", folder: root)
        #expect(second != folder)
    }

    @Test func columnOrderSpacingAndIndependentMargins() throws {
        let settings = ExtractionSettings(columns: 2, rows: 2, frameCount: 3,
            frameWidth: 16, frameHeight: 16, horizontalSpacing: 3, verticalSpacing: 5,
            marginX: 2, marginY: 4, order: .columnMajor)
        let frames = try FrameExtractor.extract(source: source(39, 45), settings: settings)
        #expect(frames.map(\.pixelRect) == [
            PixelRect(x: 2, y: 4, width: 16, height: 16),
            PixelRect(x: 2, y: 25, width: 16, height: 16),
            PixelRect(x: 21, y: 4, width: 16, height: 16)])
    }

    @Test func invalidGeometryNeverTraps() throws {
        let invalid = [
            ExtractionSettings(columns: 0), ExtractionSettings(rows: -1),
            ExtractionSettings(columns: Int.max, rows: Int.max),
            ExtractionSettings(frameCount: 2), ExtractionSettings(frameWidth: Int.max),
            ExtractionSettings(horizontalSpacing: Int.max, margin: Int.max),
            ExtractionSettings(columns: 2, horizontalSpacing: Int.max),
            ExtractionSettings(marginX: -1), ExtractionSettings(frameHeight: 0),
            ExtractionSettings(columns: 128, rows: 128, frameCount: 16_384)]
        for settings in invalid {
            #expect(throws: (any Error).self) { try FrameExtractor.extract(source: source(128, 128), settings: settings) }
        }
        let image = try fixture(128, 128)
        #expect(throws: (any Error).self) {
            try FrameExtractor.crop(image, rect: PixelRect(x: Int.max, width: 1, height: 1))
        }
    }

    @Test func ambiguousSuggestionsRemainChoices() {
        let suggestions = FrameExtractor.suggestions(for: source(256, 128))
        #expect(suggestions.compactMap(\.frameWidth) == [16, 32, 64, 128])
    }

    @Test func completeAndPartialMetadata() throws {
        let metadata = try AnimationMetadata.decode(Data(#"{"columns":4,"rows":2,"frameCount":8,"fps":8,"future":true}"#.utf8))
        #expect(metadata.hasCompleteGrid)
        #expect(metadata.fps == 8)
        let frames = try FrameExtractor.extract(source: source(256, 128), settings: metadata.applying(to: ExtractionSettings()))
        #expect(frames.count == 8)
        #expect(frames[0].pixelRect.width == 64 && frames[0].pixelRect.height == 64)
        let partial = try AnimationMetadata.decode(Data(#"{"fps":12,"columns":4}"#.utf8))
        #expect(!partial.hasCompleteGrid)
        #expect(partial.rows == nil && partial.frameCount == nil)
        #expect(partial.applying(to: ExtractionSettings(rows: 2)).rows == 2)
    }

    @Test(arguments: ["{}", "{", "[]", #"{"fps":0}"#, #"{"fps":61}"#, #"{"rows":"2"}"#,
                      #"{"columns":-1}"#, #"{"columns":2,"rows":2,"frameCount":5}"#])
    func invalidMetadata(_ json: String) {
        #expect(throws: MetadataError.self) { try AnimationMetadata.decode(Data(json.utf8)) }
    }

    @Test func playbackPauseStepAndEndBehavior() {
        var cursor = AnimationPlayback()
        #expect((cursor.advance(count: 3, loops: false, pingPong: false)))
        #expect(cursor.index == 1)
        #expect((cursor.advance(count: 3, loops: false, pingPong: false)))
        #expect(cursor.index == 2)
        #expect((!cursor.advance(count: 3, loops: false, pingPong: false)))
        #expect((cursor.advance(count: 3, loops: true, pingPong: false)))
        #expect(cursor.index == 0)
        cursor.direction = -1
        #expect((cursor.advance(count: 3, loops: true, pingPong: false)))
        #expect(cursor.index == 2)
        #expect((cursor.advance(count: 3, loops: false, pingPong: false)))
        #expect(cursor.index == 1)
        cursor = AnimationPlayback(index: 2, direction: 1)
        #expect((cursor.advance(count: 3, loops: false, pingPong: true)))
        #expect(cursor.index == 1 && cursor.direction == -1)
        #expect((cursor.advance(count: 3, loops: false, pingPong: true)))
        #expect((!cursor.advance(count: 3, loops: false, pingPong: true)))
        #expect((!cursor.advance(count: 0, loops: true, pingPong: false)))
    }

    @Test func damagedPNGAndMemoryLimit() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        #expect(throws: (any Error).self) { try PNGFrameCodec.load(url) }
        #expect(throws: (any Error).self) { try PNGFrameCodec.validateSize(width: Int.max, height: Int.max) }
    }

    @Test func transferAppendsWithoutReplacingProject() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ProjectStorage(rootDirectory: root)
        var original = SpriteProject(name: "Recovery")
        let sourceURL = try storage.sourcesDirectory(for: original.id).appending(path: "test.png")
        try PNGFrameCodec.write(fixture(128, 128), to: sourceURL)
        let item = source(128, 128)
        original.sources = [item]
        original.frames = try FrameExtractor.extract(source: item,
            settings: ExtractionSettings(columns: 2, rows: 2, frameCount: 4))
        var target = SpriteProject(name: "Existing")
        target.animationFPS = 24
        let existingFrame = SpriteFrame(id: UUID(), sourceID: UUID(), pixelRect: PixelRect(width: 1, height: 1))
        target.frames = [existingFrame]
        try storage.save(target)
        let result = try await RecoveryProjectService(storage: storage).transfer(
            from: original, frames: original.frames, fps: 8, targetID: target.id, name: "")
        #expect(result.frames.first == existingFrame)
        #expect(result.frames.count == 5)
        #expect(result.animationFPS == 24)
        #expect(result.sources.first?.id != item.id)
        let restored = try storage.loadProject(id: target.id)
        #expect(restored.frames == result.frames)
    }
}
