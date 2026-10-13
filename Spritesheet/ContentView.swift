import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = EditorViewModel()
    @State private var isImporterPresented = false
    @State private var isLayoutPresented = false
    @State private var isAnimationPresented = false
    @State private var isExportPresented = false
    @State private var extractionSource: SpriteSource?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EditorPreview(model: model)
                ProjectSummary(model: model)
                FrameTimeline(model: model) { source in
                    extractionSource = source
                }
                EditorActions(
                    importAction: { isImporterPresented = true },
                    layoutAction: { isLayoutPresented = true },
                    animationAction: { isAnimationPresented = true },
                    exportAction: { isExportPresented = true }
                )
            }
            .navigationTitle(model.project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") {}
                        Button("Save Project", systemImage: "square.and.arrow.down") {
                            Task { await model.save() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Project actions")
                }
            }
        }
        .task {
            await model.restoreMostRecentProject()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                model.importFiles(urls)
            case let .failure(error):
                let nsError = error as NSError
                if nsError.code != NSUserCancelledError {
                    model.presentedError = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $isLayoutPresented) {
            LayoutEditorView(model: model)
        }
        .sheet(isPresented: $isAnimationPresented) {
            AnimationPreviewView(model: model)
        }
        .sheet(isPresented: $isExportPresented) {
            ExportView(model: model)
        }
        .sheet(item: $extractionSource) { source in
            ExtractionView(model: model, source: source)
        }
        .alert("Import result", isPresented: Binding(
            get: { model.importReport != nil },
            set: { if !$0 { model.importReport = nil } }
        )) {
            Button("OK") { model.importReport = nil }
        } message: {
            Text(model.importReport ?? "")
        }
        .alert("Error", isPresented: Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )) {
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
               let source = model.project.sources.first(where: { $0.id == selected.sourceID }) {
                FrameThumbnailView(projectID: model.project.id, source: source, frame: selected)
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
                Text("\(layout.outputWidth) × \(layout.outputHeight) px · \(model.project.frames.count) frames")
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
                ForEach(model.project.frames.enumerated(), id: \.element.id) { index, frame in
                    let source = model.project.sources.first { $0.id == frame.sourceID }
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
                                    model.selectedFrameIDs.contains(frame.id) ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame \(index + 1)")
                    .accessibilityValue(model.selectedFrameIDs.contains(frame.id) ? "Selected" : "Not selected")
                    .contextMenu {
                        if let source {
                            Button("Extract Source as Grid", systemImage: "square.grid.3x3") {
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

    private func action(_ title: LocalizedStringKey, _ symbol: String, _ action: @escaping () -> Void) -> some View {
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

#Preview {
    ContentView()
}
