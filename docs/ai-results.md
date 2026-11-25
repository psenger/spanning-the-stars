# AI opponent results

Tournament output per milestone. Every run is reproducible: the same command gives the same table.
Win rate is win credit per seat-game, so an even 2-player match reads 50% and a tie for first is shared.
The 95% interval is only meaningful between different levels: in a mirror match the win rate is 50% by
construction.

## M2: Level 1 Cadet and the tournament runner

Cadet settings: temperature 2.0, mistake rate 0, no planner, scorer, opponent model or search.
Weights: `pointsNow` 1.0, `draw` 1.0, `newContracts` -2.0. These are the starting values; no tuning was needed.

```text
$ swift run -c release Tournament --a 1 --b 1 --games 1000 --players 2 --seed 42
1000 games, 2 players, seed 42, hazards off
seats: Cadet, Cadet
level      samples  win rate  95% CI          avg score  completed  failed
Cadet         2000     50.0%  47.8% - 52.2%        18.5       0.17    3.52
avg turns 85.9, illegal moves 0
```

## M4: Level 2 Pilot

Pilot settings: planner on, temperature 1.0, mistake rate 0.15, no scorer, opponent model or search.
Weights: `pointsNow` 1.0, `draw` 1.0, `newContracts` -2.0, `wantedClaim` 6.0, `offPlanPenalty` 4.0,
`cardNeed` 3.0, `keepCostWeight` 0.5. A blind draw counts 0.3 of `cardNeed`. These are the starting values;
the 75% target was met on the first run, so no tuning was done.

```text
$ swift run -c release Tournament --a 2 --b 1 --games 2000 --players 2 --seed 42
2000 games, 2 players, seed 42, hazards off
seats: Pilot, Cadet
level      samples  win rate  95% CI          avg score  completed  failed
Cadet         2000     17.2%  15.7% - 19.0%        13.6       0.16    3.46
Pilot         2000     82.8%  81.0% - 84.3%        54.5       1.91    2.29
avg turns 84.3, illegal moves 0
```

## M5: Level 3 Navigator

Navigator settings: planner and scorer on, temperature 0.15, mistake rate 0.05, no opponent model or search.
Weights: `pointsNow` 1.0, `draw` 1.0, `newContracts` -2.0, `offPlanPenalty` 4.0, `cardNeed` 3.0,
`keepCostWeight` 1.2 (Navigator only; Pilot keeps 0.5), `planProgress` 1.5, `urgency` 0.5, `coreValue` 4.0,
`claimNowBonus` 2.0, `contractBeaconFloor` 15, `endgameBeacons` 8, `endgamePointsBoost` 1.5. Fixed values:
a blind draw counts 0.3 of `cardNeed` (nothing once every Contract is fulfilled or abandoned), each Core in a
payment costs 1.0 (0.1 in endgame mode), `drawContracts` scores 3.0 once every Contract is fulfilled or
abandoned, and a detour counts for at most 10. The `claimNowBonus` lead over the best draw is held by a wanted
lane's payment with the fewest Cores; each further Core puts a payment 1.0 below it.

The starting values (temperature 0.3, `keepCostWeight` 0.5) gave 57.6%, short of the 65% target. Two tuning
rounds of the 6 allowed were used:

| Round | Change | Navigator win rate |
| --- | --- | --- |
| 0 | starting values | 57.6% |
| 1 | temperature 0.3 to 0.15 | 60.2% |
| 2 | `keepCostWeight` 0.5 to 1.2 for Navigator | 80.7% |

With `keepCostWeight` above 1 a Contract is kept only when most of its route is already wanted, so the
Navigator keeps the minimum at setup and fails 0.95 Contracts a game where the Pilot fails 2.60.

The tuning rounds were run before the review fix that moved the `claimNowBonus` lead to after the Core cost and
took the `cardNeed` share off a blind draw when nothing is wanted. The table below is from the fixed code
(80.0%, from 80.7% before the fix); no further tuning was needed.

