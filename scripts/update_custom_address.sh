#!/usr/bin/env bash
set -Eeuo pipefail

operation=${1:-}
target=${2:-}
base=/modules/kdeconnect

[[ "$operation" == add || "$operation" == remove ]] || exit 64
[[ -n "$target" && "$target" != *$'\t'* && "$target" != *$'\n'* && "$target" != *' '* && "$target" != */* ]] || exit 64

for dependency in gdbus busctl sed tr; do
    command -v "$dependency" >/dev/null 2>&1 || exit 127
done

raw=$(gdbus call --session --dest org.kde.kdeconnect \
    --object-path "$base" --method org.freedesktop.DBus.Properties.Get \
    org.kde.kdeconnect.daemon customDevices 2>/dev/null) || exit 69

entries=$(printf '%s' "$raw" | sed -E 's/.*\[//; s/\].*//' | tr ',' '\n' \
    | sed -nE "s/^[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\1/p")
[[ -n "$entries" || "$raw" =~ \[[[:space:]]*\] ]] || exit 70

addresses=()
found=false
while IFS= read -r address; do
    [[ -n "$address" ]] || continue
    if [[ "$address" == "$target" ]]; then
        found=true
        [[ "$operation" == remove ]] && continue
    fi
    addresses+=("$address")
done <<< "$entries"

if [[ "$operation" == add && "$found" != true ]]; then
    addresses+=("$target")
fi

busctl --user set-property org.kde.kdeconnect /modules/kdeconnect \
    org.kde.kdeconnect.daemon customDevices as "${#addresses[@]}" "${addresses[@]}"
