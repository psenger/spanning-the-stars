import SwiftUI
import StarsCore

/// The most recent public events, newest first.
struct LogView: View {
    let log: [GameEvent]
    let players: [PlayerState]
    let map: GalaxyMap

    var body: some View {
        let lines = ConcordLog.recent(log, players: players, map: map)
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(text: "Concord Log")
            if lines.isEmpty {
                Text("No moves yet this Charter")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.dimText)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        LogLineView(line: line, newest: i == 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            // Lines fade out at the bottom edge when the panel is short, a hint that the log scrolls.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .black.opacity(0.2), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }
}

private struct LogLineView: View {
    let line: ConcordLog.Line
    let newest: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if let house = line.house {
                    ArtImage(.house(house))
                } else {
                    Image(systemName: line.isEnding ? "flag.checkered" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.brass)
                }
            }
            .frame(width: 18, height: 18)
            Text(line.text)
                .font(.system(size: 12.5, weight: newest ? .medium : .regular))
                .foregroundStyle(newest ? Palette.text : Palette.text.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Turns public `GameEvent`s into themed log lines. Blind draws never name the card.
enum ConcordLog {
    struct Line: Equatable {
        var house: House?
        var text: String
        var isEnding = false
    }

    /// Up to `limit` lines, newest first, merging consecutive Exchange resets and consecutive
    /// blind draws by one House. Walks back from the end, so cost does not grow with the log.
    static func recent(_ log: [GameEvent], players: [PlayerState], map: GalaxyMap, limit: Int = 8) -> [Line] {
        var entries: [(event: GameEvent, count: Int)] = []
        for event in log.reversed() {
            if merges(event), let last = entries.last, last.event == event {
                entries[entries.count - 1].count += 1
                continue
            }
            if entries.count == limit { break }
            entries.append((event, 1))
        }
        return entries.map { line($0.event, count: $0.count, players: players, map: map) }
    }

    /// Repeats of these merge into one line: a run of resets, or both blind draws of a turn.
    private static func merges(_ event: GameEvent) -> Bool {
        switch event {
        case .drewBlind, .exchangeReset: true
        default: false
        }
    }

    private static func line(_ event: GameEvent, count: Int, players: [PlayerState], map: GalaxyMap) -> Line {
        func house(_ seat: Int) -> House? { players.indices.contains(seat) ? players[seat].house : nil }
        func name(_ seat: Int) -> String { house(seat)?.displayName ?? "A House" }

        switch event {
        case .drewBlind(let p):
            let cards = count == 1 ? "a Resource Card" : "\(count) Resource Cards"
            return Line(house: house(p), text: "\(name(p)) requisitioned \(cards)")
        case .exchangeReset:
            return Line(house: nil, text: "The Exchange was refreshed")
        case let .drewExchange(p, card):
            return Line(house: house(p), text: "\(name(p)) took \(card.displayName) from the Exchange")
        case let .claimed(p, laneID, points):
            let lane = map.lane(laneID)
            return Line(house: house(p),
                        text: "\(name(p)) anchored \(map.system(lane.a).name) to \(map.system(lane.b).name) (+\(points))")
        case let .keptContracts(p, n):
            let contracts = n == 1 ? "1 Concord Contract" : "\(n) Concord Contracts"
            return Line(house: house(p), text: "\(name(p)) accepted \(contracts)")
        case .passed(let p):
            return Line(house: house(p), text: "\(name(p)) held position")
        case .finalRoundBegan(let p):
            return Line(house: house(p), text: "\(name(p)) is nearly out of Anchor Beacons: the final round begins")
        case .gameEnded:
            return Line(house: nil, text: "The Charter Era has closed", isEnding: true)
        }
    }
}
