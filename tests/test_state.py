import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
BASH = shutil.which("bash") or "bash"


# ---------------------------------------------------------------------------
# Data parsing, formatting & command construction helpers
# ---------------------------------------------------------------------------

def parse_device(line):
    parts = line.split("\t")
    if len(parts) < 9 or parts[0] != "DEVICE":
        return None
    plugins = set(parts[8].split(","))
    net_type = parts[9].strip() if len(parts) > 9 else ""
    net_strength = int(parts[10]) if len(parts) > 10 and parts[10].isdigit() else -1
    return {
        "id": parts[1],
        "name": parts[2] or parts[1],
        "type": parts[3] or "unknown",
        "paired": parts[4] == "true",
        "reachable": parts[5] == "true",
        "battery": int(parts[6]) if parts[6].isdigit() else -1,
        "charging": parts[7] == "true",
        "networkType": net_type,
        "networkStrength": net_strength,
        "pairRequested": len(parts) > 11 and parts[11] == "true",
        "pairRequestedByPeer": len(parts) > 12 and parts[12] == "true",
        "verificationKey": parts[13].strip() if len(parts) > 13 else "",
        "capabilities": {
            "battery": "kdeconnect_battery" in plugins,
            "ping": "kdeconnect_ping" in plugins,
            "ring": "kdeconnect_findmyphone" in plugins,
            "text": "kdeconnect_share" in plugins,
            "clipboard": "kdeconnect_clipboard" in plugins,
            "file": "kdeconnect_share" in plugins,
            "commands": "kdeconnect_runcommand" in plugins,
            "network": "kdeconnect_connectivity_report" in plugins,
            "sms": "kdeconnect_sms" in plugins,
            "media": ("kdeconnect_mprisremote" in plugins)
            or ("kdeconnect_mpriscontrol" in plugins)
            or ("kdeconnect_mpris" in plugins),
            "pair": True,
        },
    }


def categorize(exit_code, operation):
    return {
        127: f"{operation} unavailable",
        69: f"{operation} unavailable",
        2: f"{operation} rejected",
        3: f"{operation} timed out",
    }.get(exit_code, f"{operation} failed")


def format_file_path(path):
    value = str(path or "").strip()
    if value.startswith("file://"):
        value = value[7:]
        from urllib.parse import unquote
        value = unquote(value)
    if "\x00" in value or not value:
        return None
    return value


def build_action_command(action_type, device_id, extra_arg=None):
    if action_type == "ring":
        return ["kdeconnect-cli", "-d", str(device_id), "--ring"]
    elif action_type == "clipboard":
        return ["kdeconnect-cli", "-d", str(device_id), "--send-clipboard"]
    elif action_type == "file":
        clean_path = format_file_path(extra_arg)
        if not clean_path:
            return None
        return ["kdeconnect-cli", "-d", str(device_id), "--share", clean_path]
    elif action_type == "sms":
        return ["bash", "scripts/open_sms.sh", str(device_id)]
    elif action_type == "ping":
        is_valid, content = validate_composer_input(extra_arg)
        if not is_valid:
            return None
        return ["kdeconnect-cli", "-d", str(device_id), "--ping-msg", content]
    elif action_type == "text":
        is_valid, content = validate_composer_input(extra_arg)
        if not is_valid:
            return None
        return ["kdeconnect-cli", "-d", str(device_id), "--share-text", content]
    return None


def format_network_status(device):
    if not device or not device.get("networkType"):
        return ""
    net_type = str(device.get("networkType")).strip()
    if not net_type or net_type == "null":
        return ""
    str_val = device.get("networkStrength", -1)
    if isinstance(str_val, int) and str_val >= 0:
        return f"{net_type} ({str_val}/4)"
    return net_type


def device_type_icon(dev_type):
    t = str(dev_type or "").lower().strip()
    return {
        "phone": "󰄜",
        "tablet": "󰓹",
        "laptop": "󰌢",
        "desktop": "󰍹",
        "tv": "󰵔",
    }.get(t, "󰄜")


def format_battery_status(device, show_battery=True, show_network=True):
    if not device or not device.get("reachable", True):
        return ""
    battery_text = ""
    if show_battery and device.get("capabilities", {}).get("battery") and device.get("battery", -1) >= 0:
        battery = device.get("battery", -1)
        charging = device.get("charging") or device.get("isCharging")
        if charging:
            battery_text = f"{battery}% • Charging"
        elif battery <= 20:
            battery_text = f"{battery}% • Low battery"
        else:
            battery_text = f"{battery}% • Discharging"
    net_text = format_network_status(device) if show_network else ""
    if battery_text and net_text:
        return f"{battery_text} • {net_text}"
    if battery_text:
        return battery_text
    if net_text:
        return net_text
    return ""


def compute_available_actions(device, settings=None):
    if not device or not device.get("paired") or not device.get("reachable"):
        return []
    caps = device.get("capabilities", {})
    s = settings or {}
    res = []
    if caps.get("ring") and s.get("showActionRing", True):
        res.append("ring")
    if caps.get("clipboard") and s.get("showActionClipboard", True):
        res.append("clipboard")
    if caps.get("file") and s.get("showActionFile", True):
        res.append("file")
    if caps.get("sms") and s.get("showActionSms", True):
        res.append("sms")
    if caps.get("ping") and s.get("showActionPing", False):
        res.append("ping")
    if caps.get("text") and s.get("showActionText", True):
        res.append("text")
    return res


def validate_composer_input(text):
    clean = str(text or "").strip()
    if not clean:
        return False, "Message cannot be empty"
    return True, clean


def format_overview_status(device):
    if not device:
        return "No devices found"
    if not device.get("paired"):
        return "Not paired"
    if not device.get("reachable"):
        return "Paired, offline"
    return "Paired & reachable"


