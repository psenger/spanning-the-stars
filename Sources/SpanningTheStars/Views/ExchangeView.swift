import SwiftUI
import StarsCore

/// The five face-up Exchange slots, the Supply Depot (blind draw) and the Concord Contract deck.
struct ExchangeView: View {
    let state: GameState
    let options: TurnOptions
    /// False while the board is shown without the active House at the console.
    let enabled: Bool
    let perform: (Action) -> Void

    private let deckSize = CGSize(width: 40, height: 60)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(text: "The Exchange", detail: "Salvage Heap \(state.salvage.count)")
            HStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { slot in
                    slotView(slot)
                }
            }
            HStack(spacing: 10) {
                DeckButton(title: "Supply Depot", count: state.depot.count, unit: "card",
                           hint: "Draw blind", kind: .resource, size: deckSize,
                           enabled: enabled && options.canDrawBlind) { perform(.drawBlind) }
                DeckButton(title: "Concord Contracts", count: state.contractDeck.count, unit: "contract",
                           hint: "Draw up to 3", kind: .contract, size: deckSize,
                           enabled: enabled && options.canDrawContracts) { perform(.drawContracts) }
            }
        }
        .panel()
    }

    @ViewBuilder
    private func slotView(_ slot: Int) -> some View {
        if let card = state.exchange.indices.contains(slot) ? state.exchange[slot] : nil {
            let takeable = enabled && options.exchangeSlots.contains(slot)
            CardButton(enabled: takeable, help: help(for: card, takeable: takeable)) {
                perform(.drawExchange(slot: slot))
            } label: {
                ResourceCardView(card: card, size: GameLayout.exchangeCard)
            }
        } else {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Palette.dimText.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.03)))
                .frame(width: GameLayout.exchangeCard.width, height: GameLayout.exchangeCard.height)
                .overlay(Text("Empty").font(.system(size: 11)).foregroundStyle(Palette.dimText.opacity(0.7)))
                .accessibilityLabel("Empty Exchange slot")
        }
    }

    private func help(for card: Card, takeable: Bool) -> String {
        if takeable { return card == .core ? "Take the Quantum Core (ends your turn)" : "Take this card" }
        if card == .core, state.phase == .drawingSecondCard { return "A face-up Quantum Core cannot be the second pick" }
        return "Not available now"
    }
}

/// A card that lifts and glows under the pointer when it can be taken, and dims when it cannot.
struct CardButton<Label: View>: View {
    let enabled: Bool
    var help: String = ""
    let action: () -> Void
    @ViewBuilder var label: Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .shadow(color: hovering && enabled ? Palette.brass.opacity(0.8) : .black.opacity(0.4),
                        radius: hovering && enabled ? 8 : 3, y: 2)
                .offset(y: hovering && enabled ? -4 : 0)
                .saturation(enabled ? 1 : 0.35)
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

private struct DeckButton: View {
    let title: String
    let count: Int
    let unit: String
    let hint: String
    let kind: CardBackView.Kind
    let size: CGSize
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        CardButton(enabled: enabled, help: enabled ? hint : "Not available now", action: action) {
            HStack(spacing: 8) {
                ZStack {
                    if count > 1 {
                        CardBackView(kind: kind, size: size).offset(x: 3, y: -3).opacity(0.7)
                    }
                    if count > 0 {
                        CardBackView(kind: kind, size: size)
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Palette.dimText.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .frame(width: size.width, height: size.height)
                    }
                }
                .frame(width: size.width + 3, height: size.height + 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(count == 1 ? "1 \(unit)" : "\(count) \(unit)s")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Palette.dimText)
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.brass.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel("\(title), " + (count == 1 ? "1 \(unit)" : "\(count) \(unit)s"))
    }
}
