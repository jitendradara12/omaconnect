#!/usr/bin/env bash
set -Eeuo pipefail

operation=${1:-}
device_id=${2:-}
argument=${3:-}

[[ "$operation" =~ ^(status|action|volume|seek)$ ]] || exit 64
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
        vol_raw=$(value "$(property volume 2>/dev/null)") || vol_raw=-1
        pos_raw=$(value "$(property position 2>/dev/null)") || pos_raw=0
        len_raw=$(value "$(property length 2>/dev/null)") || len_raw=0
        can_seek=$(value "$(property canSeek 2>/dev/null)") || can_seek=false

        [[ "$is_playing" == true ]] || is_playing=false
        [[ "$can_seek" == true ]] || can_seek=false
        vol=-1
        [[ "$vol_raw" =~ ^-?[0-9]+$ ]] && vol=$vol_raw
        pos=0
        [[ "$pos_raw" =~ ^[0-9]+$ ]] && pos=$pos_raw
        len=0
        [[ "$len_raw" =~ ^[0-9]+$ ]] && len=$len_raw

        if command -v python3 >/dev/null 2>&1; then
            python3 -c "import json, sys; print(json.dumps({'isPlaying': sys.argv[1]=='true', 'title': sys.argv[2], 'artist': sys.argv[3], 'album': sys.argv[4], 'player': sys.argv[5], 'volume': int(sys.argv[6]), 'position': int(sys.argv[7]), 'length': int(sys.argv[8]), 'canSeek': sys.argv[9]=='true'}))" \
                "$is_playing" "$title" "$artist" "$album" "$player" "$vol" "$pos" "$len" "$can_seek"
        else
            printf '{"isPlaying":%s,"title":"%s","artist":"%s","album":"%s","player":"%s","volume":%d,"position":%d,"length":%d,"canSeek":%s}\n' \
                "$is_playing" "${title//\"/\\\"}" "${artist//\"/\\\"}" "${album//\"/\\\"}" "${player//\"/\\\"}" "$vol" "$pos" "$len" "$can_seek"
        fi
        ;;
    action)
        action_name="$argument"
        [[ -n "$action_name" && "$action_name" =~ ^[A-Za-z]+$ ]] || exit 64
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.kde.kdeconnect.device.mprisremote.sendAction "$action_name" >/dev/null 2>&1 || exit 69
        ;;
    volume)
        volume_val="$argument"
        [[ "$volume_val" =~ ^[0-9]+$ && "$volume_val" -ge 0 && "$volume_val" -le 100 ]] || exit 64
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.kde.kdeconnect.device.mprisremote.setVolume "$volume_val" >/dev/null 2>&1 || exit 69
        ;;
    seek)
        offset_val="$argument"
        [[ "$offset_val" =~ ^-?[0-9]+$ ]] || exit 64
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.kde.kdeconnect.device.mprisremote.seek "$offset_val" >/dev/null 2>&1 || exit 69
        ;;
    *)
        exit 64
        ;;
esac
