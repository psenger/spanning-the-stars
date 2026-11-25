import Testing
@testable import StarsCore

private let tiny = GalaxyMap.tiny

private func hand(_ cards: [Card: Int]) -> Hand {
    var h = Hand()
    for (card, n) in cards { h.add(card, n) }
    return h
}

@Suite struct CardNeedsTests {
    @Test func neededColorScoresAboveUnneeded() {
        // Wanted lane A-B, red 2.
        let empty = CardNeeds(lanes: [tiny.lane(0)], hand: Hand(), hazards: false)
        #expect(empty.value(of: .resource(.red)) == 0.5)
        #expect(empty.value(of: .resource(.blue)) == 0)
        let oneShort = CardNeeds(lanes: [tiny.lane(0)], hand: hand([.resource(.red): 1]), hazards: false)
        #expect(oneShort.value(of: .resource(.red)) == 1)   // the card completes the lane
    }

    @Test func satisfiedLaneNeedsNothing() {
        let needs = CardNeeds(lanes: [tiny.lane(0)], hand: hand([.resource(.red): 2]), hazards: false)
        #expect(needs.value(of: .resource(.red)) == 0)
    }

    @Test func coreHelpsWhileAnythingIsUnpaid() {
        let lanes = [tiny.lane(0), tiny.lane(1)]
        let unpaid = CardNeeds(lanes: lanes, hand: hand([.resource(.red): 2]), hazards: false)
        #expect(unpaid.value(of: .core) > 0)   // the open lane B-C is still one card short
        let paid = CardNeeds(lanes: lanes, hand: hand([.resource(.red): 3]), hazards: false)
        #expect(paid.value(of: .core) == 0)
        #expect(CardNeeds(lanes: [], hand: Hand(), hazards: false).value(of: .core) == 0)
    }

    @Test func openLaneWantsTheColorHeldMost() {
        // Wanted lane B-C, open 3.
        let needs = CardNeeds(lanes: [tiny.lane(1)], hand: hand([.resource(.green): 2]), hazards: false)
        #expect(needs.value(of: .resource(.green)) == 1)
        #expect(needs.value(of: .resource(.green)) > needs.value(of: .resource(.red)))
        #expect(needs.value(of: .resource(.red)) == 0)
    }

    @Test func aHeldCoreCountsTowardEveryLane() {
        let needs = CardNeeds(lanes: [tiny.lane(0)], hand: hand([.resource(.red): 1, .core: 1]), hazards: false)
        #expect(needs.value(of: .resource(.red)) == 0)
        #expect(needs.value(of: .core) == 0)
    }

    @Test func hazardsChangeWhatALaneNeeds() {
        // E-F, orange 3, Gravity Well: one card fewer with hazards on.
        let orange = hand([.resource(.orange): 1])
        #expect(CardNeeds(lanes: [tiny.lane(5)], hand: orange, hazards: false).value(of: .resource(.orange)) == 0.5)
        #expect(CardNeeds(lanes: [tiny.lane(5)], hand: orange, hazards: true).value(of: .resource(.orange)) == 1)
        // D-E, purple 3, Spectrum: distinct colors with hazards on.
        let purple = hand([.resource(.purple): 2])
        let plain = CardNeeds(lanes: [tiny.lane(4)], hand: purple, hazards: false)
        #expect(plain.value(of: .resource(.purple)) == 1 && plain.value(of: .resource(.red)) == 0)
        let spectrum = CardNeeds(lanes: [tiny.lane(4)], hand: purple, hazards: true)
        #expect(spectrum.value(of: .resource(.purple)) == 0 && spectrum.value(of: .resource(.red)) == 0.5)
    }
}
