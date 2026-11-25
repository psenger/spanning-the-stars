import SwiftUI
import StarsCore

#if DEBUG

/// Seeded mid-game states for the debug routes `-game` and `-game2`, reached by playing real engine
/// actions with a simple policy: one focus House builds up its hand and contracts while anchoring
/// lanes toward them, and its rivals anchor whatever they can afford.
enum DebugGames {
    struct Recipe {
        var houses: Int
        var hazards: Bool
        var seed: UInt64
        /// The House whose turn the state stops on.
        var focus: Int
        var handTarget: Int
        var contractTarget: Int
        var focusLanes: Int
        /// Rivals stop anchoring below this many beacons, so the final round does not begin.
        var rivalBeaconFloor: Int
    }

    /// Review Focus 5: 5 Houses, hazards on, House Ashkar holding 45+ cards and 12 contracts.
    static let bigHands = Recipe(houses: 5, hazards: true, seed: 6, focus: 3, handTarget: 45,
                                 contractTarget: 12, focusLanes: 4, rivalBeaconFloor: 10)
    /// An ordinary 2-House game, hazards off, a few rounds in.
    static let twoHouses = Recipe(houses: 2, hazards: false, seed: 22, focus: 0, handTarget: 9,
                                  contractTarget: 3, focusLanes: 5, rivalBeaconFloor: 30)

    /// Route `-end`: a 3-House game with hazards, played to the Final Review. Varn chases its
    /// contracts; the rivals anchor the longest lane they can until their beacons run out.
    static let finished = Recipe(houses: 3, hazards: true, seed: 5, focus: 0, handTarget: .max,
                                 contractTarget: 4, focusLanes: .max, rivalBeaconFloor: 0)

    @MainActor static func session(_ recipe: Recipe) -> GameSession {
        let slots = InMemorySaveSlots()
        let saved = try? slots.write(name: "Debug", state: state(recipe))
        // The save was just written, so it loads.
        let session = try! GameSession.load(id: saved!.id, store: InMemoryGameStore(), saves: slots)
        session.reveal()
        return session
    }

    static func state(_ r: Recipe) -> GameState {
        let engine = GameEngine(map: .standard)
        let houses = Array(House.allCases.prefix(r.houses))
        var s = engine.newGame(GameConfig(houses: houses, frontierHazards: r.hazards, seed: r.seed))
        for _ in 0..<4000 {
            if s.current == r.focus, s.phase == .awaitingAction, ready(s, r) { break }
            guard let action = choose(s, r, engine: engine),
                  (try? engine.apply(action, to: &s)) != nil else { break }
        }
        return s
    }

    private static func ready(_ s: GameState, _ r: Recipe) -> Bool {
        let p = s.players[r.focus]
        return p.hand.total >= r.handTarget && p.contracts.count >= r.contractTarget && p.lanes.count >= r.focusLanes
    }

    private static func choose(_ s: GameState, _ r: Recipe, engine: GameEngine) -> Action? {
        let legal = engine.legalActions(s)
        let me = s.players[s.current]
        let isFocus = s.current == r.focus
        switch s.phase {
        case .setupContracts(let offered):
            return .keepContracts(Array(offered.prefix(isFocus ? max(2, min(3, r.contractTarget)) : 2)))
        case .choosingContracts(let offered):
            let want = isFocus ? max(1, min(offered.count, r.contractTarget - me.contracts.count)) : 1
            return .keepContracts(Array(offered.prefix(want)))
        case .drawingSecondCard:
            return draw(legal)
        case .awaitingAction:
            let claims = legal.compactMap { a -> (lane: Lane, payment: Payment)? in
                if case let .claim(id, p) = a { return (engine.map.lane(id), p) }
                return nil
            }
            if isFocus {
                if me.contracts.count < r.contractTarget, legal.contains(.drawContracts) { return .drawContracts }
                if me.lanes.count < r.focusLanes {
                    let wanted = wantedLanes(me, in: s, map: engine.map)
                    if let c = cheapest(claims.filter { wanted.contains($0.lane.id) }) { return c }
                }
            } else if let c = cheapest(claims.filter {
                me.beacons - beaconCost($0.lane, hazards: s.config.frontierHazards) >= r.rivalBeaconFloor
            }) {
                return c
            } else if me.contracts.count < 5, legal.contains(.drawContracts) {
                // Rivals take contracts instead of cards now and then, so the Supply Depot lasts.
                return .drawContracts
            }
            return draw(legal) ?? legal.first
        default:
            return nil
        }
    }

