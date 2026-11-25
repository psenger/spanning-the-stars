# Spanning the Stars: AI Opponent Plan

## Goal and how to use this brief

Add five difficulty levels of computer opponent, with no LLM, to Spanning the Stars, a native Swift macOS game that is already built. This brief sets requirements and recommends a design; Claude Code decides how that design fits the existing code, and may change it.

This brief is planning input, not a spec. It runs unattended: Claude Code makes every judgment call itself and logs it, and never stops to ask questions.

1. Save this file in the repo, for example as `docs/spanning-the-stars-ai-plan.md`.
2. Launch Claude Code on Fable for the main session and every subagent:

   ```
   CLAUDE_CODE_SUBAGENT_MODEL=fable claude --model fable
   ```

3. Paste the kickoff prompt from the last section.
4. `superpowers:writing-plans` writes the plan straight from this brief and the code. Brainstorming is skipped because it is interactive.
5. `superpowers:subagent-driven-development` runs the plan with a fresh subagent per task, and independent milestones run side by side (see Milestones).
6. You review the plan's Decisions log and the results afterward.

Every statement in this brief is one of three kinds:

| Kind | Meaning | What Claude Code does with it |
| --- | --- | --- |
| Requirement | Must hold whatever the design | Meet it. If the code makes it impossible, take the closest workable reading, log it, and continue. |
| Recommendation | The author's opinion, with the reason for it | Check it against the code. Adopt, adapt or reject it, and record which in the Decisions log with a one-line reason. |
| Starting value | A number to tune | Use it as a first guess. Tournament results overrule it. |

Anything not in the Requirements section is a recommendation or a starting value. This brief does not know the game's pieces, rules or code structure: words such as route, goal, hand and piece are placeholders. Where the brief and the code disagree, the code wins and the Decisions log notes the difference.

## Requirements

These hold whatever design Claude Code chooses.

- **No LLM, no network.** The AI runs fully offline inside the app.
- **No cheating.** A bot decides using only what a human player in that seat could see under the game's rules.
- **No invented rules.** Pieces and rules come from the code. If the code doesn't settle a rule, take the reading the code best supports and log it as an assumption.
- **Human play is unchanged.** Adding the AI must not change the rules, scoring or existing test results. Changes to existing code are kept as small as possible, and each one is listed in the Decisions log with its reason.
- **Five selectable levels,** each measurably stronger than the one below it in bot-vs-bot games.
- **Reproducible.** Given the same seed, a bot game replays exactly.
- **Headless.** Bots can play complete games without the UI, so tests and tournaments can run thousands of games.
- **Responsive.** AI thinking never blocks the main thread or freezes the UI.
- **Process.** Follow the Superpowers TDD loop for every task, and name the milestone in each commit message.
- **No questions.** Never stop to ask me. Every judgment call goes in a Decisions log at the top of the plan: the decision, the options considered, and the reason. Big calls, such as changing existing game code, are marked so I can find them first.

## Recommended design

Recommendation: one rule-based agent shared by Levels 1 to 4, with Monte Carlo search added for Level 5, all reaching the game through one access layer. The reason: games like this have hidden information, chance and several players, which makes deep search expensive, while their strategy breaks into clear parts a hand-tuned agent handles well.

