/// Draws the top depot card, reshuffling salvage into the depot when it runs dry.
func drawFromDepot(_ s: inout GameState) -> Card? {
    if s.depot.isEmpty, !s.salvage.isEmpty {
        s.depot = s.salvage
        s.salvage = []
        s.depot.shuffle(using: &s.rng)
    }
    return s.depot.popLast()
}

/// Fills empty Exchange slots, then resets the Exchange while it holds 3+ Cores
/// (Rules Section 10). A reset needs at least 3 non-Core cards available overall.
func refillExchange(_ s: inout GameState) -> [GameEvent] {
    var events: [GameEvent] = []
    func fill() {
        for i in s.exchange.indices where s.exchange[i] == nil {
            s.exchange[i] = drawFromDepot(&s)
        }
    }
    func isCore(_ c: Card?) -> Bool { c == .core }
    fill()
    var resets = 0
    while s.exchange.filter(isCore).count >= 3, resets < 20 {
        let nonCore = (s.depot + s.salvage + s.exchange.compactMap { $0 }).filter { $0 != .core }.count
        if nonCore < 3 { break }
        s.salvage += s.exchange.compactMap { $0 }
        s.exchange = Array(repeating: nil, count: 5)
        fill()
        events.append(.exchangeReset)
        resets += 1
    }
    return events
}

extension GameEngine {
    func drawBlind(_ s: inout GameState) throws(RuleError) -> [GameEvent] {
        guard let card = drawFromDepot(&s) else { throw .noCardsToDraw }
        let seat = s.current
        s.players[seat].hand.add(card)
        return finishDraw(&s, events: [.drewBlind(player: seat)], first: s.phase == .awaitingAction)
    }

    func drawExchange(_ slot: Int, _ s: inout GameState) throws(RuleError) -> [GameEvent] {
        guard s.exchange.indices.contains(slot), let card = s.exchange[slot] else { throw .slotEmpty }
        let isFirst = s.phase == .awaitingAction
        if !isFirst, card == .core { throw .coreMustBeFirst }
        let seat = s.current
        s.exchange[slot] = nil
        s.players[seat].hand.add(card)
        var events: [GameEvent] = [.drewExchange(player: seat, card: card)]
        events += refillExchange(&s)
        if isFirst, card == .core { return events + endTurn(&s) }
        return finishDraw(&s, events: events, first: isFirst)
    }

    /// After a draw: ends the turn on a second card, or when no second card exists.
    private func finishDraw(_ s: inout GameState, events: [GameEvent], first: Bool) -> [GameEvent] {
        if first, secondDrawPossible(s) {
            s.phase = .drawingSecondCard
            return events
        }
        return events + endTurn(&s)
    }

    private func secondDrawPossible(_ s: GameState) -> Bool {
        !s.depot.isEmpty || !s.salvage.isEmpty
            || s.exchange.contains { $0 != nil && $0 != .core }
    }

    func drawActions(_ s: GameState) -> [Action] {
        var actions: [Action] = []
        if !s.depot.isEmpty || !s.salvage.isEmpty { actions.append(.drawBlind) }
        let second = s.phase == .drawingSecondCard
        for (i, c) in s.exchange.enumerated() {
            if let c, !(second && c == .core) { actions.append(.drawExchange(slot: i)) }
        }
        return actions
    }
}
