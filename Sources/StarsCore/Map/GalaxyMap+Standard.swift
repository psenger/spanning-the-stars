/// The standard galaxy map: 36 systems, the lanes between them, and the 33 Concord Contracts.
///
/// Coordinates sit in a 1000x620 space that matches the map backdrop art. The Core Worlds lie
/// west of center, the Veil Nebula to the north-east, the Ember Belt to the south-east, and the
/// Shattered Rim around the edge. The Silent Expanse, a circle at (520, 310) with radius 110, holds
/// no systems and is crossed only by three long bridges. Lane ids are array indices; twin lanes
/// (High-Traffic Corridors) sit next to each other. Hazards apply only when the variant is on.
public extension GalaxyMap {
    static let standard: GalaxyMap = {
        func sys(_ id: String, _ name: String, _ region: Region, _ x: Double, _ y: Double) -> StarSystem {
            StarSystem(id: id, name: name, region: region, x: x, y: y)
        }
        func lane(_ id: Int, _ a: String, _ b: String, _ length: Int, _ color: LaneColor,
                  _ hazard: Hazard = .none, twin: Int? = nil) -> Lane {
            Lane(id: id, a: a, b: b, length: length, color: color, hazard: hazard, twinID: twin)
        }

        let systems = [
            // Core Worlds
            sys("concordia-prime", "Concordia Prime", .coreWorlds, 310, 310),
            sys("aurelis", "Aurelis", .coreWorlds, 290, 225),
            sys("halcyon", "Halcyon", .coreWorlds, 205, 262),
            sys("bastion", "Bastion", .coreWorlds, 215, 350),
            sys("corvane", "Corvane", .coreWorlds, 200, 435),
            sys("ostara", "Ostara", .coreWorlds, 290, 395),
            sys("vantor-reach", "Vantor Reach", .coreWorlds, 368, 243),
            sys("lumen-gate", "Lumen Gate", .coreWorlds, 390, 320),
            sys("solace-spire", "Solace Spire", .coreWorlds, 370, 405),
            // Shattered Rim
            sys("wraithmere", "Wraithmere", .shatteredRim, 75, 60),
            sys("farhold", "Farhold", .shatteredRim, 225, 65),
            sys("thessaly", "Thessaly", .shatteredRim, 70, 240),
            sys("pale-harbor", "Pale Harbor", .shatteredRim, 75, 420),
            sys("ashkar-sands", "Ashkar Sands", .shatteredRim, 120, 570),
            sys("varga-deep", "Varga Deep", .shatteredRim, 310, 580),
            sys("sable-point", "Sable Point", .shatteredRim, 505, 540),
            sys("kythera-drift", "Kythera Drift", .shatteredRim, 400, 95),
            sys("morrows-edge", "Morrow's Edge", .shatteredRim, 560, 50),
            sys("ironmouth", "Ironmouth", .shatteredRim, 650, 312),
            sys("last-light", "Last Light", .shatteredRim, 945, 318),
            // Veil Nebula
            sys("shroud", "Shroud", .veilNebula, 660, 135),
            sys("iridia", "Iridia", .veilNebula, 745, 95),
            sys("mistral-haven", "Mistral Haven", .veilNebula, 850, 80),
            sys("paleglow", "Paleglow", .veilNebula, 925, 150),
            sys("seraphine", "Seraphine", .veilNebula, 800, 170),
            sys("echo", "Echo", .veilNebula, 715, 195),
            sys("lantern", "Lantern", .veilNebula, 632, 220),
            sys("velvet-reach", "Velvet Reach", .veilNebula, 870, 240),
            // Ember Belt
            sys("kessra", "Kessra", .emberBelt, 635, 405),
            sys("forgeholm", "Forgeholm", .emberBelt, 715, 445),
            sys("cinderfall", "Cinderfall", .emberBelt, 860, 405),
            sys("pyrrhus", "Pyrrhus", .emberBelt, 935, 480),
            sys("slagstar", "Slagstar", .emberBelt, 800, 480),
            sys("brimstone", "Brimstone", .emberBelt, 690, 525),
            sys("tallow", "Tallow", .emberBelt, 770, 565),
            sys("meridian-fields", "Meridian Fields", .emberBelt, 880, 555),
        ]

        let lanes = [
            // Silent Expanse bridges
            lane(0, "vantor-reach", "lantern", 6, .color(.green)),
            lane(1, "lumen-gate", "ironmouth", 6, .open),
            lane(2, "solace-spire", "kessra", 6, .open),
            // Core Worlds
            lane(3, "aurelis", "vantor-reach", 2, .color(.blue)),
            lane(4, "vantor-reach", "lumen-gate", 2, .color(.purple), twin: 5),
            lane(5, "vantor-reach", "lumen-gate", 2, .color(.white), twin: 4),
            lane(6, "concordia-prime", "lumen-gate", 2, .color(.orange), twin: 7),
            lane(7, "concordia-prime", "lumen-gate", 2, .color(.red), twin: 6),
            lane(8, "ostara", "solace-spire", 2, .color(.red), twin: 9),
            lane(9, "ostara", "solace-spire", 2, .color(.green), twin: 8),
            lane(10, "concordia-prime", "aurelis", 2, .color(.purple), twin: 11),
            lane(11, "concordia-prime", "aurelis", 2, .color(.white), twin: 10),
            lane(12, "concordia-prime", "ostara", 2, .color(.yellow), twin: 13),
            lane(13, "concordia-prime", "ostara", 2, .color(.black), twin: 12),
            lane(14, "lumen-gate", "solace-spire", 2, .color(.blue)),
            lane(15, "bastion", "ostara", 2, .color(.white)),
            lane(16, "halcyon", "bastion", 2, .color(.yellow)),
            lane(17, "aurelis", "halcyon", 3, .color(.black)),
            lane(18, "corvane", "ostara", 3, .open),
            lane(19, "bastion", "corvane", 2, .color(.purple), twin: 20),
            lane(20, "bastion", "corvane", 2, .color(.red), twin: 19),
            lane(21, "concordia-prime", "bastion", 3, .color(.blue)),
            // Rim west and south
            lane(22, "wraithmere", "farhold", 4, .open),
            lane(23, "wraithmere", "thessaly", 5, .color(.yellow)),
            lane(24, "halcyon", "thessaly", 4, .color(.orange), twin: 25),
            lane(25, "halcyon", "thessaly", 4, .color(.blue), twin: 24),
            lane(26, "thessaly", "pale-harbor", 5, .open),
            lane(27, "bastion", "pale-harbor", 4, .color(.green)),
            lane(28, "corvane", "ashkar-sands", 4, .color(.white)),
            lane(29, "pale-harbor", "ashkar-sands", 4, .color(.purple)),
            lane(30, "ashkar-sands", "varga-deep", 5, .open),
            lane(31, "corvane", "varga-deep", 5, .color(.yellow)),
            lane(32, "solace-spire", "sable-point", 5, .open),
            lane(33, "varga-deep", "sable-point", 5, .color(.white)),
            lane(34, "sable-point", "brimstone", 5, .color(.red)),
            lane(35, "sable-point", "kessra", 5, .color(.purple)),
            // Rim north
            lane(36, "aurelis", "farhold", 4, .color(.green)),
            lane(37, "farhold", "kythera-drift", 4, .color(.blue)),
            lane(38, "vantor-reach", "kythera-drift", 4, .color(.black)),
            lane(39, "kythera-drift", "morrows-edge", 4, .color(.purple)),
            lane(40, "morrows-edge", "shroud", 3, .color(.orange)),
            // Veil Nebula
            lane(41, "shroud", "echo", 2, .open),
            lane(42, "echo", "lantern", 2, .color(.blue), twin: 43),
            lane(43, "echo", "lantern", 2, .color(.white), twin: 42),
            lane(44, "seraphine", "echo", 2, .color(.black), twin: 45),
            lane(45, "seraphine", "echo", 2, .color(.green), twin: 44),
            lane(46, "shroud", "lantern", 2, .color(.red), .spectrum),
            lane(47, "shroud", "iridia", 3, .color(.yellow), .spectrum),
            lane(48, "iridia", "mistral-haven", 3, .color(.orange), .spectrum),
            lane(49, "mistral-haven", "seraphine", 3, .color(.white)),
            lane(50, "mistral-haven", "paleglow", 3, .color(.black), .spectrum),
            lane(51, "seraphine", "velvet-reach", 3, .color(.yellow), .spectrum),
            lane(52, "paleglow", "velvet-reach", 3, .color(.orange), .spectrum),
            lane(53, "iridia", "echo", 3, .open),
            // Ironmouth hub
            lane(54, "ironmouth", "lantern", 3, .color(.black), twin: 55),
            lane(55, "ironmouth", "lantern", 3, .color(.orange), twin: 54),
            lane(56, "ironmouth", "kessra", 3, .color(.blue), twin: 57),
            lane(57, "ironmouth", "kessra", 3, .color(.yellow), twin: 56),
            lane(58, "ironmouth", "forgeholm", 4, .color(.green)),
            lane(59, "ironmouth", "velvet-reach", 6, .color(.red)),
            // East rim
            lane(60, "last-light", "velvet-reach", 3, .open),
            lane(61, "last-light", "paleglow", 4, .color(.red)),
            lane(62, "last-light", "cinderfall", 3, .color(.black)),
            lane(63, "last-light", "pyrrhus", 4, .color(.orange)),
            lane(64, "velvet-reach", "cinderfall", 4, .color(.purple)),
            // Ember Belt
            lane(65, "forgeholm", "brimstone", 2, .color(.blue)),
            lane(66, "brimstone", "tallow", 2, .color(.orange), .gravityWell),
            lane(67, "kessra", "forgeholm", 2, .color(.red), twin: 68),
            lane(68, "kessra", "forgeholm", 2, .color(.orange), twin: 67),
            lane(69, "slagstar", "tallow", 3, .open),
            lane(70, "forgeholm", "slagstar", 3, .color(.black), twin: 71),
            lane(71, "forgeholm", "slagstar", 3, .color(.white), twin: 70),
            lane(72, "pyrrhus", "meridian-fields", 3, .color(.yellow), .gravityWell),
            lane(73, "cinderfall", "slagstar", 3, .color(.green), .gravityWell),
            lane(74, "cinderfall", "pyrrhus", 3, .color(.white), .gravityWell),
            lane(75, "slagstar", "meridian-fields", 3, .color(.blue), .gravityWell),
            lane(76, "tallow", "meridian-fields", 3, .color(.purple)),
            lane(77, "kessra", "brimstone", 3, .color(.black), .gravityWell),
        ]

        let contracts: [(a: String, b: String, flavor: String)] = [
            ("halcyon", "meridian-fields", "Halcyon's crowded habitats need a standing grain line from Meridian Fields."),
            ("pale-harbor", "shroud", "The salvage crews of Pale Harbor want a way into the wrecks hidden in the Shroud."),
            ("kythera-drift", "slagstar", "Kythera Drift's broken habitats need Slagstar steel to rebuild."),
            ("aurelis", "last-light", "The scholars of Aurelis want a charted route to Last Light, the edge of the known stars."),
            ("corvane", "echo", "Corvane's archivists are paying for a secure link to the deep-space relay at Echo."),
            ("wraithmere", "lantern", "Wraithmere went silent a century ago, and the Concord wants a lane from Lantern to learn why."),
            ("solace-spire", "pyrrhus", "The Solace Trust wants its financiers on the ground at the volcano mines of Pyrrhus."),
            ("ashkar-sands", "brimstone", "House Ashkar wants Brimstone sulfur flowing to the markets of Ashkar Sands."),
            ("farhold", "seraphine", "Farhold's frozen colonists need Seraphine's medicine before the long winter."),
            ("lumen-gate", "paleglow", "The beacon foundries of Lumen Gate run on crystal harvested near Paleglow."),
            ("morrows-edge", "brimstone", "Morrow's Edge needs Brimstone fuel to keep its shields lit."),
            ("ostara", "slagstar", "Ostara's terraformers have ordered heavy machinery from Slagstar."),
            ("sable-point", "velvet-reach", "The silk traders of Velvet Reach want a southern market at Sable Point."),
            ("bastion", "lantern", "Bastion's garrison needs a patrol route out to the frontier beacon at Lantern."),
            ("halcyon", "ironmouth", "Ironmouth's ore haulers want a standing contract with the foundries of Halcyon."),
            ("echo", "tallow", "The refinery crews of Tallow need their orders relayed straight from Echo."),
            ("kessra", "vantor-reach", "Kessra's ore must reach the shipyards at Vantor Reach."),
            ("thessaly", "concordia-prime", "The refugee world of Thessaly needs medical supply access to the Core Worlds."),
            ("pale-harbor", "varga-deep", "The miners of Varga Deep depend on water shipments from Pale Harbor."),
            ("iridia", "kythera-drift", "Iridia's prism glass must reach the greenhouse domes of Kythera Drift."),
            ("last-light", "brimstone", "The outpost at Last Light needs Brimstone reactor fuel to stay lit."),
            ("corvane", "sable-point", "Corvane's banks want a vault route to the frontier claims at Sable Point."),
            ("shroud", "kessra", "Kessra's survey drones need clear passage to chart the Shroud."),
            ("concordia-prime", "halcyon", "The Concord council wants a fast courier lane between Concordia Prime and Halcyon."),
            ("ostara", "ashkar-sands", "Spice from Ashkar Sands must reach the dinner tables of Ostara."),
            ("echo", "mistral-haven", "Mistral Haven's storm stations report through the relay at Echo."),
            ("forgeholm", "cinderfall", "Forgeholm needs Cinderfall coal to keep its forges burning."),
            ("ironmouth", "velvet-reach", "Velvet Reach wants armor plate from the smelters at Ironmouth."),
            ("seraphine", "last-light", "Seraphine's healers have promised aid to the outpost at Last Light."),
            ("lumen-gate", "sable-point", "The prospectors of Sable Point need supply runs from Lumen Gate."),
            ("kessra", "tallow", "Tallow's fuel tanks stand empty until Kessra's ore arrives."),
            ("bastion", "pale-harbor", "Pale Harbor needs Bastion's patrols to keep raiders off its docks."),
            ("lantern", "morrows-edge", "The keepers of Lantern need a supply line to the lonely station at Morrow's Edge."),
        ]

        return GalaxyMap(systems: systems, lanes: lanes, contractPairs: contracts)
    }()
}
