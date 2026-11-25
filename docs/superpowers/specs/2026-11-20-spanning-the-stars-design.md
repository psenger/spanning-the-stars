# Spanning the Stars: Design

Date: 2026-11-20. Status: approved. Rules text lives in [docs/RULES.md](../../RULES.md).

## Context

At the start of this design, the repo held a README describing rival shipping houses competing to connect star systems. The goal is a native macOS game, sized for a 14" MacBook Pro (default 1512x982 pt), played pass-the-laptop by 2 to 5 human players. A heuristic AI player is a later addition, so the rules engine must be UI-independent and able to enumerate legal actions and simulate.

The game has 33 Concord Contracts. Each House draws four at setup and keeps at least two.

### Decisions made with the user

| Topic | Decision |
|---|---|
| Toolkit | Swift + SwiftUI, native macOS |
| Hand-off | Full-screen privacy screen between turns; 2 to 5 houses |
| Edge cases | Use the Concord Rulings in Section 10 of the rules |
| Expansion lanes | Optional Frontier Hazards toggle adds Spectrum and Gravity Well Lanes |
| Veil Nebula lanes | **Spectrum Lanes**: pay N cards of N *different* colors (Cores fill any) |
| Ember Belt lanes | **Gravity Assist**: pay 1 fewer card than length, spend 1 extra Anchor Beacon |

### Calls I made (correct any of these)

