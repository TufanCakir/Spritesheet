//
//  LayoutEditorView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct LayoutEditorView: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Grid") {
                    IntegerField(
                        "Columns",
                        value: $model.project.layout.columns,
                        minimum: 1
                    )
                    Toggle("Automatic rows", isOn: automaticRowsBinding)
                    if model.project.layout.manualRows != nil {
                        IntegerField(
                            "Rows",
                            value: manualRowsBinding,
                            minimum: 1
                        )
                    }
                }

                Section("Spacing") {
                    IntegerField(
                        "Horizontal",
                        value: $model.project.layout.horizontalSpacing,
                        minimum: 0,
                        suffix: "px"
                    )
                    IntegerField(
                        "Vertical",
                        value: $model.project.layout.verticalSpacing,
                        minimum: 0,
                        suffix: "px"
                    )
                    IntegerField(
                        "Margin",
                        value: $model.project.layout.margin,
                        minimum: 0,
                        suffix: "px"
                    )
                }

                Section("Alignment") {
                    Picker(
                        "Horizontal",
                        selection: $model.project.layout.horizontalAlignment
                    ) {
                        Text("Leading").tag(HorizontalAlignmentOption.leading)
                        Text("Center").tag(HorizontalAlignmentOption.center)
                        Text("Trailing").tag(HorizontalAlignmentOption.trailing)
                    }
                    Picker(
                        "Vertical",
                        selection: $model.project.layout.verticalAlignment
                    ) {
                        Text("Top").tag(VerticalAlignmentOption.top)
                        Text("Center").tag(VerticalAlignmentOption.center)
                        Text("Bottom").tag(VerticalAlignmentOption.bottom)
                    }
                }

                if let calculated = model.calculatedLayout {
                    Section("Output") {
                        LabeledContent(
                            "Frames",
                            value: model.project.frames.count.formatted()
                        )
                        LabeledContent(
                            "Size",
                            value:
                                "\(calculated.outputWidth) × \(calculated.outputHeight) px"
                        )
                    }
                } else if !model.project.frames.isEmpty {
                    Section {
                        Text(layoutError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.project.markModified()
                        Task { await model.save() }
                        dismiss()
                    }
                    .disabled(
                        !model.project.frames.isEmpty
                            && model.calculatedLayout == nil
                    )
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var automaticRowsBinding: Binding<Bool> {
        Binding(
            get: { model.project.layout.manualRows == nil },
            set: {
                model.project.layout.manualRows =
                    $0 ? nil : max(1, model.calculatedLayout?.rows ?? 1)
            }
        )
    }

    private var manualRowsBinding: Binding<Int> {
        Binding(
            get: { model.project.layout.manualRows ?? 1 },
            set: { model.project.layout.manualRows = $0 }
        )
    }

    private var layoutError: String {
        do {
            _ = try LayoutCalculator.calculate(
                frameRects: model.project.frames.map(\.pixelRect),
                layout: model.project.layout
            )
            return ""
        } catch {
            return error.localizedDescription
        }
    }
}

struct IntegerField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let minimum: Int
    var suffix: String?

    init(
        _ title: LocalizedStringKey,
        value: Binding<Int>,
        minimum: Int,
        suffix: String? = nil
    ) {
        self.title = title
        _value = value
        self.minimum = minimum
        self.suffix = suffix
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("Value", value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 64)
                    .onChange(of: value) { _, newValue in
                        if newValue < minimum { value = minimum }
                    }
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
                Button {
                    if value > minimum { value -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Decrease \(title)")
                Button {
                    let (next, overflow) = value.addingReportingOverflow(1)
                    if !overflow { value = next }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Increase \(title)")
            }
        } label: {
            Text(title)
        }
    }
}
