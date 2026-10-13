//
//  ProjectStorage.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import Foundation

struct ProjectStorage: Sendable {
    private let rootDirectory: URL?

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
    }

    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(
            path: "Spritesheet",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func storageRoot() throws -> URL {
        if let rootDirectory {
            try FileManager.default.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
            return rootDirectory
        }
        return try Self.applicationSupportDirectory()
    }

    func projectsDirectory() throws -> URL {
        let directory = try storageRoot()
            .appending(path: "Projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func projectDirectory(for projectID: UUID, create: Bool = true) throws
        -> URL
    {
        let directory = try projectsDirectory()
            .appending(path: projectID.uuidString, directoryHint: .isDirectory)
        if create {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }

    func sourcesDirectory(for projectID: UUID) throws -> URL {
        let directory = try projectDirectory(for: projectID)
            .appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func sourceURL(projectID: UUID, relativePath: String) throws -> URL {
        try projectDirectory(for: projectID).appending(path: relativePath)
    }

    func listProjects() throws -> [SpriteProject] {
        let directory = try projectsDirectory()
        let directories = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { try? loadProject(at: $0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func loadProject(id: UUID) throws -> SpriteProject {
        try loadProject(at: projectDirectory(for: id, create: false))
    }

    func loadMostRecentProject() throws -> SpriteProject? {
        try listProjects().first
    }

    func save(_ project: SpriteProject) throws {
        let directory = try projectDirectory(for: project.id)
        let finalURL = directory.appending(path: "project.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Data's atomic write creates and replaces its temporary file as one operation.
        // Unlike replaceItemAt, it does not race over separately managed temporary URLs.
        try encoder.encode(project).write(
            to: finalURL,
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    func deleteProject(id: UUID) throws {
        let directory = try projectDirectory(for: id, create: false)
        guard FileManager.default.fileExists(atPath: directory.path()) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    func duplicateProject(_ original: SpriteProject, name: String) throws
        -> SpriteProject
    {
        var duplicate = SpriteProject(id: UUID(), name: name)
        duplicate.frames = original.frames
        duplicate.layout = original.layout
        duplicate.exportSettings = original.exportSettings
        duplicate.animationFPS = original.animationFPS
        duplicate.animationLoops = original.animationLoops
        duplicate.animationPlaysBackward = original.animationPlaysBackward
        duplicate.animationPingPong = original.animationPingPong

        let destinationSources = try sourcesDirectory(for: duplicate.id)
        for source in original.sources {
            let newSourceID = UUID()
            let destinationName = "\(newSourceID.uuidString).png"
            let sourceURL = try sourceURL(
                projectID: original.id,
                relativePath: source.relativePath
            )
            let destinationURL = destinationSources.appending(
                path: destinationName
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            var copiedSource = source
            let oldID = copiedSource.id
            copiedSource = SpriteSource(
                id: newSourceID,
                relativePath: "Sources/\(destinationName)",
                originalFilename: copiedSource.originalFilename,
                pixelWidth: copiedSource.pixelWidth,
                pixelHeight: copiedSource.pixelHeight,
                bitsPerComponent: copiedSource.bitsPerComponent,
                bitsPerPixel: copiedSource.bitsPerPixel,
                colorSpaceName: copiedSource.colorSpaceName,
                hasAlpha: copiedSource.hasAlpha
            )
            duplicate.sources.append(copiedSource)
            duplicate.frames = duplicate.frames.map { frame in
                guard frame.sourceID == oldID else { return frame }
                return SpriteFrame(
                    id: frame.id,
                    sourceID: newSourceID,
                    pixelRect: frame.pixelRect
                )
            }
        }
        duplicate.markModified()
        do {
            try save(duplicate)
            return duplicate
        } catch {
            try? deleteProject(id: duplicate.id)
            throw error
        }
    }

    private func loadProject(at directory: URL) throws -> SpriteProject {
        let metadataURL = directory.appending(path: "project.json")
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(SpriteProject.self, from: data)
        guard project.schemaVersion == SpriteProject.schemaVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return project
    }
}

actor AutosaveCoordinator {
    private let storage: ProjectStorage
    private var pendingTask: Task<Void, Never>?
    private var lastSavedRevision: [UUID: Int] = [:]

    init(storage: ProjectStorage = ProjectStorage()) {
        self.storage = storage
    }

    func schedule(
        _ project: SpriteProject,
        delay: Duration = .milliseconds(350)
    ) {
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                try saveIfNewest(project)
            } catch is CancellationError {
                return
            } catch {
                // The explicit flush path reports errors to the UI.
            }
        }
    }

    func flush(_ project: SpriteProject) throws {
        pendingTask?.cancel()
        pendingTask = nil
        try saveIfNewest(project)
    }

    private func saveIfNewest(_ project: SpriteProject) throws {
        guard project.revision >= lastSavedRevision[project.id, default: -1]
        else { return }
        try storage.save(project)
        lastSavedRevision[project.id] = project.revision
    }
}
