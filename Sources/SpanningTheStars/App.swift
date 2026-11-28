import SwiftUI
import StarsCore

/// Content sizes. The default is a little under 1512x945 so the window and its title bar fit a 14"
/// MacBook Pro's visible screen; it is clamped to smaller screens at launch.
enum WindowSize {
    static let preferred = CGSize(width: 1512, height: 900)
    static let minimum = CGSize(width: 1280, height: 800)
    static let titleBar: CGFloat = 32
}

/// Where the app keeps its files: `~/Library/Application Support/SpanningTheStars/`.
enum AppFolders {
    static let root = URL.applicationSupportDirectory.appending(path: "SpanningTheStars")
    static let autosave = root.appending(path: "autosave")
    static let saves = root.appending(path: "Saves")
    static let logs = root.appending(path: "Logs")
}

/// The app's screens, saves and current game. One window, so one model.
@MainActor @Observable
final class AppModel {
    enum Route: Equatable { case title, setup, game }
    enum Sheet: String, Identifiable {
        case save, load
        var id: String { rawValue }
    }

    var route: Route = .title
    var sheet: Sheet?
    private(set) var session: GameSession?
    /// True when the autosave holds a game that is not over.
    private(set) var canContinue = false

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private let saves: SaveSlots

    init(store: GameStore = FileGameStore(directory: AppFolders.autosave),
         saves: SaveSlots = FileSaveSlots(directory: AppFolders.saves)) {
        self.store = store
        self.saves = saves
        canContinue = GameSession.resume(store: store, saves: saves, log: nil) != nil
    }

    /// A game is under way: loading another or starting over replaces it.
    var gameInProgress: Bool {
        guard let session else { return false }
        return session.state.phase != .gameOver
    }

    var canSave: Bool { gameInProgress }

    /// `kinds` has one entry per House in seat order; nil seats only humans.
    func startNewCharter(houses: [House], hazards: Bool, kinds: [PlayerKind]? = nil) {
        let config = GameConfig(houses: houses, frontierHazards: hazards, seed: UInt64.random(in: 1...UInt64.max),
                                kinds: kinds)
        session = GameSession(config: config, store: store, saves: saves, log: Self.makeLog())
        route = .game
    }

    func continueCharter() {
        guard let resumed = GameSession.resume(store: store, saves: saves, log: Self.makeLog()) else {
            canContinue = false
            return
        }
        session = resumed
        route = .game
    }

    /// Set while "Abandon the current charter?" is showing.
    var confirmingNewCharter = false

    /// New Charter from the title, the menu or the Final Review. When a game is under way, or an
    /// autosave could be continued, it asks first; Begin in Setup is what replaces that game.
    func requestNewCharter() {
        refreshContinue()
        if gameInProgress || canContinue { confirmingNewCharter = true } else { openSetup() }
    }

    func openSetup() { route = .setup }

    /// Leaves Setup: back to the game under way, or to the title.
    func closeSetup() {
        if gameInProgress {
            route = .game
        } else {
            refreshContinue()
            route = .title
        }
    }

    func returnToTitle() {
        session = nil
        refreshContinue()
        route = .title
    }

    private func refreshContinue() {
        canContinue = GameSession.resume(store: store, saves: saves, log: nil) != nil
    }

    // MARK: Saves

    func savedGames() -> [SavedGameSummary] { saves.list() }

    func saveGame(named name: String, replacing: UUID?) throws {
        guard let session else { throw SaveError.noGame }
        try session.saveGame(named: name, replacing: replacing)
    }

    /// Opens the save as a new session, so a changed logging setting applies to it.
    func loadGame(id: UUID) throws {
        session = try GameSession.load(id: id, store: store, saves: saves, log: Self.makeLog())
        route = .game
    }

    func deleteSavedGame(id: UUID) throws { try saves.remove(id: id) }

    var suggestedSaveName: String {
        guard let state = session?.state else { return "Charter" }
        let lanes = state.laneOwner.count
        return "\(state.players.count) Houses, \(lanes) lane\(lanes == 1 ? "" : "s") anchored"
    }

    // MARK: Diagnostic logging

    /// A replay log when the Settings toggle is on (read when a game starts, loads or resumes).
    private static func makeLog() -> ReplayLog? {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.diagnosticLogging) else { return nil }
        return try? ReplayLog(directory: AppFolders.logs)
    }
}

struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            #if DEBUG
            if let route = DebugRoute.current {
                route.view
            } else {
                screens
            }
            #else
            screens
            #endif
        }
        .frame(minWidth: WindowSize.minimum.width, minHeight: WindowSize.minimum.height)
        // A dark title bar and dark sheets, so no light strip frames the starfield.
        .preferredColorScheme(.dark)
        .alert("Abandon the current charter?",
               isPresented: Binding(get: { model.confirmingNewCharter }, set: { model.confirmingNewCharter = $0 })) {
            Button("Abandon", role: .destructive) {
                InteractionSound.activate.play()
                model.openSetup()
            }
            Button("Cancel", role: .cancel) { InteractionSound.activate.play() }
        } message: {
            Text("Beginning a new Charter replaces it. Named saves are kept.")
        }
        .sheet(item: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { sheet in
            switch sheet {
            case .save: SaveGameSheet(model: model)
            case .load: LoadGameSheet(model: model)
            }
        }
    }

    @ViewBuilder private var screens: some View {
        switch model.route {
        case .title:
            TitleView(canContinue: model.canContinue, onContinue: model.continueCharter,
                      onNewCharter: model.requestNewCharter)
        case .setup:
            SetupView(onBegin: { model.startNewCharter(houses: $0, hazards: $1, kinds: $2) },
                      onBack: model.closeSetup)
        case .game:
            if let session = model.session {
                GameView(session: session, onNewCharter: model.requestNewCharter, onTitle: model.returnToTitle)
                    .id(ObjectIdentifier(session))
            } else {
                TitleView(canContinue: model.canContinue, onContinue: model.continueCharter,
                          onNewCharter: model.requestNewCharter)
            }
        }
    }
}

/// The File menu. Replacing the new item also removes New Window, so a second window cannot
/// write to the same autosave.
private struct GameCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Charter") {
                InteractionSound.activate.play()
                model.requestNewCharter()
            }
                .keyboardShortcut("n")
            Button("Load Game\u{2026}") {
                InteractionSound.activate.play()
                model.sheet = .load
            }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Game\u{2026}") {
                InteractionSound.activate.play()
                model.sheet = .save
            }
                .keyboardShortcut("s")
                .disabled(!model.canSave)
        }
    }
}

@main
struct SpanningTheStarsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Spanning the Stars") { RootView(model: model) }
            .defaultWindowPlacement { _, context in
                // The placement size is the whole window, title bar included: 1512x900 of content
                // plus the title bar, but never larger than the screen's visible area.
                let visible = context.defaultDisplay.visibleRect.size
                let size = CGSize(width: min(WindowSize.preferred.width, visible.width),
                                  height: min(WindowSize.preferred.height + WindowSize.titleBar, visible.height))
                return WindowPlacement(size: size)
            }
            .windowResizability(.contentMinSize)
            .commands { GameCommands(model: model) }
        Settings { SettingsView() }
    }
}

/// The packaged .app gets its Dock icon from AppIcon.icns. `swift run` has no bundle, so the icon
/// is set from the SVG once launching finishes (setting it earlier is overwritten).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        NSApp.setActivationPolicy(.regular)
        if let url = ResourceLocator.url("AppIcon.svg"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}
