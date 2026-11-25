import Foundation
import Testing
@testable import StarsCore

/// Validator for `GalaxyMap.standard`. Zones match the Art Contract backdrop.
@Suite struct MapTests {
    let map = GalaxyMap.standard

    struct Ellipse {
        let cx, cy, rx, ry: Double
        func contains(_ p: (Double, Double)) -> Bool {
            pow((p.0 - cx) / rx, 2) + pow((p.1 - cy) / ry, 2) < 1
        }
    }

    static let zones: [Region: Ellipse] = [
        .coreWorlds: Ellipse(cx: 250, cy: 320, rx: 170, ry: 150),
        .veilNebula: Ellipse(cx: 780, cy: 150, rx: 190, ry: 120),
        .emberBelt: Ellipse(cx: 780, cy: 480, rx: 190, ry: 120),
    ]
    static let expanseCenter = (520.0, 310.0)
    static let expanseRadius = 110.0

    func pos(_ id: String) -> (Double, Double) {
        let s = map.system(id)
        return (s.x, s.y)
    }

    func distance(_ p: (Double, Double), _ q: (Double, Double)) -> Double {
        hypot(p.0 - q.0, p.1 - q.1)
    }

    func shareEndpoint(_ l: Lane, _ m: Lane) -> Bool {
        l.a == m.a || l.a == m.b || l.b == m.a || l.b == m.b
    }

    func crossesExpanse(_ l: Lane) -> Bool {
        distanceToSegment(Self.expanseCenter, pos(l.a), pos(l.b)) < Self.expanseRadius
    }

    func region(_ id: String) -> Region { map.system(id).region }

    @Test func geometryHelpers() {
        #expect(segmentsCross((0, 0), (10, 10), (0, 10), (10, 0)))
        #expect(!segmentsCross((0, 0), (10, 0), (0, 5), (10, 5)))
        #expect(!segmentsCross((0, 0), (4, 4), (5, 5), (9, 0)))
        #expect(!segmentsCross((0, 0), (10, 0), (10, 0), (10, 10)))
        #expect(distanceToSegment((5, 3), (0, 0), (10, 0)) == 3)
        #expect(distanceToSegment((13, 4), (0, 0), (10, 0)) == 5)
        #expect(distanceToSegment((-3, -4), (0, 0), (10, 0)) == 5)
    }

    @Test func has36SystemsAnd33Contracts() {
        #expect(map.systems.count == 36)
        #expect(Set(map.systems.map(\.id)).count == 36)
        #expect(Set(map.systems.map(\.name)).count == 36)
        let perRegion = Dictionary(grouping: map.systems, by: \.region).mapValues(\.count)
        #expect(perRegion == [.coreWorlds: 9, .shatteredRim: 11, .veilNebula: 8, .emberBelt: 8])
        #expect(map.contracts.count == 33)
    }

    @Test func lanesBetween75And90() {
        #expect((75...90).contains(map.lanes.count))
        #expect(map.lanes.map(\.id) == Array(map.lanes.indices))
        let ids = Set(map.systems.map(\.id))
        for l in map.lanes {
            #expect(ids.contains(l.a) && ids.contains(l.b) && l.a != l.b, "lane \(l.id)")
        }
    }

    @Test func twinPairsBetween10And14() {
        let twins = map.lanes.filter { $0.twinID != nil }
        #expect(twins.count % 2 == 0)
        #expect((10...14).contains(twins.count / 2))
        for l in twins {
            let t = map.lane(l.twinID!)
            #expect(t.id != l.id && t.twinID == l.id, "lane \(l.id)")
            #expect(Set([l.a, l.b]) == Set([t.a, t.b]), "lane \(l.id)")
            #expect(t.length == l.length, "lane \(l.id)")
            #expect(t.color != l.color || l.color == .open, "lane \(l.id) twin colors")
        }
        // Only twins may share both endpoints.
        for (i, l) in map.lanes.enumerated() {
            for m in map.lanes[(i + 1)...] where Set([l.a, l.b]) == Set([m.a, m.b]) {
                #expect(l.twinID == m.id, "lanes \(l.id) and \(m.id) duplicate")
            }
        }
    }

    @Test func lengthsOneToSix() {
        for l in map.lanes { #expect((1...6).contains(l.length), "lane \(l.id)") }
    }

    @Test func graphConnected() {
        var seen: Set<String> = [map.systems[0].id]
        var frontier = [map.systems[0].id]
        while let n = frontier.popLast() {
            for l in map.lanes where l.a == n || l.b == n {
                let o = l.a == n ? l.b : l.a
                if seen.insert(o).inserted { frontier.append(o) }
            }
        }
        #expect(seen.count == map.systems.count)
    }

    @Test func noLanesCross() {
        for (i, l) in map.lanes.enumerated() {
            for m in map.lanes[(i + 1)...] where !shareEndpoint(l, m) {
                #expect(!segmentsCross(pos(l.a), pos(l.b), pos(m.a), pos(m.b)),
                        "lanes \(l.id) and \(m.id) cross")
            }
        }
    }

