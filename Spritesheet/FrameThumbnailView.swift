import SwiftUI

struct FrameThumbnailView: View {
    let projectID: UUID
    let source: SpriteSource?
    let frame: SpriteFrame

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Checkerboard(squareSize: 8)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else {
                ProgressView()
            }
        }
        .task(id: frame.id) {
            guard let source else { return }
            image = try? await ImagePipeline.shared.thumbnail(
                projectID: projectID,
                source: source,
                frame: frame
            )
        }
    }
}
