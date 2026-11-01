import SwiftUI

struct RecoveryProjectTransferView: View {
    let project: SpriteProject
    let frames: [SpriteFrame]
    let fps: Double
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [SpriteProject] = []
    @State private var name = ""
    @State private var busy = false
    @State private var message: String?
    @State private var completed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("New Spritesheet") {
                    TextField("Project Name", text: $name)
                    Button("Create Project from Frames") { transfer(to: nil) }
                }
                Section("Append to Existing Project") {
                    Text("Frames are appended. Existing frames and playback settings are kept.")
                    ForEach(projects) { target in
                        Button(target.name) { transfer(to: target.id) }
                    }
                }
                if busy { ProgressView() }
                if let message { Text(message) }
            }
            .disabled(busy || completed)
            .navigationTitle("Use in Another Project")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                do { projects = try await RecoveryProjectService().projects(excluding: project.id) }
                catch { message = error.localizedDescription }
            }
        }
    }

    private func transfer(to id: UUID?) {
        busy = true
        Task {
            do {
                let result = try await RecoveryProjectService().transfer(
                    from: project, frames: frames, fps: fps, targetID: id,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "Recovered Animation") : name)
                message = String(localized: "Frames saved in \(result.name). Open it from Projects.")
                completed = true
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
