//
//  ContentView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let model: EditorViewModel
    let close: () async -> Void

    @State private var isImporterPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isImportMenuPresented = false
    @State private var isLayoutPresented = false
    @State private var isAnimationPresented = false
    @State private var isExportPresented = false
    @State private var extractionSource: SpriteSource?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var showsFrameExport = false

    var body: some View {
        VStack(spacing: 0) {
            EditorPreview(model: model)
            ProjectSummary(model: model)
            FrameTimeline(model: model) { extractionSource = $0 }
            EditorActions(
                importAction: { isImportMenuPresented = true },
                layoutAction: { isLayoutPresented = true },
                animationAction: { isAnimationPresented = true },
                exportAction: { isExportPresented = true }
            )
        }
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Projects", systemImage: "chevron.backward") {
                    Task { await close() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Restore Animation", systemImage: "film") { model.showsRecovery = true }
                    Button("Export Frames", systemImage: "square.and.arrow.up") { showsFrameExport = true }
                        .disabled(model.project.frames.isEmpty)
                    Button("Rename", systemImage: "pencil") {
                        renameText = model.project.name
                        isRenamePresented = true
                    }
                    Button("Save Project", systemImage: "square.and.arrow.down")
                    {
                        Task { await model.save() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Project actions")
            }
        }
        .confirmationDialog("Import", isPresented: $isImportMenuPresented) {
            Button("Import from Files", systemImage: "folder") {
                isImporterPresented = true
            }
            Button("Import from Photos", systemImage: "photo.on.rectangle") {
                isPhotoPickerPresented = true
            }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoItems,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var payloads: [(Data, String)] = []
                for (index, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(
                        type: Data.self
                    ) {
                        payloads.append((data, "Photo-\(index + 1).png"))
                    }
                }
                photoItems = []
                model.importPhotoData(payloads)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(urls)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    model.presentedError = String(
                        localized: "The selected files could not be imported."
                    )
                }
            }
        }
        .sheet(isPresented: Binding(get: { model.showsRecovery }, set: { model.showsRecovery = $0 })) {
            RecoverySourceView(model: model)
        }
        .sheet(isPresented: $showsFrameExport) {
            FrameExportView(project: model.project, frames: model.selectedFrameIDs.isEmpty
                ? model.project.frames : model.project.frames.filter { model.selectedFrameIDs.contains($0.id) })
        }
        .sheet(isPresented: $isLayoutPresented) {
            LayoutEditorView(model: model)
        }
        .sheet(isPresented: $isAnimationPresented) {
            AnimationPreviewView(model: model)
        }
        .sheet(isPresented: $isExportPresented) { ExportView(model: model) }
        .sheet(item: $extractionSource) {
            ExtractionView(model: model, source: $0)
        }
        .alert("Rename Project", isPresented: $isRenamePresented) {
            TextField("Project Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { model.rename(to: renameText) }
        }
        .alert(
            "Import Result",
            isPresented: Binding(
                get: { model.importReport != nil },
                set: { if !$0 { model.importReport = nil } }
            )
        ) {
            Button("OK") { model.importReport = nil }
        } message: {
            Text(model.importReport ?? "")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
        .overlay {
            if model.isImporting {
                ProgressView("Importing PNG files…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
    }
}

private struct EditorPreview: View {
    let model: EditorViewModel

    var body: some View {
        ZStack {
            Checkerboard()
            if let selected = selectedFrame,
                let source = model.project.sources.first(where: {
                    $0.id == selected.sourceID
                })
            {
                FrameThumbnailView(
                    projectID: model.project.id,
                    source: source,
                    frame: selected
                )
                .padding(24)
            } else if model.project.frames.isEmpty {
                ContentUnavailableView(
                    "No Frames",
                    systemImage: "square.grid.3x3",
                    description: Text("Import one or more PNG files to begin.")
                )
            } else {
                Text("Select a frame below")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 18))
        .padding([.horizontal, .top])
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frame preview")
    }

    private var selectedFrame: SpriteFrame? {
        if let id = model.selectedFrameIDs.first {
            return model.project.frames.first { $0.id == id }
        }
        return model.project.frames.first
    }
}

private struct ProjectSummary: View {
    let model: EditorViewModel

    var body: some View {
        HStack {
            if let layout = model.calculatedLayout {
                Text(
                    "\(layout.outputWidth) × \(layout.outputHeight) px · \(model.project.frames.count) frames"
                )
            } else {
                Text("\(model.project.frames.count) frames")
            }
            Spacer()
            if !model.selectedFrameIDs.isEmpty {
                Menu("Edit") {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        model.duplicateSelection()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        model.removeSelection()
                    }
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

private struct FrameTimeline: View {
    let model: EditorViewModel
    let extractAction: (SpriteSource) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(model.project.frames.enumerated(), id: \.element.id) {
                    index,
                    frame in
                    let source = model.project.sources.first {
                        $0.id == frame.sourceID
                    }
                    Button {
                        model.toggleSelection(frame.id)
                    } label: {
                        VStack(spacing: 4) {
                            FrameThumbnailView(
                                projectID: model.project.id,
                                source: source,
                                frame: frame
                            )
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 8))
                            Text("\(index + 1)")
                                .font(.caption2)
                        }
                        .padding(4)
                        .background(
                            model.selectedFrameIDs.contains(frame.id)
                                ? Color.accentColor.opacity(0.2)
                                : Color.secondary.opacity(0.08),
                            in: .rect(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    model.selectedFrameIDs.contains(frame.id)
                                        ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame \(index + 1)")
                    .accessibilityValue(
                        model.selectedFrameIDs.contains(frame.id)
                            ? "Selected" : "Not selected"
                    )
                    .contextMenu {
                        if let source {
                            Button(
                                "Extract Source as Grid",
                                systemImage: "square.grid.3x3"
                            ) {
                                extractAction(source)
                            }
                        }
                        Button("Move Earlier", systemImage: "arrow.left") {
                            model.moveFrame(id: frame.id, by: -1)
                        }
                        .disabled(index == 0)
                        Button("Move Later", systemImage: "arrow.right") {
                            model.moveFrame(id: frame.id, by: 1)
                        }
                        .disabled(index == model.project.frames.count - 1)
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: model.project.frames.isEmpty ? 0 : 112)
    }
}

private struct EditorActions: View {
    let importAction: () -> Void
    let layoutAction: () -> Void
    let animationAction: () -> Void
    let exportAction: () -> Void

    var body: some View {
        HStack {
            action("Import", "square.and.arrow.down", importAction)
            action("Layout", "square.grid.3x3", layoutAction)
            action("Animation", "play", animationAction)
            action("Export", "square.and.arrow.up", exportAction)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func action(
        _ title: LocalizedStringKey,
        _ symbol: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
