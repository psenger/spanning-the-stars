import Foundation
import Observation

/// Drives one pass-the-laptop game. Hidden hands stay behind a hand-off screen between seats.
/// Bot seats play by themselves; with a single human seat there is nobody to hand off to.
@MainActor @Observable
public final class GameSession {
    public enum Screen: Equatable { case handoff(player: Int), playing, finalReview, botTurn(player: Int) }

    public private(set) var state: GameState
    public private(set) var screen: Screen
    public private(set) var lastError: RuleError?
    /// Public events since the previous human seat's turn began, shown on the hand-off screen.
    /// Bot moves made between two humans are included.
    public private(set) var recentEvents: [GameEvent] = []
    public let engine: GameEngine
    /// Set when the last autosave failed; play carries on regardless.
    public private(set) var saveProblem: String?

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private let saves: SaveSlots
    @ObservationIgnored private let log: ReplayLog?
    @ObservationIgnored private let driver: BotDriver
    @ObservationIgnored private let botDelay: Duration
    @ObservationIgnored private let botDeadline: Duration
    /// The pending bot move, nil when no bot is deciding.
    @ObservationIgnored private var botTask: Task<Void, Never>?

    private var turnEvents: [GameEvent] = []

    public convenience init(
        config: GameConfig, map: GalaxyMap = .standard,
        store: GameStore = InMemoryGameStore(), saves: SaveSlots = InMemorySaveSlots(),
        log: ReplayLog? = nil,
        botDelay: Duration = .milliseconds(800), botDeadline: Duration = .seconds(1.5)
    ) {
        self.init(config: config, map: map, store: store, saves: saves, log: log,
                  botDelay: botDelay, botDeadline: botDeadline, roster: nil)
    }

    /// `roster` replaces the standard bots; tests use it to seat a bot of their own.
    init(
        config: GameConfig, map: GalaxyMap = .standard,
        store: GameStore = InMemoryGameStore(), saves: SaveSlots = InMemorySaveSlots(),
        log: ReplayLog? = nil,
        botDelay: Duration, botDeadline: Duration, roster: BotRoster?
    ) {
        let engine = GameEngine(map: map)
        let initial = engine.newGame(config)
        self.engine = engine
        self.store = store
        self.saves = saves
        self.log = log
        driver = BotDriver(engine: engine, roster: roster ?? BotRoster(engine: engine))
        self.botDelay = botDelay
        self.botDeadline = botDeadline
        state = initial
        screen = .handoff(player: initial.current)
        log?.start(config)
        // Saved at once, so Continue always resumes the newest game.
        autosave()
        showCurrentSeat()
    }

    private init(state: GameState, map: GalaxyMap, store: GameStore, saves: SaveSlots, log: ReplayLog?,
                 botDelay: Duration, botDeadline: Duration,
                 reason: String = "resumed", saveName: String? = nil) {
        let engine = GameEngine(map: map)
        self.engine = engine
        self.store = store
        self.saves = saves
        self.log = log
        driver = BotDriver(engine: engine)
        self.botDelay = botDelay
        self.botDeadline = botDeadline
        self.state = state
        screen = .finalReview
        log?.snapshot(state, reason: reason, saveName: saveName)
        showCurrentSeat()
    }

    isolated deinit { botTask?.cancel() }

    /// Opens a named save as a new session, on the screen for the seat to act (or the final review if
    /// it is over); a bot to move starts at once. It becomes the autosaved game.
    public static func load(id: UUID, map: GalaxyMap = .standard, store: GameStore, saves: SaveSlots,
                            log: ReplayLog? = nil, botDelay: Duration = .milliseconds(800),
                            botDeadline: Duration = .seconds(1.5)) throws -> GameSession {
        let game = try saves.load(id: id)
        let session = GameSession(state: game.state, map: map, store: store, saves: saves, log: log,
                                  botDelay: botDelay, botDeadline: botDeadline,
                                  reason: "loaded", saveName: game.name)
        session.autosave()
        return session
    }

