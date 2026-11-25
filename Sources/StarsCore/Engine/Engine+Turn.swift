extension GameEngine {
    /// Closes the current turn: fills empty Exchange spaces when cards are available (Rules Section 10),
    /// tracks passes, runs the final round countdown and advances the seat. A full Exchange is left
    /// as it is, even one the reset stop left with 3+ Cores.
    func endTurn(_ s: inout GameState, passed: Bool = false) -> [GameEvent] {
        s.consecutivePasses = passed ? s.consecutivePasses + 1 : 0
        let canFill = s.exchange.contains(nil) && (!s.depot.isEmpty || !s.salvage.isEmpty)
        var events = canFill ? refillExchange(&s) : []
        if let remaining = s.finalTurnsRemaining {
            s.finalTurnsRemaining = remaining - 1
            if remaining - 1 == 0 { return finishGame(&s, events) }
        } else if s.players[s.current].beacons <= 2 {
            s.finalTurnsRemaining = s.players.count
            events.append(.finalRoundBegan(trigger: s.current))
        }
        if s.consecutivePasses == s.players.count { return finishGame(&s, events) }
        s.current = (s.current + 1) % s.players.count
        s.phase = .awaitingAction
        return events
    }

    private func finishGame(_ s: inout GameState, _ events: [GameEvent]) -> [GameEvent] {
        s.phase = .gameOver
        return events + [.gameEnded]
    }

    func passAction(_ s: inout GameState) throws(RuleError) -> [GameEvent] {
        guard legalActions(s) == [.pass] else { throw .passNotAllowed }
        let seat = s.current
        return [.passed(player: seat)] + endTurn(&s, passed: true)
    }
}
