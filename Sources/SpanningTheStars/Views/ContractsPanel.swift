import SwiftUI
import StarsCore

/// The active House's Concord Contracts. A check marks each one its anchored lanes already connect.
struct ContractsPanel: View {
    let player: PlayerState
    let map: GalaxyMap
    var hidden = false
    @Binding var hoveredContract: Int?

    var body: some View {
        let rows = ContractsPanel.rows(player, map: map)
        let done = rows.filter(\.complete).count
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(text: "Concord Contracts",
                       detail: hidden ? nil : "\(done) of \(rows.count) fulfilled")
            if hidden {
                note("Hidden until the House at the console reveals its hand")
            } else if rows.isEmpty {
                note("No Concord Contracts held")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(rows, id: \.contract.id) { row in
                            let id = row.contract.id
                        ContractRow(row: row, map: map)
                            .onHover { inside in
                                if inside { hoveredContract = id }
                                else if hoveredContract == id { hoveredContract = nil }
                            }
                            .onDisappear {
                                if hoveredContract == id { hoveredContract = nil }
                            }
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.visible)
                // Rows fade out at the bottom edge, a hint that the list scrolls.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .black.opacity(0.25), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.dimText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    struct Row {
        let contract: Contract
        let complete: Bool
    }

    /// Held contracts in the order they were accepted, each checked against the House's lanes.
    static func rows(_ player: PlayerState, map: GalaxyMap) -> [Row] {
        let owned = player.lanes.map(map.lane)
        return player.contracts.map { id in
            let c = map.contracts[id]
            return Row(contract: c, complete: isComplete(c, lanes: owned))
        }
    }
}

private struct ContractRow: View {
    let row: ContractsPanel.Row
    let map: GalaxyMap

    var body: some View {
        let c = row.contract
        HStack(spacing: 8) {
            Image(systemName: row.complete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.complete ? Palette.hex(0x4CC36B) : Palette.dimText.opacity(0.6))
            Text("\(map.system(c.a).name) to \(map.system(c.b).name)")
                .font(.system(size: 12.5, weight: row.complete ? .regular : .medium))
                .foregroundStyle(row.complete ? Palette.text.opacity(0.75) : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Text("\(c.value)")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.brass)
                .frame(minWidth: 26)
                .padding(.vertical, 1)
                .background(Palette.brass.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(row.complete ? Palette.hex(0x4CC36B, opacity: 0.08) : Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .help("Connect \(map.system(c.a).name) to \(map.system(c.b).name) with your own lanes. "
              + "Gain \(c.value) Standing if fulfilled or lose \(c.value) if unfulfilled.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(map.system(c.a).name) to \(map.system(c.b).name), \(c.value) points, "
                            + (row.complete ? "fulfilled" : "not yet fulfilled"))
    }
}
