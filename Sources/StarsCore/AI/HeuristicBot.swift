import Foundation

/// Weights of the action scores, in Standing points. Later tasks add fields.
public struct BotWeights: Sendable, Equatable {
    public var pointsNow = 1.0     // per Standing point scored by a claim
    public var draw = 1.0          // base score of a card draw
    public var newContracts = -2.0 // base score of drawContracts
    public var wantedClaim = 6.0   // added to a claim on a planned route
    public var offPlanPenalty = 4.0 // taken off a claim on no planned route
    public var cardNeed = 3.0      // per unit of CardNeeds value of a drawn card
    public var keepCostWeight = 0.5 // per route length a kept Contract still has to claim
    public var planProgress = 1.5  // per Contract point a wanted claim brings nearer
    public var urgency = 0.5       // per lane length of detour if a wanted lane were lost
    public var coreValue = 4.0     // a face-up Core while a wanted lane is unpaid
    public var claimNowBonus = 2.0 // least lead of a payable wanted claim over every draw
    public var contractBeaconFloor = 15 // fewest beacons at which new Contracts are drawn
    public var endgameBeacons = 8  // endgame mode starts when a seat has this many beacons or fewer
    public var endgamePointsBoost = 1.5 // multiplies claim points in endgame mode
    public var block = 0.6         // per Standing point a claim is expected to deny rivals
    public var span = 0.5          // per lane length a claim adds to a Great Span in reach
    public var spanReach = 6       // span growth counts from this far behind the longest rival span
    public var closeOut = 5.0      // added to the claim that starts the final round from a safe lead
    public var closeOutLead = 10   // least projected lead over every rival's score to close out
    public var blockCrowdScale = 0.0 // multiplies block with 3 or more Houses; tuned, see docs/ai-results.md
    public var holdBackMargin = 8.0 // a final-round claim from behind waits for an action this close; tuned
}

/// What one level may use and how carelessly it plays.
public struct BotSettings: Sendable, Equatable {
    public var usesPlanner: Bool
    public var usesScorer: Bool
    public var usesOpponentModel: Bool
    public var temperature: Double   // softmax temperature, in Standing points
    public var mistakeRate: Double
    public var playouts: Int         // 0 = no search
    public var weights: BotWeights

    /// Admiral ranks actions as a Commander that makes no mistakes; `playouts` is its search budget.
    public static func level(_ level: BotLevel) -> BotSettings {
        if level == .navigator || level == .commander || level == .admiral {
            var weights = BotWeights()
            // Commander and Admiral put a higher cost on the route work an offered Contract needs.
            weights.keepCostWeight = level == .navigator ? 1.2 : 1.5
            if level != .navigator {
                weights.block = 2.0   // tuned, see docs/ai-results.md
                if level == .admiral {
                    return BotSettings(usesPlanner: true, usesScorer: true, usesOpponentModel: true,
                                       temperature: 0, mistakeRate: 0, playouts: 48, weights: weights)
                }
                return BotSettings(usesPlanner: true, usesScorer: true, usesOpponentModel: true,
                                   temperature: 0.05, mistakeRate: 0.02, playouts: 0, weights: weights)
            }
            return BotSettings(usesPlanner: true, usesScorer: true, usesOpponentModel: false,
                               temperature: 0.15, mistakeRate: 0.05, playouts: 0, weights: weights)
        }
        if level == .pilot {
            return BotSettings(usesPlanner: true, usesScorer: false, usesOpponentModel: false,
                               temperature: 1.0, mistakeRate: 0.15, playouts: 0, weights: BotWeights())
        }
        return BotSettings(usesPlanner: false, usesScorer: false, usesOpponentModel: false,
                           temperature: 2.0, mistakeRate: 0, playouts: 0, weights: BotWeights())
    }
}

/// An unfulfilled Contract of the seat and the route that would complete it; nil when none exists.
struct Goal: Equatable {
    let contractID: Int
    let value: Int
    let route: Route?
}

/// Share of a blind draw's card need: the chance the unseen card is one the hand wants.
private let blindShare = 0.3
/// Taken off a claim for each step down the engine's payment list for its lane (Pilot) or for
/// each Core in its payment (Navigator).
private let paymentStep = 1.0
/// Navigator's score for drawContracts once nothing is left to work for.
private let contractsWanted = 3.0
/// The most a lost lane's detour counts for; a Contract left with no route counts as this.
private let detourCap = 10

