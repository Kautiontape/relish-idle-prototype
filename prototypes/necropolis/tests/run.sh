#!/usr/bin/env bash
# Usage: tests/run.sh [--only=a,b] [--slow]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! out=$(godot --headless --path "$DIR" --import 2>&1); then
	printf '%s\n' "$out"
	exit 1
fi

exec godot --headless --path "$DIR" --script res://tests/run_tests.gd -- "$@"
