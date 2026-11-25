import SwiftUI
import StarsCore

/// The privacy screen between seats. It covers the blurred board (whose secrets `Secrets` already
/// hides) with the starfield, names the House to take the console, and lists what happened since
/// the last hand-off.
///
/// "Reveal my hand" has no keyboard shortcut and takes no focus: a Return or Space meant for the
/// previous House's last action must never open the next House's hand.
struct HandoffView: View {
    let house: House
    /// True before a setup contract pick, false before a turn.
    let setupPick: Bool
    let lines: [ConcordLog.Line]
    /// The game was continued or loaded, so no events since a hand-off are known.
    var resumed = false
    let reveal: () -> Void

    var body: some View {
        GeometryReader { geo in
            let unit = min(1, geo.size.height / 900)
            ZStack {
                SpaceBackground().opacity(0.82)
                VStack(spacing: 20 * unit) {
                    ArtImage(.house(house))
                        .frame(width: 128, height: 128)
                        .shadow(color: Palette.houseRim(house).opacity(0.7), radius: 24)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Hand the console to \(house.displayName)")
                            .font(.system(size: 34 * max(unit, 0.85), weight: .semibold, design: .serif))
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.center)
                        Text(setupPick
                             ? "Choose the Concord Contracts your House will pursue. Everyone else, look away."
                             : "Your turn. Everyone else, look away.")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.dimText)
                    }
                    RecentEvents(lines: lines, resumed: resumed)
                        .frame(maxWidth: 520)
                    Button("Reveal my hand", action: reveal)
                        .buttonStyle(TitleButtonStyle(prominent: true))
                        .focusable(false)
                        .accessibilityLabel("Reveal my hand")
                        .padding(.top, 6)
                }
                .padding(32)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Public events since the last hand-off, oldest first, as they happened.
private struct RecentEvents: View {
    let lines: [ConcordLog.Line]
    let resumed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PanelTitle(text: "Since the last hand-off")
            if lines.isEmpty {
                Text(resumed ? "Charter resumed from a save. Earlier moves are in the Concord Log."
                             : "The Charter begins. No moves yet.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.dimText)
            } else {
                ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 10) {
                        Group {
                            if let house = line.house {
                                ArtImage(.house(house))
                            } else {
                                Image(systemName: line.isEnding ? "flag.checkered" : "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.brass)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(line.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .panel(padding: 16)
    }
}
