import SwiftUI
import UniformTypeIdentifiers

struct ExtractionView: View {
    let model: EditorViewModel
    let source: SpriteSource
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExtractionSettings()
    @State private var frames: [SpriteFrame] = []
    @State private var selected: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var status: String?
    @State private var showsJSON = false
    @State private var showsGrid = true
    @State private var fps = 12.0
    @State private var animation: EditorViewModel?
    @State private var showsAnimation = false
    @State private var showsExport = false
    @State private var exportFrames: [SpriteFrame] = []
    @State private var detail: SpriteFrame?
    @State private var showsTransfer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SheetGridPreview(projectID: model.project.id, source: source,
                                     frames: frames, showsGrid: showsGrid)
                }
                        Section("Source") {
                            Text(source.originalFilename)
                            Text("\(source.pixelWidth) × \(source.pixelHeight) px")
                            Toggle("Show Grid", isOn: $showsGrid)
                            Button("Import JSON", systemImage: "doc") { showsJSON = true }
                            Text("Choose a grid suggestion or enter your own values. Image dimensions alone cannot identify the original frames.")
                            Menu("Grid Suggestions") {
                                ForEach(FrameExtractor.suggestions(for: source), id: \.frameWidth) { suggestion in
                                    Button("\(suggestion.frameWidth ?? 0) × \(suggestion.frameHeight ?? 0) px") {
                                        settings = suggestion
                                    }
                                }
                            }
                        }
                        RecoveryGridSettings(settings: $settings, fps: $fps)
                Section {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    if let status { Text(status).foregroundStyle(.secondary) }
                    if let first = frames.first {
                        Text("\(first.pixelRect.width) × \(first.pixelRect.height) px · \(frames.count) frames")
                    }
                    RecoveryFrameGrid(projectID: model.project.id, source: source, frames: frames,
                                      selected: $selected, detail: $detail)
                    if !frames.isEmpty {
                        VStack(spacing: 12) {
                            Button("Preview Animation", systemImage: "play") {
                                var project = model.project
                                project.frames = frames
                                project.animationFPS = Double(fps)
                                animation = EditorViewModel(project: project)
                                showsAnimation = true
                            }
                            Button("Export All Frames", systemImage: "square.and.arrow.up") {
                                exportFrames = frames; showsExport = true
                            }
                            Button("Export Selected Frames") {
                                exportFrames = frames.filter { selected.contains($0.id) }; showsExport = true
                            }.disabled(selected.isEmpty)
                            Button("Add Frames to Current Project", systemImage: "plus") {
                                model.project.frames.append(contentsOf: frames.map { $0.duplicated() })
                                model.project.animationFPS = Double(fps)
                                model.projectDidChange()
                                dismiss()
                            }
                            Button("Use in Another Project", systemImage: "folder") { showsTransfer = true }
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Recovery exports editable PNG frames. Original layers and Pixel Studio project files cannot be reconstructed from a flattened image.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Restore Animation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { fps = min(60, max(1, model.project.animationFPS)); refresh() }
            .onChange(of: settings) { _, _ in refresh() }
            .fileImporter(isPresented: $showsJSON, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task {
                        do {
                            let metadata = try await AnimationMetadataImporter().load(url)
                            settings = metadata.applying(to: settings)
                            if let value = metadata.fps { fps = value }
                            status = metadata.hasCompleteGrid
                                ? String(localized: "Metadata applied. Frames are ready when the grid is valid.")
                                : String(localized: "Partial metadata applied. Check the remaining grid values.")
                            refresh()
                        } catch { errorMessage = error.localizedDescription }
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
                }
            }
            .sheet(isPresented: $showsAnimation) {
                if let animation { AnimationPreviewView(model: animation) }
            }
            .sheet(isPresented: $showsExport) { FrameExportView(project: model.project, frames: exportFrames) }
            .sheet(item: $detail) { frame in
                NavigationStack {
                    FrameThumbnailView(projectID: model.project.id, source: source, frame: frame)
                        .padding()
                        .navigationTitle("Frame Details")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } }
                            ToolbarItem(placement: .bottomBar) {
                                Button("Export Frame") {
                                    detail = nil
                                    exportFrames = [frame]
                                    showsExport = true
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showsTransfer) {
                RecoveryProjectTransferView(project: model.project, frames: frames, fps: Double(fps))
            }
        }
    }

    private func refresh() {
        do {
            frames = try FrameExtractor.extract(source: source, settings: settings)
            selected.removeAll()
            errorMessage = nil
        } catch {
            frames = []
            selected.removeAll()
            errorMessage = error.localizedDescription
        }
    }
}

private struct RecoveryGridSettings: View {
    @Binding var settings: ExtractionSettings
    @Binding var fps: Double

    var body: some View {
        Section("Grid") {
            IntegerField("Columns", value: $settings.columns, minimum: 1)
            IntegerField("Rows", value: $settings.rows, minimum: 1)
            IntegerField("Frame count", value: $settings.frameCount, minimum: 1)
            Button("Use Full Grid") {
                let (count, overflow) = settings.columns.multipliedReportingOverflow(by: settings.rows)
                if !overflow { settings.frameCount = min(count, FrameExtractor.maximumFrameCount) }
            }
            IntegerField("Frame Width (0 = automatic)", value: Binding(
                get: { settings.frameWidth ?? 0 }, set: { settings.frameWidth = $0 == 0 ? nil : $0 }), minimum: 0)
            IntegerField("Frame Height (0 = automatic)", value: Binding(
                get: { settings.frameHeight ?? 0 }, set: { settings.frameHeight = $0 == 0 ? nil : $0 }), minimum: 0)
            IntegerField("Horizontal spacing", value: $settings.horizontalSpacing, minimum: 0)
            IntegerField("Vertical spacing", value: $settings.verticalSpacing, minimum: 0)
            IntegerField("X Margin", value: Binding(get: { settings.marginX ?? 0 },
                set: { settings.marginX = $0 }), minimum: 0)
            IntegerField("Y Margin", value: Binding(get: { settings.marginY ?? 0 },
                set: { settings.marginY = $0 }), minimum: 0)
            Picker("Extraction order", selection: $settings.order) {
                Text("Left to right, then down").tag(ExtractionOrder.rowMajor)
                Text("Top to bottom, then right").tag(ExtractionOrder.columnMajor)
            }
            LabeledContent("FPS") {
                TextField("FPS", value: $fps, format: .number)
                    .keyboardType(.decimalPad)
                    .onChange(of: fps) { _, value in fps = value.isFinite ? min(60, max(1, value)) : 12 }
            }
        }
    }
}

private struct SheetGridPreview: View {
    let projectID: UUID
    let source: SpriteSource
    let frames: [SpriteFrame]
    let showsGrid: Bool
    @State private var image: CGImage?
    @State private var error: String?

    var body: some View {
        VStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable().interpolation(.none)
                    .aspectRatio(CGFloat(source.pixelWidth) / CGFloat(source.pixelHeight), contentMode: .fit)
                    .overlay {
                        if showsGrid {
                            Canvas { context, size in
                                let sx = size.width / CGFloat(source.pixelWidth)
                                let sy = size.height / CGFloat(source.pixelHeight)
                                for frame in frames {
                                    let rect = frame.pixelRect
                                    let path = Path(CGRect(x: CGFloat(rect.x) * sx, y: CGFloat(rect.y) * sy,
                                        width: CGFloat(rect.width) * sx, height: CGFloat(rect.height) * sy))
                                    context.stroke(path, with: .color(.white), lineWidth: 3)
                                    context.stroke(path, with: .color(.black), lineWidth: 1)
                                }
                            }.accessibilityHidden(true)
                        }
                    }
                    .background(Checkerboard())
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else { ProgressView() }
        }
        .frame(maxHeight: 320)
        .task(id: source.id) {
            do {
                let frame = SpriteFrame(id: source.id, sourceID: source.id,
                    pixelRect: PixelRect(width: source.pixelWidth, height: source.pixelHeight))
                image = try await ImagePipeline.shared.thumbnail(projectID: projectID, source: source, frame: frame)
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct RecoveryFrameGrid: View {
    let projectID: UUID
    let source: SpriteSource
    let frames: [SpriteFrame]
    @Binding var selected: Set<UUID>
    @Binding var detail: SpriteFrame?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
            ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                VStack {
                    Button {
                        if !selected.insert(frame.id).inserted { selected.remove(frame.id) }
                    } label: {
                        FrameThumbnailView(projectID: projectID, source: source, frame: frame)
                            .frame(height: 90)
                            .overlay(alignment: .topTrailing) {
                                if selected.contains(frame.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                    }
                    .accessibilityLabel("Frame \(index + 1)")
                    .accessibilityAddTraits(selected.contains(frame.id) ? .isSelected : [])
                    Button("Frame \(index + 1)") { detail = frame }.font(.caption)
                }
            }
        }
    }
}
