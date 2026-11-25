import SwiftUI
import StarsCore

/// The main game screen: House status across the top, the star map with the Exchange and Concord
/// Log beside it, and the active House's hand and contracts along the bottom. Contract choices
/// replace the right column, the hand-off covers the blurred board, and the Final Review replaces
/// the board once the Charter closes. On a bot's turn the board stays in view; only the Codex
/// button and the Concord Log take input.
///
/// Everything a player does goes through `session.perform`. Controls are enabled from one
/// `TurnOptions` value, derived from `legalActions` once per game state.
struct GameView: View {
    let session: GameSession
    var onNewCharter: () -> Void = {}
    var onTitle: () -> Void = {}

    @State private var options = TurnOptionsCache()
    @State private var reviews = FinalReviewCache()
    @State private var claimLane: Int?
    /// The error showing when the claim sheet opened; the sheet shows only errors raised after that.
    @State private var errorBeforeClaim: RuleError?
    @State private var showCodex = false

    var body: some View {
        let state = session.state
        let map = session.engine.map
        Group {
            if session.screen == .finalReview {
                EndGameView(state: state, map: map, review: reviews.review(for: state, map: map),
                            onNewCharter: onNewCharter, onTitle: onTitle)
            } else {
                ZStack {
                    let handoff = if case .handoff = session.screen { true } else { false }
                    board(state: state, map: map)
                        .blur(radius: handoff ? 22 : 0)
                        .allowsHitTesting(BoardInput(screen: session.screen).reference)
                        .accessibilityHidden(handoff)
                    if case .handoff(let seat) = session.screen {
                        HandoffView(house: state.players[seat].house,
                                    setupPick: ContractPickView.pick(for: state.phase).map { $0.minimum == 2 } ?? false,
                                    lines: ConcordLog.recent(session.recentEvents, players: state.players, map: map),
                                    resumed: session.recentEvents.isEmpty && !state.log.isEmpty,
                                    reveal: session.reveal)
                    }
                }
            }
        }
        .sheet(isPresented: $showCodex) { CodexView() }
        .onChange(of: session.screen) { _, screen in
            if screen != .playing { claimLane = nil }
        }
    }

