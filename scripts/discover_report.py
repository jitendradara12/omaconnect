#!/usr/bin/env python3
"""Structured busctl --json=short parsing for the discovery/address scripts.

Replaces the gdbus-text sed chains in discover_devices.sh and
update_custom_address.sh: gdbus quotes strings as <'value'> and wraps
multiline values, which no sed substitution chain can un reliably. busctl
emits JSON, so hostile device names and metadata are values again, never
syntax (a name containing a tab cannot forge extra TSV fields).

Importable as a module for unit tests; every parse function returns None on
malformed input instead of raising. Subcommands (exit 3 on malformed input,
which callers map to skip-device / exit-70):

    ids        stdin: daemon.devices() call reply          -> ids, one per line
    addresses  stdin: customDevices get-property reply     -> addresses, one per line
    truthy     stdin: single-boolean call reply            -> exit 0 iff data == [true]
    device     argv: <id> <device_json> <battery_json> <connectivity_json>
              -> one 14-field DEVICE tab-separated line for the QML contract

Dependencies: busctl (systemd) for the callers, python3.
"""

import sys

from media_status import parse_call_result, parse_properties

# Same capability list, same order, as the old discover_devices.sh loop.
PLUGIN_FILTER = [
    "kdeconnect_battery",
    "kdeconnect_ping",
    "kdeconnect_share",
    "kdeconnect_runcommand",
    "kdeconnect_findmyphone",
    "kdeconnect_clipboard",
    "kdeconnect_connectivity_report",
    "kdeconnect_sms",
    "kdeconnect_mprisremote",
    "kdeconnect_mpriscontrol",
    "kdeconnect_mpris",
]


def parse_string_list(raw):
    """as-typed string list -> list of non-empty strings, or None.

    Accepts both reply shapes: `call` wraps the return value once
    ({"data": [["a", "b"]]}), `get-property` returns the value directly
    ({"data": ["a", "b"]}).
    """
    obj = parse_call_result(raw)
    if obj is None:
        return None
    data = obj
    if len(data) == 1 and isinstance(data[0], list):
        data = data[0]
    if not isinstance(data, list):
        return None
    return [item for item in data if isinstance(item, str) and item]


def sanitize(text):
    """Fold tabs/newlines to spaces: a remote value must never forge TSV."""
    return str(text).replace("\t", " ").replace("\n", " ")


def _field(value):
    if isinstance(value, str):
        return value
    if value is None or isinstance(value, (bool, list, dict)):
        return ""
    return str(value)


def _flag(value):
    return "true" if value is True else "false"


def _nonneg_int(value):
    if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
        return value
    return None


def format_device(device_id, device_props, battery_props=None, conn_props=None):
    """Flattened GetAll properties -> the frozen 14-field DEVICE TSV line.

    Fields: DEVICE, id, name, type, paired, reachable, charge (-1 n/a),
    charging, plugins (comma list), netType, netStrength (-1 n/a),
    pairRequested, pairRequestedByPeer, verificationKey. Battery and
    connectivity values are only honored when the corresponding plugin is in
    the device's supportedPlugins list, mirroring the old gating.
    """
    props = device_props or {}
    supported = props.get("supportedPlugins")
    supported = {p for p in supported if isinstance(p, str)} if isinstance(supported, list) else set()
    plugins = [p for p in PLUGIN_FILTER if p in supported]
    plugin_set = set(plugins)

    charge = -1
    charging = False
    if "kdeconnect_battery" in plugin_set and battery_props:
        value = _nonneg_int(battery_props.get("charge"))
        if value is not None:
            charge = value
        charging = battery_props.get("isCharging") is True

    net_type = ""
    net_strength = -1
    if "kdeconnect_connectivity_report" in plugin_set and conn_props:
        raw_type = conn_props.get("cellularNetworkType")
        if isinstance(raw_type, str) and raw_type and raw_type != "null":
            net_type = raw_type
        strength = _nonneg_int(conn_props.get("cellularNetworkStrength"))
        if strength is not None:
            net_strength = strength

    fields = [
        "DEVICE",
        sanitize(_field(device_id)),
        sanitize(_field(props.get("name"))),
        sanitize(_field(props.get("type"))),
        _flag(props.get("isPaired")),
        _flag(props.get("isReachable")),
        str(charge),
        _flag(charging),
        ",".join(plugins),
        sanitize(net_type),
        str(net_strength),
        _flag(props.get("isPairRequested")),
        _flag(props.get("isPairRequestedByPeer")),
        sanitize(_field(props.get("verificationKey"))),
    ]
    return "\t".join(fields)


def _fail(message):
    print("discover_report: %s" % (message,), file=sys.stderr)
    return 3


def main(argv):
    if len(argv) < 2:
        print("usage: discover_report.py ids|addresses|truthy|device ...", file=sys.stderr)
        return 64
    command = argv[1]

    if command in ("ids", "addresses"):
        items = parse_string_list(sys.stdin.read())
        if items is None:
            return _fail("malformed %s reply" % (command,))
        for item in items:
            print(sanitize(item))
        return 0

    if command == "truthy":
        data = parse_call_result(sys.stdin.read())
        return 0 if data == [True] else 1

    if command == "device":
        if len(argv) < 6:
            print("usage: discover_report.py device <id> <device_json> <battery_json> <conn_json>", file=sys.stderr)
            return 64
        device_props = parse_properties(argv[3]) if argv[3].strip() else None
        battery_props = parse_properties(argv[4]) if argv[4].strip() else None
        conn_props = parse_properties(argv[5]) if argv[5].strip() else None
        if device_props is None:
            return _fail("malformed device GetAll reply")
        print(format_device(argv[2], device_props, battery_props, conn_props))
        return 0

    print("discover_report: unknown command %r" % (command,), file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
