//
//  AnimationPreviewView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct AnimationPreviewView: View {
    let model: EditorViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = false
    @State private var startDate = Date()
    @State private var stoppedIndex = 0
    @State private var playsBackward = false
    @State private var loops = true
    @State private var pingPong: Bool

    init(model: EditorViewModel) {
        self.model = model
        _loops = State(initialValue: model.project.animationLoops ?? true)
        _playsBackward = State(
            initialValue: model.project.animationPlaysBackward ?? false
        )
        _pingPong = State(
            initialValue: model.project.animationPingPong ?? false
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TimelineView(.animation(paused: !isPlaying)) { timeline in
                    preview(index: displayedIndex(at: timeline.date))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Checkerboard())
                .clipShape(.rect(cornerRadius: 18))

                HStack(spacing: 24) {
                    Button("Previous", systemImage: "backward.end.fill") {
                        step(-1)
                    }
                    .labelStyle(.iconOnly)
                    Button(
                        isPlaying ? "Pause" : "Play",
                        systemImage: isPlaying ? "pause.fill" : "play.fill"
                    ) {
                        if isPlaying {
                            stoppedIndex = displayedIndex(at: .now)
                            isPlaying = false
                        } else {
                            startDate = .now
                            isPlaying = model.project.frames.count > 1
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    Button("Stop", systemImage: "stop.fill") {
                        isPlaying = false
                        stoppedIndex = 0
                    }
                    .labelStyle(.iconOnly)
                    Button("Next", systemImage: "forward.end.fill") { step(1) }
                        .labelStyle(.iconOnly)
                }
                .font(.title2)
                .controlSize(.large)

                Form {
                    Section("Playback") {
                        IntegerField(
                            "FPS",
                            value: Binding(
                                get: { Int(model.project.animationFPS) },
                                set: {
                                    model.project.animationFPS = Double(
                                        min(60, max(1, $0))
                                    )
                                }
                            ),
                            minimum: 1
                        )
                        Toggle("Loop", isOn: $loops)
                        Toggle("Backward", isOn: $playsBackward)
                        Toggle("Ping-pong", isOn: $pingPong)
                    }
                }
                .frame(maxHeight: 250)
            }
            .padding()
            .navigationTitle("Animation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.project.animationLoops = loops
                        model.project.animationPlaysBackward = playsBackward
                        model.project.animationPingPong = pingPong
                        model.projectDidChange()
                        dismiss()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    stoppedIndex = displayedIndex(at: .now)
                    isPlaying = false
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func preview(index: Int) -> some View {
        if model.project.frames.indices.contains(index) {
            let frame = model.project.frames[index]
            let source = model.project.sources.first { $0.id == frame.sourceID }
            ZStack(alignment: .bottom) {
                FrameThumbnailView(
                    projectID: model.project.id,
                    source: source,
                    frame: frame
                )
                .padding(24)
                Text("Frame \(index + 1) of \(model.project.frames.count)")
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
            }
        } else {
            ContentUnavailableView("No Frames", systemImage: "play.slash")
        }
    }

    private func displayedIndex(at date: Date) -> Int {
        let count = model.project.frames.count
        guard count > 1, isPlaying else {
            return min(stoppedIndex, max(0, count - 1))
        }
        let elapsed = max(0, date.timeIntervalSince(startDate))
        let ticks = Int(elapsed * model.project.animationFPS)
        let base = stoppedIndex + ticks
        let index: Int
        if pingPong {
            let period = max(1, (count - 1) * 2)
            let position = base % period
            index = position < count ? position : period - position
        } else if loops {
            index = base % count
        } else {
            index = min(base, count - 1)
        }
        return playsBackward ? count - 1 - index : index
    }

    private func step(_ amount: Int) {
        isPlaying = false
        let count = model.project.frames.count
        guard count > 0 else { return }
        stoppedIndex = min(max(0, stoppedIndex + amount), count - 1)
    }
}