def parse_remote_commands(text):
    source = str(text or "").strip()
    if not source:
        return []
    result = []
    try:
        data = json.loads(source)
        if data is None or not isinstance(data, (dict, list)):
            return []
        values = data if isinstance(data, list) else [{"key": k, "name": v} for k, v in data.items()]
        for item in values:
            if isinstance(item, str) and item.strip():
                result.append({"key": item.strip(), "name": item.strip()})
            elif isinstance(item, dict):
                k = item.get("key") or item.get("id") or item.get("command")
                if k is not None:
                    k_str = str(k).strip()
                    if k_str:
                        n = item.get("name") or item.get("label") or item.get("title") or k_str
                        result.append({"key": k_str, "name": str(n).strip() or k_str})
        return result
    except Exception:
        import re
        for line in source.splitlines():
            val = str(line or "").strip()
            val = re.sub(r"^[-*•]\s*|^\d+\.\s*", "", val).strip()
            if not val or re.search(r"no.*commands", val, re.IGNORECASE):
                continue
            if ":" in val:
                k, n = val.split(":", 1)
                k = k.strip()
                n = n.strip()
                if k:
                    result.append({"key": k, "name": n or k})
            elif val:
                result.append({"key": val, "name": val})
        return result


def accept_completion(target_generation, current_generation, target_id, selected_id):
    return target_generation == current_generation and target_id == selected_id


# ---------------------------------------------------------------------------
# Controller state machines
# ---------------------------------------------------------------------------

class MediaPlayerState:
    def __init__(self, selected_device_id="dev-1"):
        self.selected_device_id = selected_device_id
        self.is_playing = False
        self.title = ""
        self.artist = ""
        self.album = ""
        self.player = ""
        self.player_list = []
        self.album_art = ""
        self.loading = False

    def select_device(self, new_device_id):
        if self.selected_device_id != new_device_id:
            self.selected_device_id = new_device_id
            self.is_playing = False
            self.title = ""
            self.artist = ""
            self.album = ""
            self.player = ""
            self.player_list = []
            self.album_art = ""
            self.loading = False

    def apply_status(self, data, target_device_id):
        if target_device_id != self.selected_device_id:
            return False
        self.loading = False
        if not data or not isinstance(data, dict):
            self.is_playing = False
            self.title = ""
            self.artist = ""
            self.album = ""
            self.player = ""
            self.player_list = []
            self.album_art = ""
            return True

        self.is_playing = bool(data.get("isPlaying", False))
        self.title = str(data.get("title") or "")
        self.artist = str(data.get("artist") or "")
        self.album = str(data.get("album") or "")
        self.player = str(data.get("player") or "")
        self.player_list = list(data.get("playerList") or [])
        self.album_art = str(data.get("albumArt") or "")
        return True

    def select_player(self, player_name):
        if player_name in self.player_list:
            self.player = player_name
            return True
        return False

    def build_action_command(self, action_name):
        return ["bash", "scripts/media_control.sh", "action", str(self.selected_device_id), str(action_name)]

    def build_player_command(self, player_name):
        return ["bash", "scripts/media_control.sh", "player", str(self.selected_device_id), str(player_name)]

    def build_status_command(self):
        return ["bash", "scripts/media_control.sh", "status", str(self.selected_device_id)]


class ComposerState:
    def __init__(self, selected_device_id="dev-1"):
        self.active_composer = "none"  # "none", "ping", "text"
        self.draft_ping = ""
        self.draft_text = ""
        self.composer_error = ""
        self.action_state = "idle"  # "idle", "running", "accepted", "failed", "blocked"
        self.action_message = ""
        self.action_error = ""
        self.selected_device_id = selected_device_id
        self.action_generation = 0

    def open_composer(self, composer_type):
        if composer_type in ("ping", "text"):
            self.active_composer = composer_type
            self.composer_error = ""
        else:
            self.active_composer = "none"

    def close_composer(self):
        self.active_composer = "none"
        self.composer_error = ""

    def select_device(self, new_device_id):
        if self.selected_device_id != new_device_id:
            self.selected_device_id = new_device_id
            self.active_composer = "none"
            self.draft_ping = ""
            self.draft_text = ""
            self.composer_error = ""
            self.action_state = "idle"
            self.action_message = ""
            self.action_error = ""

    def submit_ping(self, text=None):
        input_text = text if text is not None else self.draft_ping
        is_valid, content_or_err = validate_composer_input(input_text)
        if not is_valid:
            self.composer_error = content_or_err
            self.action_state = "blocked"
            self.action_error = content_or_err
            self.action_message = ""
            return False

        self.action_generation += 1
        self.action_state = "running"
        self.action_message = "Requesting ping"
        self.action_error = ""
        self.draft_ping = ""
        self.close_composer()
        return True

    def submit_text(self, text=None):
        input_text = text if text is not None else self.draft_text
        is_valid, content_or_err = validate_composer_input(input_text)
        if not is_valid:
            self.composer_error = content_or_err
            self.action_state = "blocked"
            self.action_error = content_or_err
            self.action_message = ""
            return False

        self.action_generation += 1
        self.action_state = "running"
        self.action_message = "Requesting text share"
        self.action_error = ""
        self.draft_text = ""
        self.close_composer()
        return True

    def handle_action_completed(self, target_generation, target_device_id, exit_code, operation, accepted_msg):
        if target_generation != self.action_generation or target_device_id != self.selected_device_id:
            return False
        if exit_code == 0:
            self.action_state = "accepted"
            self.action_message = accepted_msg
            self.action_error = ""
        else:
            self.action_state = "failed"
            self.action_message = ""
            self.action_error = categorize(exit_code, operation)
        return True


class RemoteCommandsState:
    def __init__(self, selected_device_id="dev-1"):
        self.selected_device_id = selected_device_id
        self.commands_expanded = False
        self.commands_loading = False
        self.command_target_id = ""
        self.remote_commands = []
        self.generation = 1
        self.command_selected_index = 0

    def select_device(self, device_id):
        self.selected_device_id = device_id
        self.commands_expanded = False
        self.commands_loading = False
        self.command_target_id = ""
        self.remote_commands = []
        self.command_selected_index = 0

    def toggle_commands_expanded(self, device_capabilities):
        self.commands_expanded = not self.commands_expanded
        if self.commands_expanded and device_capabilities.get("commands"):
            return self.fetch_remote_commands(self.selected_device_id, device_capabilities)
        return False

    def fetch_remote_commands(self, device_id, device_capabilities):
        if not device_capabilities.get("commands") or device_id != self.selected_device_id:
            return False
        self.commands_loading = True
        self.command_target_id = device_id
        return True

    def handle_commands_completed(self, target_generation, target_device_id, exit_code, output):
        self.commands_loading = False
        if target_generation != self.generation or target_device_id != self.selected_device_id:
            return False
        self.remote_commands = parse_remote_commands(output) if exit_code == 0 else []
        return True

    def select_command(self, delta):
        if not self.remote_commands:
            return
        self.command_selected_index = max(0, min(len(self.remote_commands) - 1, self.command_selected_index + delta))


