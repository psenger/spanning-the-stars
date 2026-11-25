import SwiftUI
import StarsCore

/// Everything the Final Review shows, computed once when the Charter closes (never per render).
struct FinalReview {
    struct ContractResult {
        let contract: Contract
        let fulfilled: Bool
    }

    let scores: [FinalScore]
    let ranking: [[Int]]
    /// Per seat, each held contract in accepted order with its result.
    let contracts: [[ContractResult]]
    /// The lanes of one longest span for each House that holds the Great Span Award.
    let spanLanes: Set<Int>

    init(state: GameState, map: GalaxyMap) {
        scores = finalScores(state, map: map)
        ranking = StarsCore.ranking(scores)
        let owned = state.players.map { $0.lanes.map(map.lane) }
        contracts = state.players.indices.map { seat in
            state.players[seat].contracts.map { id in
                let c = map.contracts[id]
                return ContractResult(contract: c, fulfilled: isComplete(c, lanes: owned[seat]))
            }
        }
        spanLanes = Set(scores.filter { $0.spanBonus > 0 }.flatMap { greatSpanTrail(lanes: owned[$0.player]).map(\.id) })
    }

    var winners: [Int] { ranking.first ?? [] }

    /// Who won and why, from `ranking`'s tiebreak order: Standing, fulfilled Contracts, Great Span Award.
    static func verdict(_ scores: [FinalScore], ranking: [[Int]], houses: [House]) -> (headline: String, reason: String) {
        guard let top = ranking.first, let first = top.first else { return ("The Charter Era has closed", "") }
        let names = top.map { houses[$0].displayName }
        if top.count > 1 {
            let list = names.dropLast().joined(separator: ", ") + " and " + names.last!
            return ("Shared victory: \(list)",
                    "Tied on Concord Standing, fulfilled Contracts and the Great Span Award.")
        }
        let headline = "\(names[0]) wins the Charter"
        let best = scores[first]
        guard ranking.count > 1, let next = ranking[1].first.map({ scores[$0] }), next.total == best.total else {
            return (headline, "Highest Concord Standing: \(best.total).")
        }
        if best.contractsCompleted != next.contractsCompleted {
            return (headline, "Tied on \(best.total) Standing; wins on fulfilled Contracts, "
                    + "\(best.contractsCompleted) to \(next.contractsCompleted).")
        }
        return (headline, "Tied on \(best.total) Standing and fulfilled Contracts; wins by holding the Great Span Award.")
    }
}

/// The Final Review: each House's lane Standing counts up, its Contracts turn over as fulfilled or
/// not, the Great Span lights up on the map, then the totals and the winner appear.
struct EndGameView: View {
    let state: GameState
    let map: GalaxyMap
    let review: FinalReview
    let onNewCharter: () -> Void
    let onTitle: () -> Void

