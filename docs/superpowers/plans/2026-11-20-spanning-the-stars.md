# Spanning the Stars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS pass-the-laptop board game for 2 to 5 players who claim hyperspace lanes and fulfill Contracts. Include the optional Frontier Hazards variant.

**Architecture:** A pure-Swift rules library (`StarsCore`) holds the value-type game state, a validating engine, scoring, the galaxy map and an observable session that drives the privacy hand-off. A SwiftUI executable (`SpanningTheStars`) renders it with code-drawn vector art. The engine exposes `legalActions` so a heuristic AI can be added later without UI changes.

**Tech Stack:** Swift 6.4, Swift Package Manager, SwiftUI, Observation, Swift Testing (`import Testing`). macOS 26. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-20-spanning-the-stars-design.md`; rules text `docs/RULES.md` (the source of truth for every rule below).

## Global Constraints

- `// swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 language mode (strict concurrency).
- `StarsCore` must not import SwiftUI or AppKit. `Foundation`, `Observation` and `os` (for `Logger`) only.
- Saves: up to 5 named saves (names clipped to 30 characters) plus one autosave that does not count toward the 5; nothing is deleted automatically. Diagnostic replay logging is a setting, off by default; logs keep the newest 20 files. Storage: `~/Library/Application Support/SpanningTheStars/` with `autosave/`, `Saves/`, `Logs/`.
- No third-party packages. Art ships as hand-authored SVG files in `Sources/SpanningTheStars/Resources/Art/`, loaded at runtime with `NSImage(contentsOf:)` and shown with `Image(nsImage:).resizable()` (verified on this machine: macOS loads SVG as a vector `_NSSVGImageRep`, no asset catalog needed). Lanes, beacon slots and text stay drawn in SwiftUI/`Canvas`.
- Art file names, viewBoxes and safe zones are fixed by the **Art Contract** below. Placeholders and final art share them exactly, so swapping art never changes code.
- Responsive layout (user decision 2026-11-21): the game fills the whole window at every size (min 1280x800, and full screen) with no letterboxing; the background fills edge to edge; fixed-size chrome (status bar, right column, bottom tray) and a flexible star map that keeps its own aspect ratio inside the remaining space. Designed first for 1512x945 (14" MacBook Pro default, minus menu bar). Nothing clips; only the contracts list and the log scroll inside their panels.
- All player-facing copy uses the theme vocabulary from the spec's Theme Glossary (House, Star System, Lane, Anchor Beacon, Resource Card, Quantum Core, Exchange, Supply Depot, Salvage Heap, Concord Contract, Concord Standing, Great Span Award). Never "train", "ticket", "route", "city", "locomotive" in UI text.
- Counts: 45 beacons per House; 8 colors x 12 cards + 14 Quantum Cores = 110; 33 contracts; 4 cards and 4 contracts dealt (keep at least 2); draw 3 contracts (keep at least 1); Exchange of 5; reset at 3+ Cores; end trigger at 0, 1 or 2 beacons; Great Span Award 10.
- Lane points: 1→1, 2→2, 3→4, 4→7, 5→10, 6→15.
- Commit messages: no `Co-Authored-By` trailer (user's global instruction).
- Writing style in docs and copy: no em-dashes, no section sign.

## Review Focus

1. **Deadlock.** All lanes claimed or unaffordable, the Depot, Heap and Contract deck empty, nobody at 2 or fewer beacons: the game must still end. Expected: if every House passes in one full round, the Final Review begins. (New ruling; user to confirm, then add to `docs/RULES.md` Section 10.) Test in Task 7.
2. **Thin Exchange.** Depot and Heap empty so Exchange slots are empty (`nil`): drawing, the second-card check and the UI must cope. Expected: empty slots are not selectable; if no second card exists the turn ends. Test in Task 4.
3. **Hand-off leaks.** A secret hand or contract shown to the wrong player during setup picks or after a turn. Expected: every turn-ending action and every setup pick puts the session in `.handoff`; the log never names a blind-drawn card or a kept contract. Test in Task 12.
4. **Beacon shortfall at the end.** A House with 3 beacons trying a length-3 Gravity Well lane (needs 4). Expected: not offered, and `apply` throws `.notEnoughBeacons`. Test in Task 8.
5. **Big hands on a small screen.** 40+ cards in hand and 10+ contracts at 1512x945 with 5 Houses. Expected: hand groups by card type with counts; the contract list scrolls inside its panel; nothing clips. Check in Task 15.

---

## Execution Order (subagent-driven, parallel tracks)

```
Task 1 (scaffold) ──> Task A1 (placeholder SVGs, minutes) ──┬──> Tasks 2-9, 11, 12  (rules engine, main tree)
                                                            ├──> Task 10            (galaxy map, worktree "map")
                                                            └──> Task A2            (final SVG art, worktree "art", background)
merge "map" before Task 11 (the fuzz test needs .standard) · merge "art" whenever it lands
Task 12 ──> Task 12A (saves) ──> Task 12B (replay log), main tree
Task A3 (app icon, worktree "icon") runs any time; merge before Task 16
Tasks 13-16 (UI) use whatever SVGs are present: placeholders until A2 merges ──> Task 17
```

- Task A1 runs right after Task 1, so every UI task can reference real files from the start.
- Task A2 runs in the background in its own git worktree and touches only `Resources/Art/*.svg` and `Tests/StarsCoreTests/ArtTests.swift`, so its merge is conflict-free. It does not block any task.
- Task 10 depends only on Task 1 and touches only `Map/` and `MapTests.swift`, so it also runs in its own worktree alongside Tasks 2 to 9.
- Each task still gets its reviewer before it is marked done; Task A2 is reviewed from its contact sheet (see below).

## Art Contract

Directory: `Sources/SpanningTheStars/Resources/Art/`. Every file is `<svg xmlns="http://www.w3.org/2000/svg" viewBox="...">` with the exact viewBox below.

Allowed SVG features (the subset `NSSVGImageRep` renders reliably): `path`, `rect`, `circle`, `ellipse`, `line`, `polygon`, `polyline`, `g`, `defs`, `linearGradient`, `radialGradient`, `clipPath`, `transform`, `opacity`, `fill-opacity`, `stroke-*`. Forbidden: `<image>`, `<script>`, `<style>`, `<filter>`/`filter=`, `<foreignObject>`, external `href`, embedded fonts. `<text>` is allowed in placeholders only.

| Group | Files | viewBox | Content and safe zones |
|---|---|---|---|
| Resource cards | `card-red`, `card-purple`, `card-black`, `card-white`, `card-blue`, `card-green`, `card-yellow`, `card-orange`, `card-core` | `0 0 200 300` | Full card face incl. rounded corners (rx 14). Resource motif centered in y 40 to 220. Keep y 236 to 290 calm and dark: SwiftUI draws the resource name there. |
| Card backs | `card-back-resource`, `contract-back` | `0 0 200 300` | Concord seal back designs. |
| Contract face | `contract-front` | `0 0 200 300` | Frame only. Keep empty: y 18 to 110 (system names, drawn by SwiftUI), y 120 to 250 (flavor text), circle at (166, 36) r 24 (value badge). |
| Award | `award-great-span` | `0 0 200 300` | Great Span Award card; "10" may be drawn as paths. |
| Resource icons | `icon-red` ... `icon-orange`, `icon-core` | `0 0 64 64` | Silhouette symbols: plasma flame, crystal lattice hexagon, dark-matter void rings, hull-alloy plate, coolant snowflake, bio-gel cell, solar sail, fusion-ore cube, quantum-core atom. Each readable at 20 px and distinct by shape alone (color-blind support). |
| House emblems | `house-varn`, `house-solace`, `house-meridian`, `house-ashkar`, `house-palefleet` | `0 0 128 128` | Circular crests in house color: Varn hammer and gear, Solace coin and star, Meridian wheat ring, Ashkar dune and crescent, Pale Fleet chevron with pale rim. |
| System markers | `star-coreworlds`, `star-shatteredrim`, `star-veilnebula`, `star-emberbelt` | `0 0 48 48` | Glowing star or planet glyph per region; transparent background. |
| Hazard glyphs | `glyph-spectrum`, `glyph-gravity` | `0 0 32 32` | Prism with rainbow split; gravity-well rings. |
| Backgrounds | `bg-starfield` | `0 0 1512 945` | Deep-space field for title and hand-off screens. |
| | `map-backdrop` | `0 0 1000 620` | Region tints in the map coordinate space (zones below). No stars brighter than the system markers; no lines that look like lanes. |
| | `title-emblem` | `0 0 512 512` | Game emblem: a ring of anchored lanes around a star. No lettering. |

36 files in total. Map zones (shared by `map-backdrop.svg` and Task 10): Silent Expanse circle center (520, 310) r 110, darkest; Core Worlds ellipse center (250, 320) rx 170 ry 150, warm gold haze; Veil Nebula ellipse center (780, 150) rx 190 ry 120, violet and teal cloud; Ember Belt ellipse center (780, 480) rx 190 ry 120, orange-red dust; Shattered Rim is everything else, cold blue-gray.

## File Map

```
Package.swift
Sources/StarsCore/
  Model/Cards.swift          ResourceColor, Card, Hand, standardDeck()
  Model/Board.swift          Region, StarSystem, LaneColor, Hazard, Lane, Contract, GalaxyMap
  Model/House.swift          House, PlayerKind, PlayerState
  Model/GameState.swift      GameConfig, TurnPhase, GameState
  Model/Action.swift         Action, Payment, RuleError, GameEvent
  Support/SeededRNG.swift    SplitMix64 RNG (Codable)
  Engine/GameEngine.swift    newGame, apply, legalActions (dispatch only)
  Engine/Engine+Draw.swift   card drawing, Exchange refill and reset
  Engine/Engine+Claim.swift  claim validation and application
  Engine/Engine+Contracts.swift
  Engine/Engine+Turn.swift   end of turn, final round, pass, deadlock
  Rules/Payments.swift       paymentOptions
  Rules/Scoring.swift        lanePoints, contract completion, greatSpan, finalScores, ranking
  Map/GalaxyMap+Standard.swift   the real map (systems, lanes, contract pairs + flavor)
  Map/MapGeometry.swift      shortestPath, segment intersection helpers
  Session/GameSession.swift  @Observable screen state machine
  Session/SavedGames.swift   5 named save slots (ported from saltmarsh-isles)
  Session/GameStore.swift    autosave store
  Session/ReplayLog.swift    diagnostic JSONL replay log
Sources/SpanningTheStars/
  App.swift
  Theme/Palette.swift  Theme/CardArt.swift
  Views/ (TitleView, SetupView, HandoffView, ContractPickView, GameView, StatusBar,
          StarMapView, ExchangeView, HandTray, ContractsPanel, ClaimSheet, LogView,
          EndGameView, CodexView, SavedGamesSheets, SettingsView)
  Theme/ArtAsset.swift       enum of the 36 art names + ArtImage view (Task A1)
  Resources/RULES.md         copied from docs/RULES.md by bundle.sh and by a test check
  Resources/Art/*.svg        36 files per the Art Contract
Tests/StarsCoreTests/
  TestMaps.swift  CardsTests  SetupTests  DrawTests  ClaimTests  ContractTests
  TurnTests  ScoringTests  HazardTests  MapTests  FuzzTests  SessionTests  ArtTests
scripts/art-contact-sheet.swift   renders every SVG to PNG + one contact sheet
scripts/bundle.sh
```

---

### Task 1: Package scaffold and core model

**Files:**
- Create: `Package.swift`, `Sources/StarsCore/Model/*.swift`, `Sources/StarsCore/Support/SeededRNG.swift`, `Sources/StarsCore/Map/MapGeometry.swift` (`shortestPath` only), `Sources/SpanningTheStars/App.swift` (placeholder window), `Tests/StarsCoreTests/CardsTests.swift`, `Tests/StarsCoreTests/TestMaps.swift`, `.gitignore` (`.build/`, `*.app`, `.swiftpm/`)

**Interfaces (Produces):**
```swift
public enum ResourceColor: String, CaseIterable, Codable, Sendable { case red, purple, black, white, blue, green, yellow, orange
  public var resourceName: String }   // "Plasma Fuel", "Crystal Lattice", "Dark-Matter Ballast", "Hull Alloy", "Coolant Ice", "Bio-Gel", "Solar Sails", "Fusion Ore"
public enum Card: Hashable, Codable, Sendable { case resource(ResourceColor), core }
public struct Hand: Codable, Sendable, Equatable { public var counts: [Card: Int]
  public func count(_ c: Card) -> Int; public var total: Int
  public mutating func add(_ c: Card, _ n: Int = 1); public mutating func remove(_ p: Payment) throws(RuleError) }
public func standardDeck() -> [Card]   // 110 cards
public struct SeededRNG: RandomNumberGenerator, Codable, Sendable { public init(seed: UInt64) }  // SplitMix64

public enum Region: String, Codable, Sendable, CaseIterable { case coreWorlds, shatteredRim, veilNebula, emberBelt }
public struct StarSystem: Identifiable, Codable, Sendable { public let id: String; name: String; region: Region; x: Double; y: Double }
public enum LaneColor: Hashable, Codable, Sendable { case color(ResourceColor), open }
public enum Hazard: String, Codable, Sendable { case none, spectrum, gravityWell }
public struct Lane: Identifiable, Codable, Sendable { public let id: Int; a: String; b: String; length: Int; color: LaneColor; hazard: Hazard; twinID: Int? }
public struct Contract: Identifiable, Codable, Sendable { public let id: Int; a: String; b: String; value: Int; flavor: String }
public struct GalaxyMap: Sendable { public let systems: [StarSystem]; lanes: [Lane]; contracts: [Contract]
  public init(systems:lanes:contractPairs:[(a: String, b: String, flavor: String)])  // value = d + max(0, d - 12) / 4 with d = shortestPath; ids assigned in order
  public func lane(_ id: Int) -> Lane; public func system(_ id: String) -> StarSystem }
public func shortestPath(_ map: GalaxyMap, _ a: String, _ b: String) -> Int   // Dijkstra on lane length; used by init

public enum House: String, CaseIterable, Codable, Sendable { case varn, solace, meridian, ashkar, paleFleet
  public var displayName: String }   // "Varn Industrial", "The Solace Trust", "Meridian Collective", "House Ashkar", "The Pale Fleet"
public enum PlayerKind: Codable, Sendable { case human }   // .ai added later
public struct PlayerState: Codable, Sendable { public let house: House; kind: PlayerKind
  public var hand: Hand; contracts: [Int]; beacons: Int = 45; score: Int = 0; lanes: [Int] = [] }

public struct GameConfig: Codable, Sendable { public var houses: [House]; frontierHazards: Bool; seed: UInt64 }
public enum TurnPhase: Codable, Sendable, Equatable {
  case setupContracts(offered: [Int]), awaitingAction, drawingSecondCard, choosingContracts(offered: [Int]), gameOver }
public struct GameState: Codable, Sendable {
  public var config: GameConfig; players: [PlayerState]; current: Int; firstPlayer: Int; phase: TurnPhase
  public var depot: [Card]       // top = last
  public var exchange: [Card?]   // always 5 slots
  public var salvage: [Card]
  public var contractDeck: [Int] // top = last, bottom = index 0
  public var pendingOffers: [[Int]]   // setup offers per seat
  public var setupReturns: [Int]
  public var laneOwner: [Int: Int]  // laneID -> player index
  public var finalTurnsRemaining: Int?   // nil until triggered
  public var consecutivePasses: Int
  public var rng: SeededRNG; public var log: [GameEvent] }

public struct Payment: Hashable, Codable, Sendable { public var counts: [Card: Int]; public var total: Int }
public enum Action: Hashable, Codable, Sendable { case drawBlind, drawExchange(slot: Int), claim(laneID: Int, payment: Payment), drawContracts, keepContracts([Int]), pass }
public enum RuleError: Error, Equatable { case wrongPhase, slotEmpty, coreMustBeFirst, noCardsToDraw, laneTaken, laneClosed, ownsTwin, notEnoughBeacons, invalidPayment, cardsNotInHand, contractDeckEmpty, mustKeepAtLeast(Int), notOffered, passNotAllowed, gameOver }
public enum GameEvent: Codable, Sendable, Equatable {
  case drewBlind(player: Int), drewExchange(player: Int, card: Card), exchangeReset,
       claimed(player: Int, laneID: Int, points: Int), keptContracts(player: Int, count: Int),
       passed(player: Int), finalRoundBegan(trigger: Int), gameEnded }
```

`TestMaps.swift` defines `GalaxyMap.tiny`, used by Tasks 3 to 8: systems A to F; lanes: 0 A-B red 2; 1 B-C open 3; 2 C-D blue 1 twin 3; 3 C-D green 1 twin 2; 4 D-E purple 3 spectrum; 5 E-F orange 3 gravityWell; 6 A-F white 6; 7 B-E black 4. Contracts: A-C, A-D, B-F, A-E.

- [x] **Step 1: Write failing tests** in `CardsTests.swift`:
  - `deckHas110Cards`: `standardDeck().count == 110`; each color count 12; `.core` count 14.
  - `seededRNGIsDeterministic`: two `SeededRNG(seed: 42)` shuffles of `standardDeck()` are equal; seed 43 differs.
  - `rngSurvivesCoding`: encode/decode RNG mid-sequence; next 5 values match the original.
  - `handRemoveThrowsWhenShort`: hand with 1 red, removing `Payment([.resource(.red): 2])` throws `.cardsNotInHand`.
  - `tinyMapContractValues`: on `GalaxyMap.tiny`, `shortestPath(A, D) == 6` (A-B 2, B-C 3, C-D 1) and that contract's value is 6.
- [x] **Step 2:** `swift test` fails (types missing).
- [x] **Step 3:** Implement the types above. `Payment.init(_ counts: [Card: Int])` drops zero entries.
- [x] **Step 4:** `swift build && swift test` pass; `swift run SpanningTheStars` opens an empty window.
- [x] **Step 5:** Commit `Scaffold package and core model`.

### Task A1: Placeholder art (runs right after Task 1)

**Files:** Create the 36 files in `Sources/SpanningTheStars/Resources/Art/`, `Sources/SpanningTheStars/Theme/ArtAsset.swift`, `Tests/StarsCoreTests/ArtTests.swift`, `scripts/art-contact-sheet.swift`; modify `Package.swift` (app target `resources: [.copy("Resources/Art")]`).

**Interfaces (Produces):**
```swift
enum ArtAsset: String, CaseIterable { case cardRed = "card-red", ... /* all 36, raw value = file name without .svg */
  static func card(_ c: Card) -> ArtAsset; static func icon(_ c: Card) -> ArtAsset
  static func house(_ h: House) -> ArtAsset; static func star(_ r: Region) -> ArtAsset }
struct ArtImage: View { init(_ asset: ArtAsset) }   // NSImage(contentsOf:) from the Art folder, cached in a static dictionary; .resizable(); missing file → magenta rectangle
```
Art folder lookup: `Bundle.main.resourceURL` SwiftPM resource bundle first, then `Bundle.module` (same rule as `CodexText`, Task 13).

Placeholders: a flat fill in the item's color with a 2-unit border and its file name as `<text>`; cards get a darker band in their text safe zone so the zone is visible.

- [x] **Step 1: Failing test** `ArtTests.allArtFilesExistWithContractViewBox`: a literal table of the 36 names and viewBoxes from the Art Contract; each file at `#filePath`-relative `Sources/SpanningTheStars/Resources/Art/<name>.svg` exists and contains `viewBox="<exact>"`. Also `artUsesOnlyAllowedFeatures`: no file contains `<image`, `<script`, `<style`, `<filter`, `filter=`, `<foreignObject`, `href="http`.
- [x] **Step 2:** FAIL. **Step 3:** Write the placeholders (a small script generating them is fine), `ArtAsset.swift`, and `art-contact-sheet.swift` (`swift scripts/art-contact-sheet.swift <out-dir>`: renders each SVG via `NSImage` to PNG at 2x, plus `contact-sheet.png` in a labeled grid).
- [x] **Step 4:** `swift test` PASS; `swift build` PASS; run the contact sheet into the scratchpad and view it.
- [x] **Step 5:** Commit `Add placeholder art and art loader`.

### Task A2: Final SVG art (background, worktree "art")

**Files:** Replace the 36 SVGs in place; modify `ArtTests.swift` only to add the test below. Touch nothing else.

**Interfaces:** Consumes the Art Contract. Produces the same file names and viewBoxes.

Style direction: painterly-sci-fi in flat vector form: layered gradients, soft glows made from stacked translucent circles (no filters), thin gold Concord linework on card frames, deep navy and black backgrounds, each resource with its own hue family from the spec's resource table. Card faces must stay legible at 70x105 pt in the hand tray. Do not imitate any existing game's art or trade dress.

- [x] **Step 1: Failing test** `finalArtHasNoText`: no art file contains `<text`.
- [x] **Step 2:** FAIL against placeholders.
- [x] **Step 3:** Author the art, group by group (cards, icons, emblems, markers, glyphs, backgrounds). After each group, run `swift scripts/art-contact-sheet.swift <scratch>` and view the PNGs; fix anything that renders blank, clipped or off-center.
- [x] **Step 4:** `swift test` PASS (all ArtTests).
- [x] **Step 5:** Commit per group (`Art: resource cards`, ...). Final report includes the contact sheet path for the reviewer and the user.

### Task A3: App icon and README icon (art agent, worktree "icon")

User request (2026-11-21): an icon for the desktop app (Dock, Finder, app switcher) and an icon for the rebuilt README.

**Files:** Create `Sources/SpanningTheStars/Resources/AppIcon.svg` (master, viewBox `0 0 1024 1024`), `scripts/make-icon.sh`, `docs/images/icon.svg`, `docs/images/icon-256.png`, `docs/images/icon-512.png`. Integration (Info.plist and the running app) happens in Task 16.

Design (controller's call, user may correct): macOS-style icon: rounded-square body (Apple's macOS icon grid: 824x824 body centred in 1024 with corner radius about 185, soft drop shadow in the margin), deep navy field, brass rim, the title-emblem motif (a luminous star ringed by anchored lanes and beacon points) scaled up and simplified so it reads at 16x16. Same palette and line language as the A2 art (`title-emblem.svg` on branch worktree-agent-a8fc74ac00cb47ddb). Same allowed SVG feature list as the Art Contract; no text.

- `scripts/make-icon.sh`: renders the SVG with NSImage (same renderer as the game) to the 10 iconset PNGs (16, 32, 128, 256, 512 at 1x and 2x), builds `build/AppIcon.icns` with `iconutil`, and writes the README PNGs.
- `docs/images/icon.svg`: the same master (GitHub renders SVG in README); the PNGs are fallbacks.
- [x] **Step 1:** Author the SVG; render at 1024, 128, 32 and 16; critique legibility at each size against macOS app icons in the Dock; iterate at least twice.
- [x] **Step 2:** `scripts/make-icon.sh` produces a valid `.icns` (`iconutil` exits 0; `sips -g pixelWidth` on the iconset shows all sizes).
- [x] **Step 3:** Commit `Add app icon and README icon` (stage files by explicit path).

### Task 2: New game setup

**Files:** Create `Engine/GameEngine.swift`, `Engine/Engine+Draw.swift` (refill/reset only), `Tests/StarsCoreTests/SetupTests.swift`.

**Interfaces (Produces):**
```swift
public struct GameEngine: Sendable { public let map: GalaxyMap; public init(map: GalaxyMap)
  public func newGame(_ config: GameConfig) -> GameState
  public func apply(_ action: Action, to state: inout GameState) throws(RuleError) -> [GameEvent]
  public func legalActions(_ state: GameState) -> [Action] }
func refillExchange(_ s: inout GameState) -> [GameEvent]   // internal; fills nil slots, then resets while 3+ cores
func drawFromDepot(_ s: inout GameState) -> Card?           // internal; reshuffles salvage into depot when empty
```

`newGame`: shuffle deck with `config.seed`; deal 4 cards to each player; fill Exchange; shuffle contract ids, deal 4 to each player as offers; `current = 0`, `phase = .setupContracts(offered:)` for player 0; `firstPlayer = Int.random(in:, using: &rng)`.

Exchange reset algorithm (Rules Section 10 ruling): while the Exchange holds 3+ Cores: if the non-Core cards across depot + salvage + exchange number fewer than 3, stop; else move all 5 to salvage, draw 5 (via `drawFromDepot`), emit `.exchangeReset`. Stop after 20 resets as a guard.

- [x] **Step 1: Failing tests:**
  - `setupDealsFourCardsAndFourOffers` (3 houses): each hand total 4; `pendingOffers` has 3 lists of 4 ids; phase `.setupContracts(offered: pendingOffers[0])`; `contractDeck.count == map.contracts.count - 12`.
  - `setupCardConservation`: hands + depot + exchange + salvage == 110.
  - `exchangeResetsOnThreeCores`: state with exchange `[core, core, core, red, blue]` and depot of 10 reds; call `refillExchange` → the exchange holds fewer than 3 Cores, salvage holds the 5 old cards, events include `.exchangeReset`.
  - `exchangeResetStopsWhenImpossible`: exchange of 5 Cores, depot and salvage empty → exchange unchanged, no infinite loop.
  - `beaconsStartAt45`, `scoresStartAt0`.
- [x] **Step 2:** Run, see FAIL.
- [x] **Step 3:** Implement.
- [x] **Step 4:** PASS.
- [x] **Step 5:** Commit `Add game setup and Exchange reset`.

### Task 3: Setup contract picks

**Files:** Create `Engine/Engine+Contracts.swift`, `Tests/StarsCoreTests/ContractTests.swift` (setup part).

`apply(.keepContracts(ids))` in `.setupContracts(offered)`: ids must be a subset of offered (`.notOffered`), count at least 2 (`.mustKeepAtLeast(2)`). Kept go to the player; the rest append to `setupReturns`. Move to the next seat's offer (offers come from `pendingOffers`, dealt in `newGame`). After the last seat: shuffle `setupReturns` with `rng`, insert at the bottom of `contractDeck`, set `current = firstPlayer`, `phase = .awaitingAction`. Emit `.keptContracts(player:count:)`.

- [x] **Step 1: Failing tests:** `setupKeepTwoAdvancesSeat`; `setupKeepOneThrows` (`.mustKeepAtLeast(2)`); `setupKeepUnofferedThrows`; `afterLastSeatPlayStartsAtFirstPlayer` (current == firstPlayer, phase awaitingAction, returned ids at deck indices `0..<returnedCount`).
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add setup contract selection`.

### Task 4: Requisition Resources (drawing cards)

**Files:** Modify `Engine/Engine+Draw.swift`; create `Tests/StarsCoreTests/DrawTests.swift`.

Rules (RULES Section 6 and 10):
- `.drawBlind` in `.awaitingAction`: take `drawFromDepot`; if nil throw `.noCardsToDraw`. Phase → `.drawingSecondCard`.
- `.drawExchange(slot)` in `.awaitingAction`: slot nil → `.slotEmpty`. If the card is `.core`, end the turn immediately. Else phase → `.drawingSecondCard`. Refill after taking.
- In `.drawingSecondCard`: `.drawExchange` of a `.core` throws `.coreMustBeFirst`; any other draw ends the turn.
- After the first draw, if no second draw is legal (depot and salvage empty and every Exchange slot is nil or a Core), end the turn.
- Turn ending calls `endTurn(_:)` from Task 7; until then stub it as "advance `current`, phase `.awaitingAction`".
- Events: `.drewBlind` never includes the card; `.drewExchange` includes it.

- [x] **Step 1: Failing tests:** `blindThenBlindEndsTurn`; `faceUpCoreFirstEndsTurn`; `faceUpCoreSecondThrows`; `blindCoreStillDrawsTwo` (depot top is `.core`, phase after first is `.drawingSecondCard`); `refillAfterPickRevealsCoreNotTakeable` (after first pick the refilled slot is a Core → `legalActions` excludes it); `depotEmptyReshufflesSalvage`; `noCardsAnywhereThrows`; `turnEndsWhenNoSecondCardExists` (Review Focus 2: depot and salvage empty, exchange `[red, nil, nil, nil, nil]`, take red → turn ended); `blindDrawEventHidesCard`.
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add resource drawing rules`.

### Task 5: Payments and Anchor 1 Lane (base rules)

**Files:** Create `Rules/Payments.swift`, `Engine/Engine+Claim.swift`, `Tests/StarsCoreTests/ClaimTests.swift`.

**Interfaces (Produces):**
```swift
public func paymentOptions(for lane: Lane, hand: Hand, hazards: Bool) -> [Payment]  // deduped, sorted by core count ascending then color raw value
public func lanePoints(_ length: Int) -> Int
public func beaconCost(_ lane: Lane, hazards: Bool) -> Int   // length, or length + 1 for gravityWell when hazards
func isClosed(_ lane: Lane, in s: GameState) -> Bool        // twin claimed and players.count <= 3
```
Base payment: colored lane of length L: for k in 0...L, `{color: L-k, core: k}` when the hand has them. Open lane: same for every color, plus all-Core once. (Hazard rules land in Task 8; with `hazards == false` hazard lanes use their `color` normally.)

Claim validation order: phase `.awaitingAction`; owned → `.laneTaken`; closed → `.laneClosed`; twin owned by the same player → `.ownsTwin`; beacons < `beaconCost` → `.notEnoughBeacons`; payment not in `paymentOptions` → `.invalidPayment`. Apply: remove cards to salvage, decrement beacons, add points to `score`, record owner, append lane, emit `.claimed`, end turn.

- [x] **Step 1: Failing tests:** `redLaneWithTwoReds` (+2 points, 43 beacons, 2 cards in salvage); `coresSubstitute` (1 red + 1 core valid); `openLaneAcceptsAnyOneColor` (3 blue valid, 2 blue + 1 green invalid → `.invalidPayment`); `pointsTable` (`lanePoints` for 1...6 == [1,2,4,7,10,15]); `cannotClaimTaken`; `twinClosedWithThreePlayers`; `twinOpenWithFourPlayersButNotSameHouse` (other house can, same house gets `.ownsTwin`); `notEnoughBeacons` (2 beacons, length-3 lane); `optionsDeduped` (hand of 3 cores on an open length-2 lane yields exactly one all-core option among others).
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add lane claiming and payments`.

### Task 6: Accept Contracts (in-game)

**Files:** Modify `Engine/Engine+Contracts.swift`, `ContractTests.swift`.

`.drawContracts` in `.awaitingAction`: deck empty → `.contractDeckEmpty`; pop up to 3 from the top → phase `.choosingContracts(offered:)`. `.keepContracts(ids)` in that phase: subset of offered, at least 1; the rest insert at the bottom (index 0) in given order; end turn. Event `.keptContracts(count:)` only (no ids).

- [x] **Step 1: Failing tests:** `drawThreeKeepOne`; `drawWithTwoLeftOffersTwo`; `keepZeroThrows` (`.mustKeepAtLeast(1)`); `returnedGoToBottom`; `emptyDeckThrows`.
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add contract drawing`.

### Task 7: Turn end, final round, pass and deadlock

**Files:** Create `Engine/Engine+Turn.swift`; replace the Task 4 stub; create `Tests/StarsCoreTests/TurnTests.swift`.

`endTurn(_ s: inout GameState, passed: Bool) -> [GameEvent]`:
1. `consecutivePasses = passed ? consecutivePasses + 1 : 0`.
2. If `finalTurnsRemaining != nil`, decrement it; if it reaches 0 → `.gameOver`, emit `.gameEnded`, return.
3. Else if the current player's `beacons <= 2` → `finalTurnsRemaining = players.count`, emit `.finalRoundBegan(trigger:)`.
4. If `consecutivePasses == players.count` → `.gameOver` (Review Focus 1).
5. Advance `current = (current + 1) % players.count`, phase `.awaitingAction`.

`.pass` is legal only in `.awaitingAction` when `legalActions` holds nothing else, else `.passNotAllowed`. Any action in `.gameOver` throws `.gameOver`.

- [x] **Step 1: Failing tests:** `triggerGivesEveryoneOneMoreTurnIncludingTrigger` (3 players; P1 ends at 2 beacons → exactly 3 further turns P2, P0, P1, then gameOver); `triggerAtExactlyThreeDoesNot`; `passOnlyWhenStuck`; `fullRoundOfPassesEndsGame`; `actionAfterGameOverThrows`.
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add turn sequencing and end of game`.

### Task 8: Frontier Hazards variant

**Files:** Modify `Rules/Payments.swift`; create `Tests/StarsCoreTests/HazardTests.swift`.

With `hazards == true`:
- **Spectrum lane** of length L: every payment of L cards with k Cores (0...L) plus L-k cards of pairwise distinct colors, one each. Enumerate color subsets of size L-k from the colors the hand holds.
- **Gravity Well lane**: payment as a normal lane (its color or open) of length L-1; `beaconCost` = L+1; points `lanePoints(L)`; `PlayerState.lanes` records the lane (span uses L).
- With `hazards == false` both behave as plain lanes of their `color`.

- [x] **Step 1: Failing tests:** `spectrumNeedsDistinctColors` (length-3: red+blue+green valid; red+red+blue not offered); `spectrumCoresFillGaps` (red+core+core valid); `gravityCostsOneFewerCard` (length-3 orange: 2 orange valid, 3 orange not offered); `gravitySpendsExtraBeacon` (45 → 41 beacons, +4 points); `gravityNeedsLengthPlusOneBeacons` (Review Focus 4: 3 beacons, length-3 gravity lane absent from `legalActions`, `apply` throws `.notEnoughBeacons`); `hazardsOffArePlainLanes`.
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add Frontier Hazards variant`.

### Task 9: Final scoring and ranking

**Files:** Create `Rules/Scoring.swift`, `Tests/StarsCoreTests/ScoringTests.swift`.

**Interfaces (Produces):**
```swift
public func isComplete(_ contract: Contract, lanes: [Lane]) -> Bool   // union-find over the player's lanes
public func greatSpan(lanes: [Lane]) -> Int                          // longest trail: DFS over edges, each lane once, systems revisitable, sum of lengths
public struct FinalScore: Sendable, Equatable { public let player: Int; lanePoints: Int; contractsGained: Int; contractsLost: Int; contractsCompleted: Int; span: Int; spanBonus: Int; total: Int }
public func finalScores(_ s: GameState, map: GalaxyMap) -> [FinalScore]
public func ranking(_ scores: [FinalScore]) -> [[Int]]   // groups of player indices, best first; ties broken by completed count, then spanBonus > 0
```
`lanePoints` recomputed from owned lanes (RULES Section 9 step 1), not read from `score`. Every House tied for the longest span gets 10.

- [x] **Step 1: Failing tests:** `contractCompleteOnlyWithOwnLanes`; `spanCountsLoopOnceEach` (a triangle of lengths 2,3,4 with a tail of 1 → 10); `spanTieBothScore`; `unfinishedContractSubtracts`; `tiebreakMostContracts`; `tiebreakSpanHolder`; `fullTieShared` (ranking first group has two players).
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add final scoring and tiebreakers`.

### Task 10: The galaxy map

**Files:** Create `Map/GalaxyMap+Standard.swift`, `Map/MapGeometry.swift`, `Tests/StarsCoreTests/MapTests.swift`.

**Interfaces:** Consumes `GalaxyMap.init` and `shortestPath` (Task 1). Produces `public extension GalaxyMap { static let standard: GalaxyMap }` and, in `MapGeometry.swift`, `func segmentsCross(_ p1: (Double, Double), _ p2: (Double, Double), _ q1: (Double, Double), _ q2: (Double, Double)) -> Bool` and `func distanceToSegment(...) -> Double`.

Author the map in a 1000x620 space with the 36 systems and regions named in the spec. Layout: Core Worlds west-center; Veil Nebula north-east; Ember Belt south-east; Shattered Rim as the outer arc; Silent Expanse is the empty circle centered (520, 310), radius 110. Each lane's flavor-free data is a literal; each contract pair has a one-line flavor (e.g. "Kessra's ore must reach the shipyards at Vantor Reach.", "The refugee world of Thessaly needs medical supply access to the Core Worlds."). Iterate on coordinates until the validator passes.

- [x] **Step 1: Failing tests (the validator):**
  - `has36SystemsAnd33Contracts`; `lanesBetween75And90`; `twinPairsBetween10And14` (twins share endpoints and length, reference each other).
  - `lengthsOneToSix`; `graphConnected`.
  - `noLanesCross` (twins excepted); `noLanePassesNearSystem` (no lane within 14 units of a non-endpoint system); `systemsAtLeast30Apart`.
  - `slotSpacingReadable`: distance / length between 18 and 45 for every lane.
  - `colorBalance`: slots per color within 25% of the mean across the 8 colors; open slots 15% to 25% of all slots; total slots at least 240.
  - `systemsInsideTheirZones`: each system with region coreWorlds, veilNebula or emberBelt lies inside that zone's ellipse from the Art Contract; shatteredRim systems lie outside all three ellipses and the Expanse circle.
  - `silentExpanseEmpty`: no system inside the circle; lanes crossing it number 3 to 5 and each has length 5 or 6.
  - `hazards`: exactly 6 spectrum lanes (an endpoint in veilNebula, length 2 to 4, no twin) and 6 gravityWell lanes (an endpoint in emberBelt, length 2 to 5, no twin).
  - `contractValues`: all between 4 and 22; at least 5 at 17 or more; no duplicate pairs.
- [x] **Step 2:** FAIL. **Step 3:** Author map. **Step 4:** PASS.
- [x] **Step 5:** Commit `Add the standard galaxy map`.

### Task 11: Legal actions and fuzzing

**Files:** Modify `Engine/GameEngine.swift` (`legalActions` complete); create `Tests/StarsCoreTests/FuzzTests.swift`.

`legalActions` by phase: setup and choosing → every subset of offered meeting the minimum; awaitingAction → `.drawBlind` if a card exists, each non-nil exchange slot, each `(lane, payment)` from `paymentOptions` for claimable lanes, `.drawContracts` if the deck is non-empty, else `.pass`; drawingSecondCard → blind plus non-Core slots.

- [x] **Step 1: Failing test** `randomGamesStayConsistent`: for seeds 1...500, houses count `2 + seed % 4`, hazards `seed.isMultiple(of: 2)`, on `.standard`: pick uniformly from `legalActions` with a separate `SeededRNG(seed)`; every action from `legalActions` must apply without throwing; after each action assert card conservation (110), `45 - beacons == Σ beaconCost(own lanes)`, `score == Σ lanePoints(own lanes)`; the game reaches `.gameOver` within 3000 actions.
- [x] **Step 2 to 4:** FAIL, implement, PASS (`swift test -c release` if slow).
- [x] **Step 5:** Commit `Complete legal action enumeration with fuzz test`.

### Task 12: Game session (hand-off state machine)

**Files:** Create `Session/GameSession.swift`, `Tests/StarsCoreTests/SessionTests.swift`.

**Interfaces (Produces):**
```swift
@MainActor @Observable public final class GameSession {
  public enum Screen: Equatable { case handoff(player: Int), playing, finalReview }
  public private(set) var state: GameState; public private(set) var screen: Screen
  public private(set) var lastError: RuleError?; public private(set) var recentEvents: [GameEvent]  // events since the last hand-off, shown on the hand-off screen
  public let engine: GameEngine
  public init(config: GameConfig, map: GalaxyMap = .standard)
  public func reveal()                 // .handoff -> .playing
  public func perform(_ action: Action)   // applies; on error sets lastError; on turn change or setup seat change -> .handoff(next); on gameOver -> .finalReview
  public var activePlayer: Int }
```
Starts at `.handoff(player: 0)` (the first setup pick).

- [x] **Step 1: Failing tests (Review Focus 3):** `startsAtHandoff`; `revealShowsPlaying`; `setupPickLeadsToNextHandoff`; `secondDrawLeadsToHandoff`; `firstDrawStaysPlaying`; `illegalActionKeepsScreenAndSetsError`; `eventsNeverExposeHiddenInfo` (after a full fuzz-driven 2-house game, no `GameEvent` case carries a blind-drawn card or contract id: assert over `state.log` by pattern).
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add game session with privacy hand-off`.

### Task 12A: Saved games (autosave and 5 named saves)

Ported from `../saltmarsh-isles` (`Sources/SaltmarshGame/SavedGames.swift`, `GameStore.swift`, `FileGameStore.swift`, `Tests/GameTests/SavedGamesTests.swift`); read those first and keep their behavior and names unless this task says otherwise. The resume guard (`markResuming` and the rest) is NOT ported.

**Files:** Create `Sources/StarsCore/Session/SavedGames.swift`, `Sources/StarsCore/Session/GameStore.swift`, `Tests/StarsCoreTests/SavesTests.swift`; modify `Session/GameSession.swift`, `Model/GameState.swift` (add `Equatable` to `GameState` and the types it holds, for round-trip tests).

**Interfaces (Produces):**
```swift
public enum SaveLimit { public static let maxSaves = 5, maxNameLength = 30; public static func clipped(_ name: String) -> String }
public enum SaveError: Error, Equatable { case blankName, full, notFound, noGame }
public struct SavedGameSummary: Identifiable, Equatable, Sendable { public var id: UUID; name: String; savedAt: Date; houses: [House] }
public struct SavedGame: Codable, Equatable, Sendable { public var id: UUID; name: String; savedAt: Date; state: GameState }
public protocol SaveSlots: AnyObject { func list() -> [SavedGameSummary]; func load(id: UUID) throws -> SavedGame; func put(_ game: SavedGame) throws; func remove(id: UUID) throws }
extension SaveSlots { @discardableResult public func write(name: String, state: GameState, replacing: UUID? = nil, now: Date = .now) throws -> SavedGameSummary }
public final class InMemorySaveSlots: SaveSlots; public final class FileSaveSlots: SaveSlots { public init(directory: URL) }   // one JSON file per save, <uuid>.json
public protocol GameStore: AnyObject { func save(_ state: GameState) throws; func load() throws -> GameState?; func clear() throws }
public final class InMemoryGameStore: GameStore { public private(set) var saveCount: Int }; public final class FileGameStore: GameStore { public init(directory: URL) }  // autosave.json

// GameSession additions
public init(config: GameConfig, map: GalaxyMap = .standard, store: GameStore = InMemoryGameStore(), saves: SaveSlots = InMemorySaveSlots(), log: ReplayLog? = nil)
public static func resume(map: GalaxyMap = .standard, store: GameStore, saves: SaveSlots, log: ReplayLog?) -> GameSession?   // nil when no autosave or it is .gameOver
public func saveGame(named: String, replacing: UUID?) throws      // .noGame once the game is over
public func loadGame(id: UUID) throws                               // replaces state; screen -> .handoff(player: activePlayer), or .finalReview if over
public func deleteSavedGame(id: UUID) throws
public func savedGames() -> [SavedGameSummary]
```
Behavior: autosave (`store.save`) after every successful `perform`; a failed autosave sets a `public private(set) var saveProblem: String?` and never blocks play. When the game ends, `store.clear()`. All 5 used: `write` without `replacing` throws `.full`; nothing is deleted automatically. A save file that cannot be decoded is left out of `list()`.

- [x] **Step 1: Failing tests:** `listIsNewestFirst`; `sixthSaveThrowsFull`; `replacingKeepsCountAtFive`; `blankNameThrows`; `nameClippedTo30`; `deleteRemoves`; `unreadableFileSkipped` (FileSaveSlots in a temp dir with a junk `.json`); `fileSlotsRoundTrip` (a mid-game state from a seeded game encodes and decodes equal); `sessionAutosavesEachAction` (`saveCount` rises per successful perform, not on a thrown action); `loadOpensAtHandoff` (load a save made mid-turn: screen is `.handoff(player:)` of that state's active player); `saveAfterGameOverThrowsNoGame`; `resumeFromAutosave`; `gameOverClearsAutosave`.
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add autosave and named saved games`.

### Task 12B: Diagnostic replay log

**Files:** Create `Sources/StarsCore/Session/ReplayLog.swift`, `Tests/StarsCoreTests/ReplayLogTests.swift`; modify `Session/GameSession.swift`.

Format: JSON Lines, one file per session, `yyyyMMdd-HHmmss-<seed>.jsonl`. Line kinds (`"kind"` field):
- `start`: `{version: 1, config: GameConfig, startedAt}` (new game);
- `snapshot`: `{reason: "loaded" | "resumed", saveName?, state: GameState}` (a load or an autosave resume; replay restarts from here);
- `action`: `{seq, player, house, phase: TurnPhase, action: Action, result: "ok" | "<RuleError case>"}`.
Also mirror each line, compact, to `os.Logger(subsystem: "local.spanningthestars", category: "game")`.

**Interfaces (Produces):**
```swift
public final class ReplayLog { public init(directory: URL, keep: Int = 20) throws   // prunes to the newest `keep` files on init
  public func start(_ config: GameConfig); public func snapshot(_ s: GameState, reason: String, saveName: String?)
  public func action(_ a: Action, by player: Int, state before: GameState, result: Result<Void, RuleError>)
  public var fileURL: URL { get }
  public static func replay(_ url: URL, engine: GameEngine) throws -> GameState }   // from the last start/snapshot; throws if a logged result differs from what the engine now does
```
`GameSession` calls the log when it is non-nil: `start` in `init`, `snapshot` in `loadGame` and `resume`, `action` in every `perform` (including thrown ones).

- [x] **Step 1: Failing tests:** `replayReproducesGame` (seeded 3-House game, 300 random legal actions plus 2 illegal ones, through a session with a log; `replay` returns a state equal to the session's); `replayFromSnapshotAfterLoad`; `prunesToNewest20` (25 files in a temp dir → 20 remain, oldest gone); `errorsAreLogged` (an illegal action produces an `action` line with `result` `"coreMustBeFirst"`).
- [x] **Step 2 to 4:** FAIL, implement, PASS.
- [x] **Step 5:** Commit `Add diagnostic replay log`.

### Task 13: App shell, theme, card art, bundling

**Files:** Create `Sources/SpanningTheStars/App.swift`, `Theme/Palette.swift`, `Theme/CardArt.swift`, `scripts/bundle.sh`, `Sources/SpanningTheStars/Resources/RULES.md`; modify `Package.swift` (add `.copy("Resources/RULES.md")` next to the Art folder).

**Interfaces:** Consumes `ArtAsset`, `ArtImage` (Task A1).

- `App.swift`: `WindowGroup` with `.defaultSize(width: 1512, height: 945)`, `.windowResizability(.contentMinSize)`, min 1280x800. Root view switches Title → Setup → session screens. (Superseded 2026-11-21: the fixed scaled canvas is replaced by the responsive layout in Global Constraints; Task 15 converts the game screen, Task 16 the remaining screens.)
- `Palette.swift`: deep-space background gradient; colors for 8 resources, 5 houses (Pale Fleet black with pale rim glow), 4 region tints (used for UI accents; the map tint itself comes from `map-backdrop.svg`).
- `CardArt.swift`: `ResourceCardView(card: Card, size: CGSize)`: `ArtImage(.card(card))` with the resource name drawn in the bottom safe zone. `ContractCardView(contract:, completed: Bool?)`: `ArtImage(.contractFront)` with system names, flavor line and value badge in the contract safe zones. `CardBackView(kind: .resource | .contract)`. All sizes derive from the 200x300 art ratio.
- `bundle.sh`: `swift build -c release`; assemble `build/Spanning the Stars.app` (`Contents/MacOS/SpanningTheStars`, `Contents/Info.plist` with `CFBundleIdentifier` `local.spanningthestars`, `LSMinimumSystemVersion` 26.0, `NSHighResolutionCapable` true), copy the SwiftPM resource bundles (RULES.md and Art) into `Contents/Resources`, `codesign -s - --force --deep`.
- Codex loading: `CodexText.load()` looks in `Bundle.main.resourceURL` for the SwiftPM resource bundle first, then falls back to `Bundle.module`.

- [x] **Step 1:** Implement. Add a test `rulesCopyMatchesDocs` in `MapTests` that reads both `docs/RULES.md` and `Sources/SpanningTheStars/Resources/RULES.md` via `#filePath` and expects equality.
- [x] **Step 2:** `swift test` PASS; `scripts/bundle.sh` then `open "build/Spanning the Stars.app"`: the app launches and shows a card gallery debug screen with all 9 card faces, both backs and a contract. Screenshot.
- [x] **Step 3:** Commit `Add app shell, theme, card art and bundling`.

### Task 14: Star map view

**Files:** Create `Views/StarMapView.swift`.

`StarMapView(map:, state:, hazards:, highlight: Set<Int>, onSelectLane: (Int) -> Void)` drawn with `Canvas` in map space scaled to its frame (target about 1150x650):
- Background: `ArtImage(.mapBackdrop)` stretched to the map frame (same 1000x620 space) under the `Canvas`.
- Systems: `ArtImage(.star(region))` at about 22 pt, name label drawn in SwiftUI.
- Lanes: `length` rounded slots along the segment; twins offset 6 units perpendicular; open lanes gray; spectrum lanes with a rainbow outline and `glyph-spectrum` at the midpoint, gravity lanes with `glyph-gravity` (only when `hazards`); closed twins dimmed and dashed.
- Claimed slots filled with the owner's beacon color.
- Hover: lane tooltip (length, points, cost text). Click: `onSelectLane`. Hit test by distance to segment under 10 units.
- [x] **Step 1:** Implement with a SwiftUI preview of `.standard`.
- [x] **Step 2:** Run the app on a debug route showing the map at 1512x945; screenshot; check every name is legible and no lanes overlap labels.
- [x] **Step 3:** Commit `Add star map view`.

### Task 15: Game screen

**Files:** Create `Views/GameView.swift`, `StatusBar.swift`, `ExchangeView.swift`, `HandTray.swift`, `ContractsPanel.swift`, `ClaimSheet.swift`, `LogView.swift`.

Layout per the spec's Screen Layout sketch.
- `StatusBar`: per House: `ArtImage(.house(h))` crest, name, Standing, beacons, card count, contract count; active House highlighted; "Final round" banner when `finalTurnsRemaining != nil`; Codex button.
- `ExchangeView`: 5 slots (empty slots drawn as hollow frames and disabled), Supply Depot back with count (tap = blind draw), Contract deck with count (tap = draw contracts). Disabled per `legalActions`.
- `HandTray`: one stack per card type (`ResourceCardView` at 70x105) with a count badge, sorted by color order then Core.
- `ContractsPanel`: active House's contracts; completed ones get a check (via `isComplete`); scrolls inside its frame.
- `ClaimSheet`: opened from a lane click; lists `paymentOptions` as card rows; confirm performs `.claim`; shows "Not enough beacons" or "Lane closed" messages from the engine's checks.
- `LogView`: last 8 public events, themed text (e.g. "House Ashkar anchored Kessra to Forgeholm (+7)").
- [x] **Step 1:** Implement.
- [x] **Step 2:** Run with a debug state of 5 Houses, 45 cards in one hand and 12 contracts (Review Focus 5); screenshot at 1512x945; nothing clips.
- [x] **Step 3:** Commit `Add main game screen`.

### Task 16: Flow screens

**Files:** Create `Views/TitleView.swift`, `SetupView.swift`, `HandoffView.swift`, `ContractPickView.swift`, `EndGameView.swift`, `CodexView.swift`, `SavedGamesSheets.swift`, `SettingsView.swift`; modify `App.swift` (commands, Settings scene, stores in Application Support).

- All Task 16 screens fill the window responsively (Global Constraints); remove `ScaledCanvas` if nothing uses it any more.
- `TitleView`: `bg-starfield` and `title-emblem`, game title in SwiftUI type, box-back flavor text from the README, New Charter and Codex buttons.
- `SetupView`: toggle 2 to 5 Houses (fixed colors), "Frontier Hazards" toggle with a two-line description, Begin.
- `HandoffView`: `bg-starfield` over a blurred map, "Hand the console to <House>", the House crest (`ArtImage(.house(h))`, 128 pt), recent public events, "Reveal my hand" button. Shown for every `.handoff`.
- `ContractPickView`: offered contracts as cards, toggle selection, the minimum (2 at setup, 1 in-game) enforced on the Confirm button; contracts highlight their systems on the map.
- `EndGameView`: per House rows animating lane points, each contract revealed ✓ or ✗, Great Span highlight on the map with `award-great-span`, totals, winner(s) from `ranking` with the tiebreak reason.
- `SavedGamesSheets.swift`: `SaveGameSheet` and `LoadGameSheet`, ported from `../saltmarsh-isles/App/Views/SavedGamesSheets.swift`: name field, list of saves (name and date), replace-one flow when all 5 are used, trash can per save with a confirmation, load confirmation when a game is in progress. Loading lands on the hand-off screen (`GameSession.loadGame`).
- File menu commands: New Charter (Command-N), Load Game (Command-O), Save Game (Command-S, disabled with no game or after the game ends).
- `TitleView` also shows "Continue Charter" when `GameSession.resume` returns a game.
- `SettingsView` (Settings scene, Command-comma): "Diagnostic logging" toggle (`@AppStorage("diagnosticLogging")`, default off; applies from the next new, loaded or resumed game) and "Show logs in Finder" (`NSWorkspace.shared.activateFileViewerSelecting`).
- App icon (from Task A3): `scripts/bundle.sh` runs `scripts/make-icon.sh`, copies `AppIcon.icns` into `Contents/Resources`, and sets `CFBundleIconFile` to `AppIcon` in Info.plist; when run unbundled (`swift run`), `App.swift` sets `NSApplication.shared.applicationIconImage` from the bundled `AppIcon.svg` so the Dock shows it during development.
- `CodexView`: renders `CodexText.load()` as Markdown (`AttributedString(markdown:)` per block) in a scrolling sheet.
- [x] **Step 1:** Implement.
- [x] **Step 2:** Run end to end; screenshot each screen.
- [x] **Step 3:** Commit `Add title, setup, hand-off, contract pick, end game and Codex screens`.

### Task 17: Playtest and verification

Approved by the user on 2026-11-21. Steps 1 and 2 were run by the agent (137 StarsCore and 28 app tests green, bundle built). Steps 3 to 4 are a human-in-the-loop playtest owned by the user; agent screenshot coverage was skipped for speed, and findings come back as small fix rounds.

- [x] **Step 1:** `swift test` all green; record the counts.
- [x] **Step 2:** `scripts/bundle.sh`; launch the `.app` on the 14" screen; full screen on and off.
- [x] **Step 3:** Play a 2-House game to the end with hazards off. Confirm: the hand-off appears before every turn and every setup pick, twins close, the final round banner appears and the right number of final turns happen, end totals match a manual count.
- [x] **Step 3b:** Save mid-game under a name, quit, relaunch: Continue resumes at the hand-off; Load restores the named save; fill all 5 slots and check the replace flow; delete one. Turn on diagnostic logging, play a few turns, and confirm `ReplayLog.replay` on the file reproduces the state.
- [x] **Step 4:** Play a 3-House game with Frontier Hazards on; anchor at least one Spectrum and one Gravity Well lane; confirm costs and beacon spend.
- [x] **Step 5:** Fix anything found (with a failing test first for rules bugs); commit `Playtest fixes`.
