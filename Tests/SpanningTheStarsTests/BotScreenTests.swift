import Foundation
import Testing
@testable import SpanningTheStars
@testable import StarsCore

@MainActor @Suite struct BotScreenTests {
    private func player(_ house: House, _ kind: PlayerKind) -> PlayerState {
        PlayerState(house: house, kind: kind, hand: Hand(), contracts: [])
    }

    // MARK: Setup

    @Test func kindsFollowSeatOrderAndDefaultToHuman() {
        #expect(SetupView.kinds(for: [.varn, .meridian, .paleFleet],
                                choices: [.paleFleet: .bot(.admiral), .solace: .bot(.cadet)])
                == [.human, .human, .bot(.admiral)])
    }

    @Test func pickerOffersHumanAndFiveLevels() {
        #expect(SetupView.kindOptions.map(\.label) == ["Human", "Cadet (Level 1)", "Pilot (Level 2)",
            "Navigator (Level 3)", "Commander (Level 4)", "Admiral (Level 5)"])
        #expect(SetupView.kindOptions.map(\.kind)
                == [.human, .bot(.cadet), .bot(.pilot), .bot(.navigator), .bot(.commander), .bot(.admiral)])
    }

    @Test func startingWithKindsCreatesBotSeats() {
        let model = AppModel(store: InMemoryGameStore(), saves: InMemorySaveSlots())
        model.startNewCharter(houses: [.varn, .solace], hazards: false, kinds: [.human, .bot(.pilot)])
        #expect(model.route == .game)
        #expect(model.session?.state.players.map(\.kind) == [.human, .bot(.pilot)])
    }

    @Test func startingWithoutKindsSeatsOnlyHumans() {
        let model = AppModel(store: InMemoryGameStore(), saves: InMemorySaveSlots())
        model.startNewCharter(houses: [.varn, .solace], hazards: false)
        #expect(model.session?.state.players.map(\.kind) == [.human, .human])
    }

    // MARK: Bot turns

    @Test func bannerNamesTheHouseAndLevel() {
        #expect(GameView.botBanner(player(.ashkar, .bot(.navigator))) == "House Ashkar (Navigator) is plotting its move")
        #expect(GameView.botBanner(player(.ashkar, .human)) == nil)
    }

    @Test func onlyTheCodexAndLogTakeInputOnABotTurn() {
        let playing = BoardInput(screen: .playing)
        #expect(playing.play && playing.reference)
        let handoff = BoardInput(screen: .handoff(player: 0))
        #expect(!handoff.play && !handoff.reference)
        let botTurn = BoardInput(screen: .botTurn(player: 1))
        #expect(!botTurn.play && botTurn.reference)
        let finalReview = BoardInput(screen: .finalReview)
        #expect(!finalReview.play && !finalReview.reference)
    }

    @Test func chipTitleAddsTheLevelForABot() {
        #expect(HouseChip.title(for: player(.ashkar, .human)) == "House Ashkar")
        #expect(HouseChip.title(for: player(.ashkar, .bot(.navigator))) == "House Ashkar · Navigator")
    }

    @Test func botHandsStayHidden() {      // Review Focus 5
        var hand = Hand()
        hand.add(.resource(.red), 3)
        let playerWithCards = PlayerState(house: .solace, kind: .bot(.cadet), hand: hand, contracts: [1, 2])
        #expect(Secrets(screen: .botTurn(player: 1), player: playerWithCards).shown == false)
        #expect(Secrets(screen: .botTurn(player: 1), player: playerWithCards).hand == Hand())
    }
}