class PairingState:
    def __init__(self, devices=None, selected_device_id=""):
        self.devices = devices or []
        self.selected_device_id = selected_device_id or (self.devices[0]["id"] if self.devices else "")
        self.pending_pairing = {}
        self.pairing_request_times = {}
        self.unpair_confirming_id = ""
        self.action_state = "idle"
        self.action_message = ""
        self.action_error = ""
        self.generation = 1

    def select_device(self, device_id):
        device = next((d for d in self.devices if d["id"] == device_id), None)
        if not device:
            return False
        if self.selected_device_id != device["id"]:
            self.action_state = "idle"
            self.action_message = ""
            self.action_error = ""
            self.unpair_confirming_id = ""
        self.selected_device_id = device["id"]
        return True

    def refresh(self, force_network=False, current_time=0):
        if force_network:
            to_del = []
            for dev_id, state in self.pending_pairing.items():
                if state == "requesting":
                    req_time = self.pairing_request_times.get(dev_id, 0)
                    if not req_time or (current_time - req_time >= 10000):
                        to_del.append(dev_id)
            for dev_id in to_del:
                del self.pending_pairing[dev_id]

    def apply_scan(self, device_lines, target_generation):
        if target_generation != self.generation:
            return False
        next_devices = []
        for line in device_lines:
            dev = parse_device(line)
            if dev:
                next_devices.append(dev)
        self.devices = next_devices
        for dev in next_devices:
            if dev.get("paired"):
                if self.pending_pairing.get(dev["id"]) == "requesting":
                    del self.pending_pairing[dev["id"]]
                    if self.selected_device_id == dev["id"] or not self.selected_device_id:
                        self.action_state = "accepted"
                        self.action_message = "Device paired"
                        self.action_error = ""
                elif dev["id"] in self.pending_pairing:
                    del self.pending_pairing[dev["id"]]
            else:
                if self.pending_pairing.get(dev["id"]) in ("removing", "unpair_confirm"):
                    del self.pending_pairing[dev["id"]]
        if not any(d["id"] == self.selected_device_id for d in self.devices):
            preferred = next((d for d in self.devices if d.get("paired") and d.get("reachable")), None)
            if not preferred:
                preferred = next((d for d in self.devices if d.get("paired")), None)
            self.selected_device_id = (preferred or self.devices[0])["id"] if self.devices else ""
        return True

    def pair_device(self, device_id, timestamp=0):
        dev = next((d for d in self.devices if d["id"] == device_id), None)
        if not dev or not dev.get("capabilities", {}).get("pair"):
            return False
        if self.pending_pairing.get(device_id) in ("requesting", "removing", "unpair_confirm"):
            return False
        self.pending_pairing[device_id] = "requesting"
        self.pairing_request_times[device_id] = timestamp
        self.action_state = "accepted"
        self.action_message = "Pair request sent"
        self.action_error = ""
        return True

    def handle_timeout(self, device_id=None):
        target = device_id or self.selected_device_id
        if target in self.pending_pairing and self.pending_pairing[target] == "requesting":
            del self.pending_pairing[target]
        self.action_state = "failed"
        self.action_message = ""
        self.action_error = "Pairing timed out or rejected"

    def check_watchdog(self, current_time):
        timed_out = []
        for dev_id, state in list(self.pending_pairing.items()):
            if state == "requesting":
                req_time = self.pairing_request_times.get(dev_id, 0)
                if current_time - req_time >= 30000:
                    del self.pending_pairing[dev_id]
                    self.pairing_request_times.pop(dev_id, None)
                    timed_out.append(dev_id)
        if self.selected_device_id in timed_out:
            self.action_state = "failed"
            self.action_message = ""
            self.action_error = "Pairing timed out or rejected"
        return timed_out

    def request_unpair_confirm(self, device_id):
        dev = next((d for d in self.devices if d["id"] == device_id), None)
        if not dev or not dev.get("paired") or not dev.get("capabilities", {}).get("pair"):
            return False
        if self.pending_pairing.get(device_id) in ("requesting", "removing"):
            return False
        self.unpair_confirming_id = device_id
        self.pending_pairing[device_id] = "unpair_confirm"
        return True

    def cancel_unpair_confirm(self, device_id=None):
        target = device_id or self.unpair_confirming_id
        if self.unpair_confirming_id == target:
            self.unpair_confirming_id = ""
        if target in self.pending_pairing and self.pending_pairing[target] == "unpair_confirm":
            del self.pending_pairing[target]

    def confirm_unpair(self, device_id):
        dev = next((d for d in self.devices if d["id"] == device_id), None)
        if not dev or not dev.get("capabilities", {}).get("pair"):
            return False
        if self.pending_pairing.get(device_id) in ("requesting", "removing"):
            return False
        if self.unpair_confirming_id == device_id:
            self.unpair_confirming_id = ""
        self.pending_pairing[device_id] = "removing"
        self.action_state = "accepted"
        self.action_message = "Device unpaired"
        self.action_error = ""
        return True

    def handle_pair_process_completed(self, target_generation, target_device_id, exit_code, is_pair=True):
        op = "pairing" if is_pair else "unpairing"
        if exit_code == 0:
            self.pending_pairing[target_device_id] = "requesting" if is_pair else "accepted"
        else:
            if is_pair:
                if target_device_id in self.pending_pairing:
                    del self.pending_pairing[target_device_id]
            else:
                self.pending_pairing[target_device_id] = "failed"
        if target_generation != self.generation or target_device_id != self.selected_device_id:
            return False
        if exit_code == 0:
            self.action_state = "accepted"
            self.action_message = "Pair request sent" if is_pair else "Device unpaired"
            self.action_error = ""
        else:
            self.action_state = "failed"
            self.action_message = ""
            self.action_error = "Pairing timed out or rejected" if is_pair else categorize(exit_code, op)
        return True


# ---------------------------------------------------------------------------
# Test Suites
# ---------------------------------------------------------------------------

