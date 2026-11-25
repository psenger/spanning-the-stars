import Foundation

/// Dijkstra on lane length. Returns `Int.max` when unreachable.
public func shortestPath(_ map: GalaxyMap, _ a: String, _ b: String) -> Int {
    var dist: [String: Int] = [a: 0]
    var done: Set<String> = []
    while let (node, d) = dist.filter({ !done.contains($0.key) }).min(by: { $0.value < $1.value }) {
        if node == b { return d }
        done.insert(node)
        for lane in map.lanes where lane.a == node || lane.b == node {
            let other = lane.a == node ? lane.b : lane.a
            if d + lane.length < dist[other, default: .max] { dist[other] = d + lane.length }
        }
    }
    return .max
}

/// True when segments p1-p2 and q1-q2 properly intersect. Touching at an endpoint does not count.
public func segmentsCross(_ p1: (Double, Double), _ p2: (Double, Double),
                          _ q1: (Double, Double), _ q2: (Double, Double)) -> Bool {
    func orient(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Double {
        (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
    }
    return orient(p1, p2, q1) * orient(p1, p2, q2) < 0 && orient(q1, q2, p1) * orient(q1, q2, p2) < 0
}

/// Distance from point p to the segment a-b.
public func distanceToSegment(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
    let dx = b.0 - a.0, dy = b.1 - a.1
    let len2 = dx * dx + dy * dy
    let t = len2 == 0 ? 0 : max(0, min(1, ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / len2))
    return hypot(p.0 - (a.0 + t * dx), p.1 - (a.1 + t * dy))
}
