import SwiftUI

struct Checkerboard: View {
    var squareSize: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color.secondary.opacity(0.18)
                        : Color.secondary.opacity(0.08)
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