- **Build system:** Swift Package (library `StarsCore` + executable `SpanningTheStars`), plus `scripts/bundle.sh` that wraps the release build into a `.app` with Info.plist. Avoids a generated `.xcodeproj`; still opens in Xcode via `Package.swift`. Target macOS 26 (installed: Xcode 27.2, Swift 6.4).
- **Art:** hand-authored SVG files (36, fixed names and viewBoxes in the plan's Art Contract), loaded at runtime with `NSImage`, so they stay vector. A dedicated art subagent makes placeholders first, then final art in parallel with the engine work (user request, for speed). Lanes, beacon slots and text are drawn in SwiftUI. Each resource has a unique symbol as well as a color (color-blind support). No external dependencies.
- **Map:** original star map. The scoring table covers lanes up to length 6.
- **Rules doc:** `docs/RULES.md`, also bundled and shown in-app as "The Concord Codex".
- **AI seam:** model only (`PlayerKind.human` now, `.ai` later). No AI UI in v1.
- **Pale Fleet (black) beacons** render dark with a pale rim glow so they read on a dark space map.

## Saves and diagnostics (added 2026-11-20 at user request)

- Ported from `../saltmarsh-isles`: up to 5 named saves (names up to 30 characters, with the save date); when all 5 are used the player replaces one or deletes one; nothing is deleted automatically; a trash can with confirmation on each save; loading asks for confirmation; no saving after the game ends; File menu Command-N, Command-O, Command-S.
- Autosave after every move, separate from the 5; the title screen offers Continue.
- Hot-seat privacy: a loaded or resumed game always opens on the hand-off screen.
- Diagnostic logging (setting, off by default): a JSON Lines replay log per game (seed, config, every action with the acting House and its result, plus a full state snapshot on load or resume), mirrored to the macOS Console. The engine is deterministic, so a log replays the exact game. Newest 20 files kept; "Show logs in Finder" in Settings.

## Approaches considered

1. **Swift + SwiftUI (chosen).** Native, Retina-sharp vector drawing, rules engine as a pure Swift module with fast unit tests. Mac only.
2. Godot 4: easier particle/animation work, but clumsier logic testing and a less native app.
3. TypeScript + Tauri: fastest iteration and browser portability, more moving parts.

## Architecture

```
spanning-the-stars/
  Package.swift
  Sources/StarsCore/          # pure Swift, no SwiftUI import
    Model/   ResourceColor, Card, StarSystem, Lane, Contract, House, PlayerState, GameState
    Engine/  GameEngine (apply(action) -> events, legalActions(for:)), Action, RuleError
    Rules/   Payment (paymentOptions(lane, hand, variant)), Scoring, Connectivity, GreatSpan
    Map/     GalaxyMap.swift (systems, lanes, contracts as Swift literals), MapValidator
    Support/ SeededRNG (deterministic shuffles for tests and future AI simulation)
  Sources/SpanningTheStars/   # SwiftUI app
    App.swift, Theme/ (palette, fonts, CardArt), Views/ (Title, Setup, ContractPick,
    Handoff, Game, StarMapCanvas, TradeExchange, HandTray, ClaimSheet, Log, EndGame, Codex)
    Resources/RULES.md (copied from docs)
  Tests/StarsCoreTests/
  scripts/bundle.sh
  docs/RULES.md
  docs/superpowers/specs/2026-11-20-spanning-the-stars-design.md
```

Key design points:
- `GameState` is a value type (`struct`, `Codable`, `Sendable`). `GameEngine.apply(_:to:)` validates, mutates, and returns public events for the log. Same code path for humans and future AI.
- A turn in progress is explicit state: `TurnPhase = .awaitingAction | .drawingSecondCard(firstWasBlind) | .choosingContracts(drawn:[Contract], minKeep:Int) | .setupContracts(playerIndex)`. This makes the "Core must be first card" and "keep at least N" rules enforceable.
- `legalActions(for:)` enumerates every legal action (including each distinct payment for a claim). The future heuristic AI scores these.
- Contract completion: union-find over a house's claimed lanes. Great Span: DFS over edges (each lane used at most once, cities revisitable) per house.
- Controller seam: `enum PlayerKind { case human /* case ai(Heuristic) later */ }` on each seat.

## Theme Glossary

| Term | Meaning |
|---|---|
| House | A shipping company with its own color. Varn Industrial is red, Solace Trust blue, Meridian Collective green, House Ashkar yellow, and The Pale Fleet black. |
| Star System | A location on the galaxy map |
| Hyperspace Lane | A connection between adjacent star systems |
| Open-Space Lane | A gray lane that accepts any single resource color |
| High-Traffic Corridor | A pair of lanes between the same star systems |
| Anchor Beacon | A piece placed when anchoring a lane. Each House starts with 45. |
| Resource Card | A card used to pay for a lane |
| Quantum Core | A wild Resource Card |
| Exchange | The five face-up Resource Cards |
| Supply Depot / Salvage Heap | The Resource Card deck and discard pile |
| Concord Contract | A goal to connect two specified star systems |
| Concord Standing | A House's score |
| Great Span Award | A 10-point award for the longest continuous span |
| Close of the Charter Era | The end of the game, followed by the Final Review |
| Spectrum Lane / Gravity Well Lane | Frontier Hazards lanes in the Veil Nebula and Ember Belt, respectively |

Resources (8 x 12 + 14 Cores = 110):

| Color | Resource | Symbol |
|---|---|---|
| Red | Plasma Fuel | flame |
| Purple | Crystal Lattice | hexagon / diamond |
| Black | Dark-Matter Ballast | concentric void circle |
| White | Hull Alloy | shield plate |
| Blue | Coolant Ice | snowflake |
| Green | Bio-Gel | leaf / cell |
| Yellow | Solar Sails | sun |
| Orange | Fusion Ore | ore cube |
| Wild | Quantum Core | atom, iridescent gradient |

## The Galaxy Map

Map space 1000x620 units, scaled to the map viewport. Constraints, enforced by `MapValidatorTests`:
- 36 star systems, about 80 lanes (about 12 High-Traffic Corridors), lengths 1 to 6, graph connected, no lanes crossing.
- Color usage balanced across the 8 colors; Open-Space (gray) lanes about 20% of track.
- **Silent Expanse**: empty void at the map center; only a few length 5 to 6 lanes cross it.
- **Core Worlds**: dense cluster of short lanes (1 to 3), most corridors here.
- **Shattered Rim**: outer arc, long lanes (4 to 6).
- **Veil Nebula** (north-east): 6 lanes flagged `spectrum`, length 2 to 4, never doubled, each with a base color used when the variant is off.
- **Ember Belt** (south-east): 6 lanes flagged `gravityWell`, length 2 to 5, never doubled, base color for variant-off.
- 33 Concord Contracts. Value = shortest path d (in beacons) + floor(max(0, d - 12) / 4). Spread roughly 4 to 22; about 6 "long-haul" contracts at 17+. Each has a flavor line (e.g. "Kessra's ore must reach the shipyards at Vantor Reach").

Proposed systems (names editable):
- Core Worlds (9): Concordia Prime, Vantor Reach, Halcyon, Aurelis, Bastion, Lumen Gate, Ostara, Corvane, Solace Spire
- Shattered Rim (11): Thessaly, Farhold, Last Light, Kythera Drift, Morrow's Edge, Varga Deep, Sable Point, Ironmouth, Ashkar Sands, Pale Harbor, Wraithmere
- Veil Nebula (8): Shroud, Iridia, Mistral Haven, Paleglow, Seraphine, Echo, Lantern, Velvet Reach
- Ember Belt (8): Kessra, Forgeholm, Cinderfall, Pyrrhus, Slagstar, Brimstone, Tallow, Meridian Fields

## Screen Layout (responsive: fills the window at any size from 1280x800 to full screen; designed first for 1512x945)

```
+----------------------------------------------------------------------------+
| [Varn 34 * 31b 7c 3k] [Solace 28 ...] [Meridian ...]   Round 9   [Codex]   |
+----------------------------------------------------+-----------------------+
|                                                    |  THE EXCHANGE         |
|                                                    |  [ ][ ][ ][ ][ ]      |
|               STAR MAP  (~1150 x 650)              |  [Supply Depot 62]    |
|  hover lane: cost, length, points                  |  [Contracts 21]       |
|  click lane: open Claim sheet                      |  -------------------  |
|                                                    |  Concord Log          |
+----------------------------------------------------+-----------------------+
| HAND: [Plasma x3][Ice x2][Core x1]...       | CONTRACTS: [Kessra->Vantor 9 ✓]|
+----------------------------------------------------------------------------+
```

Hand-off screen: full-screen starfield, "Hand the console to House Ashkar", last turn's public log, "Reveal my hand" button. Shown before each turn and before each setup contract pick. The map and public info stay visible; the hand and contracts are hidden.

## Implementation Steps

After this plan is approved: write the spec doc (the Approaches and Decisions above), commit, then invoke `superpowers:writing-plans` for task-level detail. Use TDD for StarsCore. Commits carry no Co-Authored-By trailer (user's global CLAUDE.md).

1. **Docs.** `docs/RULES.md` (Appendix below) and spec doc. Verify: renders; user reads.
2. **Scaffold.** `Package.swift`, empty targets, `swift build` and `swift test` green.
3. **Model + deck.** Cards (110), seeded shuffle, setup (4 cards, 45 beacons, Exchange with Core reset, 4 contracts per house). Tests: counts, reset rule, reset-stops house rule.
4. **Draw action.** Blind and Exchange draws, Core-first rule, second card, reshuffle the Salvage Heap, empty depot. Tests for each rule line.
5. **Claim action.** Payment options (color, open-space, Cores), beacon limit, corridor rules (same house; 2 to 3 players closes the twin), scoring table. Tests.
6. **Contracts action.** Draw 3 (or fewer), keep 1+, return to bottom; setup keep 2+. Tests.
7. **End and scoring.** Trigger at 0 to 2 beacons, final turns, contract completion, Great Span with loops and ties, tiebreakers, pass when stuck. Tests incl. the classic loop-path case.
8. **Frontier Hazards variant.** Spectrum payment enumeration, Gravity Assist cost and beacon spend. Tests.
9. **Galaxy map data + validator.** Coordinates, lanes, contracts; validator tests; contract values computed and checked.
10. **Fuzz test.** 500 seeded games of random legal actions for 2 to 5 houses: always terminates; card conservation (110); beacon accounting; scores equal the recomputed totals. This doubles as the harness for the future AI.
11. **UI foundation.** Theme, CardArt for 9 card types, StarMapCanvas (systems, segmented lanes, corridors offset, claimed beacons in house colors, region nebula tints, hazard glyphs).
12. **Game flow UI.** Title, Setup (2 to 5 houses, variant toggle), ContractPick, Handoff, Game screen, ClaimSheet (choose payment), Log, final-round banner.
13. **End game UI.** Contract reveal, score tally, Great Span highlight, winner and tiebreak explanation.
14. **Codex.** Bundled RULES.md rendered in a sheet.
15. **Bundle + playtest.** `scripts/bundle.sh` builds `Spanning the Stars.app`.

## Verification

- `swift test`: all rule, map, variant, and fuzz tests pass.
- `swift run SpanningTheStars` and the bundled `.app` launch at 1512x982 with no clipping or scrolling; full screen works.
- Manual playthrough: a 2-house game to completion (variant off), and a 3-house game with Frontier Hazards on. Check the privacy screen hides the hand every turn, corridor closing at 2 to 3 players, the final-round trigger, and the end-screen totals against a hand count.
- Screenshots of each screen via cmux-cua for the user to review.
