public enum ResourceColor: String, CaseIterable, Codable, Sendable {
    case red, purple, black, white, blue, green, yellow, orange

    public var resourceName: String {
        switch self {
        case .red: "Plasma Fuel"
        case .purple: "Crystal Lattice"
        case .black: "Dark-Matter Ballast"
        case .white: "Hull Alloy"
        case .blue: "Coolant Ice"
        case .green: "Bio-Gel"
        case .yellow: "Solar Sails"
        case .orange: "Fusion Ore"
        }
    }
}

public enum Card: Hashable, Codable, Sendable {
    case resource(ResourceColor)
    case core
}

public struct Hand: Codable, Sendable, Equatable {
    public var counts: [Card: Int] = [:]

    public init() {}

    public func count(_ c: Card) -> Int { counts[c, default: 0] }

    public var total: Int { counts.values.reduce(0, +) }

    public mutating func add(_ c: Card, _ n: Int = 1) {
        counts[c, default: 0] += n
    }

    /// Removes the payment cards; leaves the hand unchanged if any are missing.
    public mutating func remove(_ p: Payment) throws(RuleError) {
        for (card, n) in p.counts where count(card) < n { throw .cardsNotInHand }
        for (card, n) in p.counts {
            let left = count(card) - n
            counts[card] = left == 0 ? nil : left
        }
    }
}

public func standardDeck() -> [Card] {
    ResourceColor.allCases.flatMap { Array(repeating: Card.resource($0), count: 12) }
        + Array(repeating: Card.core, count: 14)
}