class DeviceParsingAndFormattingTests(unittest.TestCase):
    def test_authoritative_snapshot_is_stable_and_capability_aware(self):
        full_line = (
            "DEVICE\tdev-full\tFull Phone\tphone\ttrue\ttrue\t100\ttrue\t"
            "kdeconnect_battery,kdeconnect_ping,kdeconnect_share,kdeconnect_runcommand,"
            "kdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_connectivity_report,"
            "kdeconnect_sms,kdeconnect_mprisremote\t5G\t4"
        )
        parsed = parse_device(full_line)
        self.assertEqual(parsed["capabilities"], {
            "battery": True, "ping": True, "ring": True, "text": True,
            "clipboard": True, "file": True, "commands": True, "network": True,
            "sms": True, "media": True, "pair": True,
        })
        self.assertEqual(parsed["networkType"], "5G")
        self.assertEqual(parsed["networkStrength"], 4)
        self.assertEqual(format_network_status(parsed), "5G (4/4)")
        self.assertEqual(format_battery_status(parsed), "100% • Charging • 5G (4/4)")

        partial_line = "DEVICE\tdev-part\tPart Phone\tphone\ttrue\ttrue\t50\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard"
        parsed_part = parse_device(partial_line)
        self.assertEqual(parsed_part["capabilities"], {
            "battery": False, "ping": False, "ring": True, "text": False,
            "clipboard": True, "file": False, "commands": False, "network": False,
            "sms": False, "media": False, "pair": True,
        })

        empty_line = "DEVICE\tdev-empty\tEmpty Phone\tphone\tfalse\tfalse\t-1\tfalse\t"
        parsed_empty = parse_device(empty_line)
        self.assertFalse(parsed_empty["capabilities"]["battery"])
        self.assertFalse(parsed_empty["reachable"])

    def test_pairing_metadata_is_parsed_for_incoming_requests(self):
        line = "DEVICE\tdev-1\tPhone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_ping\t\t-1\ttrue\ttrue\t82C4DD3C"
        device = parse_device(line)
        self.assertTrue(device["pairRequested"])
        self.assertTrue(device["pairRequestedByPeer"])
        self.assertEqual(device["verificationKey"], "82C4DD3C")

    def test_primary_action_capability_gating_and_reachability(self):
        line_full = "DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_share"
        d_full = parse_device(line_full)
        self.assertTrue(d_full["capabilities"]["ring"])
        self.assertTrue(d_full["capabilities"]["clipboard"])
        self.assertTrue(d_full["capabilities"]["file"])

        line_offline = "DEVICE\tdev-3\tPhone\tphone\ttrue\tfalse\t80\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_share"
        d_offline = parse_device(line_offline)
        self.assertFalse(d_offline["reachable"])
        self.assertEqual(format_overview_status(d_offline), "Paired, offline")
        self.assertEqual(format_battery_status(d_offline), "")

    def test_device_type_icon_mapping_and_defaults(self):
        self.assertEqual(device_type_icon("phone"), "󰄜")
        self.assertEqual(device_type_icon("tablet"), "󰓹")
        self.assertEqual(device_type_icon("laptop"), "󰌢")
        self.assertEqual(device_type_icon("desktop"), "󰍹")
        self.assertEqual(device_type_icon("tv"), "󰵔")
        self.assertEqual(device_type_icon("unknown"), "󰄜")
        self.assertEqual(device_type_icon(""), "󰄜")
        self.assertEqual(device_type_icon(None), "󰄜")

    def test_format_overview_status(self):
        self.assertEqual(format_overview_status(None), "No devices found")
        self.assertEqual(format_overview_status({"paired": False}), "Not paired")
        self.assertEqual(format_overview_status({"paired": True, "reachable": False}), "Paired, offline")
        self.assertEqual(format_overview_status({"paired": True, "reachable": True}), "Paired & reachable")

    def test_settings_action_filtering(self):
        full_line = (
            "DEVICE\tdev-full\tFull Phone\tphone\ttrue\ttrue\t100\ttrue\t"
            "kdeconnect_battery,kdeconnect_ping,kdeconnect_share,kdeconnect_findmyphone,"
            "kdeconnect_clipboard,kdeconnect_sms\t5G\t4"
        )
        dev = parse_device(full_line)
        self.assertEqual(compute_available_actions(dev, {}), ["ring", "clipboard", "file", "sms", "text"])
        self.assertEqual(compute_available_actions(dev, {"showActionPing": True}), ["ring", "clipboard", "file", "sms", "ping", "text"])
        self.assertEqual(compute_available_actions(dev, {"showActionSms": False, "showActionPing": True}), ["ring", "clipboard", "file", "ping", "text"])
        self.assertEqual(compute_available_actions(dev, {"showActionRing": False, "showActionClipboard": False}), ["file", "sms", "text"])

    def test_settings_telemetry_filtering(self):
        full_line = "DEVICE\tdev-full\tFull Phone\tphone\ttrue\ttrue\t85\ttrue\tkdeconnect_battery,kdeconnect_connectivity_report\tLTE\t3"
        dev = parse_device(full_line)
        self.assertEqual(format_battery_status(dev, show_battery=True, show_network=True), "85% • Charging • LTE (3/4)")
        self.assertEqual(format_battery_status(dev, show_battery=True, show_network=False), "85% • Charging")
        self.assertEqual(format_battery_status(dev, show_battery=False, show_network=True), "LTE (3/4)")
        self.assertEqual(format_battery_status(dev, show_battery=False, show_network=False), "")

    def test_media_player_capability_detection(self):
        mpris = parse_device("DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\ttrue\tkdeconnect_mprisremote")
        self.assertTrue(mpris["capabilities"]["media"])
        control = parse_device("DEVICE\tdev-2\tLaptop\tlaptop\ttrue\ttrue\t90\tfalse\tkdeconnect_mpriscontrol")
        self.assertTrue(control["capabilities"]["media"])
        none = parse_device("DEVICE\tdev-3\tTablet\ttablet\ttrue\ttrue\t60\tfalse\tkdeconnect_battery,kdeconnect_ping")
        self.assertFalse(none["capabilities"]["media"])