/// Scores every legal action, then picks one by softmax. Cadet scores points only; with the
/// planner on (Pilot) claims and draws follow the routes of the seat's Contracts; with the scorer
/// on too (Navigator) the routes share lanes and claims are weighed by progress and urgency; with
/// the opponent model on as well (Commander) claims also block rivals, grow the Great Span and
/// close out a game that is won, and the game is not ended from behind.
public struct HeuristicBot: Bot {
    private let settings: BotSettings
    private let graph: MapGraph
    private let model: OpponentModel?   // Commander only
    private var map: GalaxyMap { graph.map }

    public init(settings: BotSettings, map: GalaxyMap) {
        self.settings = settings
        graph = MapGraph(map: map)
        model = settings.usesOpponentModel ? OpponentModel(graph: graph) : nil
    }

    public func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action {
        var goals = settings.usesPlanner ? goals(view: view) : []
        // A mistake: one Contract is forgotten for this decision.
        var forgot = false
        if !goals.isEmpty, settings.mistakeRate > 0, Double.random(in: 0..<1, using: &rng) < settings.mistakeRate {
            goals.remove(at: Int.random(in: goals.indices, using: &rng))
            forgot = true
        }
        return softmaxPick(scoredActions(view: view, goals: goals, forgot: forgot),
                           temperature: settings.temperature, rng: &rng)
    }

    /// Every legal action with its score, best first; ties broken by position in view.legalActions.
    /// No mistakes are applied.
    public func scoredActions(view: PlayerView) -> [(action: Action, score: Double)] {
        scoredActions(view: view, goals: settings.usesPlanner ? goals(view: view) : [])
    }

    /// The seat's unfulfilled Contracts, in hand order, each with its own route. With the scorer on
    /// the routes are a joint plan: the dearest Contract is planned first and each later route
    /// rides free on the lanes already wanted. A Contract with no route is abandoned.
    func goals(view: PlayerView) -> [Goal] {
        let owned = view.seats[view.seat].lanes.map(map.lane)
        let open = view.contracts.map { map.contracts[$0] }.filter { !isComplete($0, lanes: owned) }
        guard settings.usesScorer else {
            return open.map { Goal(contractID: $0.id, value: $0.value, route: route(for: $0, view: view)) }
        }
        var routes = [Route?](repeating: nil, count: open.count)
        var free: Set<Int> = []
        for i in open.indices.sorted(by: { (open[$1].value, $0) < (open[$0].value, $1) }) {
            routes[i] = route(for: open[i], view: view, free: free)
            free.formUnion(routes[i]?.toClaim ?? [])
        }
        return zip(open, routes).map { Goal(contractID: $0.id, value: $0.value, route: $1) }
    }

    private func route(for contract: Contract, view: PlayerView, free: Set<Int> = []) -> Route? {
        graph.route(from: contract.a, to: contract.b, seat: view.seat, laneOwner: view.laneOwner,
                    playerCount: view.seats.count, free: free)
    }

    /// `forgot`: a mistake dropped a goal, so the goals do not show every Contract still open.
    private func scoredActions(view: PlayerView, goals: [Goal], forgot: Bool = false) -> [(action: Action, score: Double)] {
        let scores = !settings.usesPlanner ? view.legalActions.map(score)
            : settings.usesScorer ? scorerScores(view: view, goals: goals, forgot: forgot)
            : plannedScores(view: view, goals: goals)
        return zip(view.legalActions, scores).enumerated()
            .map { (index: $0.offset, action: $0.element.0, score: $0.element.1) }
            .sorted { ($1.score, $0.index) < ($0.score, $1.index) }
            .map { (action: $0.action, score: $0.score) }
    }

    private func score(_ action: Action) -> Double {
        let w = settings.weights
        switch action {
        case let .claim(laneID, _): return w.pointsNow * Double(lanePoints(map.lane(laneID).length))
        case .drawBlind, .drawExchange: return w.draw
        case .drawContracts: return w.newContracts
        case let .keepContracts(ids): return -Double(ids.count)
        case .pass: return 0
        }
    }

