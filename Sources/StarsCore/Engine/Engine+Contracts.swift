extension GameEngine {
    func keepSetupContracts(_ ids: [Int], offered: [Int], state s: inout GameState) throws(RuleError) -> [GameEvent] {
        let kept = Set(ids)
        guard kept.count == ids.count, kept.isSubset(of: offered) else { throw .notOffered }
        guard ids.count >= 2 else { throw .mustKeepAtLeast(2) }

        let seat = s.current
        s.players[seat].contracts += ids
        s.setupReturns += offered.filter { !kept.contains($0) }

        if seat + 1 < s.players.count {
            s.current = seat + 1
            s.phase = .setupContracts(offered: s.pendingOffers[seat + 1])
        } else {
            s.setupReturns.shuffle(using: &s.rng)
            s.contractDeck.insert(contentsOf: s.setupReturns, at: 0)
            s.setupReturns = []
            s.current = s.firstPlayer
            s.phase = .awaitingAction
        }
        return [.keptContracts(player: seat, count: ids.count)]
    }

    func drawContracts(_ s: inout GameState) throws(RuleError) -> [GameEvent] {
        guard !s.contractDeck.isEmpty else { throw .contractDeckEmpty }
        let offered = (0..<min(3, s.contractDeck.count)).map { _ in s.contractDeck.removeLast() }
        s.phase = .choosingContracts(offered: offered)
        return []
    }

    func keepDrawnContracts(_ ids: [Int], offered: [Int], state s: inout GameState) throws(RuleError) -> [GameEvent] {
        let kept = Set(ids)
        guard kept.count == ids.count, kept.isSubset(of: offered) else { throw .notOffered }
        guard !ids.isEmpty else { throw .mustKeepAtLeast(1) }

        let seat = s.current
        s.players[seat].contracts += ids
        s.contractDeck.insert(contentsOf: offered.filter { !kept.contains($0) }, at: 0)
        return [.keptContracts(player: seat, count: ids.count)] + endTurn(&s)
    }

    /// Every subset of the offered ids with at least `minimum` elements.
    func keepSubsets(of offered: [Int], minimum: Int) -> [Action] {
        (0..<(1 << offered.count)).compactMap { mask in
            let ids = offered.indices.filter { mask & (1 << $0) != 0 }.map { offered[$0] }
            return ids.count >= minimum ? .keepContracts(ids) : nil
        }
    }
}