class ActionAndComposerTests(unittest.TestCase):
    def test_send_file_unusual_paths_and_safety(self):
        cmd_decoded = build_action_command("file", "dev-1", "file:///home/user/my%20documents/file.pdf")
        self.assertEqual(cmd_decoded, ["kdeconnect-cli", "-d", "dev-1", "--share", "/home/user/my documents/file.pdf"])

        cmd_special = build_action_command("file", "dev-1", "/tmp/it's \"a test\" file.txt")
        self.assertEqual(cmd_special, ["kdeconnect-cli", "-d", "dev-1", "--share", "/tmp/it's \"a test\" file.txt"])

        cmd_meta = build_action_command("file", "dev-1", "/tmp/$VAR; rm -rf /; $(id).txt")
        self.assertEqual(cmd_meta, ["kdeconnect-cli", "-d", "dev-1", "--share", "/tmp/$VAR; rm -rf /; $(id).txt"])
        self.assertNotIn("bash", cmd_meta[0])

        self.assertIsNone(build_action_command("file", "dev-1", "/tmp/invalid\x00file.txt"))
        self.assertIsNone(build_action_command("file", "dev-1", ""))

    def test_composer_input_validation_and_command_construction(self):
        valid, err = validate_composer_input("")
        self.assertFalse(valid)
        self.assertEqual(err, "Message cannot be empty")

        valid_space, err_space = validate_composer_input("   \t  \n  ")
        self.assertFalse(valid_space)
        self.assertEqual(err_space, "Message cannot be empty")

        self.assertIsNone(build_action_command("ping", "dev-1", "  "))
        self.assertEqual(build_action_command("ping", "dev-1", "Ping test"), ["kdeconnect-cli", "-d", "dev-1", "--ping-msg", "Ping test"])
        self.assertEqual(build_action_command("text", "dev-1", "https://example.com"), ["kdeconnect-cli", "-d", "dev-1", "--share-text", "https://example.com"])

    def test_composer_state_transitions_submit_and_cancel(self):
        state = ComposerState(selected_device_id="dev-1")
        self.assertEqual(state.active_composer, "none")

        state.open_composer("ping")
        self.assertEqual(state.active_composer, "ping")
        state.open_composer("text")
        self.assertEqual(state.active_composer, "text")

        state.close_composer()
        self.assertEqual(state.active_composer, "none")

        state.open_composer("ping")
        state.draft_ping = "   "
        self.assertFalse(state.submit_ping())
        self.assertEqual(state.action_state, "blocked")

        state.draft_ping = "Wake up!"
        self.assertTrue(state.submit_ping())
        self.assertEqual(state.active_composer, "none")
        self.assertEqual(state.action_state, "running")

    def test_draft_clearing_on_device_switch(self):
        state = ComposerState(selected_device_id="dev-1")
        state.open_composer("ping")
        state.draft_ping = "Draft message"
        state.select_device("dev-2")

        self.assertEqual(state.selected_device_id, "dev-2")
        self.assertEqual(state.active_composer, "none")
        self.assertEqual(state.draft_ping, "")

    def test_action_scoping_and_stale_target_rejection(self):
        state = ComposerState(selected_device_id="dev-1")
        state.submit_ping("Hello dev-1")
        target_gen = state.action_generation

        state.select_device("dev-2")
        accepted = state.handle_action_completed(target_gen, "dev-1", 0, "ping", "Ping sent")
        self.assertFalse(accepted)
        self.assertEqual(state.action_state, "idle")

        state.submit_text("Link for dev-2")
        accepted_valid = state.handle_action_completed(state.action_generation, "dev-2", 0, "text share", "Text sent")
        self.assertTrue(accepted_valid)
        self.assertEqual(state.action_state, "accepted")

    def test_composer_process_failure_handling(self):
        state = ComposerState(selected_device_id="dev-1")
        state.submit_ping("Test failure")
        completed = state.handle_action_completed(state.action_generation, "dev-1", 127, "ping", "Ping sent")
        self.assertTrue(completed)
        self.assertEqual(state.action_state, "failed")
        self.assertEqual(state.action_error, "ping unavailable")


class RemoteCommandsStateTests(unittest.TestCase):
    def test_remote_commands_capability_gating(self):
        dev_unsupp = parse_device("DEVICE\tdev-unsupp\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_ping")
        state = RemoteCommandsState(selected_device_id="dev-unsupp")
        self.assertFalse(state.fetch_remote_commands("dev-unsupp", dev_unsupp["capabilities"]))
        self.assertFalse(state.toggle_commands_expanded(dev_unsupp["capabilities"]))

    def test_remote_commands_parsing_json_and_text(self):
        self.assertEqual(parse_remote_commands(""), [])
        self.assertEqual(parse_remote_commands("[]"), [])
        self.assertEqual(parse_remote_commands("No remote commands configured"), [])

        json_dict = '{"cmd1": "Command One", "cmd2": "Command Two"}'
        self.assertEqual(parse_remote_commands(json_dict), [
            {"key": "cmd1", "name": "Command One"},
            {"key": "cmd2", "name": "Command Two"},
        ])

        json_arr = '[{"key": "c1", "name": "C One"}, {"command": "c2", "title": "C Two"}]'
        self.assertEqual(parse_remote_commands(json_arr), [
            {"key": "c1", "name": "C One"},
            {"key": "c2", "name": "C Two"},
        ])

        raw_text = "* lock: Lock Screen\n1. suspend: Suspend System\n• reboot: Reboot PC\nplain-cmd"
        parsed = parse_remote_commands(raw_text)
        self.assertEqual(parsed[0], {"key": "lock", "name": "Lock Screen"})
        self.assertEqual(parsed[1], {"key": "suspend", "name": "Suspend System"})
        self.assertEqual(parsed[2], {"key": "reboot", "name": "Reboot PC"})
        self.assertEqual(parsed[3], {"key": "plain-cmd", "name": "plain-cmd"})

    def test_remote_commands_lifecycle_and_stale_rejection(self):
        dev = parse_device("DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_runcommand")
        state = RemoteCommandsState(selected_device_id="dev-1")
        self.assertTrue(state.toggle_commands_expanded(dev["capabilities"]))
        self.assertTrue(state.commands_loading)

        state.select_device("dev-2")
        accepted = state.handle_commands_completed(1, "dev-1", 0, "- lock: Lock Screen")
        self.assertFalse(accepted)
        self.assertEqual(state.remote_commands, [])

    def test_remote_commands_cursor_navigation(self):
        state = RemoteCommandsState(selected_device_id="dev-1")
        state.remote_commands = [{"key": "1", "name": "One"}, {"key": "2", "name": "Two"}]
        self.assertEqual(state.command_selected_index, 0)
        state.select_command(1)
        self.assertEqual(state.command_selected_index, 1)
        state.select_command(5)
        self.assertEqual(state.command_selected_index, 1)
        state.select_command(-5)
        self.assertEqual(state.command_selected_index, 0)


