import Foundation
import Testing
@testable import StarsCore

@Suite struct CardsTests {
    @Test func deckHas110Cards() {
        let deck = standardDeck()
        #expect(deck.count == 110)
        for c in ResourceColor.allCases {
            #expect(deck.filter { $0 == .resource(c) }.count == 12)
        }
        #expect(deck.filter { $0 == .core }.count == 14)
    }

    @Test func seededRNGIsDeterministic() {
        var a = SeededRNG(seed: 42), b = SeededRNG(seed: 42), c = SeededRNG(seed: 43)
        let d = standardDeck()
        #expect(d.shuffled(using: &a) == d.shuffled(using: &b))
        var a2 = SeededRNG(seed: 42)
        #expect(d.shuffled(using: &a2) != d.shuffled(using: &c))
    }

    @Test func rngSurvivesCoding() throws {
        var rng = SeededRNG(seed: 7)
        _ = rng.next(); _ = rng.next()
        var copy = try JSONDecoder().decode(SeededRNG.self, from: JSONEncoder().encode(rng))
        for _ in 0..<5 { #expect(rng.next() == copy.next()) }
    }

    @Test func handRemoveThrowsWhenShort() {
        var hand = Hand()
        hand.add(.resource(.red))
        #expect(throws: RuleError.cardsNotInHand) {
            try hand.remove(Payment([.resource(.red): 2]))
        }
        #expect(hand.count(.resource(.red)) == 1)
    }

    @Test func tinyMapContractValues() {
        let map = GalaxyMap.tiny
        #expect(shortestPath(map, "A", "D") == 6)
        #expect(map.contracts[1].value == 6)
    }
}
