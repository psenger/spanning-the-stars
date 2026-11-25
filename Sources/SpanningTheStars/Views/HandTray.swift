import SwiftUI
import StarsCore

/// The active House's Resource Cards: one stack per card type with a count badge.
struct HandTray: View {
    let hand: Hand
    /// True while nobody has revealed the hand; the tray then shows nothing private.
    var hidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(text: "Resource Cards", detail: hidden ? nil : "\(hand.total) in hand")
            if hidden {
                placeholder("Hidden until the House at the console reveals its hand")
            } else if hand.total == 0 {
                placeholder("No Resource Cards in hand")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(HandTray.stacks(hand), id: \.card) { stack in
                        CardStack(card: stack.card, count: stack.count)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.dimText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Non-empty stacks in color order, Quantum Cores last.
    static func stacks(_ hand: Hand) -> [(card: Card, count: Int)] {
        Card.handOrder.map { ($0, hand.count($0)) }.filter { $0.1 > 0 }
    }
}

private struct CardStack: View {
    let card: Card
    let count: Int

    /// How far each card behind the top one peeks out.
    private let step: CGFloat = 3.5

    var body: some View {
        let layers = min(count, 3)
        ZStack(alignment: .bottomLeading) {
            ForEach((0..<layers).reversed(), id: \.self) { i in
                ResourceCardView(card: card, size: GameLayout.handCard)
                    .brightness(i == 0 ? 0 : -0.25)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: CGFloat(i) * step, y: -CGFloat(i) * step)
            }
        }
        .frame(width: GameLayout.handCard.width + step * 2, height: GameLayout.handCard.height + step * 2,
               alignment: .bottomLeading)
        .overlay(alignment: .topTrailing) {
            Text("×\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Palette.hex(0x05070F, opacity: 0.9), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.brass.opacity(0.85), lineWidth: 1))
                .offset(x: 8, y: -7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(card.displayName)")
    }
}

extension Card {
    /// Display order for hands and payments: the eight colors in rules order, then Quantum Cores.
    static let handOrder: [Card] = ResourceColor.allCases.map(Card.resource) + [.core]

    var displayName: String {
        switch self {
        case .core: "Quantum Core"
        case .resource(let r): r.resourceName
        }
    }
}
