/// True when the contract's two systems are connected using only the given lanes.
public func isComplete(_ contract: Contract, lanes: [Lane]) -> Bool {
    var parent: [String: String] = [:]
    func find(_ x: String) -> String {
        var root = x
        while let p = parent[root], p != root { root = p }
        var cur = x
        while let p = parent[cur], p != root { parent[cur] = root; cur = p }
        return root
    }
    for l in lanes {
        parent[l.a] = parent[l.a] ?? l.a
        parent[l.b] = parent[l.b] ?? l.b
        parent[find(l.a)] = find(l.b)
    }
    guard parent[contract.a] != nil, parent[contract.b] != nil else { return false }
    return find(contract.a) == find(contract.b)
}

/// Longest trail: each lane used once, systems may repeat, length is the sum of lane lengths.
public func greatSpan(lanes: [Lane]) -> Int {
    greatSpanTrail(lanes: lanes).reduce(0) { $0 + $1.length }
}

/// One longest trail, in walking order. Starts are tried in name order, so ties resolve the same way every time.
public func greatSpanTrail(lanes: [Lane]) -> [Lane] {
    var adjacency: [String: [(to: String, edge: Int, length: Int)]] = [:]
    for (i, l) in lanes.enumerated() {
        adjacency[l.a, default: []].append((l.b, i, l.length))
        adjacency[l.b, default: []].append((l.a, i, l.length))
    }
    var used = [Bool](repeating: false, count: lanes.count)
    var path: [Int] = []
    var best = 0
    var bestPath: [Int] = []
    func walk(_ at: String, _ total: Int) {
        if total > best {
            best = total
            bestPath = path
        }
        for step in adjacency[at] ?? [] where !used[step.edge] {
            used[step.edge] = true
            path.append(step.edge)
            walk(step.to, total + step.length)
            path.removeLast()
            used[step.edge] = false
        }
    }
    for start in adjacency.keys.sorted() { walk(start, 0) }
    return bestPath.map { lanes[$0] }
}

public struct FinalScore: Sendable, Equatable {
    public let player: Int
    public let lanePoints: Int
    public let contractsGained: Int
    public let contractsLost: Int
    public let contractsCompleted: Int
    public let span: Int
    public let spanBonus: Int
    public let total: Int
}

/// Lane points are recomputed from owned lanes. Every House tied for the longest span
/// gets 10; if every span is 0, nobody does.
public func finalScores(_ s: GameState, map: GalaxyMap) -> [FinalScore] {
    let owned = s.players.map { p in p.lanes.map { map.lane($0) } }
    let spans = owned.map { greatSpan(lanes: $0) }
    let longest = spans.max() ?? 0
    return s.players.enumerated().map { i, p in
        let points = owned[i].reduce(0) { $0 + lanePoints($1.length) }
        var gained = 0, lost = 0, completed = 0
        for id in p.contracts {
            let c = map.contracts[id]
            if isComplete(c, lanes: owned[i]) { gained += c.value; completed += 1 } else { lost += c.value }
        }
        let bonus = longest > 0 && spans[i] == longest ? 10 : 0
        return FinalScore(player: i, lanePoints: points, contractsGained: gained, contractsLost: lost,
                          contractsCompleted: completed, span: spans[i], spanBonus: bonus,
                          total: points + gained - lost + bonus)
    }
}

/// Groups of player indices, best first. Ties on total fall to contracts completed,
/// then to holding the Great Span award; players still equal share a group.
public func ranking(_ scores: [FinalScore]) -> [[Int]] {
    func key(_ f: FinalScore) -> [Int] { [f.total, f.contractsCompleted, f.spanBonus > 0 ? 1 : 0] }
    var groups: [(key: [Int], players: [Int])] = []
    for f in scores.sorted(by: { key($1).lexicographicallyPrecedes(key($0)) }) {
        if let last = groups.last, last.key == key(f) {
            groups[groups.count - 1].players.append(f.player)
        } else {
            groups.append((key(f), [f.player]))
        }
    }
    return groups.map { $0.players.sorted() }
}
