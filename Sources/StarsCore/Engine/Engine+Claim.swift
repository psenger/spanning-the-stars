extension GameEngine {
    /// Shared claim guard, in validation order. nil means the lane is claimable by `seat`.
    public func claimBlocker(_ lane: Lane, seat: Int, in s: GameState) -> RuleError? {
        StarsCore.claimBlocker(lane, seat: seat, laneOwner: s.laneOwner, playerCount: s.players.count,
                               beacons: s.players[seat].beacons, hazards: s.config.frontierHazards)
    }

    func claim(_ laneID: Int, _ payment: Payment, _ s: inout GameState) throws(RuleError) -> [GameEvent] {
        guard s.phase == .awaitingAction else { throw .wrongPhase }
        let lane = map.lane(laneID)
        let seat = s.current
        if let blocker = claimBlocker(lane, seat: seat, in: s) { throw blocker }
        let hazards = s.config.frontierHazards
        guard paymentOptions(for: lane, hand: s.players[seat].hand, hazards: hazards).contains(payment) else {
            throw .invalidPayment
        }

        try s.players[seat].hand.remove(payment)
        // Fixed order: dictionary order varies between instances, and salvage order feeds the reshuffle.
        for card in ResourceColor.allCases.map(Card.resource) + [.core] {
            s.salvage += Array(repeating: card, count: payment.counts[card, default: 0])
        }
        s.players[seat].beacons -= beaconCost(lane, hazards: hazards)
        let points = lanePoints(lane.length)
        s.players[seat].score += points
        s.laneOwner[laneID] = seat
        s.players[seat].lanes.append(laneID)
        return [.claimed(player: seat, laneID: laneID, points: points)] + endTurn(&s)
    }

    func claimActions(_ s: GameState) -> [Action] {
        let seat = s.current
        let player = s.players[seat]
        let hazards = s.config.frontierHazards
        var actions: [Action] = []
        for lane in map.lanes {
            guard claimBlocker(lane, seat: seat, in: s) == nil else { continue }
            for p in paymentOptions(for: lane, hand: player.hand, hazards: hazards) {
                actions.append(.claim(laneID: lane.id, payment: p))
            }
        }
        return actions
    }
}