```text
$ swift run -c release Tournament --a 3 --b 2 --games 2000 --players 2 --seed 42
2000 games, 2 players, seed 42, hazards off
seats: Navigator, Pilot
level      samples  win rate  95% CI          avg score  completed  failed
Pilot         2000     20.0%  18.3% - 21.8%        40.5       1.60    2.60
Navigator     2000     80.0%  78.2% - 81.7%        76.4       2.19    0.95
avg turns 78.3, illegal moves 0
```

## M6: Level 4 Commander

The values and table of this section are from before the tune-up; "Tune-up before merge" below has the two
rules added later and the current numbers.

Commander settings: planner, scorer and opponent model on, temperature 0.05, mistake rate 0.02, no search.
Weights: the Navigator's (`keepCostWeight` 1.2 included) plus `block` 2.0, `span` 0.5, `spanReach` 6,
`closeOut` 5, `closeOutLead` 10. The `BotWeights` default for `block` stays at its starting value 0.6; 2.0
is set for Commander only. The block term counts only rivals that own at least one lane, and the three
Commander terms are added to a lane's claim score after the `claimNowBonus` lead is applied.

The starting values (temperature 0.1, mistake rate 0.02, `block` 0.6) gave 55.8%, short of the 60% target.
All 6 tuning rounds were used and the target was not met: the best result is 57.3%.

| Round | Change | Commander win rate | Kept |
| --- | --- | --- | --- |
| 0 | starting values | 55.8% | |
| 1 | temperature 0.1 to 0.05 | 56.9% | yes |
| 2 | mistake rate 0.02 to 0.01 | 56.2% | no |
| 3 | `span` 0.5 to 1.0 | 51.9% | no |
| 4 | `span` 0.5 to 0.25 | 56.4% | no |
| 5 | `block` 0.6 to 1.2 | 57.0% | yes |
| 6 | `block` 1.2 to 2.0 | 57.3% | yes |

Each round changed one value from the best settings so far; a change that was not kept was undone before the
next round. The 95% interval is about 2.2 points either side, so rounds 1, 2, 4, 5 and 6 are within noise of
each other. Only round 3 moved the result clearly: a larger `span` pulls claims off the plan (1.79 Contracts
completed a game, from 1.94). Raising `block` lowered the Navigator's average score a little each time (69.5,
69.3, 68.7), which is why 2.0 was kept.

```text
$ swift run -c release Tournament --a 4 --b 3 --games 2000 --players 2 --seed 42
2000 games, 2 players, seed 42, hazards off
seats: Commander, Navigator
level      samples  win rate  95% CI          avg score  completed  failed
Navigator     2000     42.7%  40.5% - 44.9%        68.7       1.80    1.03
Commander     2000     57.3%  55.1% - 59.5%        73.1       1.92    0.99
avg turns 73.9, illegal moves 0
```

### Tune-up before merge (Task 14)

Two rules were added to Commander for the gaps recorded as D27 and D28:

- The block term is multiplied by `blockCrowdScale` when there are 3 or more Houses.
- Hold-back: the claim that would start the final round (leave 2 or fewer beacons) is put `holdBackMargin`
  under the best other legal action when the projected final total (the one `closeOut` uses) is behind the
  best rival's public score and that other action already scores within `holdBackMargin` of the claim.

Final values: `blockCrowdScale` 0 (no blocking with 3 or more Houses), `holdBackMargin` 8.0. `block` 2.0,
temperature 0.05 and mistake rate 0.02 are unchanged. Navigator, Pilot and Cadet do not use either rule:
`--a 3 --b 2` still gives 80.0%.

The starting values (`blockCrowdScale` 0.25, `holdBackMargin` 3.0) met the 4-player condition and missed the
2-player floor. All 6 tuning rounds were used. The 2-player column is Commander's win rate against Navigator
over 2,000 games; the 4-player column is Commander against Navigator in `--levels 1,2,3,4` over 1,000 games.