    private func board(state: GameState, map: GalaxyMap) -> some View {
        let turn = options.options(for: state, engine: session.engine)
        let playing = session.screen == .playing
        let input = BoardInput(screen: session.screen)
        let player = state.players[state.current]
        let secrets = Secrets(screen: session.screen, player: player)
        let pick = playing ? ContractPickView.pick(for: state.phase) : nil

        return VStack(spacing: GameLayout.gap) {
            StatusBar(state: state, onCodex: { showCodex = true })
                .frame(height: GameLayout.statusHeight)

            Group {
                if let pick {
                    ContractPickView(state: state, map: map, offered: pick.offered, minimum: pick.minimum,
                                     perform: session.perform)
                        .id(pick.offered)
                } else {
                    HStack(alignment: .top, spacing: GameLayout.gap) {
                        ZStack(alignment: .top) {
                            StarMapView(map: map, state: state, hazards: state.config.frontierHazards,
                                        highlight: claimLane.map { [$0] } ?? [],
                                        onSelectLane: { id in
                                            if playing {
                                                errorBeforeClaim = session.lastError
                                                claimLane = id
                                            }
                                        })
                            ErrorToast(error: session.lastError)
                                .padding(.top, 14)
                            if case .botTurn = session.screen, let text = GameView.botBanner(player) {
                                BotBanner(text: text)
                                    .padding(.top, 14)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(input.play)

                        VStack(spacing: GameLayout.gap) {
                            TurnPanel(player: player, phase: state.phase, options: turn,
                                      enabled: playing, perform: session.perform)
                                .allowsHitTesting(input.play)
                            ExchangeView(state: state, options: turn, enabled: playing, perform: session.perform)
                                .allowsHitTesting(input.play)
                            LogView(log: state.log, players: state.players, map: map)
                        }
                        .frame(width: GameLayout.sideWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .top, spacing: GameLayout.gap) {
                HandTray(hand: secrets.hand, hidden: !secrets.shown)
                    .frame(maxWidth: .infinity)
                ContractsPanel(player: player, map: map, hidden: !secrets.shown)
                    .frame(width: GameLayout.sideWidth)
            }
            .frame(height: GameLayout.bottomHeight)
            .allowsHitTesting(input.play)
        }
        .padding(GameLayout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SpaceBackground().ignoresSafeArea() }
        .overlay {
            if playing, pick == nil, let id = claimLane {
                // 600 wide: a 3-chip Spectrum payment row needs about 508 pt inside the padding.
                ModalBackdrop(width: 600, onDismiss: { claimLane = nil }) {
                    ClaimSheet(lane: map.lane(id), state: state, engine: session.engine, options: turn,
                               perform: session.perform,
                               error: session.lastError == errorBeforeClaim ? nil : session.lastError,
                               close: { claimLane = nil })
                }
            }
        }
    }
}

extension GameView {
    /// Banner text for a bot's turn, for example "House Ashkar (Navigator) is plotting its move".
    /// Nil for a human.
    static func botBanner(_ player: PlayerState) -> String? {
        guard case .bot(let level) = player.kind else { return nil }
        return "\(player.house.displayName) (\(level.displayName)) is plotting its move"
    }
}

/// Builds the Final Review once per final state, not on every render.
@MainActor final class FinalReviewCache {
    private var state: GameState?
    private var value: FinalReview?
    private(set) var computations = 0

    func review(for state: GameState, map: GalaxyMap) -> FinalReview {
        if let value, state == self.state { return value }
        let review = FinalReview(state: state, map: map)
        self.state = state
        value = review
        computations += 1
        return review
    }
}

/// The privacy rule for the board: the active House's hand and contracts show only on the
/// `.playing` screen, never during a hand-off or the final review.
struct Secrets: Equatable {
    /// True when the hand and contracts may be drawn.
    let shown: Bool
    /// The hand to draw: empty unless `shown`.
    let hand: Hand

    init(screen: GameSession.Screen, player: PlayerState) {
        shown = screen == .playing
        hand = shown ? player.hand : Hand()
    }
}

/// The input rule for the board: which parts take clicks and scrolling on a given screen.
struct BoardInput: Equatable {
    /// The map, the turn panel, the Exchange, the hand tray and the Contracts panel.
    let play: Bool
    /// The status bar's Codex button and the Concord Log.
    let reference: Bool

    init(screen: GameSession.Screen) {
        play = screen == .playing
        switch screen {
        case .playing, .botTurn: reference = true
        case .handoff, .finalReview: reference = false
        }
    }
}

/// Fixed sizes around the map, chosen to fit a 1280x800 window; the map takes all remaining space.
enum GameLayout {
    static let margin: CGFloat = 12
    static let gap: CGFloat = 10
    static let statusHeight: CGFloat = 54
    /// The Exchange, log and contracts column.
    static let sideWidth: CGFloat = 344
    /// The hand and contracts tray.
    static let bottomHeight: CGFloat = 168
    static let handCard = CGSize(width: 70, height: 105)
    static let exchangeCard = CGSize(width: 56, height: 84)
}

// MARK: - Turn options

/// What the active House may do right now, read from the engine's `legalActions`.
struct TurnOptions: Equatable {
    var canDrawBlind = false
    /// Exchange slots that may be taken.
    var exchangeSlots: Set<Int> = []
    var canDrawContracts = false
    /// Legal payments per lane id, in the engine's order (fewest Cores first).
    var payments: [Int: [Payment]] = [:]
    /// Nothing else is possible, so the House must hold position.
    var mustPass = false

    init(actions: [Action]) {
        for action in actions {
            switch action {
            case .drawBlind: canDrawBlind = true
            case .drawExchange(let slot): exchangeSlots.insert(slot)
            case .drawContracts: canDrawContracts = true
            case let .claim(laneID, payment): payments[laneID, default: []].append(payment)
            case .pass: mustPass = true
            case .keepContracts: break
            }
        }
    }
}

/// Recomputes `TurnOptions` only when the game state changes.
@MainActor final class TurnOptionsCache {
    private var state: GameState?
    private var value = TurnOptions(actions: [])
    private(set) var computations = 0

    func options(for state: GameState, engine: GameEngine) -> TurnOptions {
        if state != self.state {
            self.state = state
            value = TurnOptions(actions: engine.legalActions(state))
            computations += 1
        }
        return value
    }
}

// MARK: - Turn panel

/// The active House and what it may do this turn.
private struct TurnPanel: View {
    let player: PlayerState
    let phase: TurnPhase
    let options: TurnOptions
    let enabled: Bool
    let perform: (Action) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtImage(.house(player.house))
                .frame(width: 40, height: 40)
                .shadow(color: Palette.houseRim(player.house).opacity(0.6), radius: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(player.house.displayName)'s turn")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.dimText)
                    .fixedSize(horizontal: false, vertical: true)
                if options.mustPass {
                    Button("Hold position") { perform(.pass) }
                        .buttonStyle(BrassButtonStyle())
                        .accessibilityLabel("Hold position")
                        .disabled(!enabled)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .panel()
    }

    private var prompt: String {
        if options.mustPass {
            return "No lane, card or contract is open to your House. Hold position to end the turn."
        }
        switch phase {
        case .drawingSecondCard:
            return "Take one more Resource Card. A face-up Quantum Core cannot be the second pick."
        case .choosingContracts:
            return "Choose which Concord Contracts to accept."
        default:
            return "Take 2 Resource Cards, anchor a lane on the map, or draw Concord Contracts."
        }
    }
}

// MARK: - Bot banner

/// Says which bot is deciding, at the top of the map.
private struct BotBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "cpu")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Palette.hex(0x0A0F24, opacity: 0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.brass.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            .allowsHitTesting(false)
    }
}

// MARK: - Error toast

/// Shows the engine's last refusal for a few seconds.
private struct ErrorToast: View {
    let error: RuleError?
    @State private var shown: RuleError?
    /// Kept after `shown` clears, so the text does not vanish while the toast fades out.
    @State private var message = ""

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Palette.hex(0x2A0E12, opacity: 0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hex(0xE0443E, opacity: 0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            .opacity(shown == nil ? 0 : 1)
            .offset(y: shown == nil ? -8 : 0)
            .animation(.easeOut(duration: 0.25), value: shown)
            .allowsHitTesting(false)
            .accessibilityHidden(shown == nil)
            .onChange(of: error, initial: true) { _, new in
                if let new { message = new.themedMessage }
                shown = new
            }
            .task(id: shown) {
                guard shown != nil else { return }
                try? await Task.sleep(for: .seconds(3.5))
                if !Task.isCancelled { shown = nil }
            }
    }
}

extension RuleError {
    /// Player-facing wording for an engine refusal.
    var themedMessage: String {
        switch self {
        case .wrongPhase: "That move is not open right now."
        case .slotEmpty: "That Exchange slot is empty."
        case .coreMustBeFirst: "A face-up Quantum Core can only be your first pick."
        case .noCardsToDraw: "The Supply Depot and Salvage Heap are empty."
        case .laneTaken: "That lane is already anchored."
        case .laneClosed: "Lane closed: its twin is anchored."
        case .ownsTwin: "Your House already anchors the twin of this corridor."
        case .notEnoughBeacons: "Not enough beacons for this lane."
        case .invalidPayment: "Those Resource Cards cannot pay for this lane."
        case .cardsNotInHand: "Those Resource Cards are not in your hand."
        case .contractDeckEmpty: "No Concord Contracts remain to draw."
        case .mustKeepAtLeast(let n): "Accept at least \(n) Concord Contract\(n == 1 ? "" : "s")."
        case .notOffered: "That Concord Contract was not offered."
        case .passNotAllowed: "Your House still has a move, so it cannot hold position."
        case .gameOver: "The Charter Era has closed."
        }
    }
}

// MARK: - Shared styling

extension View {
    /// A dark translucent panel with a brass hairline.
    func panel(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.hex(0x0A0F24, opacity: 0.84), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.brass.opacity(0.28), lineWidth: 1))
    }
}

/// Small caps section title in brass.
struct PanelTitle: View {
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Palette.brass)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.dimText)
            }
        }
    }
}

struct BrassButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Palette.hex(0x161006) : Palette.text)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Palette.brass) : AnyShapeStyle(Color.white.opacity(0.08)))
            )
            .overlay(Capsule().strokeBorder(Palette.brass.opacity(prominent ? 0 : 0.5), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// Dims the board behind a centered card. Clicking the backdrop calls `onDismiss` when given.
private struct ModalBackdrop<Content: View>: View {
    var width: CGFloat = 560
    var onDismiss: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss?() }
            content
                .padding(24)
                .frame(width: width)
                .background(Palette.hex(0x0B1024, opacity: 0.97), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.brass.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
        }
    }
}
