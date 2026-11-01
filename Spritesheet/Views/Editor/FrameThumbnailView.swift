//
//  FrameThumbnailView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct FrameThumbnailView: View {
    let projectID: UUID
    let source: SpriteSource?
    let frame: SpriteFrame

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Checkerboard(squareSize: 8)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel("Error")
            } else {
                ProgressView()
            }
        }
        .task(id: frame.id) {
            image = nil
            failed = false
            guard let source else { failed = true; return }
            do {
                image = try await ImagePipeline.shared.thumbnail(
                    projectID: projectID, source: source, frame: frame)
            } catch { failed = true }
        }
    }
}
