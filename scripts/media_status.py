#!/usr/bin/env python3
"""Media player status for a KDE Connect device, parsed from structured JSON.

`media_control.sh status` delegates here. The D-Bus transport is
`busctl --user --json=short` (systemd) instead of gdbus text: the old regex
parser over gdbus output broke on apostrophes, quotes and multiline values,
and needed a hand-rolled escaper for the player write. busctl replies are
JSON, so remote-chosen metadata is data again, never syntax.

Stdout contract (frozen, consumed by KdeConnectController.qml):
    {"isPlaying": bool, "title": str, "artist": str, "album": str,
     "player": str, "playerList": [str], "albumArt": str}

Importable as a module for unit tests: build_status() is pure; main() is the
busctl driver. The first-player auto-select write is a busctl set-property
call in pure argv -- player names are never embedded in a quoted D-Bus
value expression. Replaces the gdbus escaped_player quoting hack.

Dependencies: busctl (systemd), python3.
"""

import json
import subprocess
import sys

PROPS_IFACE = "org.freedesktop.DBus.Properties"
MPRIS_IFACE = "org.kde.kdeconnect.device.mprisremote"
SERVICE = "org.kde.kdeconnect"

# albumArt fallback chain, most local first (same order as the old parser).
ART_KEYS = ("localAlbumArtUrl", "albumArtUrl", "artUrl", "albumArt")


def mpris_path(device_id):
    return "/modules/kdeconnect/devices/%s/mprisremote" % (device_id,)


# ---------- busctl --json=short parsing (port of omarchy-connect Model.js) ----------

def parse_call_result(raw):
    """busctl --json=short `call` reply -> list of return values, or None.

    Replies have the shape {"type": "...", "data": [<return values>]}; any
    malformed input yields None, never an exception.
    """
    if not isinstance(raw, (str, bytes)):
        return None
    try:
        obj = json.loads(raw)
    except Exception:
        return None
    if not isinstance(obj, dict) or not isinstance(obj.get("data"), list):
        return None
    return obj["data"]


def parse_properties(raw):
    """GetAll a{sv} reply -> flat {propName: value}, or None on bad input.

    data[0] is {propName: {type, data}}; the variant wrappers are stripped.
    """
    data = parse_call_result(raw)
    if not data or not isinstance(data[0], dict):
        return None
    props = {}
    for key, variant in data[0].items():
        if isinstance(variant, dict) and "data" in variant:
            props[key] = variant["data"]
    return props


# ---------- normalization ----------

def _s(props, key):
    value = props.get(key)
    return value if isinstance(value, str) else ""


def _as(props, key):
    value = props.get(key)
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def empty_status():
    return {
        "isPlaying": False,
        "title": "",
        "artist": "",
        "album": "",
        "player": "",
        "playerList": [],
        "albumArt": "",
    }


def build_status(props):
    """Flattened mprisremote properties -> (status dict, auto-select player).

    props may be None/empty (daemon down, object gone, malformed reply): the
    empty contract status is returned. Falls back title -> nowPlaying; when
    no player is set but players are known, the first one is selected and
    returned as the auto-select value so the caller can persist it.
    """
    props = props or {}
    status = empty_status()
    status["isPlaying"] = props.get("isPlaying") is True
    status["title"] = _s(props, "title") or _s(props, "nowPlaying")
    status["artist"] = _s(props, "artist")
    status["album"] = _s(props, "album")
    status["player"] = _s(props, "player")
    status["playerList"] = _as(props, "playerList")
    for key in ART_KEYS:
        if _s(props, key):
            status["albumArt"] = _s(props, key)
            break

    autoselect = None
    if not status["player"] and status["playerList"]:
        status["player"] = status["playerList"][0]
        autoselect = status["player"]
    if status["player"] and status["player"] not in status["playerList"]:
        status["playerList"] = [status["player"]] + status["playerList"]
    return status, autoselect


# ---------- busctl driver ----------

def fetch_props(device_id):
    argv = [
        "busctl", "--user", "--json=short", "call", SERVICE, mpris_path(device_id),
        PROPS_IFACE, "GetAll", "s", MPRIS_IFACE,
    ]
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=3)
    except Exception:
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return parse_properties(result.stdout)


def select_player(device_id, player):
    """Persist the auto-selected player. Pure argv: no escaping, ever."""
    argv = [
        "busctl", "--user", "set-property", SERVICE, mpris_path(device_id),
        MPRIS_IFACE, "player", "s", player,
    ]
    try:
        subprocess.run(argv, capture_output=True, text=True, timeout=2)
    except Exception:
        pass


def main(argv):
    device_id = argv[1] if len(argv) > 1 else ""
    try:
        status, autoselect = build_status(fetch_props(device_id))
        if autoselect:
            select_player(device_id, autoselect)
    except Exception as exc:  # status must always emit valid JSON, never a traceback
        print("media_status: %s" % (exc,), file=sys.stderr)
        status = empty_status()
    print(json.dumps(status))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
