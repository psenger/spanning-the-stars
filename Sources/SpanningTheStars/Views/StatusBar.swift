import SwiftUI
import StarsCore

/// Public standing of every House, the final-round banner and the Codex button.
struct StatusBar: View {
    let state: GameState
    let onCodex: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(state.players.indices, id: \.self) { seat in
                HouseChip(player: state.players[seat], active: seat == state.current)
            }
            if let remaining = state.finalTurnsRemaining {
                FinalRoundBanner(turnsRemaining: remaining)
            }
            Spacer(minLength: 0)
            Button(action: onCodex) {
                Label("Codex", systemImage: "book.closed.fill")
            }
            .buttonStyle(BrassButtonStyle(prominent: false))
            .help("Read the rules of the Charter")
            .accessibilityLabel("Codex")
        }
    }
}

struct HouseChip: View {
    let player: PlayerState
    let active: Bool

    /// The chip's top line: the House name, followed by the level for a bot, for example
    /// "House Ashkar · Navigator".
    static func title(for player: PlayerState) -> String {
        guard case .bot(let level) = player.kind else { return player.house.displayName }
        return "\(player.house.displayName) · \(level.displayName)"
    }

    var body: some View {
        let rim = Palette.houseRim(player.house)
        let name = player.house.displayName
        // Whatever follows the House name in the title is the level, drawn dim.
        let level = String(HouseChip.title(for: player).dropFirst(name.count))
        HStack(spacing: 8) {
            ArtImage(.house(player.house))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name)\(Text(level).foregroundStyle(Palette.dimText))")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 7) {
                    Stat(symbol: "star.fill", value: player.score, help: "Concord Standing")
                    Stat(symbol: "dot.radiowaves.up.forward", value: player.beacons, help: "Anchor Beacons left")
                    Stat(symbol: "rectangle.portrait.on.rectangle.portrait.fill", value: player.hand.total,
                         help: "Resource Cards in hand")
                    Stat(symbol: "scroll.fill", value: player.contracts.count, help: "Concord Contracts held")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(minWidth: 196, maxWidth: 250, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(active
                      ? AnyShapeStyle(LinearGradient(colors: [Palette.house(player.house).opacity(0.55),
                                                              Palette.hex(0x0A0F24, opacity: 0.9)],
                                                     startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(Palette.hex(0x0A0F24, opacity: 0.8)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(active ? Palette.brass : rim.opacity(0.35), lineWidth: active ? 1.5 : 1)
        }
        .shadow(color: active ? Palette.brass.opacity(0.45) : .clear, radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct Stat: View {
    let symbol: String
    let value: Int
    let help: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.brass)
            Text("\(value)")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
        }
        .fixedSize()
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(help): \(value)")
    }
}

private struct FinalRoundBanner: View {
    let turnsRemaining: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("FINAL ROUND")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Palette.hex(0xFFD9A0))
            Text(turnsRemaining == 1 ? "1 turn left" : "\(turnsRemaining) turns left")
                .font(.system(size: 11))
                .foregroundStyle(Palette.text.opacity(0.85))
        }
        // The House chips flex instead, so the banner never truncates.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(Palette.hex(0x3A1608, opacity: 0.9), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hex(0xF28C28, opacity: 0.8), lineWidth: 1.2))
        .shadow(color: Palette.hex(0xF28C28, opacity: 0.4), radius: 8)
    }
}
