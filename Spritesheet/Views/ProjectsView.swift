//
//  ProjectsView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct ProjectsView: View {
    @Bindable var library: ProjectLibraryViewModel
    let openProject: (UUID) -> Void

    @State private var projectToRename: SpriteProject?
    @State private var renameText = ""
    @State private var projectToDelete: SpriteProject?
    @State private var showsSettings = false

    var body: some View {
        Group {
            if library.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "square.grid.2x2")
                } description: {
                    Text("Create a project to import and arrange PNG frames.")
                } actions: {
                    Button(
                        "New Project",
                        systemImage: "plus",
                        action: createProject
                    )
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(library.projects) { project in
                    Button {
                        openProject(project.id)
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            renameText = project.name
                            projectToRename = project
                        }
                        Button(
                            "Duplicate",
                            systemImage: "plus.square.on.square"
                        ) {
                            library.duplicate(project)
                        }
                        Divider()
                        Button(
                            "Delete",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            projectToDelete = project
                        }
                    }
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gear") {
                    showsSettings = true
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Restore Animation", systemImage: "film") {
                    if let id = library.createProject(name: String(localized: "Recovered Animation")) {
                        library.activeEditor?.showsRecovery = true
                        openProject(id)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(
                    "New Project",
                    systemImage: "plus",
                    action: createProject
                )
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .alert("Rename Project", isPresented: renameAlertBinding) {
            TextField("Project Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let projectToRename {
                    library.rename(projectToRename, to: renameText)
                }
            }
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: deleteDialogBinding,
            presenting: projectToDelete
        ) { project in
            Button("Delete “\(project.name)”", role: .destructive) {
                library.delete(project)
            }
        } message: { _ in
            Text("This action cannot be undone.")
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.presentedError ?? "")
        }
        .onAppear {
            library.loadProjects()
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { projectToRename != nil },
            set: { if !$0 { projectToRename = nil } }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { library.presentedError != nil },
            set: { if !$0 { library.presentedError = nil } }
        )
    }

    private func createProject() {
        if let id = library.createProject(name: String(localized: "Untitled")) {
            openProject(id)
        }
    }
}

private struct ProjectRow: View {
    let project: SpriteProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(project.frames.count) frames")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    project.modifiedAt,
                    format: .relative(presentation: .named)
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the project")
    }
}
