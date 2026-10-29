#!/usr/bin/env bash
set -Eeuo pipefail

# Media playback control over org.kde.kdeconnect.device.mprisremote.
#
# Transport is `busctl --user` (systemd) instead of gdbus: every remote-
# chosen value crosses as a single argv element, so player names with
# apostrophes, quotes or spaces need no escaping hack (the gdbus
# escaped_player quoting is gone). `status` delegates to media_status.py,
# a pure parser over busctl --json=short GetAll output that is importable
# for unit tests and emits the frozen JSON contract:
#   {isPlaying, title, artist, album, player, playerList, albumArt}
# (albumArt falls back localAlbumArtUrl -> albumArtUrl -> artUrl -> albumArt;
# title falls back to nowPlaying; an empty player auto-selects the first
# playerList entry via a pure-argv busctl set-property call).
#
# Exit codes: 64 bad usage, 127 missing dependencies, 69 D-Bus failure.

operation=${1:-}
device_id=${2:-}
argument=${3:-}

[[ "$operation" =~ ^(status|action|player|request_players)$ ]] || exit 64
[[ -n "$device_id" && "$device_id" != *$'\t'* && "$device_id" != *$'\n'* && "$device_id" != *' '* && "$device_id" != */* ]] || exit 64

command -v busctl >/dev/null 2>&1 || exit 127

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
base="/modules/kdeconnect/devices/$device_id/mprisremote"

case "$operation" in
    status)
        command -v python3 >/dev/null 2>&1 || exit 127
        exec python3 "$script_dir/media_status.py" "$device_id"
        ;;
    request_players)
        busctl --user call org.kde.kdeconnect "$base" \
            org.kde.kdeconnect.device.mprisremote requestPlayerList >/dev/null 2>&1 || true
        ;;
    action)
        action_name="$argument"
        [[ "$action_name" =~ ^(PlayPause|Next|Previous)$ ]] || exit 64
        busctl --user call org.kde.kdeconnect "$base" \
            org.kde.kdeconnect.device.mprisremote sendAction s "$action_name" >/dev/null 2>&1 || exit 69
        ;;
    player)
        target_player="$argument"
        [[ -n "$target_player" && "$target_player" != *$'\n'* && "$target_player" != *$'\r'* ]] || exit 64
        busctl --user set-property org.kde.kdeconnect "$base" \
            org.kde.kdeconnect.device.mprisremote player s "$target_player" >/dev/null 2>&1 || exit 69
        ;;
    *)
        exit 64
        ;;
esac
