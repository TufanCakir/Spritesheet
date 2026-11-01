import SwiftUI
import UniformTypeIdentifiers

struct FrameExportView: View {
    let project: SpriteProject
    let frames: [SpriteFrame]
    @Environment(\.dismiss) private var dismiss
    @State private var prefix = "frame"
    @State private var choosesFolder = false
    @State private var isExporting = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Export Frames") {
                    Text("\(frames.count) frames")
                    TextField("Filename prefix", text: $prefix)
                    Text("Original pixel size and transparency are preserved.")
                    Button("Choose Destination Folder", systemImage: "folder") { choosesFolder = true }
                        .disabled(isExporting || frames.isEmpty)
                    if isExporting { ProgressView("Exporting…") }
                    if let message { Text(message).textSelection(.enabled) }
                }
            }
            .navigationTitle("Export Frames")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(isExporting)
                }
            }
            .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let folder):
                    isExporting = true
                    message = nil
                    task = Task {
                        do {
                            let url = try await FrameExportService().export(
                                project: project, frames: frames, prefix: prefix, folder: folder)
                            message = String(localized: "Exported to \(url.lastPathComponent).")
                        } catch is CancellationError {
                        } catch { message = error.localizedDescription }
                        isExporting = false
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
                }
            }
            .interactiveDismissDisabled(isExporting)
            .onDisappear { task?.cancel() }
        }
    }
}
