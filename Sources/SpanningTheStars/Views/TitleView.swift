import SwiftUI
import StarsCore

/// The opening screen: emblem, title, the box-back flavor text and the way into a Charter.
struct TitleView: View {
    let canContinue: Bool
    let onContinue: () -> Void
    let onNewCharter: () -> Void

    @State private var showCodex = false

    var body: some View {
        GeometryReader { geo in
            // Everything scales with the window height, so the stack fits from 800 pt to full screen.
            let unit = min(geo.size.height / 900, geo.size.width / 1400)
            VStack(spacing: 22 * unit) {
                ArtImage(.titleEmblem)
                    .frame(width: 300 * unit, height: 300 * unit)
                    .shadow(color: Palette.brass.opacity(0.35), radius: 30 * unit)
                    .accessibilityHidden(true)
                VStack(spacing: 10 * unit) {
                    Text("Spanning the Stars")
                        .font(.system(size: 64 * unit, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text)
                        .shadow(color: .black.opacity(0.8), radius: 8)
                    Text("The galaxy has been dark for three hundred years. Now the lanes are opening.")
                        .font(.system(size: 19 * unit, weight: .medium, design: .serif).italic())
                        .foregroundStyle(Palette.brass)
                }
                Text(TitleView.flavor)
                    .font(.system(size: 15 * unit, design: .serif))
                    .foregroundStyle(Palette.text.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4 * unit)
                    .frame(maxWidth: 640 * unit)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if canContinue {
                        GameButton("Continue Charter", help: "Resume the autosaved game", action: onContinue)
                            .buttonStyle(TitleButtonStyle(prominent: true))
                            .accessibilityLabel("Continue Charter")
                    }
                    GameButton("New Charter", help: "Set up a new game", action: onNewCharter)
                        .buttonStyle(TitleButtonStyle(prominent: !canContinue))
                        .accessibilityLabel("New Charter")
                    GameButton(help: "Open the in-game rules and card guide") {
                        showCodex = true
                    } label: {
                        Label("Codex", systemImage: "book.closed.fill")
                    }
                    .buttonStyle(TitleButtonStyle(prominent: false))
                    .accessibilityLabel("Codex")
                }
                .padding(.top, 10 * unit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { SpaceBackground().ignoresSafeArea() }
        .sheet(isPresented: $showCodex) { CodexView() }
    }

    /// The box-back text from the README, after its opening line.
    static let flavor = "Claim hyperspace corridors, fulfill contracts for desperate worlds, and outbuild your rivals "
        + "to forge the greatest network in the known stars. But every lane you anchor is one your rivals can't use, "
        + "and space is not as big as it looks.\n\nThe Concord is watching. Start spanning the stars."
}

/// A larger brass capsule for the title and setup screens.
struct TitleButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(prominent ? Palette.hex(0x161006) : Palette.text)
            .padding(.horizontal, 26).padding(.vertical, 11)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Palette.brass) : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().strokeBorder(Palette.brass.opacity(prominent ? 0 : 0.6), lineWidth: 1))
            .shadow(color: prominent ? Palette.brass.opacity(0.35) : .clear, radius: 10)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}