    @Test func noLanePassesNearSystem() {
        for l in map.lanes {
            for s in map.systems where s.id != l.a && s.id != l.b {
                #expect(distanceToSegment((s.x, s.y), pos(l.a), pos(l.b)) >= 14,
                        "lane \(l.id) passes \(s.id)")
            }
        }
    }

    @Test func systemsAtLeast30Apart() {
        for (i, s) in map.systems.enumerated() {
            for t in map.systems[(i + 1)...] {
                #expect(distance((s.x, s.y), (t.x, t.y)) >= 30, "\(s.id) and \(t.id)")
            }
        }
    }

    @Test func slotSpacingReadable() {
        for l in map.lanes {
            let perSlot = distance(pos(l.a), pos(l.b)) / Double(l.length)
            #expect((18...45).contains(perSlot), "lane \(l.id): \(perSlot)")
        }
    }

    @Test func colorBalance() {
        var slots: [LaneColor: Int] = [:]
        for l in map.lanes { slots[l.color, default: 0] += l.length }
        let total = slots.values.reduce(0, +)
        let colored = ResourceColor.allCases.map { slots[.color($0), default: 0] }
        let mean = Double(colored.reduce(0, +)) / Double(colored.count)
        for (c, n) in zip(ResourceColor.allCases, colored) {
            #expect(abs(Double(n) - mean) <= 0.25 * mean, "\(c): \(n) slots, mean \(mean)")
        }
        let openShare = Double(slots[.open, default: 0]) / Double(total)
        #expect((0.15...0.25).contains(openShare), "open share \(openShare)")
        #expect(total >= 240)
    }

    @Test func systemsInsideTheirZones() {
        for s in map.systems {
            let p = (s.x, s.y)
            #expect((0...1000).contains(s.x) && (0...620).contains(s.y), "\(s.id) off board")
            if let zone = Self.zones[s.region] {
                #expect(zone.contains(p), "\(s.id) outside \(s.region)")
            } else {
                #expect(Self.zones.values.allSatisfy { !$0.contains(p) }, "\(s.id) inside a zone")
                #expect(distance(p, Self.expanseCenter) >= Self.expanseRadius, "\(s.id) in Expanse")
            }
        }
    }

    @Test func silentExpanseEmpty() {
        for s in map.systems {
            #expect(distance((s.x, s.y), Self.expanseCenter) >= Self.expanseRadius, "\(s.id)")
        }
        let crossing = map.lanes.filter(crossesExpanse)
        #expect((3...5).contains(crossing.count), "\(crossing.count) lanes cross the Expanse")
        for l in crossing { #expect([5, 6].contains(l.length), "lane \(l.id)") }
    }

    @Test func hazards() {
        let spectrum = map.lanes.filter { $0.hazard == .spectrum }
        let wells = map.lanes.filter { $0.hazard == .gravityWell }
        #expect(spectrum.count == 6)
        #expect(wells.count == 6)
        for l in spectrum {
            #expect(region(l.a) == .veilNebula || region(l.b) == .veilNebula, "lane \(l.id)")
            #expect((2...4).contains(l.length) && l.twinID == nil, "lane \(l.id)")
        }
        for l in wells {
            #expect(region(l.a) == .emberBelt || region(l.b) == .emberBelt, "lane \(l.id)")
            #expect((2...5).contains(l.length) && l.twinID == nil, "lane \(l.id)")
        }
        for l in spectrum + wells {
            if case .open = l.color { Issue.record("hazard lane \(l.id) needs a color") }
        }
    }

    @Test func contractValues() {
        let ids = Set(map.systems.map(\.id))
        for c in map.contracts {
            #expect((4...22).contains(c.value), "contract \(c.id): \(c.value)")
            #expect(ids.contains(c.a) && ids.contains(c.b) && c.a != c.b, "contract \(c.id)")
            #expect(!c.flavor.isEmpty && !c.flavor.contains("\u{2014}"), "contract \(c.id)")
        }
        #expect(map.contracts.filter { $0.value >= 17 }.count >= 5)
        #expect(Set(map.contracts.map { Set([$0.a, $0.b]) }).count == map.contracts.count)
    }

    @Test func rulesCopyMatchesDocs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let docs = try String(contentsOf: root.appendingPathComponent("docs/RULES.md"), encoding: .utf8)
        let copy = try String(contentsOf: root.appendingPathComponent("Sources/SpanningTheStars/Resources/RULES.md"),
                              encoding: .utf8)
        #expect(docs == copy)
    }
}
