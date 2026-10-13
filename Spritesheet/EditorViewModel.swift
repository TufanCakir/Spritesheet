import Foundation
import Observation

@MainActor
@Observable
final class EditorViewModel {
    var project: SpriteProject
    var selectedFrameIDs: Set<UUID> = []
    var isImporting = false
    var isExporting = false
    var presentedError: String?
    var importReport: String?
    var exportResult: ExportResult?

    private let importer = ImageImportService()
    private let exporter = ExportService()
    private let storage = ProjectStorage()
    private var hasRestored = false

    init(project: SpriteProject = SpriteProject()) {
        self.project = project
    }

    var calculatedLayout: CalculatedLayout? {
        try? LayoutCalculator.calculate(frameRects: project.frames.map(\.pixelRect), layout: project.layout)
    }

    func restoreMostRecentProject() async {
        guard !hasRestored else { return }
        hasRestored = true
        do {
            if let restored = try storage.loadMostRecentProject() {
                project = restored
            }
        } catch {
            presentedError = "The most recent project could not be restored: \(error.localizedDescription)"
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            let result = await importer.importPNGs(urls, projectID: project.id)
            project.sources.append(contentsOf: result.imported.map(\.source))
            project.frames.append(contentsOf: result.imported.map(\.frame))
            project.markModified()
            isImporting = false

            if !result.failures.isEmpty {
                let details = result.failures.compactMap(\.errorDescription).joined(separator: "\n")
                importReport = "\(result.imported.count) imported. \(result.failures.count) failed.\n\(details)"
            }
            await save()
        }
    }

    func toggleSelection(_ id: UUID) {
        if selectedFrameIDs.contains(id) {
            selectedFrameIDs.remove(id)
        } else {
            selectedFrameIDs.insert(id)
        }
    }

    func duplicateSelection() {
        let selected = project.frames.filter { selectedFrameIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let duplicates = selected.map { $0.duplicated() }
        project.frames.append(contentsOf: duplicates)
        selectedFrameIDs = Set(duplicates.map(\.id))
        project.markModified()
        Task { await save() }
    }

    func removeSelection() {
        guard !selectedFrameIDs.isEmpty else { return }
        project.frames.removeAll { selectedFrameIDs.contains($0.id) }
        selectedFrameIDs.removeAll()
        project.markModified()
        Task { await save() }
    }

    func moveFrame(id: UUID, by offset: Int) {
        guard let sourceIndex = project.frames.firstIndex(where: { $0.id == id }) else { return }
        let destination = sourceIndex + offset
        guard project.frames.indices.contains(destination) else { return }
        project.frames.swapAt(sourceIndex, destination)
        project.markModified()
        Task { await save() }
    }

    func extractFrames(from sourceID: UUID, settings: ExtractionSettings) throws {
        guard let source = project.sources.first(where: { $0.id == sourceID }) else { return }
        let extracted = try FrameExtractor.extract(source: source, settings: settings)
        guard let firstIndex = project.frames.firstIndex(where: { $0.sourceID == sourceID }) else {
            project.frames.append(contentsOf: extracted)
            return
        }
        project.frames.removeAll { $0.sourceID == sourceID }
        project.frames.insert(contentsOf: extracted, at: min(firstIndex, project.frames.count))
        selectedFrameIDs = Set(extracted.prefix(1).map(\.id))
        project.markModified()
        Task { await save() }
    }

    func exportPNG() {
        let snapshot = ProjectSnapshot(project: project)
        isExporting = true
        exportResult = nil
        Task {
            do {
                exportResult = try await exporter.export(snapshot: snapshot)
            } catch is CancellationError {
                presentedError = "Export cancelled."
            } catch {
                presentedError = error.localizedDescription
            }
            isExporting = false
        }
    }

    func save() async {
        do {
            try await storage.save(project)
        } catch {
            presentedError = "The project could not be saved: \(error.localizedDescription)"
        }
    }
}
