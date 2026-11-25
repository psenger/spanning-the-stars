public struct GameResult: Sendable, Equatable {
    public let state: GameState
    public let scores: [FinalScore]
    public let ranking: [[Int]]
    /// Decisions taken in the awaitingAction phase.
    public let turns: Int
    public let illegalMoves: Int
}

/// Plays a whole game without the UI. Every seat must be a bot. Stops after maxActions as a guard.
public func playGame(config: GameConfig, engine: GameEngine, driver: BotDriver? = nil,
                     maxActions: Int = 5000) -> GameResult {
    let driver = driver ?? BotDriver(engine: engine)
    var state = engine.newGame(config)
    precondition(state.players.allSatisfy { $0.kind != .human }, "playGame needs a bot in every seat")
    var actions = 0, turns = 0, illegalMoves = 0
    while actions < maxActions, let decision = driver.decide(state) {
        if state.phase == .awaitingAction { turns += 1 }
        if decision.substituted { illegalMoves += 1 }
        _ = try! engine.apply(decision.action, to: &state)
        actions += 1
    }
    let scores = finalScores(state, map: engine.map)
    return GameResult(state: state, scores: scores, ranking: ranking(scores), turns: turns,
                      illegalMoves: illegalMoves)
}
