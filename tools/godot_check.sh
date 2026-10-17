#!/bin/sh
# Imports the Godot project headless and prints the unique script errors.
cd "$(dirname "$0")/.." || exit 1
LOG=$(mktemp)
timeout 900 tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --import >"$LOG" 2>&1
grep -A1 "SCRIPT ERROR\|Parse Error" "$LOG" | grep -v "^--" | paste - - | sed 's/\s\+/ /g' | sort | uniq | head -${1:-40}
echo "errors: $(grep -c 'SCRIPT ERROR' "$LOG")"
rm -f "$LOG"
