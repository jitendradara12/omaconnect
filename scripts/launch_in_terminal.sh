#!/usr/bin/env bash
# Launch a target script in a terminal emulator.
#
# The target path always arrives as a single argv element ($1) and is passed
# on as argv wherever possible. The Omarchy floating-terminal launcher only
# accepts a single command *string*, which a shell will re-parse; for that
# path the script builds the string with printf '%q' so the target path
# survives re-parsing even when it contains quotes, spaces, or dollar signs.
#
# Verified contract of omarchy-launch-floating-terminal-with-presentation:
# it joins its arguments with "$*" and later runs `bash -c "<that string>"`,
# so exactly one argument is handed over and the %q quoting round-trips.
# `bash --` (both paths) keeps a target starting with '-' from being parsed
# as an option — printf '%q' alone does not neutralize a leading dash.
set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
    echo "Usage: launch_in_terminal.sh <script-path>" >&2
    exit 2
fi
target="$1"

if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    exec omarchy-launch-floating-terminal-with-presentation "bash -- $(printf '%q' "$target")"
elif command -v xdg-terminal-exec >/dev/null 2>&1; then
    exec xdg-terminal-exec bash -- "$target"
else
    echo "No terminal launcher found (need omarchy-launch-floating-terminal-with-presentation or xdg-terminal-exec)." >&2
    exit 127
fi
