import Foundation

/// Pixel coordinates use a top-left origin. X increases right; Y increases down.
struct PixelRect: Codable, Hashable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(x: Int = 0, y: Int = 0, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct SpriteSource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var relativePath: String
    var originalFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var bitsPerComponent: Int
    var bitsPerPixel: Int
    var colorSpaceName: String?
    var hasAlpha: Bool
}

struct SpriteFrame: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceID: UUID
    var pixelRect: PixelRect

    func duplicated() -> SpriteFrame {
        SpriteFrame(id: UUID(), sourceID: sourceID, pixelRect: pixelRect)
    }
}

enum HorizontalAlignmentOption: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

enum VerticalAlignmentOption: String, Codable, CaseIterable, Sendable {
    case top
    case center
    case bottom
}

struct SheetLayout: Codable, Equatable, Sendable {
    var columns = 5
    var manualRows: Int?
    var cellWidth: Int?
    var cellHeight: Int?
    var horizontalSpacing = 0
    var verticalSpacing = 0
    var margin = 0
    var horizontalAlignment = HorizontalAlignmentOption.center
    var verticalAlignment = VerticalAlignmentOption.center
}

struct ExportSettings: Codable, Equatable, Sendable {
    var filename = "spritesheet"
    var transparentBackground = true
}

struct SpriteProject: Identifiable, Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    var name: String
    var sources: [SpriteSource]
    var frames: [SpriteFrame]
    var layout: SheetLayout
    var exportSettings: ExportSettings
    var animationFPS: Double
    var modifiedAt: Date
    var revision: Int

    init(id: UUID = UUID(), name: String = "Untitled") {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        sources = []
        frames = []
        layout = SheetLayout()
        exportSettings = ExportSettings()
        animationFPS = 12
        modifiedAt = .now
        revision = 0
    }

    mutating func markModified() {
        revision += 1
        modifiedAt = .now
    }
}

struct ProjectSnapshot: Sendable {
    let projectID: UUID
    let revision: Int
    let sources: [SpriteSource]
    let frames: [SpriteFrame]
    let layout: SheetLayout
    let exportSettings: ExportSettings

    init(project: SpriteProject) {
        projectID = project.id
        revision = project.revision
        sources = project.sources
        frames = project.frames
        layout = project.layout
        exportSettings = project.exportSettings
    }
}