    /// Reopens the autosaved game on the screen for the seat to act; a bot to move starts at once.
    /// Nil when there is no autosave, it cannot be read, or the game it holds is over.
    public static func resume(map: GalaxyMap = .standard, store: GameStore, saves: SaveSlots, log: ReplayLog? = nil,
                              botDelay: Duration = .milliseconds(800),
                              botDeadline: Duration = .seconds(1.5)) -> GameSession? {
        guard let state = try? store.load(), state.phase != .gameOver else { return nil }
        return GameSession(state: state, map: map, store: store, saves: saves, log: log,
                           botDelay: botDelay, botDeadline: botDeadline)
    }

    public func saveGame(named name: String, replacing: UUID?) throws {
        guard state.phase != .gameOver else { throw SaveError.noGame }
        try saves.write(name: name, state: state, replacing: replacing)
    }

    public func loadGame(id: UUID) throws {
        let game = try saves.load(id: id)
        state = game.state
        log?.snapshot(state, reason: "loaded", saveName: game.name)
        turnEvents = []
        recentEvents = []
        lastError = nil
        showCurrentSeat()
        autosave()
    }

    public func deleteSavedGame(id: UUID) throws { try saves.remove(id: id) }

    public func savedGames() -> [SavedGameSummary] { saves.list() }

    public var activePlayer: Int { state.current }

    public func reveal() {
        if case .handoff = screen {
            lastError = nil
            screen = .playing
        }
    }

    /// Ignored while a hand-off, a bot's turn or the final review is showing, so nobody acts before
    /// the right player sees the board.
    public func perform(_ action: Action) {
        guard screen == .playing else { return }
        apply(action)
    }

    /// Returns once no bot move is pending: a human is to act or the game is over.
    public func waitForBots() async {
        while let task = botTask { await task.value }
    }

    private func apply(_ action: Action) {
        let before = state
        do {
            let events = try engine.apply(action, to: &state)
            lastError = nil
            log?.action(action, by: before.current, state: before, result: .success(()))
            afterAction(events, previous: before)
        } catch {
            lastError = error
            log?.action(action, by: before.current, state: before, result: .failure(error))
        }
    }

    private func autosave() {
        do {
            if state.phase == .gameOver { try store.clear() } else { try store.save(state) }
            saveProblem = nil
        } catch {
            saveProblem = "The game could not be saved automatically."
        }
    }

    private func afterAction(_ events: [GameEvent], previous: GameState) {
        autosave()
        turnEvents += events
        let wasSetup: Bool
        if case .setupContracts = previous.phase { wasSetup = true } else { wasSetup = false }
        let isSetup: Bool
        if case .setupContracts = state.phase { isSetup = true } else { isSetup = false }
        if state.phase == .gameOver || state.current != previous.current || (wasSetup && !isSetup) {
            showCurrentSeat()
        } else if case .botTurn = screen {
            startBotMove()
        }
    }

    /// Picks the screen for the seat now to act and starts its move when it is a bot. A human seat
    /// (or the final review) also gets the events gathered since the last human seat.
    private func showCurrentSeat() {
        botTask?.cancel()
        botTask = nil
        if state.phase != .gameOver, case .bot = state.players[state.current].kind {
            screen = .botTurn(player: state.current)
            startBotMove()
            return
        }
        recentEvents = turnEvents
        turnEvents = []
        lastError = nil
        if state.phase == .gameOver {
            screen = .finalReview
        } else if state.players.count(where: { $0.kind == .human }) == 1 {
            screen = .playing
        } else {
            screen = .handoff(player: state.current)
        }
    }

    /// Decides off the main actor, waits out `botDelay`, then applies the action unless the game
    /// has moved on (a load) since the decision was asked for.
    private func startBotMove() {
        let captured = state
        let clock = ContinuousClock()
        let started = clock.now
        botTask = Task { [weak self, driver, botDelay, botDeadline] in
            let decision = await Task.detached {
                driver.decide(captured, deadline: started + botDeadline)
            }.value
            try? await clock.sleep(until: started + botDelay)
            guard !Task.isCancelled, let self else { return }
            self.botTask = nil
            guard self.state == captured else { return }
            guard let decision else {
                assertionFailure("no decision on a bot's turn")
                return
            }
            self.apply(decision.action)
            if let error = self.lastError {
                assertionFailure("the engine rejected a bot's action: \(error)")
            }
        }
    }
}
