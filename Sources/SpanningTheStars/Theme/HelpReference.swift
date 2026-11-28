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

    struct GuideSection {
        let id: String
        let title: String
        let steps: [String]
    }

    static let gameplayIntro = "Build a network of hyperspace lanes and finish with the most Concord Standing (points). "
        + "You score when you claim a lane. At the end, your private contracts earn or cost points depending on which systems you connected."

    static let gameplay = [
        GuideSection(id: "start", title: "Start a game", steps: [
            "Click **New Charter**. For a first game, keep the two selected Houses and set one **Played by** menu to **Cadet (Level 1)**. "
                + "Leave **Frontier Hazards** off and click **Begin the Charter**.",
            "If the game pauses at a handoff, click **Reveal my hand** when it is your turn."
        ]),
        GuideSection(id: "contracts", title: "Pick your first contracts", steps: [
            "Each contract names two star systems and shows a point value. Hover over a card to find its systems on the map. "
                + "For your first game, look for pairs that are close together or share a system.",
            "Select at least two of the four cards, then click **Accept 2 Contracts** if you chose two. You complete a contract by joining its "
                + "two systems with a continuous chain of lanes you own. You can build that chain over several turns."
        ]),
        GuideSection(id: "turn", title: "Take one action per turn", steps: [
            "**Draw Resource Cards.** Click a face-up card in **The Exchange** or draw a hidden card from the **Supply Depot**. "
                + "You normally take two cards and can mix the two sources. A face-up Quantum Core must be your first pick "
                + "and uses the whole turn. A Core drawn from the Depot counts as one draw.",
            "**Anchor a lane.** Click the row of slots between two systems. The lane details show its cost and which cards you can pay. "
                + "A colored lane needs one matching card per slot. A gray lane lets you choose one color for the whole payment. "
                + "Quantum Cores can stand in for any color. Choose a payment and click **Anchor lane**.",
            "**Draw new contracts.** Click the **Concord Contracts** deck below the Exchange. Draw up to three cards, keep at least one, "
                + "and confirm. This takes your turn. Check how much you can still build before committing to another route."
        ]),
        GuideSection(id: "board", title: "Check your progress", steps: [
            "The highlighted House at the top is taking its turn. The star counts your current points. The beacon symbol counts "
                + "your beacons in stock. The stacked cards and scroll count your Resource Cards and contracts.",
            "Your cards are along the bottom. Hover over a contract in the bottom-right panel to light up its two systems. "
                + "A checkmark means your lanes already connect them."
        ]),
        GuideSection(id: "score", title: "Finish and score", steps: [
            "When a House ends its turn with two or fewer Anchor Beacons left, every House gets one more turn, including the House that triggered it.",
            "The Final Review adds fulfilled contract values and subtracts unfulfilled values from your lane points. The longest "
                + "continuous span earns the **Great Span Award** worth 10 points. The House with the highest final Standing wins."
        ])
    ]

    enum FirstLane {
        static let anchor = "example"
        static let title = "Try it: anchor Kessra–Forgeholm"
        static let cardArt = "card-red"
        static let cardName = "Plasma Fuel"
        static let from = "Kessra"
        static let to = "Forgeholm"
        static let cost = 2
        static let illustrationDescription = "Two red Plasma Fuel cards pay for the two red lane slots between Kessra and Forgeholm."
        static let steps = [
            "Collect two red **Plasma Fuel** cards. On a later turn, find **Kessra** and **Forgeholm** in the lower-right part of the map.",
            "With Frontier Hazards off, click the **red** lane between them. Choose the two Plasma Fuel cards and click **Anchor lane (+2)**.",
            "Your House fills both slots with Anchor Beacons, scores two Standing, and ends its turn. You now own that connection "
                + "and can use it as part of a contract route."
        ]
    }

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
