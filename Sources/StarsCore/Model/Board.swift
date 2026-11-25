public enum Region: String, Codable, Sendable, CaseIterable {
    case coreWorlds, shatteredRim, veilNebula, emberBelt
}

public struct StarSystem: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var region: Region
    public var x: Double
    public var y: Double
}

public enum LaneColor: Hashable, Codable, Sendable {
    case color(ResourceColor)
    case open
}

public enum Hazard: String, Codable, Sendable {
    case none, spectrum, gravityWell
}

public struct Lane: Identifiable, Codable, Sendable {
    public let id: Int
    public var a: String
    public var b: String
    public var length: Int
    public var color: LaneColor
    public var hazard: Hazard
    public var twinID: Int?
}

public struct Contract: Identifiable, Codable, Sendable {
    public let id: Int
    public var a: String
    public var b: String
    public var value: Int
    public var flavor: String
}

public struct GalaxyMap: Sendable {
    public let systems: [StarSystem]
    public let lanes: [Lane]
    public private(set) var contracts: [Contract] = []

    /// Contract value is `d + max(0, d - 12) / 4`, d being the shortest path length.
    public init(systems: [StarSystem], lanes: [Lane],
                contractPairs: [(a: String, b: String, flavor: String)]) {
        self.systems = systems
        self.lanes = lanes
        contracts = contractPairs.enumerated().map { i, p in
            let d = shortestPath(self, p.a, p.b)
            return Contract(id: i, a: p.a, b: p.b, value: d + max(0, d - 12) / 4, flavor: p.flavor)
        }
    }

    public func lane(_ id: Int) -> Lane { lanes[id] }

    public func system(_ id: String) -> StarSystem {
        systems.first { $0.id == id }!
    }
}
