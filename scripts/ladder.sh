#!/bin/bash
# Short ladder check: each level against the one below it, 200 games a rung (40 for Admiral).
# Exits 1 if any rung misses its target by more than two standard errors.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release Tournament --ladder --games 200 --seed 42