    /// 0 nothing yet, 1 lane Standing, 2 Contracts, 3 Great Span, 4 totals and winner.
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let verdict = FinalReview.verdict(review.scores, ranking: review.ranking, houses: state.players.map(\.house))
        VStack(spacing: GameLayout.gap) {
            header(verdict)
            HStack(alignment: .top, spacing: GameLayout.gap) {
                ZStack(alignment: .bottomLeading) {
                    StarMapView(map: map, state: state, hazards: state.config.frontierHazards,
                                highlight: step >= 3 ? review.spanLanes : [])
                    if step >= 3 {
                        GreatSpanBadge(holders: review.scores.filter { $0.spanBonus > 0 }.map { state.players[$0.player].house },
                                       length: review.scores.map(\.span).max() ?? 0)
                            .padding(14)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        ForEach(state.players.indices, id: \.self) { seat in
                            ScoreRow(house: state.players[seat].house, map: map, score: review.scores[seat],
                                     contracts: review.contracts[seat], step: step,
                                     winner: step >= 4 && review.winners.contains(seat))
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: EndGameView.boardWidth)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 12) {
                if step < 4 {
                    Button("Show all") { finish() }
                        .buttonStyle(BrassButtonStyle(prominent: false))
                        .accessibilityLabel("Show all")
                }
                Spacer()
                Button("Title screen", action: onTitle)
                    .buttonStyle(BrassButtonStyle(prominent: false))
                    .accessibilityLabel("Title screen")
                Button("New Charter", action: onNewCharter)
                    .buttonStyle(BrassButtonStyle())
                    .accessibilityLabel("New Charter")
            }
        }
        .padding(GameLayout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SpaceBackground().ignoresSafeArea() }
        .task { await play() }
    }

    static let boardWidth: CGFloat = 560

    private func header(_ verdict: (headline: String, reason: String)) -> some View {
        VStack(spacing: 4) {
            Text(step >= 4 ? verdict.headline : "The Final Review")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(step >= 4 ? Palette.brass : Palette.text)
                .contentTransition(.opacity)
            Text(step >= 4 ? verdict.reason : "The Charter Era has closed. The Concord tallies every House.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.dimText)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .panel(padding: 10)
    }

    private func play() async {
        if reduceMotion { step = 4; return }
        for next in 1...4 {
            try? await Task.sleep(for: .seconds(next == 1 ? 0.4 : 1.4))
            if Task.isCancelled || step >= next { continue }
            withAnimation(.easeOut(duration: next == 1 ? 1.2 : 0.5)) { step = next }
        }
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.3)) { step = 4 }
    }
}

private struct ScoreRow: View {
    let house: House
    let map: GalaxyMap
    let score: FinalScore
    let contracts: [FinalReview.ContractResult]
    let step: Int
    let winner: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtImage(.house(house))
                .frame(width: 44, height: 44)
                .shadow(color: Palette.houseRim(house).opacity(0.6), radius: 6)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(house.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    if winner {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(Palette.brass)
                            .accessibilityLabel("Winner")
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    Text("Total")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.dimText)
                    CountUp(value: step >= 4 ? Double(score.total) : 0)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(step >= 4 ? Palette.brass : Palette.dimText.opacity(0.4))
                }
                HStack(spacing: 16) {
                    stat("Lanes") {
                        CountUp(value: step >= 1 ? Double(score.lanePoints) : 0)
                    }
                    stat("Contracts") {
                        Text(step >= 2 ? "+\(score.contractsGained)  \u{2212}\(score.contractsLost)" : "...")
                    }
                    stat("Great Span") {
                        Text(step >= 3 ? "\(score.span)" + (score.spanBonus > 0 ? "  +\(score.spanBonus)" : "") : "...")
                            .foregroundStyle(step >= 3 && score.spanBonus > 0 ? Palette.brass : Palette.text)
                    }
                }
                if !contracts.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(contracts.enumerated()), id: \.offset) { i, result in
                                ContractChip(result: result, map: map, revealed: step >= 2)
                                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.06), value: step >= 2)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .padding(12)
        .background(winner ? Palette.house(house).opacity(0.22) : Palette.hex(0x0A0F24, opacity: 0.84),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(winner ? Palette.brass : Palette.brass.opacity(0.25), lineWidth: winner ? 1.5 : 1))
    }

    private func stat(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Palette.dimText)
            value()
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
        }
    }
}

/// A held contract, face down until the reveal, then marked fulfilled or not.
private struct ContractChip: View {
    let result: FinalReview.ContractResult
    let map: GalaxyMap
    let revealed: Bool

    var body: some View {
        let c = result.contract
        let route = "\(map.system(c.a).name) to \(map.system(c.b).name)"
        let tint = revealed ? (result.fulfilled ? Palette.hex(0x4CC36B) : Palette.hex(0xE0443E)) : Palette.dimText
        HStack(spacing: 4) {
            Image(systemName: revealed ? (result.fulfilled ? "checkmark" : "xmark") : "questionmark")
                .font(.system(size: 10, weight: .bold))
            Text(revealed ? route : "Concord Contract")
                .font(.system(size: 11.5))
                .lineLimit(1)
            Text(revealed ? (result.fulfilled ? "+\(c.value)" : "\u{2212}\(c.value)") : "")
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(revealed ? Palette.text : Palette.dimText)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
        .fixedSize()
        .accessibilityLabel(revealed
            ? "\(route), " + (result.fulfilled ? "fulfilled, plus \(c.value)" : "unfulfilled, minus \(c.value)")
            : "Contract not yet revealed")
    }
}

/// The Great Span Award card beside the map, naming its holders.
private struct GreatSpanBadge: View {
    let holders: [House]
    let length: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ArtImage(.awardGreatSpan)
                .frame(width: 84, height: 126)
                .shadow(color: Palette.brass.opacity(0.6), radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("GREAT SPAN AWARD")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.brass)
                Text(holders.isEmpty ? "No House anchored a lane" : holders.map(\.displayName).joined(separator: ", "))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                if !holders.isEmpty {
                    Text("Longest span: \(length) beacons. +10 Standing")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.dimText)
                }
            }
        }
        .padding(10)
        .background(Palette.hex(0x0B1024, opacity: 0.9), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.brass.opacity(0.5), lineWidth: 1))
    }
}

/// A number that counts up when its value animates.
private struct CountUp: View, Animatable {
    var value: Double
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))").monospacedDigit()
    }
}
