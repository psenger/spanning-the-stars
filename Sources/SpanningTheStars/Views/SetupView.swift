import SwiftUI
import StarsCore

/// Chooses the Houses (2 to 5, each with its fixed color), who plays each one and the Frontier
/// Hazards variant.
struct SetupView: View {
    let onBegin: (_ houses: [House], _ hazards: Bool, _ kinds: [PlayerKind]) -> Void
    let onBack: () -> Void

    @State private var chosen: Set<House> = [.varn, .solace]
    /// Who plays each House; a House with no entry is human. Kept when a House is turned off.
    @State private var choices: [House: PlayerKind] = [:]
    @State private var hazards = false

    /// Seats follow the fixed House order.
    private var houses: [House] { House.allCases.filter(chosen.contains) }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("Charter the Houses")
                            .font(.system(size: 40, weight: .semibold, design: .serif))
                            .foregroundStyle(Palette.text)
                        Text("Choose 2 to 5 Houses. Seats follow the order below; the Concord draws lots for who goes first.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.dimText)
                    }

                    VStack(spacing: 8) {
                        ForEach(House.allCases, id: \.self) { house in
                            HouseToggleRow(house: house, isOn: binding(house), kind: kindBinding(house),
                                           locked: chosen.contains(house) && chosen.count <= 2)
                        }
                    }
                    .frame(maxWidth: SetupView.columnWidth)

                    Toggle(isOn: $hazards) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Frontier Hazards")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Text("Spectrum Lanes in the Veil Nebula need a different resource for each slot.\n"
                                 + "Gravity Well Lanes in the Ember Belt take one card fewer but cost an extra Anchor Beacon.")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.dimText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .help("Enable Spectrum and Gravity Well lane rules")
                    .onChange(of: hazards) { InteractionSound.selection.play() }
                    .tint(Palette.brass)
                    .panel(padding: 16)
                    .frame(maxWidth: SetupView.columnWidth)

                    HStack(spacing: 14) {
                        GameButton("Back", help: "Leave game setup", action: onBack)
                            .buttonStyle(TitleButtonStyle(prominent: false))
                            .accessibilityLabel("Back")
                            .keyboardShortcut(.cancelAction)
                        GameButton("Begin the Charter (\(houses.count) Houses)", help: "Start a game with these Houses") {
                            onBegin(houses, hazards, SetupView.kinds(for: houses, choices: choices))
                        }
                            .buttonStyle(TitleButtonStyle(prominent: true))
                            .accessibilityLabel("Begin the Charter with \(houses.count) Houses")
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { SpaceBackground().ignoresSafeArea() }
    }

    private func binding(_ house: House) -> Binding<Bool> {
        Binding(get: { chosen.contains(house) }, set: { on in
            if on { chosen.insert(house) } else if chosen.count > 2 { chosen.remove(house) }
        })
    }

    private func kindBinding(_ house: House) -> Binding<PlayerKind> {
        Binding(get: { choices[house] ?? .human }, set: { choices[house] = $0 })
    }
}

private struct HouseToggleRow: View {
    let house: House
    @Binding var isOn: Bool
    @Binding var kind: PlayerKind
    /// One of the last two Houses: it cannot be turned off.
    let locked: Bool

    var body: some View {
        GameButton(help: locked ? "A Charter needs at least 2 Houses"
                   : isOn ? "Remove \(house.displayName) from the Charter" : "Add \(house.displayName) to the Charter",
                   sound: locked ? nil : .selection) {
            if !locked { isOn.toggle() }
        } label: {
            HStack(spacing: 14) {
                ArtImage(.house(house))
                    .frame(width: 46, height: 46)
                    .saturation(isOn ? 1 : 0.2)
                    .opacity(isOn ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(house.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.text : Palette.dimText)
                    Text(SetupView.motto(house))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.dimText)
                }
                Spacer()
                if isOn {
                    // Room for the picker, which sits over the row so it is not part of the button.
                    Color.clear.frame(width: HouseToggleRow.pickerWidth, height: 1)
                }
                Capsule()
                    .fill(Palette.house(house))
                    .overlay(Capsule().strokeBorder(Palette.houseRim(house), lineWidth: 1))
                    .frame(width: 34, height: 12)
                    .accessibilityHidden(true)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? Palette.brass : Palette.dimText.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isOn ? Palette.house(house).opacity(0.18) : Palette.hex(0x0A0F24, opacity: 0.8),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isOn ? Palette.brass.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(house.displayName)
        .accessibilityValue(isOn ? "In the Charter" : "Not in the Charter")
        .overlay(alignment: .trailing) {
            if isOn {
                Picker("Played by", selection: option) {
                    ForEach(SetupView.kindOptions.indices, id: \.self) { index in
                        Text(SetupView.kindOptions[index].label).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: HouseToggleRow.pickerWidth)
                // Clear of the color capsule and the checkmark at the row's trailing edge.
                .padding(.trailing, 16 + 22 + 14 + 34 + 14)
                .help("Who plays \(house.displayName)")
                .accessibilityLabel("\(house.displayName) played by")
            }
        }
    }

    /// Fits "Commander (Level 4)", the longest option.
    private static let pickerWidth: CGFloat = 170

    /// The picker selects a row of `kindOptions` (`PlayerKind` is not Hashable).
    private var option: Binding<Int> {
        Binding(get: { SetupView.kindOptions.firstIndex { $0.kind == kind } ?? 0 },
                set: { index in
                    let next = SetupView.kindOptions[index].kind
                    guard next != kind else { return }
                    kind = next
                    InteractionSound.selection.play()
                })
    }
}

extension SetupView {
    /// Width of the House list and the variant panel: room for a motto beside the player picker.
    static let columnWidth: CGFloat = 780

    /// Kinds in seat order for the chosen Houses; a House with no choice is human.
    static func kinds(for houses: [House], choices: [House: PlayerKind]) -> [PlayerKind] {
        houses.map { choices[$0] ?? .human }
    }

    /// Picker rows: "Human", then "Cadet (Level 1)" to "Admiral (Level 5)".
    static let kindOptions: [(label: String, kind: PlayerKind)] = [("Human", .human)]
        + BotLevel.allCases.map { ("\($0.displayName) (Level \($0.rawValue))", .bot($0)) }

    /// One line per House, from the README.
    static func motto(_ house: House) -> String {
        switch house {
        case .varn: "Blue-collar haulers from the forge worlds. Practical and relentless."
        case .solace: "Old-money financiers who see every lane as an investment."
        case .meridian: "A cooperative of agricultural colonies trying to feed the galaxy."
        case .ashkar: "Desert-world traders with a reputation for cutthroat deals."
        case .paleFleet: "Former military logistics officers who went private after the collapse."
        }
    }
}
