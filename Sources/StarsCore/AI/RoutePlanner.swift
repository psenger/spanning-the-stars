/// The lanes a seat still has to claim to join two systems.
public struct Route: Sendable, Equatable {
    public let toClaim: [Int]   // unowned lane ids on the path, in path order from `from`
    public let cost: Int        // sum of the lengths of toClaim lanes not in `free`
}

/// A map indexed for route searches.
public struct MapGraph: Sendable {
    public let map: GalaxyMap
    private let index: [String: Int]
    private let neighbors: [[(lane: Int, to: Int)]]   // per system, in lane id order

    public init(map: GalaxyMap) {
        self.map = map
        let index = Dictionary(uniqueKeysWithValues: map.systems.enumerated().map { ($1.id, $0) })
        var neighbors = [[(lane: Int, to: Int)]](repeating: [], count: map.systems.count)
        for lane in map.lanes {
            guard let a = index[lane.a], let b = index[lane.b] else { continue }
            neighbors[a].append((lane.id, b))
            neighbors[b].append((lane.id, a))
        }
        self.index = index
        self.neighbors = neighbors
    }

    /// Cheapest way for `seat` to join the two systems. Lanes the seat owns cost 0, lanes in `free`
    /// cost 0, any lane the seat could not claim (taken by a rival, closed, or twin of its own lane)
    /// is blocked. Beacons are ignored. nil when no route exists. Ties: fewer lanes to claim, then
    /// the lower lane ids. A route between already joined systems is Route(toClaim: [], cost: 0).
    public func route(from: String, to: String, seat: Int, laneOwner: [Int: Int], playerCount: Int,
                      free: Set<Int> = []) -> Route? {
        guard let start = index[from], let goal = index[to] else { return nil }
        var best = [Route?](repeating: nil, count: neighbors.count)
        var done = [Bool](repeating: false, count: neighbors.count)
        best[start] = Route(toClaim: [], cost: 0)
        while true {
            var node = -1
            for i in best.indices where !done[i] {
                guard let r = best[i] else { continue }
                if node < 0 || isBetter(r, than: best[node]!) { node = i }
            }
            guard node >= 0, let here = best[node] else { return nil }
            if node == goal { return here }
            done[node] = true
            for (id, other) in neighbors[node] where !done[other] {
                let lane = map.lane(id)
                let next: Route
                if laneOwner[id] == seat {
                    next = here
                } else if claimBlocker(lane, seat: seat, laneOwner: laneOwner, playerCount: playerCount,
                                       beacons: .max, hazards: false) == nil {
                    next = Route(toClaim: here.toClaim + [id],
                                 cost: here.cost + (free.contains(id) ? 0 : lane.length))
                } else {
                    continue
                }
                if best[other].map({ isBetter(next, than: $0) }) ?? true { best[other] = next }
            }
        }
    }

    /// Lower cost, then fewer lanes to claim, then the lower lane ids (compared smallest first).
    private func isBetter(_ a: Route, than b: Route) -> Bool {
        if a.cost != b.cost { return a.cost < b.cost }
        if a.toClaim.count != b.toClaim.count { return a.toClaim.count < b.toClaim.count }
        return a.toClaim.sorted().lexicographicallyPrecedes(b.toClaim.sorted())
    }
}
