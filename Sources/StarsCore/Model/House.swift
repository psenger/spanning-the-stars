public enum House: String, CaseIterable, Codable, Sendable {
    case varn, solace, meridian, ashkar, paleFleet

    public var displayName: String {
        switch self {
        case .varn: "Varn Industrial"
        case .solace: "The Solace Trust"
        case .meridian: "Meridian Collective"
        case .ashkar: "House Ashkar"
        case .paleFleet: "The Pale Fleet"
        }
    }
}

/// Computer opponent strength, weakest first.
public enum BotLevel: Int, CaseIterable, Codable, Sendable {
    case cadet = 1, pilot, navigator, commander, admiral

    public var displayName: String {
        switch self {
        case .cadet: "Cadet"
        case .pilot: "Pilot"
        case .navigator: "Navigator"
        case .commander: "Commander"
        case .admiral: "Admiral"
        }
    }
}

public enum PlayerKind: Codable, Sendable, Equatable { case human, bot(BotLevel) }

public struct PlayerState: Codable, Sendable, Equatable {
    public let house: House
    public var kind: PlayerKind
    public var hand: Hand
    public var contracts: [Int]
    public var beacons: Int = 45
    public var score: Int = 0
    public var lanes: [Int] = []
}