```
+------------------+      +---------------------------+      +-------------------+
|  Existing game   | <--- |    Game access layer      | <--- | Tournament runner |
|  rules, board,   |      |  existing API or adapter  |      | bot vs bot games, |
|  scoring (not    |      |    (option A, B or C)     |      | win rate per level|
|  rewritten)      |      +---------------------------+      +-------------------+
+------------------+           |                ^
                               v                | simulations
                      +------------------+      |
                      |    PlayerView    |      |
                      | only what that   |      |
                      | seat can see     |      |
                      +------------------+      |
                               |                |
                               v                |
  +------------------------------------------+  |   +----------------------+
  | Bot agent: Levels 1 to 4                 |  +---|   Level 5 search     |
  |  +----------------+  +----------------+  |      | samples hidden info, |
  |  | Planner        |  | Resource       |  | ---> | plays out with       |
  |  | plan toward    |  | tracker: what  |  | top  | Level 3, picks best  |
  |  | its goals      |  | it still needs |  | moves| average              |
  |  +----------------+  +----------------+  |      +----------------------+
  |  +----------------+  +----------------+  |
  |  | Opponent model |  | Action scorer  |  |
  |  | Level 4 and up |  | weights, noise,|  |
  |  |                |  | mistakes       |  |
  |  +----------------+  +----------------+  |
  +------------------------------------------+
```

Levels 1 to 4 are the same agent with different settings. Level 5 asks that agent for its best few moves, then tests each one in simulated games. The boxes and function names are suggestions: Claude Code maps them onto the existing types, renames them to fit, or merges them.

Alternative worth weighing: one Monte Carlo search for all five levels, made weaker with smaller time budgets and added noise. It means less code, but weak levels tend to play oddly, and it needs fast simulation from the start. The Decisions log says which approach was chosen and why.

### Connecting to the existing code

The AI needs five capabilities from the game. The names are placeholders; the existing Swift types may already provide them under other names.

| Capability | Needed by | Placeholder |
| --- | --- | --- |
| List every legal move for a player | All levels | `legalMoves` |
| See only what that player may see | All levels | `playerView` |
| Apply a move to a copy, never the live game | Level 5 mainly, Levels 3 and 4 for short lookahead | `applying(_:)`, copy |
| Know when the game is over and read the scores | Level 5, tournament runner | `isOver`, `scores` |
| Play a full game without the UI, from a seed | Tests, tournament runner | seeded RNG |

Three ways to provide them. Claude Code picks after reading the code, and may mix them, for example the existing API for listing moves and an adapter for simulation.

| Option | What it is | Fits when | Cost |
| --- | --- | --- | --- |
| A. Use the existing API | The AI calls the game's own model types directly | Rules sit in a model layer apart from SwiftUI, and state is a struct or cheap to copy | Lowest: nothing new to maintain |
| B. Adapter (proxy) | A protocol in the AI module, for example `GameAdapter`, implemented by a thin type that reads the live game and returns a value-type snapshot the AI can copy and simulate on | State lives in classes or `@Observable` / `ObservableObject` view models, or the API doesn't match what the AI needs | Medium: the adapter has to track rule changes |
| C. Extract a rules model | Move the rule checks and scoring out of views into a plain model type that both the UI and the AI use | Rules are tangled into views, so no headless game is possible | Highest: changes existing code, so use it only when A and B can't work, and mark it as a big call |

Recommendation: prefer A, then B, and use C only if B would mean writing the rules a second time. An adapter must call the game's own rule code, never reimplement it, because two copies of the rules drift apart. The Decisions log names the option chosen, the reason, and every existing type it touches.

Swift notes for the decision:

- If game state is made of structs, `var copy = state` is already the copy the AI needs, and simulation is cheap.
- If state is in classes, a snapshot struct (option B) is usually the cleanest way to give the AI copies without touching the UI.
- AI work runs off the main actor, so whatever it reads must be safe to send across threads (`Sendable`, or a snapshot taken on the main actor).

## Milestones

Recommendation: build in this order, because each level reuses the one before it and the tournament runner arrives early enough to measure everything after. The "Accept when" checks are what must be shown; the work inside each milestone is a suggestion. Claude Code may merge, split or reorder milestones to fit the code, and notes why in the Decisions log. Milestone 0 becomes the opening section of the plan; writing-plans breaks the rest into tasks.

