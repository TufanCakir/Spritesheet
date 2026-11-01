import Foundation

actor RecoveryProjectService {
    private let storage: ProjectStorage
    init(storage: ProjectStorage = ProjectStorage()) { self.storage = storage }

    func projects(excluding id: UUID) throws -> [SpriteProject] {
        try storage.listProjects().filter { $0.id != id }
    }

    /// Copy source files first, append frames, then atomically save metadata.
    /// Only files created by this operation are removed if it fails.
    func transfer(from original: SpriteProject, frames: [SpriteFrame], fps: Double,
                  targetID: UUID?, name: String) throws -> SpriteProject {
        var target = try targetID.map { try storage.loadProject(id: $0) } ?? SpriteProject(name: name)
        var created: [URL] = []
        do {
            var mapping: [UUID: UUID] = [:]
            for source in original.sources where frames.contains(where: { $0.sourceID == source.id }) {
                let id = UUID()
                let filename = "\(id.uuidString).png"
                let destination = try storage.sourcesDirectory(for: target.id).appending(path: filename)
                try FileManager.default.copyItem(
                    at: storage.sourceURL(projectID: original.id, relativePath: source.relativePath), to: destination)
                created.append(destination)
                mapping[source.id] = id
                target.sources.append(SpriteSource(id: id, relativePath: "Sources/\(filename)",
                    originalFilename: source.originalFilename, pixelWidth: source.pixelWidth,
                    pixelHeight: source.pixelHeight, bitsPerComponent: source.bitsPerComponent,
                    bitsPerPixel: source.bitsPerPixel, colorSpaceName: source.colorSpaceName, hasAlpha: source.hasAlpha))
            }
            for frame in frames {
                guard let sourceID = mapping[frame.sourceID] else { throw RecoveryFailure.exportFailed }
                target.frames.append(SpriteFrame(id: UUID(), sourceID: sourceID, pixelRect: frame.pixelRect))
            }
            if targetID == nil { target.animationFPS = fps }
            target.markModified()
            try storage.save(target)
            return target
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            if targetID == nil { try? storage.deleteProject(id: target.id) }
            throw error
        }
    }
}
