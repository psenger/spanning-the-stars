.PHONY: help run build bundle test ladder bench

BENCH_ARGS ?= --a 4 --b 3 --games 200 --players 2 --seed 42

help:
	@printf '%-14s %s\n' \
		'make help' 'List available targets' \
		'make run' 'Run the macOS app from source' \
		'make build' 'Compile the Swift package in release mode' \
		'make bundle' 'Build the app bundle in build/' \
		'make test' 'Run the Swift test suite' \
		'make ladder' 'Run the short AI difficulty ladder' \
		'make bench' 'Run a headless tournament (override BENCH_ARGS to choose the matchup)'

run:
	swift run SpanningTheStars

build:
	swift build -c release

bundle:
	scripts/bundle.sh

test:
	swift test

ladder:
	scripts/ladder.sh

bench:
	swift run -c release Tournament $(BENCH_ARGS)
