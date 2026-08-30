#!/usr/bin/env bash
set -Eeuo pipefail

operation=${1:-}
device_id=${2:-}
argument=${3:-}

[[ "$operation" =~ ^(status|action)$ ]] || exit 64
[[ -n "$device_id" && "$device_id" != *$'\t'* && "$device_id" != *$'\n'* && "$device_id" != *' '* && "$device_id" != */* ]] || exit 64

for cmd in gdbus sed tr; do
    command -v "$cmd" >/dev/null 2>&1 || exit 127
done

base="/modules/kdeconnect/devices/$device_id/mprisremote"

property() {
    local name=$1
    gdbus call --session --dest org.kde.kdeconnect \
        --object-path "$base" --method org.freedesktop.DBus.Properties.Get \
        "org.kde.kdeconnect.device.mprisremote" "$name" 2>/dev/null || return 69
}

value() {
    # gdbus quotes strings as <'value'> and scalar values as <value>.
    printf '%s' "$1" | sed -E "s/^\((true|false),\)$/\1/; s/^\(<('([^']|\\\\')*'|[^>]+)>.*$/\1/; s/^<'(.*)'>,?$/\1/; s/^<([^>]*)>,?$/\1/; s/^'(.*)'$/\1/"
}

case "$operation" in
    status)
        is_playing=$(value "$(property isPlaying 2>/dev/null)") || is_playing=false
        title=$(value "$(property title 2>/dev/null)") || title=""
        artist=$(value "$(property artist 2>/dev/null)") || artist=""
        album=$(value "$(property album 2>/dev/null)") || album=""
        player=$(value "$(property player 2>/dev/null)") || player=""

        [[ "$is_playing" == true ]] || is_playing=false

        if command -v python3 >/dev/null 2>&1; then
            python3 -c "import json, sys; print(json.dumps({'isPlaying': sys.argv[1]=='true', 'title': sys.argv[2], 'artist': sys.argv[3], 'album': sys.argv[4], 'player': sys.argv[5]}))" \
                "$is_playing" "$title" "$artist" "$album" "$player"
        else
            printf '{"isPlaying":%s,"title":"%s","artist":"%s","album":"%s","player":"%s"}\n' \
                "$is_playing" "${title//\"/\\\"}" "${artist//\"/\\\"}" "${album//\"/\\\"}" "${player//\"/\\\"}"
        fi
        ;;
    action)
        action_name="$argument"
        [[ -n "$action_name" && "$action_name" =~ ^[A-Za-z]+$ ]] || exit 64
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.kde.kdeconnect.device.mprisremote.sendAction "$action_name" >/dev/null 2>&1 || exit 69
        ;;
    *)
        exit 64
        ;;
esac
