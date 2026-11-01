import SwiftUI
import UniformTypeIdentifiers

struct RecoverySourceView: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var importsPNG = false
    @State private var source: SpriteSource?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Import a spritesheet, optionally load JSON, check the grid and animation, then export editable PNG frames.")
                    Button("Import Spritesheet", systemImage: "square.and.arrow.down") { importsPNG = true }
                        .disabled(model.isImporting)
                    if model.isImporting { ProgressView("Importing PNG files…") }
                    if let report = model.importReport { Text(report) }
                }
                Section("Source") {
                    ForEach(model.project.sources) { item in
                        Button {
                            source = item
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.originalFilename)
                                Text("\(item.pixelWidth) × \(item.pixelHeight) px").font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Restore Animation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importsPNG, allowedContentTypes: [.png], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): model.importFiles(urls)
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { model.importReport = error.localizedDescription }
                }
            }
            .sheet(item: $source) { ExtractionView(model: model, source: $0) }
        }
    }
}