    /// Blind first, then any face-up card that is not a Quantum Core.
    private static func draw(_ legal: [Action]) -> Action? {
        legal.first { $0 == .drawBlind } ?? legal.first {
            if case .drawExchange = $0 { return true }
            return false
        }
    }

    /// The longest lane on offer, paid with the fewest Quantum Cores.
    private static func cheapest(_ claims: [(lane: Lane, payment: Payment)]) -> Action? {
        let best = claims.max {
            ($0.lane.length, -$0.payment.counts[.core, default: 0])
                < ($1.lane.length, -$1.payment.counts[.core, default: 0])
        }
        return best.map { .claim(laneID: $0.lane.id, payment: $0.payment) }
    }

    /// The open lanes on a shortest path for the player's cheapest contract that rivals have not cut.
    private static func wantedLanes(_ p: PlayerState, in s: GameState, map: GalaxyMap) -> Set<Int> {
        let owned = p.lanes.map(map.lane)
        let contracts = p.contracts.map { map.contracts[$0] }
            .filter { !isComplete($0, lanes: owned) }
            .sorted { ($0.value, $0.id) < ($1.value, $1.id) }
        for c in contracts {
            let path = shortestLanes(c.a, c.b, map: map)
            if path.allSatisfy({ s.laneOwner[$0] == nil || p.lanes.contains($0) }) {
                return Set(path).subtracting(p.lanes)
            }
        }
        return []
    }

    private static func shortestLanes(_ from: String, _ to: String, map: GalaxyMap) -> [Int] {
        var dist: [String: Int] = [from: 0]
        var via: [String: Lane] = [:]
        var open: Set<String> = [from]
        // Ties break by id: Set order changes between launches.
        while let at = open.min(by: { (dist[$0]!, $0) < (dist[$1]!, $1) }) {
            open.remove(at)
            if at == to { break }
            for lane in map.lanes where lane.a == at || lane.b == at {
                let next = lane.a == at ? lane.b : lane.a
                let d = dist[at]! + lane.length
                if d < dist[next, default: .max] {
                    dist[next] = d
                    via[next] = lane
                    open.insert(next)
                }
            }
        }
        var path: [Int] = []
        var cur = to
        while let lane = via[cur] {
            path.append(lane.id)
            cur = lane.a == cur ? lane.b : lane.a
        }
        return path
    }
}

/// Launch arguments that open a debug screen instead of the title.
enum DebugRoute {
    case game(DebugGames.Recipe), gallery, map

    static var current: DebugRoute? {
        let args = CommandLine.arguments
        if args.contains("-game") { return .game(DebugGames.bigHands) }
        if args.contains("-game2") { return .game(DebugGames.twoHouses) }
        if args.contains("-end") { return .game(DebugGames.finished) }
        if args.contains("-gallery") { return .gallery }
        if args.contains("-map") { return .map }
        return nil
    }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .game(let recipe): DebugGameHost(recipe: recipe)
        case .gallery: CardGalleryView().background { SpaceBackground().ignoresSafeArea() }
        case .map: StarMapDebugView().background { SpaceBackground().ignoresSafeArea() }
        }
    }
}

/// Hosts a debug game session on the game screen.
struct DebugGameHost: View {
    let recipe: DebugGames.Recipe
    @State private var session: GameSession?

    var body: some View {
        ZStack {
            if let session { GameView(session: session) } else { Color.clear }
        }
        .onAppear {
            if session == nil { session = DebugGames.session(recipe) }
        }
    }
}
#endif