| Round | Change | 2 players | 4 players | Kept |
| --- | --- | --- | --- | --- |
| 0 | starting values | 57.5% | 46.0% against 42.4% | |
| 1 | `holdBackMargin` 3.0 to 8.0 | 57.6% | 46.0% against 42.3% | yes |
| 2 | `holdBackMargin` 8.0 to 20.0 | 57.6% | 45.9% against 42.3% | no |
| 3 | `block` 2.0 to 3.0 | 57.5% | 45.6% against 42.6% | no |
| 4 | temperature 0.05 to 0.02 | 57.0% | 45.5% against 42.7% | no |
| 5 | `closeOutLead` 10 to 0 | 57.6% | 46.0% against 42.3% | no |
| 6 | `blockCrowdScale` 0.25 to 0 | 57.6% | 47.8% against 39.9% | yes |

The 4-player condition is met: Commander wins 47.8% against Navigator's 39.9%, from 42.0% against 46.1%
before this task. Scaling the block term is what moved it; dropping the term altogether widened the gap from
3.7 points to 7.9.

The 2-player target is still missed: 57.6% against a floor of 57.8% and a target of 60%. The hold-back rule
is worth 0.2 to 0.3 points (57.3% before it), inside the noise of 2.2 points either side. It seldom applies:
the projected total counts the seat's own Contracts and the rival's public score does not, so Commander is
rarely behind by that measure when it could end the game, and a wider margin (round 2) changes nothing more.
Round 5 gave the same table as round 1 to the last digit, so the close-out lead has no effect either. Per the
brief the 4-player condition was preferred; 2-player Commander stays above 55%.

```text
$ swift run -c release Tournament --a 4 --b 3 --games 2000 --players 2 --seed 42
2000 games, 2 players, seed 42, hazards off
seats: Commander, Navigator
level      samples  win rate  95% CI          avg score  completed  failed
Navigator     2000     42.4%  40.3% - 44.6%        68.8       1.80    1.03
Commander     2000     57.6%  55.4% - 59.7%        73.2       1.92    0.99
avg turns 74.1, illegal moves 0
```

```text
$ swift run -c release Tournament --levels 1,2,3,4 --games 1000 --seed 42
1000 games, 4 players, seed 42, hazards off
seats: Cadet, Pilot, Navigator, Commander
level      samples  win rate  95% CI          avg score  completed  failed
Cadet         1000      0.1%  0.0% - 0.6%           8.6       0.17    3.41
Pilot         1000     12.2%  10.3% - 14.4%        39.9       1.62    2.52
Navigator     1000     39.9%  36.9% - 43.0%        73.6       2.30    0.90
Commander     1000     47.8%  44.7% - 50.9%        75.2       2.20    0.94
avg turns 157.1, illegal moves 0
```

### Contract selection tuning (2026-11-26)

The baseline reproduced 57.6% at two Houses. At four Houses Commander led Navigator 47.8% to 39.9% with hazards off and 47.1% to 41.0% with hazards on.

For two Houses, one candidate estimated the rival's net Contract points from its public lanes and Contract count and included its Great Span when projecting the final round. A constructed position confirmed that the estimate changed the close-out decision as intended. The 2,000-game win rate still rounded to 57.6%, so the estimate was dropped.

The first weight screen ran 1,000 two-House games per variant from seed 42, hazards off, using the estimate and changing one setting at a time. The weight values below are the ones tried.

| Setting | Values tried | Commander win rate |
| --- | --- | --- |
| Estimate only | Current weights | 56.15% |
| `keepCostWeight` | 1.05, 1.35, 1.50 | 43.10%, 61.15%, 64.25% |
| `endgameBeacons` | 2, 5 | 61.00%, 58.70% |
| `planProgress` | 2.0, 0.9 | 56.55%, 55.95% |
| `endgamePointsBoost` | 1.0, 2.0 | 56.05%, 56.15% |
| `urgency` | 1.0, 2.0 | 56.45%, 56.55% |
| `offPlanPenalty` | 1.0 | 27.60% |
| `cardNeed` | 5.0 | 62.70% |
| `contractBeaconFloor` | 22 | 60.65% |