    /// Scores in view.legalActions order, planner on.
    private func plannedScores(view: PlayerView, goals: [Goal]) -> [Double] {
        let w = settings.weights
        let wanted = Set(goals.flatMap { $0.route?.toClaim ?? [] })
        let needs = CardNeeds(lanes: wanted.sorted().map(map.lane), hand: view.hand, hazards: view.hazards)

        let keepScore = keepScores(view: view)

        // The engine lists a lane's payments together, fewest Cores first.
        var lastLane: Int?, step = 0
        return view.legalActions.map { action in
            switch action {
            case let .claim(laneID, _):
                step = laneID == lastLane ? step + 1 : 0
                lastLane = laneID
                let points = w.pointsNow * Double(lanePoints(map.lane(laneID).length))
                return points + (wanted.contains(laneID) ? w.wantedClaim : -w.offPlanPenalty)
                    - paymentStep * Double(step)
            case .drawBlind: return w.draw + w.cardNeed * blindShare
            case let .drawExchange(slot):
                return w.draw + w.cardNeed * (view.exchange[slot].map(needs.value) ?? 0)
            case .drawContracts: return w.newContracts
            // Equal sums need a Contract scoring 0, so the first best subset is also a smallest one.
            case let .keepContracts(ids): return ids.reduce(0) { $0 + (keepScore[$1] ?? 0) }
            case .pass: return 0
            }
        }
    }

    /// What keeping each offered Contract is worth: its value less the work left, or its loss.
    /// Lanes in `free` are no work. Empty outside the two keep phases.
    private func keepScores(view: PlayerView, free: Set<Int> = []) -> [Int: Double] {
        var keepScore: [Int: Double] = [:]
        switch view.phase {
        case let .setupContracts(offered), let .choosingContracts(offered):
            for id in offered {
                let contract = map.contracts[id]
                keepScore[id] = route(for: contract, view: view, free: free)
                    .map { Double(contract.value) - settings.weights.keepCostWeight * Double($0.cost) }
                    ?? -Double(contract.value)
            }
        default: break
        }
        return keepScore
    }

    // MARK: Navigator

