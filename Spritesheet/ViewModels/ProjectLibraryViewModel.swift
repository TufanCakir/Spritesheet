//
//  ProjectLibraryViewModel.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class ProjectLibraryViewModel {
    var projects: [SpriteProject] = []
    var activeEditor: EditorViewModel?
    var presentedError: String?

    private let storage: ProjectStorage

    init(storage: ProjectStorage = ProjectStorage()) {
        self.storage = storage
    }

    func loadProjects() {
        do {
            projects = try storage.listProjects()
        } catch {
            presentedError = String(localized: "Projects could not be loaded.")
        }
    }

    func createProject(name: String) -> UUID? {
        var project = SpriteProject(name: name)
        project.markModified()
        do {
            try storage.save(project)
            projects.insert(project, at: 0)
            activeEditor = EditorViewModel(project: project, storage: storage)
            return project.id
        } catch {
            presentedError = String(
                localized: "The project could not be created."
            )
            return nil
        }
    }

    func openProject(id: UUID) -> EditorViewModel? {
        if activeEditor?.project.id == id {
            return activeEditor
        }
        do {
            let project = try storage.loadProject(id: id)
            let editor = EditorViewModel(project: project, storage: storage)
            activeEditor = editor
            return editor
        } catch {
            presentedError = String(
                localized: "The project could not be opened."
            )
            return nil
        }
    }

    func closeEditor() async -> Bool {
        guard let activeEditor else { return true }
        guard await activeEditor.save() else { return false }
        self.activeEditor = nil
        loadProjects()
        return true
    }

    func rename(_ project: SpriteProject, to name: String) {
        do {
            var changed = try storage.loadProject(id: project.id)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            changed.name = trimmed
            changed.markModified()
            try storage.save(changed)
            loadProjects()
        } catch {
            presentedError = String(
                localized: "The project could not be renamed."
            )
        }
    }

    func duplicate(_ project: SpriteProject) {
        do {
            _ = try storage.duplicateProject(
                project,
                name: String(localized: "\(project.name) Copy")
            )
            loadProjects()
        } catch {
            presentedError = String(
                localized: "The project could not be duplicated."
            )
        }
    }

    func delete(_ project: SpriteProject) {
        do {
            try storage.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            presentedError = String(
                localized: "The project could not be deleted."
            )
        }
    }
}
