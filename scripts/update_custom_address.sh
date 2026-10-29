#!/usr/bin/env bash
set -Eeuo pipefail

# Add/remove a KDE Connect custom device address. The list lives in the
# daemon's customDevices property and is persisted by KDE Connect itself.
# The current list is read with `busctl --user --json=short get-property`
# and parsed by discover_report.py (dependency: busctl/systemd + python3
# instead of gdbus/sed/tr -- the old text extraction could not survive
# quoting inside values); the write stays a single busctl set-property call
# in pure argv.

operation=${1:-}
target=${2:-}
base=/modules/kdeconnect

[[ "$operation" == add || "$operation" == remove ]] || exit 64
[[ -n "$target" && "$target" != -* && "$target" != *$'\t'* && "$target" != *$'\n'* && "$target" != *' '* && "$target" != */* ]] || exit 64

for dependency in busctl python3; do
    command -v "$dependency" >/dev/null 2>&1 || exit 127
done
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
report="$script_dir/discover_report.py"

raw=$(busctl --user --json=short get-property org.kde.kdeconnect "$base" \
    org.kde.kdeconnect.daemon customDevices 2>/dev/null) || exit 69

entries=$(printf '%s' "$raw" | python3 "$report" addresses) || exit 70

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