    /// Scores in view.legalActions order, planner and scorer on. `goals` is the joint plan.
    private func scorerScores(view: PlayerView, goals: [Goal], forgot: Bool) -> [Double] {
        let w = settings.weights
        let wanted = Set(goals.flatMap { $0.route?.toClaim ?? [] })
        var endgame = view.finalTurnsRemaining != nil || view.seats.contains { $0.beacons <= w.endgameBeacons }
        // Commander's terms are worked out only when there is a lane to claim. It is also in endgame
        // mode when its longest payable lane would start the final round.
        var commanderTerms: ((Int) -> (terms: Double, heldBack: Bool))?
        if let model {
            let longest = view.legalActions.map { action -> Int in
                if case let .claim(id, _) = action { beaconCost(map.lane(id), hazards: view.hazards) } else { 0 }
            }.max() ?? 0
            if longest > 0 {
                endgame = endgame || view.seats[view.seat].beacons - longest <= 2
                commanderTerms = self.commanderTerms(view: view, model: model)
            }
        }
        let keepScore = keepScores(view: view, free: wanted)

        // The goals each wanted lane serves. An unclaimed twin joins the same systems, so it serves
        // them too. Each twin has one partner, so the set's order cannot change the result.
        var users: [Int: [Goal]] = [:]
        for goal in goals {
            for id in goal.route?.toClaim ?? [] { users[id, default: []].append(goal) }
        }
        for id in wanted {
            if let twin = map.lane(id).twinID, !wanted.contains(twin), view.laneOwner[twin] == nil {
                users[twin] = users[id]
            }
        }

        // Draws first: a payable wanted claim is held above the best of them.
        let canDraw = view.legalActions.contains {
            switch $0 {
            case .drawBlind, .drawExchange: true
            default: false
            }
        }
        let needs = canDraw && !endgame
            ? CardNeeds(lanes: needLanes(wanted: wanted, view: view), hand: view.hand, hazards: view.hazards) : nil
        var bestDraw: Double?
        var scores = view.legalActions.map { action -> Double in
            let score: Double
            switch action {
            // No unseen card is wanted once nothing is.
            case .drawBlind: score = w.draw + (endgame || wanted.isEmpty ? 0 : w.cardNeed * blindShare)
            case let .drawExchange(slot):
                let card = view.exchange[slot], need = card.flatMap { needs?.value(of: $0) } ?? 0
                score = card == .core && need > 0 ? w.coreValue : w.draw + w.cardNeed * need
            case .drawContracts:
                if endgame { return -100 }
                let done = !forgot && goals.allSatisfy { $0.route == nil }
                return done && view.seats[view.seat].beacons >= w.contractBeaconFloor ? contractsWanted : w.newContracts
            case let .keepContracts(ids): return ids.reduce(0) { $0 + (keepScore[$1] ?? 0) }
            case .claim, .pass: return 0
            }
            bestDraw = max(bestDraw ?? score, score)
            return score
        }

        // In endgame mode Cores are nearly free: they only order a lane's payments.
        let coreStep = (endgame ? 0.1 : 1) * paymentStep
        var fewestCores: [Int: Int] = [:]
        for case let .claim(id, payment) in view.legalActions {
            fewestCores[id] = min(fewestCores[id] ?? .max, payment.counts[.core] ?? 0)
        }
        var laneScore: [Int: Double] = [:]   // the score of a lane's payment with the fewest Cores
        var heldBack: Set<Int> = []          // lanes whose claim would start the final round from behind
        for (i, action) in view.legalActions.enumerated() {
            guard case let .claim(id, payment) = action else { continue }
            let fewest = fewestCores[id]!
            var best = laneScore[id] ?? claimScore(id, users: users[id], wanted: wanted, endgame: endgame, view: view)
                - coreStep * Double(fewest)
            // A payable wanted lane leads every draw; further Cores order its payments below that.
            if let bestDraw, !endgame, users[id] != nil { best = max(best, bestDraw + w.claimNowBonus) }
            if laneScore[id] == nil, let commanderTerms {
                let commander = commanderTerms(id)
                best += commander.terms
                if commander.heldBack { heldBack.insert(id) }
            }
            laneScore[id] = best
            scores[i] = best - coreStep * Double((payment.counts[.core] ?? 0) - fewest)
        }
        guard !heldBack.isEmpty else { return scores }

        // Hold back: a held claim is put holdBackMargin under the best other action when that
        // action is already within the margin of it.
        func isHeld(_ action: Action) -> Bool {
            if case let .claim(id, _) = action { heldBack.contains(id) } else { false }
        }
        let others = zip(view.legalActions, scores).filter { !isHeld($0.0) }.map(\.1)
        guard let bestOther = others.max() else { return scores }
        for (i, action) in view.legalActions.enumerated()
        where isHeld(action) && bestOther >= scores[i] - w.holdBackMargin {
            scores[i] = min(scores[i], bestOther - w.holdBackMargin)
        }
        return scores
    }

    /// One lane's claim score. `users` are the goals the lane serves, nil for a lane off the plan.
    private func claimScore(_ id: Int, users: [Goal]?, wanted: Set<Int>, endgame: Bool, view: PlayerView) -> Double {
        let w = settings.weights
        let lane = map.lane(id), points = w.pointsNow * Double(lanePoints(lane.length))
        var progress = 0.0, detour = 0
        for goal in users ?? [] {
            guard let route = goal.route else { continue }
            let left = length(route)
            // Endgame mode counts only a claim that completes the Contract this turn.
            if endgame && route.toClaim.count > 1 { continue }
            progress += Double(goal.value * lane.length) / Double(left)
            if !endgame { detour = max(detour, self.detour(goal, left: left, losing: id, wanted: wanted, view: view)) }
        }
        if endgame { return points * w.endgamePointsBoost + w.planProgress * progress }
        guard users != nil else { return points - w.offPlanPenalty }
        return points + w.planProgress * progress + w.urgency * Double(detour)
    }