class PairingStateMachineTests(unittest.TestCase):
    def test_pairing_success_transition_and_local_acceptance(self):
        state = PairingState()
        state.apply_scan(["DEVICE\tdev-1\tPhone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery"], state.generation)
        self.assertTrue(state.pair_device("dev-1", timestamp=1000))
        self.assertEqual(state.pending_pairing.get("dev-1"), "requesting")

        # Scan confirms paired
        state.apply_scan(["DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_battery"], state.generation)
        self.assertNotIn("dev-1", state.pending_pairing)
        self.assertEqual(state.action_state, "accepted")
        self.assertEqual(state.action_message, "Device paired")

    def test_pairing_rejection_and_timeout_error_categorization(self):
        state = PairingState()
        state.apply_scan(["DEVICE\tdev-1\tPhone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery"], state.generation)
        state.pair_device("dev-1", timestamp=1000)

        state.handle_timeout("dev-1")
        self.assertNotIn("dev-1", state.pending_pairing)
        self.assertEqual(state.action_state, "failed")
        self.assertEqual(state.action_error, "Pairing timed out or rejected")

    def test_stale_pairing_cleanup_on_refresh(self):
        state = PairingState()
        state.pending_pairing["dev-1"] = "requesting"
        state.pairing_request_times["dev-1"] = 1000
        state.refresh(force_network=True, current_time=15000)
        self.assertNotIn("dev-1", state.pending_pairing)

    def test_inline_destructive_unpairing_confirmation_and_cancellation(self):
        state = PairingState()
        state.apply_scan(["DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_battery"], state.generation)
        self.assertTrue(state.request_unpair_confirm("dev-1"))
        self.assertEqual(state.unpair_confirming_id, "dev-1")

        state.cancel_unpair_confirm("dev-1")
        self.assertEqual(state.unpair_confirming_id, "")

        state.request_unpair_confirm("dev-1")
        state.confirm_unpair("dev-1")
        self.assertEqual(state.pending_pairing.get("dev-1"), "removing")
        self.assertEqual(state.action_message, "Device unpaired")

    def test_multi_device_pairing_watchdog_isolation(self):
        state = PairingState()
        state.devices = [
            {"id": "dev-1", "capabilities": {"pair": True}},
            {"id": "dev-2", "capabilities": {"pair": True}},
        ]
        state.selected_device_id = "dev-1"
        state.pending_pairing = {"dev-1": "requesting", "dev-2": "requesting"}
        state.pairing_request_times = {"dev-1": 1000, "dev-2": 25000}

        timed_out = state.check_watchdog(current_time=32000)
        self.assertIn("dev-1", timed_out)
        self.assertNotIn("dev-2", timed_out)
        self.assertEqual(state.action_state, "failed")

    def test_device_selection_prioritizes_paired_and_reachable(self):
        state = PairingState()
        state.apply_scan([
            "DEVICE\tdev-unpaired\tDesktop\tdesktop\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery",
            "DEVICE\tdev-offline\tTablet\ttablet\ttrue\tfalse\t50\tfalse\tkdeconnect_battery",
            "DEVICE\tdev-paired\tPhone\tphone\ttrue\ttrue\t80\ttrue\tkdeconnect_battery,kdeconnect_mprisremote",
        ], state.generation)
        self.assertEqual(state.selected_device_id, "dev-paired")


class MediaPlayerStateTests(unittest.TestCase):
    def test_media_player_state_parsing_and_selection(self):
        state = MediaPlayerState("dev-1")
        raw_status = {
            "isPlaying": True,
            "title": "Blinding Lights",
            "artist": "The Weeknd",
            "album": "After Hours",
            "player": "Spotify",
            "playerList": ["Spotify", "VLC"],
            "albumArt": "file:///tmp/art.jpg",
        }
        self.assertTrue(state.apply_status(raw_status, "dev-1"))
        self.assertTrue(state.is_playing)
        self.assertEqual(state.title, "Blinding Lights")
        self.assertEqual(state.artist, "The Weeknd")
        self.assertEqual(state.album_art, "file:///tmp/art.jpg")

        self.assertTrue(state.select_player("VLC"))
        self.assertEqual(state.player, "VLC")
        self.assertFalse(state.select_player("NonExistent"))

    def test_media_player_device_switch_clearing_and_stale_rejection(self):
        state = MediaPlayerState("dev-1")
        state.apply_status({"isPlaying": True, "title": "Track 1"}, "dev-1")
        state.select_device("dev-2")

        self.assertFalse(state.is_playing)
        self.assertEqual(state.title, "")
        self.assertFalse(state.apply_status({"isPlaying": True, "title": "Old Track"}, "dev-1"))
        self.assertEqual(state.title, "")

    def test_media_player_command_generation(self):
        state = MediaPlayerState("dev-xyz")
        self.assertEqual(state.build_action_command("PlayPause"), ["bash", "scripts/media_control.sh", "action", "dev-xyz", "PlayPause"])
        self.assertEqual(state.build_action_command("Next"), ["bash", "scripts/media_control.sh", "action", "dev-xyz", "Next"])
        self.assertEqual(state.build_action_command("Previous"), ["bash", "scripts/media_control.sh", "action", "dev-xyz", "Previous"])
        self.assertEqual(state.build_player_command("Spotify"), ["bash", "scripts/media_control.sh", "player", "dev-xyz", "Spotify"])
        self.assertEqual(state.build_status_command(), ["bash", "scripts/media_control.sh", "status", "dev-xyz"])


