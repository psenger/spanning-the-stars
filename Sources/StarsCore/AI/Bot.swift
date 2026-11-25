/// A computer player. It sees the game only through a `PlayerView`.
public protocol Bot: Sendable {
    /// Must return a member of `view.legalActions`. `deadline` is a hint only search bots use.
    func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action
}

/// Picks uniformly from the legal actions.
public struct RandomBot: Bot {
    public init() {}

    public func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action {
        view.legalActions.randomElement(using: &rng)!
    }
}

/// Builds the bot for each level once per map. Cadet to Commander are a `HeuristicBot`; Admiral is a
/// `SearchBot`.
public struct BotRoster: Sendable {
    private let bots: [any Bot]   // indexed by level, weakest first

    public init(engine: GameEngine) {
        self.init { level in
            if level != .admiral {
                return HeuristicBot(settings: .level(level), map: engine.map)
            }
            return SearchBot(settings: .level(level), engine: engine)
        }
    }

    init(_ make: (BotLevel) -> any Bot) {
        bots = BotLevel.allCases.map(make)
    }

    public func bot(_ level: BotLevel) -> any Bot { bots[level.rawValue - 1] }
}

public struct BotDecision: Sendable, Equatable {
    public let action: Action
    /// The bot's choice was illegal and `legalActions[0]` was used.
    public let substituted: Bool
}

/// Asks the current seat's bot for its action. The bot gets the seat's view and a derived rng only.
public struct BotDriver: Sendable {
    private let engine: GameEngine
    private let roster: BotRoster

    public init(engine: GameEngine) {
        self.init(engine: engine, roster: BotRoster(engine: engine))
    }

    public init(engine: GameEngine, roster: BotRoster) {
        self.engine = engine
        self.roster = roster
    }

    /// nil when the game is over or the current seat is human.
    public func decide(_ state: GameState, deadline: ContinuousClock.Instant? = nil) -> BotDecision? {
        guard state.phase != .gameOver, case let .bot(level) = state.players[state.current].kind else { return nil }
        let view = PlayerView(state: state, seat: state.current, engine: engine)
        var rng = decisionRNG(state)
        let choice = roster.bot(level).chooseAction(view: view, rng: &rng, deadline: deadline)
        if view.legalActions.contains(choice) { return BotDecision(action: choice, substituted: false) }
        return BotDecision(action: view.legalActions[0], substituted: true)
    }
}

/// rng for one decision: SplitMix seeded from seed, log length, phase tag (0 to 3) and current seat.
/// The inputs are mixed, so the result never starts from the game seed itself.
func decisionRNG(_ state: GameState) -> SeededRNG {
    let phaseTag: UInt64 = switch state.phase {
    case .setupContracts: 0
    case .awaitingAction: 1
    case .drawingSecondCard: 2
    case .choosingContracts: 3
    case .gameOver: 0   // no decision is taken once the game is over
    }
    var mixed = state.config.seed
    for input in [UInt64(state.log.count), phaseTag, UInt64(state.current)] {
        var step = SeededRNG(seed: mixed)
        mixed = step.next() ^ input
    }
    var last = SeededRNG(seed: mixed)
    return SeededRNG(seed: last.next())
}
