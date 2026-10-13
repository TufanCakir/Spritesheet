//
//  EditorViewModel.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

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

    private let importer: ImageImportService
    private let exporter = ExportService()
    private let storage: ProjectStorage
    private let autosave: AutosaveCoordinator
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    init(project: SpriteProject, storage: ProjectStorage = ProjectStorage()) {
        self.project = project
        self.storage = storage
        importer = ImageImportService(storage: storage)
        autosave = AutosaveCoordinator(storage: storage)
    }

    var calculatedLayout: CalculatedLayout? {
        try? LayoutCalculator.calculate(
            frameRects: project.frames.map(\.pixelRect),
            layout: project.layout
        )
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            let result = await importer.importPNGs(urls, projectID: project.id)
            applyImport(result)
        }
    }

    func importPhotoData(_ items: [(data: Data, filename: String)]) {
        guard !items.isEmpty else { return }
        isImporting = true
        Task {
            var imported: [ImportedImage] = []
            var failures: [ImportFailure] = []
            for item in items {
                do {
                    imported.append(
                        try await importer.importPNGData(
                            item.data,
                            filename: item.filename,
                            projectID: project.id
                        )
                    )
                } catch let failure as ImportFailure {
                    failures.append(failure)
                } catch {
                    failures.append(.copyFailed(item.filename))
                }
            }
            applyImport(
                ImportBatchResult(imported: imported, failures: failures)
            )
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
        let selected = project.frames.filter {
            selectedFrameIDs.contains($0.id)
        }
        guard !selected.isEmpty else { return }
        let duplicates = selected.map { $0.duplicated() }
        project.frames.append(contentsOf: duplicates)
        selectedFrameIDs = Set(duplicates.map(\.id))
        projectDidChange()
    }

    func removeSelection() {
        guard !selectedFrameIDs.isEmpty else { return }
        project.frames.removeAll { selectedFrameIDs.contains($0.id) }
        selectedFrameIDs.removeAll()
        projectDidChange()
    }

    func moveFrame(id: UUID, by offset: Int) {
        guard
            let sourceIndex = project.frames.firstIndex(where: { $0.id == id })
        else { return }
        let destination = sourceIndex + offset
        guard project.frames.indices.contains(destination) else { return }
        project.frames.swapAt(sourceIndex, destination)
        projectDidChange()
    }

    func extractFrames(from sourceID: UUID, settings: ExtractionSettings) throws
    {
        guard let source = project.sources.first(where: { $0.id == sourceID })
        else { return }
        let extracted = try FrameExtractor.extract(
            source: source,
            settings: settings
        )
        if let firstIndex = project.frames.firstIndex(where: {
            $0.sourceID == sourceID
        }) {
            project.frames.removeAll { $0.sourceID == sourceID }
            project.frames.insert(
                contentsOf: extracted,
                at: min(firstIndex, project.frames.count)
            )
        } else {
            project.frames.append(contentsOf: extracted)
        }
        selectedFrameIDs = Set(extracted.prefix(1).map(\.id))
        projectDidChange()
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.name else { return }
        project.name = trimmed
        projectDidChange()
    }

    func projectDidChange() {
        project.markModified()
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                _ = await self?.save()
            } catch is CancellationError {
                return
            } catch {
                self?.presentedError = String(
                    localized:
                        "The project could not be saved. Your latest changes may not be saved yet."
                )
            }
        }
    }

    func exportPNG() {
        let snapshot = ProjectSnapshot(project: project)
        isExporting = true
        exportResult = nil
        Task {
            do {
                exportResult = try await exporter.export(snapshot: snapshot)
            } catch is CancellationError {
                presentedError = String(localized: "Export cancelled.")
            } catch {
                presentedError = error.localizedDescription
            }
            isExporting = false
        }
    }

    @discardableResult
    func save() async -> Bool {
        do {
            try await autosave.flush(project)
            return true
        } catch {
            presentedError = String(
                localized:
                    "The project could not be saved. Your latest changes may not be saved yet."
            )
            return false
        }
    }

    private func applyImport(_ result: ImportBatchResult) {
        project.sources.append(contentsOf: result.imported.map(\.source))
        project.frames.append(contentsOf: result.imported.map(\.frame))
        isImporting = false
        if !result.imported.isEmpty {
            projectDidChange()
        }
        if !result.failures.isEmpty {
            let details = result.failures.compactMap(\.errorDescription).joined(
                separator: "\n"
            )
            importReport = String(
                localized:
                    "\(result.imported.count) imported. \(result.failures.count) failed.\n\(details)"
            )
        }
    }
}
