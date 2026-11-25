public struct Payment: Hashable, Codable, Sendable {
    public var counts: [Card: Int]

    /// Zero entries are dropped.
    public init(_ counts: [Card: Int]) {
        self.counts = counts.filter { $0.value != 0 }
    }

    public var total: Int { counts.values.reduce(0, +) }
}

public enum Action: Hashable, Codable, Sendable {
    case drawBlind
    case drawExchange(slot: Int)
    case claim(laneID: Int, payment: Payment)
    case drawContracts
    case keepContracts([Int])
    case pass
}

public enum RuleError: Error, Equatable {
    case wrongPhase, slotEmpty, coreMustBeFirst, noCardsToDraw, laneTaken, laneClosed
    case ownsTwin, notEnoughBeacons, invalidPayment, cardsNotInHand, contractDeckEmpty
    case mustKeepAtLeast(Int)
    case notOffered, passNotAllowed, gameOver
}

public enum GameEvent: Codable, Sendable, Equatable {
    case drewBlind(player: Int)
    case drewExchange(player: Int, card: Card)
    case exchangeReset
    case claimed(player: Int, laneID: Int, points: Int)
    case keptContracts(player: Int, count: Int)
    case passed(player: Int)
    case finalRoundBegan(trigger: Int)
    case gameEnded
}
