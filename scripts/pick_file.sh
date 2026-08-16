#!/usr/bin/env bash
set -uo pipefail

if [[ -n "${OMARCHY_PATH:-}" ]]; then
    export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"
else
    export PATH="$HOME/.local/bin:$PATH"
fi

roots=("$HOME/Downloads" "$HOME/Documents" "$HOME/Pictures" "$HOME/Videos")
formats=(jpg jpeg png webp gif heic avif mp4 mov m4v mkv webm avi pdf txt zip tar gz iso)

# omarchy-menu-select serialises the option list into a single argv entry for
# perl, so the picker dies with E2BIG once that entry exceeds Linux's
# MAX_ARG_STRLEN (32 pages, 128 KiB). The controller reads that non-zero exit as
# a cancelled selection, so one crowded media folder silently disables sharing.
# Offer the most recently modified matches that fit a conservative budget.
budget_bytes=$((64 * 1024))

# omarchy-menu-file aborts when any of its roots is missing, so resolve them here.
search_roots=()
for root in "${roots[@]}"; do
    [[ -d $root ]] && search_roots+=("$root")
done
(( ${#search_roots[@]} )) || exit 1

find_args=("${search_roots[@]}" "(" -type d -name ".*" ! -name "." -prune ")" -o -type f ! -name ".*" "(")
for index in "${!formats[@]}"; do
    (( index )) && find_args+=(-o)
    find_args+=(-iname "*.${formats[index]}")
done
find_args+=(")" -printf '%T@\t%p\n')

# Collect before piping: an early awk exit would otherwise surface as the
# pipeline's SIGPIPE status and mask the menu's own exit code.
candidates=$(find "${find_args[@]}" 2>/dev/null | sort -rn | cut -f2- |
    LC_ALL=C awk -v budget="$budget_bytes" '
        { budget -= length($0) + 8 }  # per-row JSON quoting overhead
        budget < 0 { exit }
        { print }')
[[ -n $candidates ]] || exit 1

printf '%s\n' "$candidates" | omarchy-menu-select "Select file to send" -- --width 800 --maxheight 500