The second screen used the original endgame and 2,000 two-House games per variant from seed 42. Commander won 61.475% at `keepCostWeight` 1.35, 63.975% at 1.50, and 65.275% at 1.65. The difference between 1.50 and 1.65 was small relative to the uncertainty in this run. We kept 1.50 because it also cleared the target on a separate set of seeds and improved both four-House formats. Commander and Admiral now subtract 1.5 points per unit of remaining route length when deciding which offered Contracts to keep. Navigator still subtracts 1.2.

| Match | Games | Seed | Before | With 1.50 |
| --- | ---: | ---: | ---: | ---: |
| Commander vs Navigator | 2,000 | 42 | 57.575% | 63.975% |
| Commander vs Navigator | 2,000 | 100042 | 56.225% | 64.250% |
| Cadet, Pilot, Navigator, Commander | 1,000 | 42 | 47.8% vs 39.9% | 51.3% vs 37.1% |
| Cadet, Pilot, Navigator, Commander, hazards on | 1,000 | 42 | 47.1% vs 41.0% | 51.85% vs 38.55% |

At the standard two-House seed, Commander's average completed Contracts rose from 1.923 to 2.057, and average failed Contracts fell from 0.989 to 0.856. Every screen and validation run reported zero illegal moves. Reproduce the final configuration with `Tournament --a 4 --b 3 --players 2 --games 2000 --seed 42`, then repeat with `--seed 100042`. The four-House commands are in M8.

## M7: Level 5 Admiral

Admiral settings: the Commander's planner, scorer, opponent model and weights, temperature 0, mistake rate 0,
`playouts` 48. Search values: `candidates` 6 (so 8 sampled states a decision), playout policy Navigator with
temperature 0.3 and mistake rate 0. Every candidate is played on the same sampled states with the same playout
rng. These are the starting values; the 60% target was met on the first run, so no tuning was done.

Timing, release mode, one game at a time:

```text
$ swift run -c release Tournament --a 5 --b 4 --games 4 --players 2 --seed 1 --timing
4 games, 2 players, seed 1, hazards off
seats: Admiral, Commander
level      samples  win rate  95% CI          avg score  completed  failed
Commander        4     25.0%  4.6% - 69.9%         57.2       1.75    1.25
Admiral          4     75.0%  30.1% - 95.4%        89.5       1.50    0.75
avg turns 76.5, illegal moves 0
Admiral decisions 247, mean 0.248 s, max 0.628 s
```

The maximum is under the 1.5 s target. `playouts` was left at 48: the target is met by a wide margin, the
spare time covers slower machines, and the 400-game match already takes about 20 minutes on 12 cores
(72 playouts would take about 30).

```text
$ swift run -c release Tournament --a 5 --b 4 --games 400 --players 2 --seed 42
400 games, 2 players, seed 42, hazards off
seats: Admiral, Commander
level      samples  win rate  95% CI          avg score  completed  failed
Commander      400     17.5%  14.1% - 21.5%        61.0       1.91    1.09
Admiral        400     82.5%  78.5% - 85.9%        86.7       1.42    0.61
avg turns 72.2, illegal moves 0
```

### After Contract selection tuning

```text
$ swift run -c release Tournament --a 5 --b 4 --games 400 --players 2 --seed 42
400 games, 2 players, seed 42, hazards off
seats: Admiral, Commander
level      samples  win rate  95% CI          avg score  completed  failed
Commander      400     19.0%  15.5% - 23.1%        65.6       2.06    0.97
Admiral        400     81.0%  76.9% - 84.5%        87.2       1.47    0.57
avg turns 72.2, illegal moves 0
```

Admiral won 81.0% against the tuned Commander and cleared the 60% target. The original 82.5% above was measured before the Commander tune-ups.

