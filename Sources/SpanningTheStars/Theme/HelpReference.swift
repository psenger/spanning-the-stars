/// Shared by the in-game Concord Codex and the native Help book generator.
enum HelpReference {
    struct CardEntry {
        let art: String
        let title: String
        let detail: String

        init(_ art: String, _ title: String, _ detail: String) {
            self.art = art
            self.title = title
            self.detail = detail
        }
    }

    static let gameplay = [
        "Choose two to five Houses and assign each to a human or AI. Keep at least two of the four starting Concord Contracts.",
        "On your turn, requisition Resource Cards, anchor one lane, or accept new Concord Contracts. "
            + "Use the Exchange or Supply Depot to draw cards, and click a lane to see its cost and choose a payment.",
        "Use your own anchored lanes to connect the two systems on each contract. Hover over a held contract "
            + "to see its systems on the map. Keep contracts private when passing the game to another player.",
        "When a House ends its turn with two or fewer Anchor Beacons, every House gets one final turn. Add lane "
            + "points, score contracts, and award the Great Span bonus. The House with the highest Concord Standing wins."
    ]

    static let cards = [
        resource("red", "Plasma Fuel"),
        resource("purple", "Crystal Lattice"),
        resource("black", "Dark-Matter Ballast"),
        resource("white", "Hull Alloy"),
        resource("blue", "Coolant Ice"),
        resource("green", "Bio-Gel"),
        resource("yellow", "Solar Sails"),
        resource("orange", "Fusion Ore"),
        CardEntry("card-core", "Quantum Core",
                  "A wild Resource Card that substitutes for any color. Taking it face up from the Exchange "
                    + "uses both draws. A Core drawn blind counts as one draw."),
        CardEntry("contract-front", "Concord Contract",
                  "Connect the two named systems using your own lanes. Add the printed Standing if you fulfill the contract "
                    + "or subtract it if you leave it unfulfilled."),
        CardEntry("card-back-resource", "Resource Card back",
                  "Draw a card blind from the Supply Depot when requisitioning resources."),
        CardEntry("contract-back", "Concord Contract back",
                  "Draw contracts from this deck when you choose the Accept Contracts action."),
        CardEntry("award-great-span", "Great Span Award",
                  "Earn 10 Standing for the longest continuous span of your own lanes. All Houses tied for the longest span earn it.")
    ]

    private static func resource(_ color: String, _ title: String) -> CardEntry {
        CardEntry("card-\(color)", title,
                  "The \(color) Resource Card pays for \(color) lanes and for an open-space lane paid with a single color.")
    }
}

enum HelpHouseStat: CaseIterable {
    case standing, beacons, resources, contracts

    var symbol: String {
        switch self {
        case .standing: "star.fill"
        case .beacons: "dot.radiowaves.up.forward"
        case .resources: "rectangle.portrait.on.rectangle.portrait.fill"
        case .contracts: "scroll.fill"
        }
    }

    var title: String {
        switch self {
        case .standing: "Concord Standing"
        case .beacons: "Anchor Beacons remaining"
        case .resources: "Resource Cards in hand"
        case .contracts: "Concord Contracts held"
        }
    }

    var detail: String {
        switch self {
        case .standing: "Points earned by anchoring lanes so far. Contracts and the Great Span Award are scored in the Final Review."
        case .beacons: "Beacons still in stock. Ending your turn with two or fewer starts the final round."
        case .resources: "How many Resource Cards this House holds, including Quantum Cores."
        case .contracts: "How many binding contracts this House holds, including fulfilled and unfulfilled ones."
        }
    }
}
