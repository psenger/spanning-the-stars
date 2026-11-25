# Contributing to Spanning the Stars

Thanks for your interest. Bug reports, rules corrections, interface improvements, and new features are welcome.

## Ways to help

- **Report a bug.** Include your macOS version, the steps to reproduce it, and what you expected to happen. For a game issue, include the House setup, bot levels, and whether Frontier Hazards was on.
- **Share a replay for a game bug.** Turn on **Diagnostic logging** in Settings before starting, loading, or continuing a game. After reproducing the issue, use **Show logs in Finder** to find the replay file. Review it before sharing because it can contain game state.
- **Fix something small.** Open a pull request for a typo, incorrect label, or accessibility improvement.
- **Propose a rule change or new feature.** Discuss the intended behavior first so the engine, tests, and rules text can be updated together.

## Setting up

Use macOS 26 or later and a Swift 6.2 or newer toolchain supplied by Xcode or the command line tools. From the repository root, run `make help` to see the available commands.

| Command | What it does |
| --- | --- |
| `make run` | Runs the macOS app from source |
| `make build` | Compiles a release build under `.build/` |
| `make bundle` | Creates `build/Spanning the Stars.app` |
| `make test` | Runs the Swift test suite |
| `make ladder` | Runs the short AI difficulty ladder |
| `make bench` | Runs a seeded Commander vs Navigator tournament |

To work in Xcode, open `Package.swift`. To launch the bundled app, open `build/Spanning the Stars.app` in Finder after running `make bundle`.

## How the code is laid out

- `Sources/StarsCore/` holds the engine, scoring, map, saves, and AI. Keep the rules in the engine and let the app and bots use its legal actions.
- `Sources/SpanningTheStars/` holds the SwiftUI app and its resources. Use the game's terms from the [Concord Codex](docs/RULES.md) in player-facing text.
- `Sources/Tournament/` holds the command-line entry point for seeded bot games.
- Bots make decisions from `PlayerView`, which contains the information available to their seat. Keep tournament behavior reproducible and app decisions off the main actor.
- When rules text changes, update [the Codex](docs/RULES.md) and [its bundled copy](Sources/SpanningTheStars/Resources/RULES.md) together. For a gameplay change, update the rules, engine, and relevant tests in the same pull request.

## Tests and benchmarks

Run `make test` before opening a pull request. Engine, save, and AI tests live in `Tests/StarsCoreTests/`. Screen and flow tests live in `Tests/SpanningTheStarsTests/`. Both use Swift Testing. Add a focused regression test when changing behavior and use seeded games where randomness matters.

For AI changes, run `make ladder` and compare the result with the recorded [AI benchmarks](docs/ai-results.md). Use release-mode tournaments for tuning. You can choose a matchup and game count with `BENCH_ARGS`.

```bash
make bench BENCH_ARGS='--a 4 --b 3 --games 2000 --players 2 --seed 42'
```

Record the command, seed, game count, and outcome for changes that affect bot strength. For changes to a screen, also check the affected flow in the running macOS app.

## Code style and commits

- Match the surrounding Swift 6 code and keep concurrency boundaries explicit.
- Keep changes focused and reuse existing engine rules and test fixtures.
- Describe the change in the commit subject. For work tied to an AI milestone, include its marker, as in `M6: improve Commander endgame scoring`.

## Pull requests

- Start from `main` and keep each pull request focused on one change.
- Describe what changed, why, and how you verified it. Link the relevant issue if there is one.
- Include a macOS screenshot when the change affects the interface, and report any benchmark changes when tuning the AI.

## Writing docs

Use sentence-case headings and write each paragraph or list item on a single source line. Describe gameplay using the game's own terms. Keep examples runnable from the repository root.

## License and artwork

By contributing, you agree to release your contribution under the [MIT License](LICENSE). Include third-party material only when you have permission to redistribute it, and record the source, license, and required attribution. Keep reference images with unverified permissions in your local workspace.
