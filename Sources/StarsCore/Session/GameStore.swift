import Foundation

/// Where the current game is kept between launches. The app saves to Application Support;
/// tests keep it in memory.
@MainActor
public protocol GameStore: AnyObject {
    func save(_ state: GameState) throws
    func load() throws -> GameState?
    func clear() throws
}

public final class InMemoryGameStore: GameStore {
    private var saved: GameState?
    public private(set) var saveCount = 0

    public init() {}

    public func save(_ state: GameState) throws {
        saved = state
        saveCount += 1
    }

    public func load() throws -> GameState? { saved }

    public func clear() throws { saved = nil }
}

/// Keeps the current game as JSON in `autosave.json`, so a game survives quitting the app.
public final class FileGameStore: GameStore {
    private let directory: URL
    private var file: URL { directory.appending(path: "autosave.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ state: GameState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
    }

    /// Nil when nothing is saved; throws when the file cannot be read as a game.
    public func load() throws -> GameState? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(GameState.self, from: Data(contentsOf: file))
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
