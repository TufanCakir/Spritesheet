import Foundation

struct ProjectStorage: Sendable {
    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Spritesheet", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func projectDirectory(for projectID: UUID) throws -> URL {
        let directory = try Self.applicationSupportDirectory()
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: projectID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func sourcesDirectory(for projectID: UUID) throws -> URL {
        let directory = try projectDirectory(for: projectID)
            .appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func sourceURL(projectID: UUID, relativePath: String) throws -> URL {
        try projectDirectory(for: projectID).appending(path: relativePath)
    }

    func loadMostRecentProject() throws -> SpriteProject? {
        let projectsDirectory = try Self.applicationSupportDirectory()
            .appending(path: "Projects", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: projectsDirectory.path()) else { return nil }
        let directories = try FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projects = directories.compactMap { directory -> SpriteProject? in
            let metadataURL = directory.appending(path: "project.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let project = try? decoder.decode(SpriteProject.self, from: data),
                  project.schemaVersion == SpriteProject.schemaVersion else {
                return nil
            }
            return project
        }
        return projects.max { $0.modifiedAt < $1.modifiedAt }
    }

    func save(_ project: SpriteProject) throws {
        let directory = try projectDirectory(for: project.id)
        let finalURL = directory.appending(path: "project.json")
        let temporaryURL = directory.appending(path: "project-\(UUID().uuidString).tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project).write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: finalURL.path()) {
            _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        }
    }
}
