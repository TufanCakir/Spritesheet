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
    @State private var playback = AnimationPlayback()
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
                preview(index: playback.index)
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
                            isPlaying = false
                        } else {
                            playback.direction = playsBackward ? -1 : 1
                            if playsBackward && playback.index == 0 {
                                playback.index = max(0, model.project.frames.count - 1)
                            } else if !playsBackward && playback.index == model.project.frames.count - 1 {
                                playback.index = 0
                            }
                            isPlaying = model.project.frames.count > 1
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    Button("Stop", systemImage: "stop.fill") {
                        isPlaying = false
                        playback.index = 0
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
                    isPlaying = false
                }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { isPlaying = false }
        .onChange(of: playsBackward) { _, backward in playback.direction = backward ? -1 : 1 }
        .task(id: PlaybackTaskID(playing: isPlaying, fps: model.project.animationFPS)) {
            guard isPlaying else { return }
            let clock = ContinuousClock()
            let fps = model.project.animationFPS.isFinite ? min(60, max(1, model.project.animationFPS)) : 12
            let interval = Duration.seconds(1 / fps)
            var deadline = clock.now + interval
            do {
                while !Task.isCancelled && isPlaying {
                    try await clock.sleep(until: deadline)
                    guard !Task.isCancelled else { return }
                    isPlaying = playback.advance(count: model.project.frames.count, loops: loops, pingPong: pingPong)
                    deadline += interval
                }
            } catch is CancellationError {
            } catch { isPlaying = false }
        }
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

    private func step(_ amount: Int) {
        isPlaying = false
        let count = model.project.frames.count
        guard count > 0 else { return }
        playback.index = min(max(0, playback.index + amount), count - 1)
    }
}

private struct PlaybackTaskID: Hashable {
    let playing: Bool
    let fps: Double
}
