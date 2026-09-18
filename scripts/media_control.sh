#!/usr/bin/env bash
set -Eeuo pipefail

operation=${1:-}
device_id=${2:-}
argument=${3:-}

[[ "$operation" =~ ^(status|action|player)$ ]] || exit 64
[[ -n "$device_id" && "$device_id" != *$'\t'* && "$device_id" != *$'\n'* && "$device_id" != *' '* && "$device_id" != */* ]] || exit 64

for cmd in gdbus; do
    command -v "$cmd" >/dev/null 2>&1 || exit 127
done

base="/modules/kdeconnect/devices/$device_id/mprisremote"

case "$operation" in
    status)
        command -v python3 >/dev/null 2>&1 || exit 127
        python3 - "$device_id" << 'PYEOF'
import sys, json, subprocess, re

device_id = sys.argv[1]
base = f"/modules/kdeconnect/devices/{device_id}/mprisremote"

def get_prop(name):
    try:
        res = subprocess.run([
            "gdbus", "call", "--session", "--dest", "org.kde.kdeconnect",
            "--object-path", base, "--method", "org.freedesktop.DBus.Properties.Get",
            "org.kde.kdeconnect.device.mprisremote", name
        ], capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            return res.stdout.strip()
    except Exception:
        pass
    return ""

def clean_val(raw):
    raw = raw.strip()
    if not raw:
        return ""
    # Strip enclosing (<...>,) or (<...>)
    m = re.search(r"\(<(.+)>\s*,\s*\)", raw, re.DOTALL)
    if m:
        val = m.group(1).strip()
    else:
        m2 = re.search(r"<\s*['\"]?(.*?)['\"]?\s*>", raw, re.DOTALL)
        val = m2.group(1).strip() if m2 else raw
    if val.startswith("'") and val.endswith("'"):
        val = val[1:-1]
    elif val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    return val

is_playing_raw = get_prop("isPlaying")
is_playing = "<true>" in is_playing_raw or "(true," in is_playing_raw

title = clean_val(get_prop("title"))
if not title:
    title = clean_val(get_prop("nowPlaying"))

artist = clean_val(get_prop("artist"))
album = clean_val(get_prop("album"))
player = clean_val(get_prop("player"))

# KDE Connect exposes downloaded artwork as a local file URL.
album_art = clean_val(get_prop("localAlbumArtUrl"))
if not album_art:
    album_art = clean_val(get_prop("albumArtUrl"))
if not album_art:
    album_art = clean_val(get_prop("artUrl"))
if not album_art:
    album_art = clean_val(get_prop("albumArt"))

# Check player list
player_list_raw = get_prop("playerList")
player_list = []
if player_list_raw:
    # Match strings in array e.g. ['YT Music', 'Spotify']
    matches = re.findall(r"'([^']*)'", player_list_raw)
    if matches:
        player_list = matches
    else:
        # Fallback double quotes
        matches = re.findall(r'"([^"]*)"', player_list_raw)
        if matches:
            player_list = matches

if not player_list:
    try:
        subprocess.run([
            "gdbus", "call", "--session", "--dest", "org.kde.kdeconnect",
            "--object-path", base, "--method", "org.kde.kdeconnect.device.mprisremote.requestPlayerList"
        ], capture_output=True, text=True, timeout=1)
    except Exception:
        pass

if player and player not in player_list:
    player_list.insert(0, player)

out = {
    "isPlaying": is_playing,
    "title": title,
    "artist": artist,
    "album": album,
    "player": player,
    "playerList": player_list,
    "albumArt": album_art
}
print(json.dumps(out))
PYEOF
        ;;
    action)
        action_name="$argument"
        [[ "$action_name" =~ ^(PlayPause|Next|Previous)$ ]] || exit 64
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.kde.kdeconnect.device.mprisremote.sendAction "$action_name" >/dev/null 2>&1 || exit 69
        ;;
    player)
        target_player="$argument"
        [[ -n "$target_player" && "$target_player" != *$'\n'* && "$target_player" != *$'\r'* ]] || exit 64
        escaped_player=${target_player//\\/\\\\}
        escaped_player=${escaped_player//\'/\\\'}
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.freedesktop.DBus.Properties.Set \
            "org.kde.kdeconnect.device.mprisremote" "player" "<'$escaped_player'>" >/dev/null 2>&1 || exit 69
        ;;
    *)
        exit 64
        ;;
esac
