#!/bin/sh
# Runs the headless suite. Fails on a failed check or on any script error in the output.
# Usage: tests/run_tests.sh [path-to-godot]   (run from godot/)
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.." || exit 2
"$GODOT" --headless --path . --import >/dev/null 2>&1
out=$("$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1)
code=$?
echo "$out" | grep -v '^Godot Engine'
if echo "$out" | grep -q 'SCRIPT ERROR'; then
	echo "script errors in the run"
	exit 1
fi
exit $code
