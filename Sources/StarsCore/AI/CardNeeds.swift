/// What the hand still lacks for a set of wanted lanes.
public struct CardNeeds: Sendable, Equatable {
    private let values: [Card: Double]

    public init(lanes: [Lane], hand: Hand, hazards: Bool) {
        var values: [Card: Double] = [:]
        for lane in lanes {
            let short = cardsShort(lane, hand: hand, hazards: hazards)
            guard short > 0 else { continue }
            for card in ResourceColor.allCases.map(Card.resource) + [.core] {
                var next = hand
                next.add(card)
                guard cardsShort(lane, hand: next, hazards: hazards) < short else { continue }
                values[card] = max(values[card] ?? 0, 1 / Double(short))
            }
        }
        self.values = values
    }

    /// 0 when the card helps no wanted lane, up to 1 when it completes one. Cores always score above 0
    /// while any wanted lane is unpaid.
    public func value(of card: Card) -> Double { values[card] ?? 0 }
}

/// Cards the hand is short of paying for the lane. Each lane is judged alone against the whole hand.
/// Read off the engine's payment list: with spare Cores added, the first option shows how many
/// Cores the cheapest payment needs.
private func cardsShort(_ lane: Lane, hand: Hand, hazards: Bool) -> Int {
    var padded = hand
    padded.add(.core, lane.length)
    let cores = paymentOptions(for: lane, hand: padded, hazards: hazards)[0].counts[.core] ?? 0
    return max(0, cores - hand.count(.core))
}