    /// Rise in the lane length the goal still has to claim if a rival took lane `id`, 0 to detourCap.
    private func detour(_ goal: Goal, left: Int, losing id: Int, wanted: Set<Int>, view: PlayerView) -> Int {
        let contract = map.contracts[goal.contractID]
        var owner = view.laneOwner
        owner[id] = (view.seat + 1) % view.seats.count
        guard let other = graph.route(from: contract.a, to: contract.b, seat: view.seat, laneOwner: owner,
                                      playerCount: view.seats.count, free: wanted.subtracting([id])) else {
            return detourCap
        }
        return min(detourCap, max(0, length(other) - left))
    }

    // MARK: Commander

    /// What Commander adds to a lane's claim score, never below 0: blocking, Great Span growth and
    /// closing out. `heldBack` marks the claim that would start the final round while the projected
    /// final total is behind the best rival's score. Rival guesses and spans are worked out here,
    /// once per decision.
    private func commanderTerms(view: PlayerView, model: OpponentModel) -> (Int) -> (terms: Double, heldBack: Bool) {
        let w = settings.weights, me = view.seats[view.seat]
        // With 3 or more Houses a turn spent denying one rival helps the others.
        let block = w.block * (view.seats.count >= 3 ? w.blockCrowdScale : 1)
        let rivals = view.seats.indices.filter { $0 != view.seat }
        // A rival with no lanes gives a flat guess, which says nothing.
        let targets = model.blockTargets(of: rivals.filter { !view.seats[$0].lanes.isEmpty }, view: view)
        let owned = me.lanes.map(map.lane)
        let spanBefore = greatSpan(lanes: owned)
        let reached = Set(owned.flatMap { [$0.a, $0.b] })
        let rivalSpan = rivals.map { greatSpan(lanes: view.seats[$0].lanes.map(map.lane)) }.max() ?? 0
        let rivalScore = rivals.map { view.seats[$0].score }.max() ?? 0
        return { id in
            let lane = map.lane(id), after = owned + [lane]
            // A lane apart from the seat's network is a trail of its own; the search is not needed.
            let spanAfter = reached.contains(lane.a) || reached.contains(lane.b)
                ? greatSpan(lanes: after) : max(spanBefore, lane.length)
            var heldBack = false
            var terms = block * model.blockValue(laneID: id, view: view, targets: targets)
                + w.span * Double(max(0, spanAfter - max(spanBefore, rivalSpan - w.spanReach)))
            // The claim that starts the final round, when the projected final total leads every rival.
            if view.finalTurnsRemaining == nil, me.beacons - beaconCost(lane, hazards: view.hazards) <= 2 {
                var total = me.score + lanePoints(lane.length) + (spanAfter >= rivalSpan ? 10 : 0)
                for id in view.contracts {
                    let contract = map.contracts[id]
                    total += isComplete(contract, lanes: after) ? contract.value : -contract.value
                }
                if total - rivalScore >= w.closeOutLead { terms += w.closeOut }
                heldBack = total < rivalScore
            }
            return (terms, heldBack)
        }
    }

    /// Lane length of the whole route, lanes shared with other goals included.
    private func length(_ route: Route) -> Int {
        route.toClaim.reduce(0) { $0 + map.lane($1).length }
    }

    /// The wanted lanes card needs are judged on. Either lane of an unclaimed twin pair will do:
    /// both count while neither is paid, and neither once one is.
    private func needLanes(wanted: Set<Int>, view: PlayerView) -> [Lane] {
        wanted.sorted().flatMap { id -> [Lane] in
            let lane = map.lane(id)
            guard let twinID = lane.twinID, view.laneOwner[twinID] == nil else { return [lane] }
            let pair = [lane, map.lane(twinID)]
            let paid = pair.contains { !paymentOptions(for: $0, hand: view.hand, hazards: view.hazards).isEmpty }
            return paid ? [] : pair
        }
    }
}

/// Picks by softmax over scores; temperature 0 picks the first best.
func softmaxPick(_ scored: [(action: Action, score: Double)], temperature: Double, rng: inout SeededRNG) -> Action {
    let best = scored.map(\.score).max()!
    guard temperature > 0 else { return scored.first { $0.score == best }!.action }
    let weights = scored.map { exp(($0.score - best) / temperature) }
    var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
    for (entry, weight) in zip(scored, weights) {
        if roll < weight { return entry.action }
        roll -= weight
    }
    return scored[scored.count - 1].action   // rounding left the roll past the last weight
}