## M8: Ladder and crowded boards

The follow-up runs use the release build with `keepCostWeight` 1.5 for Commander and Admiral and seed 42. M6 records the Commander baseline and the independent validation at seed 100042.

### Final ladder

Each matchup ran separately with the same seat order, seeds, and game counts as `Tournament --ladder --games 2000 --seed 42`. Individual reports also count illegal moves.

| Matchup | Games | Higher level wins | 95% interval | Target | Ladder floor |
| --- | ---: | ---: | --- | ---: | ---: |
| Pilot vs Cadet | 2,000 | 82.8% | 81.0% to 84.3% | 75% | 73.1% |
| Navigator vs Pilot | 2,000 | 80.0% | 78.2% to 81.7% | 65% | 62.9% |
| Commander vs Navigator | 2,000 | 64.0% | 61.8% to 66.1% | 60% | 57.8% |
| Admiral vs Commander | 400 | 81.0% | 76.9% to 84.5% | 60% | 55.1% |

All four matchups cleared their targets and reported zero illegal moves. Commander also won 64.25% in a separate 2,000-game run.

### Short ladder

```text
$ Tournament --ladder --games 200 --seed 42
Pilot vs Cadet           200 games  win rate  78.0%  target 75%  floor  68.9%  pass
Navigator vs Pilot       200 games  win rate  77.5%  target 65%  floor  58.3%  pass
Commander vs Navigator   200 games  win rate  64.5%  target 60%  floor  53.1%  pass
Admiral vs Commander      40 games  win rate  82.5%  target 60%  floor  44.5%  pass
exit 0
```

This is the command used by `scripts/ladder.sh`. The full Swift test suite also passed with 248 core tests and 36 app tests.

### 4-player mixed levels

```text
$ Tournament --levels 1,2,3,4 --games 1000 --seed 42
1000 games, 4 players, seed 42, hazards off
seats: Cadet, Pilot, Navigator, Commander
level      samples  win rate  95% CI          avg score  completed  failed
Cadet         1000      0.0%  0.0% - 0.4%           7.7       0.16    3.44
Pilot         1000     11.6%  9.8% - 13.7%         40.2       1.62    2.49
Navigator     1000     37.1%  34.2% - 40.1%        73.6       2.31    0.90
Commander     1000     51.3%  48.2% - 54.4%        79.2       2.36    0.83
avg turns 156.5, illegal moves 0
```

```text
$ Tournament --levels 1,2,3,4 --games 1000 --seed 42 --hazards
1000 games, 4 players, seed 42, hazards on
seats: Cadet, Pilot, Navigator, Commander
level      samples  win rate  95% CI          avg score  completed  failed
Cadet         1000      0.3%  0.1% - 0.9%          11.7       0.20    3.28
Pilot         1000      9.3%  7.7% - 11.3%         31.1       1.48    2.66
Navigator     1000     38.6%  35.6% - 41.6%        66.3       2.13    0.99
Commander     1000     51.8%  48.8% - 54.9%        71.8       2.20    0.91
avg turns 145.5, illegal moves 0
```

```text
$ Tournament --levels 2,3,4,5 --games 100 --seed 42
100 games, 4 players, seed 42, hazards off
seats: Pilot, Navigator, Commander, Admiral
level      samples  win rate  95% CI          avg score  completed  failed
Pilot          100      3.0%  1.0% - 8.5%          20.8       1.26    2.96
Navigator      100     16.0%  10.1% - 24.4%        66.2       2.44    0.99
Commander      100     25.5%  18.0% - 34.8%        70.0       2.44    0.88
Admiral        100     55.5%  45.7% - 64.9%        86.2       1.49    0.63
avg turns 145.2, illegal moves 0
```

Commander leads Navigator in the 1,000-game runs with and without Frontier Hazards. Admiral leads the 100-game mixed run, where Commander finishes second by win rate. All 2,100 four-House games reported zero illegal moves.
