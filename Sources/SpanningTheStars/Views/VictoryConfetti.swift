import SwiftUI

/// A centre burst and two corner bursts, inspired by the Saltmarsh Isles victory screen.
struct VictoryConfetti: View {
    let colors: [Color]

    private struct Piece {
        let origin: CGPoint
        let velocity: CGVector
        let color: Color
        let spin: Double
        let length: CGFloat
        let delay: TimeInterval
    }

    private static let duration = 4.0
    @State private var pieces: [Piece] = []
    @State private var started = Date()
    @State private var finished = false

    var body: some View {
        if !finished {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(started)
                    context.opacity = min(1, max(0, Self.duration - elapsed))
                    for piece in pieces where elapsed > piece.delay {
                        draw(piece, at: elapsed - piece.delay, in: context, size: size)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                pieces = burst(count: 70, from: CGPoint(x: 0.5, y: 0.42), angles: -180 ... 0, delay: 0)
                    + burst(count: 55, from: CGPoint(x: 0.05, y: 1), angles: -80 ... -45, delay: 0.18)
                    + burst(count: 55, from: CGPoint(x: 0.95, y: 1), angles: -135 ... -100, delay: 0.18)
                started = .now
                try? await Task.sleep(for: .seconds(Self.duration))
                if !Task.isCancelled { finished = true }
            }
        }
    }

    private func burst(count: Int, from origin: CGPoint, angles: ClosedRange<Double>, delay: TimeInterval) -> [Piece] {
        let palette = colors + [Palette.brass, .white, Palette.hex(0x9B5DE5), Palette.hex(0x3FA7F5)]
        return (0..<count).map { index in
            let angle = Double.random(in: angles) * .pi / 180
            let speed = Double.random(in: 0.4...1.8)
            return Piece(origin: origin, velocity: CGVector(dx: speed * cos(angle), dy: speed * sin(angle)),
                         color: palette[index % palette.count], spin: .random(in: -7...7),
                         length: .random(in: 5...13), delay: delay)
        }
    }

    private func draw(_ piece: Piece, at time: TimeInterval, in context: GraphicsContext, size: CGSize) {
        let travel = (1 - exp(-1.7 * time)) / 1.7
        let x = (piece.origin.x + piece.velocity.dx * travel) * size.width
        let y = (piece.origin.y + piece.velocity.dy * travel + 0.2 * time * time) * size.height
        guard y < size.height + piece.length else { return }
        var particle = context
        particle.translateBy(x: x, y: y)
        particle.rotate(by: .radians(piece.spin * time))
        particle.fill(Path(CGRect(x: -2.5, y: -piece.length / 2, width: 5, height: piece.length)),
                      with: .color(piece.color))
    }
}
