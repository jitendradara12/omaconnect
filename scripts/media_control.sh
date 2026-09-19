#!/usr/bin/env bash
set -Eeuo pipefail

operation=${1:-}
device_id=${2:-}
argument=${3:-}

[[ "$operation" =~ ^(status|action|player|request_players)$ ]] || exit 64
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

def query_all_props():
    try:
        res = subprocess.run([
            "gdbus", "call", "--session", "--dest", "org.kde.kdeconnect",
            "--object-path", base, "--method", "org.freedesktop.DBus.Properties.GetAll",
            "org.kde.kdeconnect.device.mprisremote"
        ], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except Exception:
        pass
    return ""

def clean_val(raw):
    raw = raw.strip()
    if not raw:
        return ""
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
    return val.replace(r"\'", "'").replace(r'\"', '"').replace(r"\\", "\\")

raw_all = query_all_props()

if raw_all and ("'isPlaying':" in raw_all or "'title':" in raw_all or "'player':" in raw_all):
    is_playing = bool(re.search(r"'isPlaying':\s*<(true|@b\s+true)>", raw_all, re.I))
    def unescape(s):
        return s.replace(r"\'", "'").replace(r'\"', '"').replace(r"\\", "\\")

    def extract_str(key):
        m = re.search(r"'" + key + r"':\s*<(?:@s\s+)?(['\"])((?:\\.|(?!\1).)*)\1>", raw_all, re.DOTALL)
        return unescape(m.group(2)) if m else ""

    title = extract_str("title") or extract_str("nowPlaying")
    artist = extract_str("artist")
    album = extract_str("album")
    player = extract_str("player")
    album_art = extract_str("localAlbumArtUrl") or extract_str("albumArtUrl") or extract_str("artUrl") or extract_str("albumArt")
    player_list = []
    m_pl = re.search(r"'playerList':\s*<.*?\[(.*?)\]>", raw_all, re.DOTALL)
    if m_pl:
        raw_items = re.findall(r"(['\"])((?:\\.|(?!\1).)*)\1", m_pl.group(1), re.DOTALL)
        player_list = [unescape(item[1]) for item in raw_items]
else:
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

    is_playing_raw = get_prop("isPlaying")
    is_playing = "<true>" in is_playing_raw or "(true," in is_playing_raw
    title = clean_val(get_prop("title")) or clean_val(get_prop("nowPlaying"))
    artist = clean_val(get_prop("artist"))
    album = clean_val(get_prop("album"))
    player = clean_val(get_prop("player"))
    album_art = clean_val(get_prop("localAlbumArtUrl")) or clean_val(get_prop("albumArtUrl")) or clean_val(get_prop("artUrl")) or clean_val(get_prop("albumArt"))
    player_list_raw = get_prop("playerList")
    player_list = []
    if player_list_raw:
        matches = re.findall(r"'([^']*)'", player_list_raw, re.DOTALL)
        player_list = matches if matches else re.findall(r'"([^"]*)"', player_list_raw, re.DOTALL)

if not player and player_list:
    player = player_list[0]
    try:
        escaped_player = player.replace("\\", "\\\\").replace("'", r"\'")
        subprocess.run([
            "gdbus", "call", "--session", "--dest", "org.kde.kdeconnect",
            "--object-path", base, "--method", "org.freedesktop.DBus.Properties.Set",
            "org.kde.kdeconnect.device.mprisremote", "player", f"<'{escaped_player}'>"
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
    request_players)
        gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$base" \
            --method org.kde.kdeconnect.device.mprisremote.requestPlayerList >/dev/null 2>&1 || true
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
