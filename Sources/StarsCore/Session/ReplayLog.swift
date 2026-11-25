import Foundation
import os

extension RuleError {
    /// The case name without associated values, e.g. `mustKeepAtLeast` for `.mustKeepAtLeast(2)`.
    public var name: String {
        let text = String(describing: self)
        return text.firstIndex(of: "(").map { String(text[..<$0]) } ?? text
    }
}

public enum ReplayError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case malformedLine(Int, String)
    case noStart
    case mismatch(line: Int, logged: String, actual: String)

    public var description: String {
        switch self {
        case let .unreadable(why): "Replay log could not be read: \(why)"
        case let .malformedLine(n, why): "Replay log line \(n) is malformed: \(why)"
        case .noStart: "Replay log has no start or snapshot line"
        case let .mismatch(line, logged, actual): "Replay log line \(line): logged result \(logged), engine now gives \(actual)"
        }
    }
}

/// Diagnostic log for one session: JSON Lines, one `start`, `snapshot` or `action` object per line.
/// The engine is deterministic, so `replay` rebuilds the exact game. Any file error turns file
/// writing off for the rest of the session; play is never affected.
public final class ReplayLog {
    private struct Line: Codable {
        var kind: String
        var version: Int?
        var config: GameConfig?
        var startedAt: Date?
        var reason: String?
        var saveName: String?
        var state: GameState?
        var seq: Int?
        var player: Int?
        var house: House?
        var phase: TurnPhase?
        var action: Action?
        var result: String?
    }

    private static let logger = Logger(subsystem: "local.spanningthestars", category: "game")

    private let directory: URL
    private let now: () -> Date
    private var url: URL?
    private var handle: FileHandle?
    private(set) var disabled = false
    private let keep: Int
    private var seq = 0

    /// Creates the directory if needed and keeps only the `keep` newest log files in it.
    public init(directory: URL, keep: Int = 20, now: @escaping () -> Date = { Date() }) throws {
        self.directory = directory
        self.now = now
        self.keep = max(keep, 1)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        prune()
    }

    /// Removes all but the newest `keep` log files (names sort by date), never this session's own file.
    private func prune() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let mine = url?.lastPathComponent
        let others = names.filter { $0.hasSuffix(".jsonl") && $0 != mine }.sorted()
        for old in others.dropLast(max(keep - (mine == nil ? 0 : 1), 0)) {
            try? fm.removeItem(at: directory.appendingPathComponent(old))
        }
    }

    deinit { try? handle?.close() }

    /// The file this session writes to. Chosen when the first line is written (it needs the seed);
    /// until then this is where it would be named, without a seed.
    public var fileURL: URL { url ?? directory.appendingPathComponent("unstarted.jsonl") }

    public func start(_ config: GameConfig) {
        open(seed: config.seed)
        write(Line(kind: "start", version: 1, config: config, startedAt: now()))
    }

    public func snapshot(_ s: GameState, reason: String, saveName: String?) {
        open(seed: s.config.seed)
        write(Line(kind: "snapshot", reason: reason, saveName: saveName, state: s))
    }

    public func action(_ a: Action, by player: Int, state before: GameState, result: Result<Void, RuleError>) {
        open(seed: before.config.seed)
        seq += 1
        let outcome: String
        switch result {
        case .success: outcome = "ok"
        case let .failure(error): outcome = error.name
        }
        write(Line(
            kind: "action", seq: seq, player: player,
            house: before.players.indices.contains(player) ? before.players[player].house : nil,
            phase: before.phase, action: a, result: outcome))
    }

    // MARK: Writing

    private func open(seed: UInt64) {
        guard url == nil, !disabled else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(formatter.string(from: now()))-\(seed)"
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(base).jsonl")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = directory.appendingPathComponent("\(base)-\(counter).jsonl")
        }
        url = candidate
        guard fm.createFile(atPath: candidate.path, contents: nil) else { return fail("could not create \(candidate.path)") }
        do { handle = try FileHandle(forWritingTo: candidate) } catch { return fail("\(error)") }
        prune()
    }

    private func write(_ line: Line) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(line)
            let text = String(decoding: data, as: UTF8.self)
            Self.logger.debug("\(text, privacy: .public)")
            guard !disabled, let handle else { return }
            try handle.write(contentsOf: data + Data("\n".utf8))
        } catch {
            fail("\(error)")
        }
    }

    private func fail(_ why: String) {
        disabled = true
        try? handle?.close()
        handle = nil
        Self.logger.error("Replay log disabled: \(why, privacy: .public)")
    }

    // MARK: Replay

    /// Rebuilds the game from the last `start` or `snapshot` line, re-applying every action after it.
    /// Throws when a line is malformed or a logged result differs from what the engine now does.
    public static func replay(_ url: URL, engine: GameEngine) throws -> GameState {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) } catch { throw ReplayError.unreadable("\(error)") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var parsed: [(number: Int, line: Line)] = []
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            do { parsed.append((i + 1, try decoder.decode(Line.self, from: Data(raw.utf8)))) } catch {
                throw ReplayError.malformedLine(i + 1, "\(error)")
            }
        }
        guard let from = parsed.lastIndex(where: { $0.line.kind == "start" || $0.line.kind == "snapshot" }) else {
            throw ReplayError.noStart
        }
        var state: GameState
        let first = parsed[from]
        if first.line.kind == "start" {
            guard let config = first.line.config else { throw ReplayError.malformedLine(first.number, "start without config") }
            state = engine.newGame(config)
        } else {
            guard let snap = first.line.state else { throw ReplayError.malformedLine(first.number, "snapshot without state") }
            state = snap
        }
        for (number, line) in parsed[(from + 1)...] {
            guard line.kind == "action", let action = line.action, let logged = line.result else {
                throw ReplayError.malformedLine(number, "expected an action line")
            }
            let actual: String
            do { _ = try engine.apply(action, to: &state); actual = "ok" } catch { actual = error.name }
            guard actual == logged else { throw ReplayError.mismatch(line: number, logged: logged, actual: actual) }
        }
        return state
    }
}
