import Foundation
import Testing
@testable import StarsCore

@MainActor @Suite struct ReplayLogTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("replaylog-\(UUID().uuidString)")
    }

    private func config(seed: UInt64 = 11) -> GameConfig {
        GameConfig(houses: [.varn, .solace, .meridian], frontierHazards: false, seed: seed)
    }

    private func lines(_ url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    private func play(_ s: GameSession, steps: Int, picker: inout SeededRNG) {
        var n = 0
        while s.screen != .finalReview, n < steps {
            s.reveal()
            let legal = s.engine.legalActions(s.state)
            if n == 0 || n == steps / 2 {
                let bad: [Action] = [.drawBlind, .drawContracts, .pass, .drawExchange(slot: 9)]
                if let illegal = bad.first(where: { !legal.contains($0) }) { s.perform(illegal) }
            }
            guard let action = legal.randomElement(using: &picker) else { break }
            s.perform(action)
            n += 1
        }
    }

    @Test func replayReproducesGame() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try ReplayLog(directory: dir)
        let s = GameSession(config: config(), log: log)
        var picker = SeededRNG(seed: 5)
        play(s, steps: 300, picker: &picker)
        let replayed = try ReplayLog.replay(log.fileURL, engine: s.engine)
        #expect(replayed == s.state)
        let kinds = try lines(log.fileURL)
        #expect(kinds.first?["kind"] as? String == "start")
        #expect(kinds.filter { ($0["result"] as? String).map { $0 != "ok" } ?? false }.count >= 2)
    }

    @Test func replayFromSnapshotAfterLoad() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saves = InMemorySaveSlots()
        let log = try ReplayLog(directory: dir)
        let s = GameSession(config: config(), saves: saves, log: log)
        var picker = SeededRNG(seed: 6)
        play(s, steps: 40, picker: &picker)
        try s.saveGame(named: "Mid", replacing: nil)
        play(s, steps: 40, picker: &picker)
        try s.loadGame(id: s.savedGames()[0].id)
        play(s, steps: 25, picker: &picker)
        let all = try lines(log.fileURL)
        #expect(all.contains { $0["kind"] as? String == "snapshot" && $0["reason"] as? String == "loaded" && $0["saveName"] as? String == "Mid" })
        #expect(try ReplayLog.replay(log.fileURL, engine: s.engine) == s.state)
    }

    @Test func resumeWritesSnapshot() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = InMemoryGameStore()
        let s = GameSession(config: config(), store: store)
        var picker = SeededRNG(seed: 8)
        play(s, steps: 20, picker: &picker)
        let log = try ReplayLog(directory: dir)
        let resumed = try #require(GameSession.resume(store: store, saves: InMemorySaveSlots(), log: log))
        play(resumed, steps: 10, picker: &picker)
        #expect(try lines(log.fileURL).first?["reason"] as? String == "resumed")
        #expect(try ReplayLog.replay(log.fileURL, engine: resumed.engine) == resumed.state)
    }

    @Test func prunesToNewest20() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 1...25 {
            let name = String(format: "20260101-0000%02d-1.jsonl", i)
            try Data().write(to: dir.appendingPathComponent(name))
        }
        _ = try ReplayLog(directory: dir)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left.count == 20)
        #expect(left.first == "20260101-000006-1.jsonl")
        #expect(!left.contains("20260101-000005-1.jsonl"))
    }

    @Test func sameSecondSameSeedDoesNotOverwrite() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let a = try ReplayLog(directory: dir, now: { now })
        let b = try ReplayLog(directory: dir, now: { now })
        a.start(config())
        b.start(config())
        #expect(a.fileURL != b.fileURL)
        #expect(a.fileURL.lastPathComponent.hasSuffix("-11.jsonl"))
    }

    @Test func errorsAreLogged() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saves = InMemorySaveSlots()
        let engine = GameEngine(map: .standard)
        var state = engine.newGame(config())
        state.phase = .awaitingAction
        state.current = 0
        state.exchange = [.resource(.red), .core, .resource(.blue), .resource(.blue), .resource(.green)]
        try saves.put(SavedGame(id: UUID(), name: "Crafted", savedAt: .now, state: state))
        let log = try ReplayLog(directory: dir)
        let s = GameSession(config: config(), saves: saves, log: log)
        try s.loadGame(id: s.savedGames()[0].id)
        s.reveal()
        s.perform(.drawExchange(slot: 0))
        s.perform(.drawExchange(slot: 1))
        #expect(s.lastError == .coreMustBeFirst)
        let last = try #require(try lines(log.fileURL).last)
        #expect(last["kind"] as? String == "action")
        #expect(last["result"] as? String == "coreMustBeFirst")
        #expect(RuleError.mustKeepAtLeast(2).name == "mustKeepAtLeast")
        #expect(try ReplayLog.replay(log.fileURL, engine: engine) == s.state)
    }

    @Test func ignoredCallsAreNotLogged() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try ReplayLog(directory: dir)
        let s = GameSession(config: config(), log: log)
        s.perform(.drawBlind)   // hand-off screen, ignored
        #expect(try lines(log.fileURL).count == 1)
    }

    @Test func replayDetectsMismatch() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try ReplayLog(directory: dir)
        let s = GameSession(config: config(), log: log)
        s.reveal()
        s.perform(.drawBlind)
        let text = try String(contentsOf: log.fileURL, encoding: .utf8).replacingOccurrences(of: "\"wrongPhase\"", with: "\"ok\"")
        try text.write(to: log.fileURL, atomically: true, encoding: .utf8)
        #expect(throws: ReplayError.self) { try ReplayLog.replay(log.fileURL, engine: s.engine) }
        try "not json\n".write(to: log.fileURL, atomically: true, encoding: .utf8)
        #expect(throws: ReplayError.self) { try ReplayLog.replay(log.fileURL, engine: s.engine) }
    }

    @Test func holdsExactlyKeepFilesOnceSessionFileExists() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 1...20 {
            try Data().write(to: dir.appendingPathComponent(String(format: "20260101-0000%02d-1.jsonl", i)))
        }
        let log = try ReplayLog(directory: dir)
        log.start(config())
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left.count == 20)
        #expect(!left.contains("20260101-000001-1.jsonl"))
        #expect(left.contains(log.fileURL.lastPathComponent))
    }

    @Test func fileTroubleNeverBreaksPlay() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try ReplayLog(directory: dir)
        // A regular file where the directory was makes creating the log file fail.
        try FileManager.default.removeItem(at: dir)
        try Data().write(to: dir)
        let s = GameSession(config: config(), log: log)
        #expect(log.disabled)
        var picker = SeededRNG(seed: 9)
        for _ in 0..<6 {
            s.reveal()
            let action = try #require(s.engine.legalActions(s.state).randomElement(using: &picker))
            let before = s.state
            s.perform(action)
            #expect(s.lastError == nil)
            #expect(s.state != before)
        }
        #expect(log.disabled)
    }
}