Parallel work for subagents (recommendation): Milestones 0 and 1 run first, in order, because everything depends on them. After that, the tournament runner (part of Milestone 2) and the planner (Milestone 3) can run side by side, and the opponent model (Milestone 6) can start alongside Milestone 5. Each level's win-rate check waits for the level below it. Subagents working in parallel must not edit the same files.

1. **Milestone 0: Learn the game and choose the integration.** Read the code and write down: every piece, card and token with counts; the board layout; every action on a turn; scoring during and at the end of the game; what ends the game; what each player can and can't see; supported player counts. Check where the rules live and whether game state is structs or classes, then choose option A, B or C. Mark each recommendation in this brief as adopted, adapted or rejected.
   - Accept when: the plan's opening section records all of this, with each item pointing to the code it came from, and the Decisions log covers every choice made.
2. **Milestone 1: Game access layer.** Build the chosen option: use the existing API, add an adapter, or extract the rules model. Add only the capabilities the existing code is missing.
   - Accept when: existing tests still pass; 1,000 headless games of random-move bots finish with no illegal moves or crashes; the same seed gives the same final scores.
3. **Milestone 2: Bot protocol, Level 1 and the tournament runner.** Suggested shape: a `Bot` protocol with one method that takes the player's view and an RNG and returns a move. Level 1 takes legal moves with a light bias toward ones that score now.
   - Accept when: 1,000 games with Level 1 bots finish legally, and the runner reports results as described in Testing and tuning.
4. **Milestone 3: Planner.** Suggested: if the game is about connecting places, a shortest-path (Dijkstra) planner over the board graph, where links the bot owns cost nothing and links an opponent owns are blocked. If goals work differently, design a planner that fits and log why.
   - Accept when: unit tests on a small hand-made board show a blocked link forces a detour, owned links cost nothing, and an impossible goal is flagged.
5. **Milestone 4: Resource tracker and Level 2.** From the plan, work out what the bot still needs and gather toward it. Level 2 follows its first plan and never replans.
   - Accept when: Level 2 beats Level 1 at the target win rate.
6. **Milestone 5: Action scorer and Level 3.** Suggested: score each legal move with weighted features taken from Milestone 0's findings, such as progress on the plan, points now, risk of losing a contested spot, scarcity and pieces left. Add replanning when blocked and an endgame mode.
   - Accept when: Level 3 beats Level 2 at the target win rate, and tests cover replanning after a block.
7. **Milestone 6: Opponent model and Level 4.** Estimate what opponents are going for from what they can be seen doing, value moves that block them, and go for end-of-game bonuses if the game has any.
   - Accept when: Level 4 beats Level 3 at the target win rate. If the game has hidden goals, a scripted test shows the model ranks the true goal in its top 3.
8. **Milestone 7: Level 5 search.** Suggested: determinized Monte Carlo. Take the top 5 to 8 moves from the Level 4 scorer; for each, fill in hidden information consistent with the player's view, play to the end with Level 3 bots, and repeat until the time budget runs out. Information-set MCTS is a stronger but more complex alternative.
   - Accept when: Level 5 beats Level 4 at the target win rate and stays within its time budget. Leak test: two different hidden true states with the same player view and seed give the same move.
9. **Milestone 8: Difficulty wiring and feel.** A difficulty picker in game setup and a short thinking delay so bots don't move instantly.
   - Accept when: a full game against each level runs in the app without blocking the UI, and the ladder tournament passes.

## The five levels

Recommendation: one agent, five settings, each level turning on more features and making fewer mistakes, so a weak bot still looks sensible instead of random. Level names are suggestions; every number in the table is a starting value.

| Level | Name | Features on | Randomness (softmax temperature) | Mistake rate | Search |
| --- | --- | --- | --- | --- | --- |
| 1 | Cadet | Legal moves, light bias to scoring now | High (near random) | n/a | None |
| 2 | Pilot | Planner, resource tracker | 1.0 | 15% | None |
| 3 | Navigator | + action scorer, replanning, endgame mode | 0.3 | 5% | None |
| 4 | Commander | + opponent model, blocking, end-game bonuses | 0.1 | 2% | None |
| 5 | Admiral | Everything in Level 4 | 0 (search decides) | 0% | Monte Carlo, 1.5 s |

