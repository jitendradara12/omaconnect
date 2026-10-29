#!/usr/bin/env bash
# Launch a target script in a terminal emulator.
#
# The target path always arrives as a single argv element ($1) and is passed
# on as argv wherever possible. The Omarchy floating-terminal launcher only
# accepts a single command *string*, which a shell will re-parse; for that
# path the script builds the string with printf '%q' so the target path
# survives re-parsing even when it contains quotes, spaces, or dollar signs.
set -euo pipefail

target="${1:-}"
if [[ -z "$target" ]]; then
    echo "Usage: launch_in_terminal.sh <script-path>" >&2
    exit 2
fi

if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    exec omarchy-launch-floating-terminal-with-presentation "bash $(printf '%q' "$target")"
elif command -v xdg-terminal-exec >/dev/null 2>&1; then
    exec xdg-terminal-exec bash "$target"
else
    echo "No terminal launcher found (need omarchy-launch-floating-terminal-with-presentation or xdg-terminal-exec)." >&2
    exit 127
fi
