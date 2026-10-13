import SwiftUI

struct ExportView: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    TextField("Filename", text: $model.project.exportSettings.filename)
                        .textInputAutocapitalization(.never)
                    LabeledContent("Format", value: "PNG spritesheet")
                }

                Section("Output") {
                    if let layout = model.calculatedLayout {
                        LabeledContent("Size", value: "\(layout.outputWidth) × \(layout.outputHeight) px")
                        LabeledContent("Frames", value: model.project.frames.count.formatted())
                        LabeledContent("Grid", value: "\(layout.columns) × \(layout.rows)")
                    } else {
                        Text("The current layout cannot be exported.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        model.exportPNG()
                    } label: {
                        Label(model.isExporting ? "Exporting…" : "Create PNG", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isExporting || model.calculatedLayout == nil)
                }

                if let result = model.exportResult {
                    Section("PNG created") {
                        LabeledContent("Verified size", value: "\(result.width) × \(result.height) px")
                        ShareLink(item: result.url) {
                            Label("Share or Save to Files", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Text("PNG encoding is lossless. The current baseline compositor uses an 8-bit premultiplied sRGB buffer; it does not claim byte-for-byte preservation for 16-bit or profile-mismatched sources.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