How the settings work:

- **Randomness:** the bot picks a move by weighted chance from its scores. A higher temperature spreads the chance across weaker moves, so a low level still plays sensible-looking moves instead of nonsense.
- **Mistake rate:** the chance per turn of a human-like slip, such as ignoring one of its goals for a turn or skipping a replan.
- **Feature flags:** each level's settings turn planner, opponent model and search on or off.

Suggested shape, adjusted to the project's conventions:

```swift
struct BotSettings: Sendable {
    var usesPlanner: Bool
    var usesScorer: Bool
    var usesOpponentModel: Bool
    var temperature: Double    // randomness when picking among scored moves
    var mistakeRate: Double    // chance per turn of a human-like slip
    var searchBudget: Duration // .zero = no search
    var weights: [String: Double]
}
```

## Testing and tuning

Requirement: levels are measured by bots playing each other headless. Recommendation: a tournament runner built in Milestone 2 as a command-line target or a test target, whichever suits the project, for example:

```
swift run Tournament --a 3 --b 2 --games 2000 --players 2 --seed 42
```

The runner reports, per bot: win rate with a 95% confidence interval, average score, goals completed and failed (if the game has goals), and average game length in turns.

Target ladder, as starting values (two-player, 2,000 games each):

| Matchup | Higher level should win |
| --- | --- |
| L2 vs L1 | at least 75% |
| L3 vs L2 | at least 65% |
| L4 vs L3 | at least 60% |
| L5 vs L4 | at least 60% |

Tuning rules:

- If two neighboring levels win about evenly, they are too similar. Widen the gap with temperature and mistake rate first, features second.
- Change one weight at a time and rerun the tournament. If manual tuning stalls, a small hill-climbing script over the weights, scored by tournament win rate, is enough.
- Also run 4-player games with mixed levels to check that bots behave sensibly on crowded boards.
- Save each milestone's results to `docs/ai-results.md` so later changes can be checked for regressions. A short 200-game version of the ladder runs in CI.

## Definition of done

- [ ] The plan's opening section lists the game's real pieces and rules, each pointing to the code it came from
- [ ] The Decisions log names the integration option (A, B or C), its reason, and every existing type it touches
- [ ] The Decisions log marks each recommendation in this brief as adopted, adapted or rejected, with a reason
- [ ] Every requirement holds, including the leak test and an unblocked UI
- [ ] All five levels are selectable in game setup and play full games without errors
- [ ] The ladder tournament meets the targets, or the Decisions log explains the gap
- [ ] The full test suite passes, and a short ladder runs in CI

## Kickoff prompt

Paste this into Claude Code from the repo root. Change the path if you saved the file somewhere else.

```
Run unattended. Do not ask me questions at any point; make each judgment
call yourself and record it in a Decisions log at the top of the plan.

Read docs/spanning-the-stars-ai-plan.md. Use superpowers:writing-plans to
write an implementation plan from it for adding five non-LLM AI opponents
(difficulty levels 1 to 5) to Spanning the Stars, a native Swift macOS game
already built in this repo. Skip brainstorming. The brief is planning
input, not a spec.

The brief's Requirements section must hold. Everything else is my
opinion: scrutinize it against the actual code. Adopt, adapt or reject
each recommendation and log which, with a reason. If you see a better
approach, take it and log why.

The brief does not know the game's pieces, rules or code structure.
Learn them from the code and never invent a piece or rule. Decide
whether the AI uses the existing API directly, goes through an adapter,
or needs the rules extracted, and log why.

Then execute the plan with superpowers:subagent-driven-development.
Run independent milestones in parallel subagents as the brief describes,
without two subagents editing the same files.
```
