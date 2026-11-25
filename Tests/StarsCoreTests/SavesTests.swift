import Foundation
import Testing
@testable import StarsCore

@MainActor @Suite struct SavesTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stars-saves-\(UUID().uuidString)")
    }

    private func config(seed: UInt64 = 7) -> GameConfig {
        GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: seed)
    }

    private func freshState() -> GameState { GameEngine(map: .standard).newGame(config()) }

    private func midGame(_ s: GameSession) {
        while case let .setupContracts(offered) = s.state.phase {
            s.reveal()
            s.perform(.keepContracts(Array(offered.prefix(2))))
        }
        s.reveal()
        s.perform(.drawBlind)
        s.perform(.drawBlind)
    }

    private func finish(_ s: GameSession) {
        var picker = SeededRNG(seed: 3)
        var steps = 0
        while s.screen != .finalReview, steps < 3000 {
            if case .handoff = s.screen { s.reveal() }
            guard let a = s.engine.legalActions(s.state).randomElement(using: &picker) else { break }
            s.perform(a)
            steps += 1
        }
    }

    private func filled(_ slots: SaveSlots) throws {
        for i in 1...SaveLimit.maxSaves {
            try slots.write(name: "Save \(i)", state: freshState(), now: Date(timeIntervalSince1970: Double(i)))
        }
    }

    @Test func listIsNewestFirst() throws {
        let slots = InMemorySaveSlots()
        let old = try slots.write(name: "Old", state: freshState(), now: Date(timeIntervalSince1970: 1))
        let new = try slots.write(name: "New", state: freshState(), now: Date(timeIntervalSince1970: 2))
        #expect(slots.list() == [new, old])
        #expect(new.houses == [.varn, .solace])
    }

    @Test func sixthSaveThrowsFull() throws {
        let slots = InMemorySaveSlots()
        try filled(slots)
        let before = slots.list()
        #expect(throws: SaveError.full) { try slots.write(name: "Sixth", state: freshState()) }
        #expect(slots.list() == before)
    }

    @Test func replacingKeepsCountAtFive() throws {
        let slots = InMemorySaveSlots()
        try filled(slots)
        let target = slots.list()[2]
        let saved = try slots.write(name: "Replacement", state: freshState(), replacing: target.id)
        #expect(saved.id == target.id)
        #expect(slots.list().count == SaveLimit.maxSaves)
        #expect(slots.list().map(\.name).contains("Replacement"))
        #expect(throws: SaveError.notFound) { try slots.write(name: "A", state: freshState(), replacing: UUID()) }
    }

    @Test func blankNameThrows() {
        #expect(throws: SaveError.blankName) { try InMemorySaveSlots().write(name: "   ", state: freshState()) }
    }

    @Test func nameClippedTo30() throws {
        let long = String(repeating: "x", count: 40)
        let saved = try InMemorySaveSlots().write(name: "  \(long)  ", state: freshState())
        #expect(saved.name.count == SaveLimit.maxNameLength)
    }

    @Test func deleteRemoves() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let slots = FileSaveSlots(directory: folder)
        let keep = try slots.write(name: "Keep", state: freshState())
        let gone = try slots.write(name: "Gone", state: freshState())
        try slots.remove(id: gone.id)
        #expect(slots.list() == [keep])
        #expect(throws: SaveError.notFound) { try slots.load(id: gone.id) }
    }

    @Test func unreadableFileSkipped() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let slots = FileSaveSlots(directory: folder)
        let good = try slots.write(name: "Good", state: freshState())
        try Data("not a game".utf8).write(to: folder.appending(path: "\(UUID().uuidString).json"))
        #expect(slots.list() == [good])
    }

    @Test func fileSlotsRoundTrip() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let s = GameSession(config: config())
        midGame(s)
        let saved = try FileSaveSlots(directory: folder).write(name: "Mid", state: s.state)
        let loaded = try FileSaveSlots(directory: folder).load(id: saved.id)
        #expect(loaded.state == s.state)
    }

    @Test func fileGameStoreRoundTripAndClear() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileGameStore(directory: folder)
        #expect(try store.load() == nil)
        let state = freshState()
        try store.save(state)
        #expect(try FileGameStore(directory: folder).load() == state)
        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test func sessionAutosavesEachAction() {
        let store = InMemoryGameStore()
        let s = GameSession(config: config(), store: store)
        s.reveal()
        #expect(store.saveCount == 1)   // the new game itself
        s.perform(.drawBlind)   // illegal in setup
        #expect(store.saveCount == 1)
        guard case let .setupContracts(offered) = s.state.phase else { return }
        s.perform(.keepContracts(Array(offered.prefix(2))))
        #expect(store.saveCount == 2)
        #expect(s.saveProblem == nil)
    }

    @Test func failedAutosaveSetsProblemAndPlayContinues() {
        final class Broken: GameStore {
            func save(_ state: GameState) throws { throw SaveError.full }
            func load() throws -> GameState? { nil }
            func clear() throws {}
        }
        let s = GameSession(config: config(), store: Broken())
        s.reveal()
        guard case let .setupContracts(offered) = s.state.phase else { return }
        s.perform(.keepContracts(Array(offered.prefix(2))))
        #expect(s.saveProblem != nil)
        #expect(s.activePlayer == 1)
    }

    @Test func loadOpensAtHandoff() throws {
        let s = GameSession(config: config())
        midGame(s)
        s.reveal()
        let saved = s.state
        try s.saveGame(named: "Mid", replacing: nil)
        let id = s.savedGames()[0].id
        s.perform(.drawBlind)
        #expect(s.state != saved)
        try s.loadGame(id: id)
        #expect(s.state == saved)
        #expect(s.screen == .handoff(player: saved.current))
    }

    @Test func saveAfterGameOverThrowsNoGame() {
        let s = GameSession(config: config())
        finish(s)
        #expect(s.screen == .finalReview)
        #expect(throws: SaveError.noGame) { try s.saveGame(named: "Done", replacing: nil) }
    }

    @Test func deleteSavedGameRemoves() throws {
        let s = GameSession(config: config())
        try s.saveGame(named: "A", replacing: nil)
        try s.deleteSavedGame(id: s.savedGames()[0].id)
        #expect(s.savedGames().isEmpty)
    }

    @Test func resumeFromAutosave() throws {
        let store = InMemoryGameStore(), saves = InMemorySaveSlots()
        let s = GameSession(config: config(), store: store, saves: saves)
        midGame(s)
        let resumed = try #require(GameSession.resume(store: store, saves: saves))
        #expect(resumed.state == s.state)
        #expect(resumed.screen == .handoff(player: s.state.current))
        #expect(GameSession.resume(store: InMemoryGameStore(), saves: saves) == nil)
    }

    @Test func gameOverClearsAutosave() throws {
        let store = InMemoryGameStore()
        let s = GameSession(config: config(), store: store)
        finish(s)
        #expect(s.screen == .finalReview)
        #expect(try store.load() == nil)
        #expect(GameSession.resume(store: store, saves: InMemorySaveSlots()) == nil)
    }
    @Test func staticLoadOpensAtHandoffAndAutosaves() throws {
        let store = InMemoryGameStore()
        let slots = InMemorySaveSlots()
        let s = GameSession(config: config(), store: store, saves: slots)
        midGame(s)
        try s.saveGame(named: "Mid", replacing: nil)
        let id = s.savedGames()[0].id
        let loaded = try GameSession.load(id: id, store: store, saves: slots)
        #expect(loaded.state == s.state)
        #expect(loaded.screen == .handoff(player: s.state.current))
        #expect(try store.load() == s.state)
        #expect(throws: SaveError.notFound) {
            try GameSession.load(id: UUID(), store: store, saves: slots)
        }
    }
    @Test func newSessionIsAutosavedAtStart() throws {
        let store = InMemoryGameStore()
        let s = GameSession(config: config(), store: store)
        #expect(try store.load() == s.state)
        let resumed = GameSession.resume(store: store, saves: InMemorySaveSlots())
        #expect(resumed?.state == s.state)
    }
}
