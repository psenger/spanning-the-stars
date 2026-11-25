@testable import StarsCore

extension GalaxyMap {
    /// Small fixture map used by rules tests.
    static var tiny: GalaxyMap {
        let systems = ["A", "B", "C", "D", "E", "F"].enumerated().map { i, n in
            StarSystem(id: n, name: n, region: .coreWorlds, x: Double(i), y: 0)
        }
        func lane(_ id: Int, _ a: String, _ b: String, _ len: Int, _ color: LaneColor,
                  _ hazard: Hazard = .none, twin: Int? = nil) -> Lane {
            Lane(id: id, a: a, b: b, length: len, color: color, hazard: hazard, twinID: twin)
        }
        let lanes = [
            lane(0, "A", "B", 2, .color(.red)),
            lane(1, "B", "C", 3, .open),
            lane(2, "C", "D", 1, .color(.blue), twin: 3),
            lane(3, "C", "D", 1, .color(.green), twin: 2),
            lane(4, "D", "E", 3, .color(.purple), .spectrum),
            lane(5, "E", "F", 3, .color(.orange), .gravityWell),
            lane(6, "A", "F", 6, .color(.white)),
            lane(7, "B", "E", 4, .color(.black)),
        ]
        return GalaxyMap(systems: systems, lanes: lanes, contractPairs: [
            (a: "A", b: "C", flavor: "t"), (a: "A", b: "D", flavor: "t"),
            (a: "B", b: "F", flavor: "t"), (a: "A", b: "E", flavor: "t"),
        ])
    }
}

extension GalaxyMap {
    /// Tiny map with 20 extra contracts, enough for setup offers.
    static var big: GalaxyMap {
        let t = GalaxyMap.tiny
        let pairs = (0..<20).map { _ in (a: "A", b: "C", flavor: "t") }
        return GalaxyMap(systems: t.systems, lanes: t.lanes, contractPairs: pairs)
    }
}
