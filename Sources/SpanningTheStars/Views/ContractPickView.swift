import SwiftUI
import StarsCore

/// Choosing Concord Contracts, at setup (keep at least 2 of 4) or in a turn (keep at least 1 of up
/// to 3). The offered contracts are cards that toggle on click; the systems of every chosen or
/// hovered contract are ringed on the map. Confirm stays disabled until the minimum is chosen.
struct ContractPickView: View {
    let state: GameState
    let map: GalaxyMap
    let offered: [Int]
    let minimum: Int
    let perform: (Action) -> Void
    var heldHighlight: Set<String> = []

    @State private var selected: Set<Int> = []
    @State private var hovered: Int?

    /// The minimum to keep in a given phase, or nil when no contract choice is open.
    static func pick(for phase: TurnPhase) -> (offered: [Int], minimum: Int)? {
        switch phase {
        case .setupContracts(let offered): (offered, 2)
        case .choosingContracts(let offered): (offered, 1)
        default: nil
        }
    }

    private var marked: Set<String> {
        var ids = selected
        if let hovered { ids.insert(hovered) }
        return heldHighlight.union(ids.flatMap { [map.contracts[$0].a, map.contracts[$0].b] })
    }

    var body: some View {
        HStack(alignment: .top, spacing: GameLayout.gap) {
            StarMapView(map: map, state: state, hazards: state.config.frontierHazards, highlightSystems: marked)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            panel
                .frame(width: ContractPickView.panelWidth)
                .frame(maxHeight: .infinity)
        }
    }

    static let panelWidth: CGFloat = 440

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(text: "Concord Contracts offered", detail: "\(selected.count) of \(offered.count) chosen")
            Text(minimum == 2
                 ? "Keep at least 2. The rest return to the bottom of the Contract deck."
                 : "Keep at least 1. The rest return to the bottom of the Contract deck.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.dimText)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                let columns = 2
                let rows = (offered.count + 1) / 2
                let gap: CGFloat = 12
                let byWidth = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                let byHeight = (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows) * CardMetrics.aspect
                let size = CGSize(width: min(byWidth, byHeight), height: min(byWidth, byHeight) / CardMetrics.aspect)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(size.width), spacing: gap), count: columns),
                          spacing: gap) {
                    ForEach(offered, id: \.self) { id in
                        OfferedCard(contract: map.contracts[id], map: map, size: size,
                                    selected: selected.contains(id),
                                    toggle: { toggle(id) },
                                    hover: { inside in hovered = inside ? id : (hovered == id ? nil : hovered) })
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            HStack {
                GameButton(selected.count == offered.count ? "Clear" : "Choose all",
                           help: selected.count == offered.count ? "Clear your contract choices" : "Choose every offered contract",
                           sound: .selection) {
                    selected = selected.count == offered.count ? [] : Set(offered)
                }
                .buttonStyle(BrassButtonStyle(prominent: false))
                .accessibilityLabel(selected.count == offered.count ? "Clear" : "Choose all")
                Spacer()
                let confirm = selected.count < minimum
                    ? "Choose at least \(minimum)"
                    : "Accept \(selected.count) Contract\(selected.count == 1 ? "" : "s")"
                GameButton(confirm, help: "Keep the chosen contracts and return the rest to the deck") {
                    perform(.keepContracts(offered.filter(selected.contains)))
                }
                .buttonStyle(BrassButtonStyle())
                .accessibilityLabel(confirm)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.count < minimum)
            }
        }
        .panel()
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

private struct OfferedCard: View {
    let contract: Contract
    let map: GalaxyMap
    let size: CGSize
    let selected: Bool
    let toggle: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        GameButton(help: (selected ? "Remove this contract from your choices. " : "Choose this contract to keep. ")
                   + contract.flavor, sound: .selection, action: toggle) {
            ContractCardView(contract: contract, completed: nil, size: size, map: map)
                .opacity(selected ? 1 : 0.78)
                .overlay {
                    RoundedRectangle(cornerRadius: 14 * size.width / 200)
                        .strokeBorder(selected ? Palette.brass : Color.white.opacity(0.12), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selected ? Palette.brass : Color.white.opacity(0.5))
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
                .shadow(color: selected ? Palette.brass.opacity(0.5) : .clear, radius: 10)
                .scaleEffect(selected ? 1 : 0.97)
                .animation(.easeOut(duration: 0.15), value: selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .accessibilityLabel("\(map.system(contract.a).name) to \(map.system(contract.b).name), \(contract.value) points")
        .accessibilityValue(selected ? "Chosen" : "Not chosen")
    }
}
