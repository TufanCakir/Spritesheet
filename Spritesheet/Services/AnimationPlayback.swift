import Foundation

/// A deterministic playback cursor shared by the timed view and unit tests.
struct AnimationPlayback: Equatable, Sendable {
    var index = 0
    var direction = 1

    mutating func advance(count: Int, loops: Bool, pingPong: Bool) -> Bool {
        guard count > 1 else { index = 0; return false }
        let next = index + direction
        if (0..<count).contains(next) {
            index = next
            return true
        }
        if pingPong {
            if !loops && direction == -1 { return false }
            direction = -direction
            index += direction
            return true
        }
        guard loops else { return false }
        index = direction > 0 ? 0 : count - 1
        return true
    }
}