class ManifestValidationTests(unittest.TestCase):
    def test_manifest_structure_and_entrypoints(self):
        manifest_path = ROOT / "manifest.json"
        self.assertTrue(manifest_path.is_file())
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual(manifest["entryPoints"], {"service": "Service.qml", "barWidget": "BarWidget.qml"})
        self.assertTrue((ROOT / manifest["entryPoints"]["service"]).is_file())
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).is_file())
        self.assertTrue((ROOT / "Panel.qml").is_file())

    def test_manifest_settings_schema(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        settings = manifest.get("settings", {})
        expected_keys = [
            "showBatteryStats", "showBarBattery", "showNetworkStats",
            "showDeviceTypeIcons", "showMediaPlayer", "showRemoteCommands",
            "showActionRing", "showActionClipboard", "showActionFile",
            "showActionSms", "showActionPing", "showActionText",
        ]
        for key in expected_keys:
            self.assertIn(key, settings)
            self.assertIn("default", settings[key])
        self.assertFalse(settings["showBarBattery"]["default"])
        self.assertFalse(settings["showActionPing"]["default"])
        self.assertTrue(settings["showMediaPlayer"]["default"])


class ScriptIntegrationTests(unittest.TestCase):
    def test_file_picker_bounds_option_list_and_skips_missing_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "Downloads").mkdir()
            for index in range(400):
                entry = home / "Downloads" / f"{'n' * 200}-{index:04d}.pdf"
                entry.write_text("x")
                os.utime(entry, (index, index))

            stub_dir = home / ".local" / "bin"
            stub_dir.mkdir(parents=True)
            stub = stub_dir / "omarchy-menu-select"
            stub.write_text("#!/usr/bin/env bash\ncat\n")
            stub.chmod(0o755)

            result = subprocess.run(
                ["bash", str(ROOT / "scripts" / "pick_file.sh")],
                capture_output=True,
                text=True,
                env={**os.environ, "HOME": str(home), "OMARCHY_PATH": ""},
            )

        self.assertEqual(result.returncode, 0)
        options = result.stdout.splitlines()
        self.assertTrue(options)
        self.assertLess(len(options), 400)
        self.assertLess(len(result.stdout.encode()), 128 * 1024)
        self.assertTrue(options[0].endswith("-0399.pdf"))

    def test_file_picker_supports_expanded_formats_and_desktop(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "Desktop").mkdir()
            (home / "Downloads").mkdir()

            (home / "Desktop" / "presentation.pptx").write_text("dummy")
            (home / "Downloads" / "song.mp3").write_text("dummy")
            (home / "Downloads" / "archive.7z").write_text("dummy")

            stub_dir = home / ".local" / "bin"
            stub_dir.mkdir(parents=True)
            stub = stub_dir / "omarchy-menu-select"
            stub.write_text("#!/usr/bin/env bash\ncat\n")
            stub.chmod(0o755)

            deep_dir = home / "Downloads" / "a" / "b" / "c" / "d" / "e"
            deep_dir.mkdir(parents=True)
            (deep_dir / "hidden_too_deep.mp3").write_text("dummy")

            result = subprocess.run(
                ["bash", str(ROOT / "scripts" / "pick_file.sh")],
                capture_output=True,
                text=True,
                env={**os.environ, "HOME": str(home), "OMARCHY_PATH": ""},
            )

        self.assertEqual(result.returncode, 0)
        basenames = {Path(line).name for line in result.stdout.splitlines()}
        self.assertIn("presentation.pptx", basenames)
        self.assertIn("song.mp3", basenames)
        self.assertIn("archive.7z", basenames)
        self.assertNotIn("hidden_too_deep.mp3", basenames)

    def test_media_control_argument_validation(self):
        script = ROOT / "scripts" / "media_control.sh"
        self.assertEqual(subprocess.run(["bash", str(script), "invalid_op", "dev-1"], capture_output=True).returncode, 64)
        self.assertEqual(subprocess.run(["bash", str(script), "action", "dev/bad", "Play"], capture_output=True).returncode, 64)
        self.assertEqual(subprocess.run(["bash", str(script), "player", "dev-1", ""], capture_output=True).returncode, 64)
        self.assertEqual(subprocess.run(["bash", str(script), "action", "dev-1", "Stop"], capture_output=True).returncode, 64)

    def test_media_control_status_and_metadata_parsing(self):
        script = ROOT / "scripts" / "media_control.sh"
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            gdbus = stub_dir / "gdbus"
            gdbus.write_text(r"""#!/usr/bin/env bash
case "$*" in
  *GetAll*) cat << 'EOF'
({
  'album': <'Greatest Hits'>,
  'artist': <'Guns N\' Roses'>,
  'isPlaying': <true>,
  'localAlbumArtUrl': <'file:///tmp/cover.jpg'>,
  'player': <'Spotify'>,
  'playerList': <['Spotify', 'VLC']>,
  'title': <'A Day In The Life
(Take 1)'>
},)
EOF
  ;;
  *) printf "(<' '>,)\n" ;;
esac
""")
            gdbus.chmod(0o755)

            result = subprocess.run(
                ["bash", str(script), "status", "dev-1"],
                capture_output=True,
                text=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data["isPlaying"])
        self.assertEqual(data["artist"], "Guns N' Roses")
        self.assertEqual(data["title"], "A Day In The Life\n(Take 1)")
        self.assertEqual(data["albumArt"], "file:///tmp/cover.jpg")
        self.assertEqual(data["playerList"], ["Spotify", "VLC"])

    def test_media_control_action_and_player_dispatch(self):
        script = ROOT / "scripts" / "media_control.sh"
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            log_path = Path(tmp) / "calls.log"
            gdbus = stub_dir / "gdbus"
            gdbus.write_text(f"#!/usr/bin/env bash\necho \"$*\" >> {log_path}\nexit 0\n")
            gdbus.chmod(0o755)

            res_action = subprocess.run(
                [BASH, str(script), "action", "dev-1", "PlayPause"],
                capture_output=True,
                text=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            res_player = subprocess.run(
                [BASH, str(script), "player", "dev-1", "Spotify"],
                capture_output=True,
                text=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            self.assertEqual(res_action.returncode, 0)
            self.assertEqual(res_player.returncode, 0)
            log = log_path.read_text()
            self.assertIn("mprisremote.sendAction PlayPause", log)
            self.assertIn("Properties.Set org.kde.kdeconnect.device.mprisremote player <'Spotify'>", log)

    def test_custom_address_update_add_and_remove(self):
        script = ROOT / "scripts" / "update_custom_address.sh"

        # Invalid operation
        self.assertEqual(subprocess.run([BASH, str(script), "invalid", "100.64.0.1"], capture_output=True).returncode, 64)
        # Invalid IP address syntax
        self.assertEqual(subprocess.run([BASH, str(script), "add", "bad/ip addr"], capture_output=True).returncode, 64)

        # Successful add and remove via D-Bus / busctl
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            gdbus = stub_dir / "gdbus"
            gdbus.write_text("#!/usr/bin/env bash\nprintf \"(<['100.64.0.1']>,)\\n\"\n")
            gdbus.chmod(0o755)
            busctl = stub_dir / "busctl"
            busctl.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\"\n")
            busctl.chmod(0o755)

            res_add = subprocess.run(
                [BASH, str(script), "add", "100.64.0.2"],
                capture_output=True,
                text=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            self.assertEqual(res_add.returncode, 0)
            self.assertIn("customDevices as 2 100.64.0.1 100.64.0.2", res_add.stdout)

            res_remove = subprocess.run(
                [BASH, str(script), "remove", "100.64.0.1"],
                capture_output=True,
                text=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            self.assertEqual(res_remove.returncode, 0)
            self.assertIn("customDevices as 0", res_remove.stdout)

    def test_discover_devices_end_to_end(self):
        script = ROOT / "scripts" / "discover_devices.sh"

        # Missing required dependency exits 127
        with tempfile.TemporaryDirectory() as empty_dir:
            res_dep = subprocess.run([BASH, str(script)], capture_output=True, env={**os.environ, "PATH": empty_dir})
            self.assertEqual(res_dep.returncode, 127)

        # Daemon not running exits 69
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            gdbus = stub_dir / "gdbus"
            gdbus.write_text("#!/usr/bin/env bash\nprintf '(false,)\\n'\n")
            gdbus.chmod(0o755)
            res_offline = subprocess.run(
                [BASH, str(script)],
                capture_output=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            self.assertEqual(res_offline.returncode, 69)

        # Full discovery produces valid formatted output
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            gdbus = stub_dir / "gdbus"
            gdbus.write_text(r"""#!/usr/bin/env bash
if [[ "$*" == *NameHasOwner* ]]; then
  printf '(true,)\n'
elif [[ "$*" == *daemon.devices* ]]; then
  printf "(['dev-1'],)\n"
elif [[ "$*" == *customDevices* ]]; then
  printf "(<['100.64.0.5']>,)\n"
elif [[ "$*" == *name* ]]; then
  printf "(<'My Phone'>,)\n"
elif [[ "$*" == *type* ]]; then
  printf "(<'phone'>,)\n"
elif [[ "$*" == *isPaired* ]]; then
  printf "(<true>,)\n"
elif [[ "$*" == *isReachable* ]]; then
  printf "(<true>,)\n"
elif [[ "$*" == *supportedPlugins* ]]; then
  printf "(<['kdeconnect_battery', 'kdeconnect_ping']>,)\n"
elif [[ "$*" == *battery*charge* ]]; then
  printf "(<85>,)\n"
elif [[ "$*" == *battery*isCharging* ]]; then
  printf "(<true>,)\n"
elif [[ "$*" == *networkType* ]]; then
  printf "(<'WiFi'>,)\n"
elif [[ "$*" == *cellularNetworkStrength* ]]; then
  printf "(<3>,)\n"
else
  printf "(<false>,)\n"
fi
""")
            gdbus.chmod(0o755)
            kdeconnect_cli = stub_dir / "kdeconnect-cli"
            kdeconnect_cli.write_text("#!/usr/bin/env bash\nexit 0\n")
            kdeconnect_cli.chmod(0o755)

            result = subprocess.run(
                [BASH, str(script)],
                capture_output=True,
                text=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0)
            lines = result.stdout.splitlines()
            self.assertIn("CUSTOM_ADDRESSES_READY", lines)
            self.assertIn("CUSTOM_ADDRESS\t100.64.0.5", lines)

            device_line = next(line for line in lines if line.startswith("DEVICE\t"))
            device = parse_device(device_line)
            self.assertIsNotNone(device)
            self.assertEqual(device["id"], "dev-1")
            self.assertEqual(device["name"], "My Phone")  # Tab/newline sanitized
            self.assertEqual(device["battery"], 85)
            self.assertTrue(device["charging"])
            self.assertTrue(device["capabilities"]["battery"])
            self.assertTrue(device["capabilities"]["ping"])

    def test_open_sms_script_execution(self):
        script = ROOT / "scripts" / "open_sms.sh"

        # Missing binary exits 127
        with tempfile.TemporaryDirectory() as empty_dir:
            res_missing = subprocess.run([BASH, str(script)], capture_output=True, env={**os.environ, "PATH": empty_dir})
            self.assertEqual(res_missing.returncode, 127)

        # Available binary runs with device argument
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            log_path = stub_dir / "sms.log"
            sms_bin = stub_dir / "kdeconnect-sms"
            sms_bin.write_text(f"#!/usr/bin/env bash\necho \"$*\" > {log_path}\nexit 0\n")
            sms_bin.chmod(0o755)

            res = subprocess.run(
                [BASH, str(script), "dev-42"],
                capture_output=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            time.sleep(0.1)
            self.assertEqual(res.returncode, 0)
            self.assertEqual(log_path.read_text().strip(), "--device dev-42")

    def test_open_app_script_execution(self):
        script = ROOT / "scripts" / "open_app.sh"

        # Missing any KDE Connect app binary exits 127
        with tempfile.TemporaryDirectory() as empty_dir:
            res_missing = subprocess.run([BASH, str(script)], capture_output=True, env={**os.environ, "PATH": empty_dir})
            self.assertEqual(res_missing.returncode, 127)

        # Falls back to kdeconnect-settings if kdeconnect-app is absent
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp)
            app_bin = stub_dir / "kdeconnect-settings"
            app_bin.write_text("#!/usr/bin/env bash\nexit 0\n")
            app_bin.chmod(0o755)

            res = subprocess.run(
                [BASH, str(script)],
                capture_output=True,
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"},
            )
            self.assertEqual(res.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
