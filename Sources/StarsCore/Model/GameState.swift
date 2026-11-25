public struct GameConfig: Codable, Sendable, Equatable {
    public var houses: [House]
    public var frontierHazards: Bool
    public var seed: UInt64
    /// nil = all human; else one per House. Optional so configs saved without it still decode.
    public var kinds: [PlayerKind]?

    public init(houses: [House], frontierHazards: Bool, seed: UInt64, kinds: [PlayerKind]? = nil) {
        self.houses = houses
        self.frontierHazards = frontierHazards
        self.seed = seed
        self.kinds = kinds
    }
}

public enum TurnPhase: Codable, Sendable, Equatable {
    case setupContracts(offered: [Int])
    case awaitingAction
    case drawingSecondCard
    case choosingContracts(offered: [Int])
    case gameOver
}

public struct GameState: Codable, Sendable, Equatable {
    public var config: GameConfig
    public var players: [PlayerState]
    public var current: Int
    public var firstPlayer: Int
    public var phase: TurnPhase
    public var depot: [Card]       // top = last
    public var exchange: [Card?]   // always 5 slots
    public var salvage: [Card]
    public var contractDeck: [Int] // top = last, bottom = index 0
    public var pendingOffers: [[Int]]   // setup offers per seat
    public var setupReturns: [Int]
    public var laneOwner: [Int: Int]  // laneID -> player index
    public var finalTurnsRemaining: Int?   // nil until triggered
    public var consecutivePasses: Int
    public var rng: SeededRNG
    public var log: [GameEvent]
}
