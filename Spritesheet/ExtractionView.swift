import SwiftUI

struct ExtractionView: View {
    @Bindable var model: EditorViewModel
    let source: SpriteSource
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExtractionSettings()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    LabeledContent("File", value: source.originalFilename)
                    LabeledContent("Size", value: "\(source.pixelWidth) × \(source.pixelHeight) px")
                }
                Section("Grid") {
                    IntegerField("Columns", value: $settings.columns, minimum: 1)
                    IntegerField("Rows", value: $settings.rows, minimum: 1)
                    IntegerField("Frame count", value: $settings.frameCount, minimum: 1)
                }
                Section("Geometry") {
                    IntegerField("Horizontal spacing", value: $settings.horizontalSpacing, minimum: 0, suffix: "px")
                    IntegerField("Vertical spacing", value: $settings.verticalSpacing, minimum: 0, suffix: "px")
                    IntegerField("Margin", value: $settings.margin, minimum: 0, suffix: "px")
                }
                Section("Order") {
                    Picker("Extraction order", selection: $settings.order) {
                        Text("Left to right, then down").tag(ExtractionOrder.rowMajor)
                        Text("Top to bottom, then right").tag(ExtractionOrder.columnMajor)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Extract Spritesheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Extract") {
                        do {
                            try model.extractFrames(from: source.id, settings: settings)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .onChange(of: settings.columns) { _, _ in updateDefaultCount() }
            .onChange(of: settings.rows) { _, _ in updateDefaultCount() }
        }
    }

    private func updateDefaultCount() {
        let (capacity, overflow) = settings.columns.multipliedReportingOverflow(by: settings.rows)
        if !overflow { settings.frameCount = capacity }
    }
}
