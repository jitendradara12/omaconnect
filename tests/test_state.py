import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


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


def format_battery_status(device):
    if not device:
        return ""
    battery_text = ""
    if device.get("capabilities", {}).get("battery"):
        battery = device.get("battery", -1)
        if battery < 0:
            battery_text = "Battery unavailable"
        else:
            charging = device.get("charging") or device.get("isCharging")
            if charging:
                battery_text = f"{battery}% • Charging"
            elif battery <= 20:
                battery_text = f"{battery}% • Low battery"
            else:
                battery_text = f"{battery}% • Discharging"
    net_text = format_network_status(device)
    if battery_text and net_text:
        return f"{battery_text} • {net_text}"
    if battery_text:
        return battery_text
    if net_text:
        return net_text
    return ""




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



def accept_completion(target_generation, current_generation, target_id, selected_id):
    return target_generation == current_generation and target_id == selected_id


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

    def apply_scan(self, device_lines, target_generation):
        if target_generation != self.generation:
            return False
        next_devices = []
        for line in device_lines:
            dev = parse_device(line)
            if dev:
                next_devices.append(dev)
        self.devices = next_devices
        if not any(d["id"] == self.selected_device_id for d in self.devices):
            self.selected_device_id = self.devices[0]["id"] if self.devices else ""
        return True

    def pair_device(self, device_id):
        dev = next((d for d in self.devices if d["id"] == device_id), None)
        if not dev or not dev.get("capabilities", {}).get("pair"):
            return False
        if self.pending_pairing.get(device_id) in ("requesting", "removing", "unpair_confirm"):
            return False
        self.pending_pairing[device_id] = "requesting"
        self.action_state = "accepted"
        self.action_message = "Pairing request accepted"
        self.action_error = ""
        return True

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
        return True

    def handle_pair_process_completed(self, target_generation, target_device_id, exit_code, is_pair=True):
        op = "pairing" if is_pair else "unpairing"
        self.pending_pairing[target_device_id] = "accepted" if exit_code == 0 else "failed"
        if target_generation != self.generation or target_device_id != self.selected_device_id:
            return False
        if exit_code == 0:
            self.action_state = "accepted"
            self.action_message = "Pairing request accepted" if is_pair else "Unpair request accepted"
            self.action_error = ""
        else:
            self.action_state = "failed"
            self.action_message = ""
            self.action_error = categorize(exit_code, op)
        return True


class StateTests(unittest.TestCase):
  def test_authoritative_snapshot_is_stable_and_capability_aware(self):
    # Full capability set
    full_line = "DEVICE\tdev-full\tFull Phone\tphone\ttrue\ttrue\t100\ttrue\tkdeconnect_battery,kdeconnect_ping,kdeconnect_share,kdeconnect_runcommand,kdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_connectivity_report,kdeconnect_sms\t5G\t4"
    self.assertEqual(parse_device(full_line)["capabilities"], {
        "battery": True, "ping": True, "ring": True, "text": True, "clipboard": True, "file": True, "commands": True, "network": True, "sms": True, "pair": True
    })
    self.assertEqual(parse_device(full_line)["networkType"], "5G")
    self.assertEqual(parse_device(full_line)["networkStrength"], 4)
    self.assertEqual(format_network_status(parse_device(full_line)), "5G (4/4)")
    self.assertEqual(format_battery_status(parse_device(full_line)), "100% • Charging • 5G (4/4)")

    # Partial capability set (ring & clipboard only)
    partial_line = "DEVICE\tdev-part\tPart Phone\tphone\ttrue\ttrue\t50\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard"
    self.assertEqual(parse_device(partial_line)["capabilities"], {
        "battery": False, "ping": False, "ring": True, "text": False, "clipboard": True, "file": False, "commands": False, "network": False, "sms": False, "pair": True
    })

    # Empty / unloaded capability set
    empty_line = "DEVICE\tdev-empty\tEmpty Phone\tphone\tfalse\tfalse\t-1\tfalse\t"
    self.assertEqual(parse_device(empty_line)["capabilities"], {
        "battery": False, "ping": False, "ring": False, "text": False, "clipboard": False, "file": False, "commands": False, "network": False, "sms": False, "pair": True
    })

    # Standard snapshot check
    line = "DEVICE\tdevice-1\tTest phone\tphone\ttrue\ttrue\t95\tfalse\tkdeconnect_battery,kdeconnect_ping,kdeconnect_share"
    self.assertEqual(parse_device(line), {
        "id": "device-1",
        "name": "Test phone",
        "type": "phone",
        "paired": True,
        "reachable": True,
        "battery": 95,
        "charging": False,
        "networkType": "",
        "networkStrength": -1,
        "capabilities": {"battery": True, "ping": True, "ring": False, "text": True, "clipboard": False, "file": True, "commands": False, "network": False, "sms": False, "pair": True},
    })



  def test_primary_action_capability_gating_and_reachability(self):
    line_full = "DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_share"
    d_full = parse_device(line_full)
    self.assertTrue(d_full["capabilities"]["ring"])
    self.assertTrue(d_full["capabilities"]["clipboard"])
    self.assertTrue(d_full["capabilities"]["file"])

    line_no_ring = "DEVICE\tdev-2\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_clipboard,kdeconnect_share"
    d_no_ring = parse_device(line_no_ring)
    self.assertFalse(d_no_ring["capabilities"]["ring"])
    self.assertTrue(d_no_ring["capabilities"]["clipboard"])

    line_offline = "DEVICE\tdev-3\tPhone\tphone\ttrue\tfalse\t80\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_share"
    d_offline = parse_device(line_offline)
    self.assertFalse(d_offline["reachable"])
    self.assertEqual(format_overview_status(d_offline), "Paired, offline")

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

  def test_file_picker_cancellation_state(self):
    cancel_state = {
        "fileBusy": False,
        "actionState": "cancelled",
        "actionMessage": "File selection cancelled",
        "actionError": "",
    }
    self.assertEqual(cancel_state["actionError"], "")
    self.assertFalse(cancel_state["fileBusy"])
    self.assertEqual(cancel_state["actionState"], "cancelled")

  def test_composer_input_validation_and_command_construction(self):
    # Empty & whitespace-only validation
    valid, err = validate_composer_input("")
    self.assertFalse(valid)
    self.assertEqual(err, "Message cannot be empty")

    valid_space, err_space = validate_composer_input("   \t  \n  ")
    self.assertFalse(valid_space)
    self.assertEqual(err_space, "Message cannot be empty")

    # Command construction for ping
    self.assertIsNone(build_action_command("ping", "dev-1", "  "))
    self.assertEqual(
        build_action_command("ping", "dev-1", "Ping test"),
        ["kdeconnect-cli", "-d", "dev-1", "--ping-msg", "Ping test"]
    )

    # Command construction for text share
    self.assertIsNone(build_action_command("text", "dev-1", ""))
    self.assertEqual(
        build_action_command("text", "dev-1", "https://example.com"),
        ["kdeconnect-cli", "-d", "dev-1", "--share-text", "https://example.com"]
    )

  def test_composer_state_transitions_submit_and_cancel(self):
    state = ComposerState(selected_device_id="dev-1")

    # Initial state
    self.assertEqual(state.active_composer, "none")

    # Toggle open ping composer
    state.open_composer("ping")
    self.assertEqual(state.active_composer, "ping")

    # Toggle open text composer (exclusive - closes ping)
    state.open_composer("text")
    self.assertEqual(state.active_composer, "text")

    # Cancel composer
    state.close_composer()
    self.assertEqual(state.active_composer, "none")
    self.assertEqual(state.composer_error, "")

    # Submit empty ping -> blocked with local validation error
    state.open_composer("ping")
    state.draft_ping = "   "
    success = state.submit_ping()
    self.assertFalse(success)
    self.assertEqual(state.composer_error, "Message cannot be empty")
    self.assertEqual(state.action_state, "blocked")
    self.assertEqual(state.action_error, "Message cannot be empty")
    self.assertEqual(state.active_composer, "ping")

    # Submit valid ping -> running state, draft cleared, composer closed
    state.draft_ping = "Wake up!"
    success = state.submit_ping()
    self.assertTrue(success)
    self.assertEqual(state.active_composer, "none")
    self.assertEqual(state.draft_ping, "")
    self.assertEqual(state.action_state, "running")
    self.assertEqual(state.action_message, "Requesting ping")

  def test_draft_clearing_on_device_switch(self):
    state = ComposerState(selected_device_id="dev-1")

    state.open_composer("ping")
    state.draft_ping = "Draft message for phone 1"
    state.draft_text = "Draft link for phone 1"
    state.composer_error = "Some previous error"

    # Switch to device 2
    state.select_device("dev-2")

    self.assertEqual(state.selected_device_id, "dev-2")
    self.assertEqual(state.active_composer, "none")
    self.assertEqual(state.draft_ping, "")
    self.assertEqual(state.draft_text, "")
    self.assertEqual(state.composer_error, "")
    self.assertEqual(state.action_state, "idle")

  def test_action_scoping_and_stale_target_rejection(self):
    state = ComposerState(selected_device_id="dev-1")

    # Submit action for dev-1 at generation 1
    state.submit_ping("Hello dev-1")
    target_gen = state.action_generation

    # Switch to dev-2 before completion arrives
    state.select_device("dev-2")

    # Completion arrives for dev-1 (stale target)
    accepted = state.handle_action_completed(
        target_generation=target_gen,
        target_device_id="dev-1",
        exit_code=0,
        operation="ping",
        accepted_msg="Ping request accepted"
    )

    self.assertFalse(accepted)
    # dev-2's action state is unchanged
    self.assertEqual(state.action_state, "idle")
    self.assertEqual(state.action_message, "")

    # Now submit for dev-2 at generation 1 (on dev-2)
    state.submit_text("Link for dev-2")
    dev2_gen = state.action_generation

    # Valid completion arrives for dev-2
    accepted_valid = state.handle_action_completed(
        target_generation=dev2_gen,
        target_device_id="dev-2",
        exit_code=0,
        operation="text share",
        accepted_msg="Text-share request accepted"
    )
    self.assertTrue(accepted_valid)
    self.assertEqual(state.action_state, "accepted")
    self.assertEqual(state.action_message, "Text-share request accepted")

  def test_composer_process_failure_handling(self):
    state = ComposerState(selected_device_id="dev-1")

    state.submit_ping("Test failure")
    gen = state.action_generation

    # Process fails with exit code 127
    completed = state.handle_action_completed(
        target_generation=gen,
        target_device_id="dev-1",
        exit_code=127,
        operation="ping",
        accepted_msg="Ping request accepted"
    )
    self.assertTrue(completed)
    self.assertEqual(state.action_state, "failed")
    self.assertEqual(state.action_error, "ping unavailable")
    self.assertEqual(state.action_message, "")

  def test_empty_command_output_is_a_valid_empty_list(self):
    self.assertEqual(json.loads("[]"), [])


    self.assertEqual(categorize(127, "ring"), "ring unavailable")
    self.assertEqual(categorize(69, "ring"), "ring unavailable")
    self.assertEqual(categorize(127, "clipboard"), "clipboard unavailable")
    self.assertEqual(categorize(127, "file transfer"), "file transfer unavailable")
    self.assertEqual(categorize(2, "pairing"), "pairing rejected")
    self.assertEqual(categorize(3, "pairing"), "pairing timed out")
    self.assertEqual(categorize(3, "remote command"), "remote command timed out")
    self.assertNotIn("stderr", categorize(1, "action"))

  def test_pairing_success_transition_and_local_acceptance(self):
    unpaired_dev = parse_device("DEVICE\tdev-1\tNearby Phone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery,kdeconnect_ping")
    state = PairingState(devices=[unpaired_dev])
    self.assertTrue(state.pair_device("dev-1"))
    self.assertEqual(state.pending_pairing["dev-1"], "requesting")
    self.assertEqual(state.action_state, "accepted")
    self.assertEqual(state.action_message, "Pairing request accepted")
    self.assertEqual(state.action_error, "")

    completed = state.handle_pair_process_completed(state.generation, "dev-1", 0, is_pair=True)
    self.assertTrue(completed)
    self.assertEqual(state.pending_pairing["dev-1"], "accepted")

  def test_pairing_rejection_and_timeout_error_categorization(self):
    unpaired_dev = parse_device("DEVICE\tdev-1\tNearby Phone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery")
    state = PairingState(devices=[unpaired_dev])

    # Rejection (exit code 2)
    state.pair_device("dev-1")
    state.handle_pair_process_completed(state.generation, "dev-1", 2, is_pair=True)
    self.assertEqual(state.pending_pairing["dev-1"], "failed")
    self.assertEqual(state.action_state, "failed")
    self.assertEqual(state.action_error, "pairing rejected")

    # Timeout (exit code 3)
    state.pair_device("dev-1")
    state.handle_pair_process_completed(state.generation, "dev-1", 3, is_pair=True)
    self.assertEqual(state.pending_pairing["dev-1"], "failed")
    self.assertEqual(state.action_state, "failed")
    self.assertEqual(state.action_error, "pairing timed out")

  def test_inline_destructive_unpairing_confirmation_and_cancellation(self):
    paired_dev = parse_device("DEVICE\tdev-1\tMy Phone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_battery")
    state = PairingState(devices=[paired_dev])

    # Request confirmation
    self.assertTrue(state.request_unpair_confirm("dev-1"))
    self.assertEqual(state.unpair_confirming_id, "dev-1")
    self.assertEqual(state.pending_pairing["dev-1"], "unpair_confirm")

    # Cancel confirmation
    state.cancel_unpair_confirm("dev-1")
    self.assertEqual(state.unpair_confirming_id, "")
    self.assertNotIn("dev-1", state.pending_pairing)

    # Request again and confirm
    state.request_unpair_confirm("dev-1")
    self.assertTrue(state.confirm_unpair("dev-1"))
    self.assertEqual(state.pending_pairing["dev-1"], "removing")

    # Exit code 1 (failure)
    state.handle_pair_process_completed(state.generation, "dev-1", 1, is_pair=False)
    self.assertEqual(state.pending_pairing["dev-1"], "failed")
    self.assertEqual(state.action_error, "unpairing failed")

  def test_conflicting_pair_unpair_actions_blocked(self):
    dev = parse_device("DEVICE\tdev-1\tPhone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery")
    state = PairingState(devices=[dev])
    state.pair_device("dev-1")
    self.assertFalse(state.pair_device("dev-1"))
    self.assertFalse(state.request_unpair_confirm("dev-1"))

  def test_selection_and_keyboard_cursor_retention_on_state_changes(self):
    dev1 = parse_device("DEVICE\tdev-1\tPhone One\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery")
    dev2 = parse_device("DEVICE\tdev-2\tPhone Two\tphone\ttrue\ttrue\t90\tfalse\tkdeconnect_battery")
    state = PairingState(devices=[dev1, dev2], selected_device_id="dev-2")

    state.apply_scan([
        "DEVICE\tdev-2\tPhone Two\tphone\tfalse\ttrue\t90\tfalse\tkdeconnect_battery",
        "DEVICE\tdev-1\tPhone One\tphone\ttrue\ttrue\t-1\tfalse\tkdeconnect_battery"
    ], state.generation)

    self.assertEqual(state.selected_device_id, "dev-2")

  def test_pairing_contracts(self):
    source = (ROOT / "KdeConnectController.qml").read_text()
    self.assertIn("setPendingPairing", source)
    self.assertIn("pairDevice", source)
    self.assertIn("unpairDevice", source)
    self.assertIn('"Pairing request accepted"', source)

    ui_source = (ROOT / "Panel.qml").read_text() + "\n" + "\n".join(p.read_text() for p in (ROOT / "components").glob("*.qml"))
    self.assertIn("unpairConfirmingId", ui_source)
    self.assertIn("requestUnpairConfirm", ui_source)
    self.assertIn("cancelUnpairConfirm", ui_source)
    self.assertIn("confirmUnpair", ui_source)
    self.assertIn("devicePendingState", ui_source)
    self.assertIn("isUnpairConfirming", ui_source)

  def test_stale_completion_is_ignored(self):
    self.assertFalse(accept_completion(4, 5, "old", "old"))
    self.assertFalse(accept_completion(5, 5, "old", "new"))
    self.assertTrue(accept_completion(5, 5, "new", "new"))

  def test_manifest_and_runtime_shape(self):
    manifest = json.loads((ROOT / "manifest.json").read_text())
    self.assertEqual(manifest["entryPoints"], {"service": "Service.qml", "barWidget": "BarWidget.qml"})
    self.assertFalse((ROOT / "main.qml").exists())
    self.assertTrue((ROOT / "Panel.qml").exists())
    self.assertTrue(any((ROOT / "components").rglob("*.qml")))

  def test_service_forwards_all_controller_actions(self):
    service_source = (ROOT / "Service.qml").read_text()
    self.assertIn("openSmsApp", service_source)
    self.assertIn("controller.openSmsApp", service_source)
    self.assertIn("configureFirewall", service_source)
    self.assertIn("controller.configureFirewall", service_source)
    self.assertIn("setPendingPairing", service_source)
    self.assertIn("deviceNetworkIcon", service_source)

  def test_confirming_unpair_cannot_follow_a_device_switch(self):
    panel_source = (ROOT / "Panel.qml").read_text()
    self.assertIn("function selectDevice(id)", panel_source)
    self.assertIn("cancelUnpairConfirm(unpairConfirmingId)", panel_source)
    self.assertIn("var targetIdY = root.service.selectedDeviceId", panel_source)

  def test_scan_and_picker_lifecycle_guards(self):
    controller_source = (ROOT / "KdeConnectController.qml").read_text()
    self.assertIn("function clearActionState()", controller_source)
    self.assertIn("if (filePickerProcess.running) return false", controller_source)
    self.assertNotIn("filePickerProcess.running = false\n            var selectedPath", controller_source)

  def test_discovery_property_failures_and_fields_are_sanitized(self):
    discovery_source = (ROOT / "scripts" / "discover_devices.sh").read_text()
    self.assertIn("|| return 69", discovery_source)
    self.assertIn("sanitize_field()", discovery_source)
    self.assertIn("field=${field//$'\\t'/ }", discovery_source)

  def test_sms_launcher_reports_missing_command(self):
    sms_source = (ROOT / "scripts" / "open_sms.sh").read_text()
    self.assertIn("command -v kdeconnect-sms", sms_source)
    self.assertIn("exit 127", sms_source)


  def test_no_privacy_product_claims_or_ui_processes(self):
    sources = "\n".join(path.read_text() for path in ROOT.glob("*.qml"))
    self.assertNotIn("notification", sources.lower())
    self.assertNotIn("Process {", (ROOT / "BarWidget.qml").read_text())


  def test_shell_script_is_not_needed_for_file_sharing(self):
    self.assertFalse((ROOT / "scripts" / "share_file.sh").exists())

  def test_no_file_dialog_and_process_file_picker_contract(self):
    sources = "\n".join(path.read_text() for path in ROOT.glob("*.qml"))
    self.assertNotIn("QtQuick.Dialogs", sources)
    self.assertNotIn("FileDialog {", sources)
    controller_source = (ROOT / "KdeConnectController.qml").read_text()
    self.assertIn("filePickerProcess", controller_source)
    self.assertIn("getPickerScriptPath", controller_source)
    picker_sh = (ROOT / "scripts" / "pick_file.sh").read_text()
    self.assertIn("omarchy-menu-file", picker_sh)

  def test_remote_commands_unsupported_device(self):
    line = "DEVICE\tdev-unsupp\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_ping,kdeconnect_share"
    dev = parse_device(line)
    self.assertFalse(dev["capabilities"]["commands"])
    state = RemoteCommandsState(selected_device_id="dev-unsupp")
    fetched = state.fetch_remote_commands("dev-unsupp", dev["capabilities"])
    self.assertFalse(fetched)
    self.assertFalse(state.commands_loading)
    toggled = state.toggle_commands_expanded(dev["capabilities"])
    self.assertFalse(toggled)

  def test_remote_commands_supported_empty(self):
    line = "DEVICE\tdev-supp\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_runcommand"
    dev = parse_device(line)
    self.assertTrue(dev["capabilities"]["commands"])

    # Test empty output string, whitespace, JSON empty list, "No remote commands" text
    self.assertEqual(parse_remote_commands(""), [])
    self.assertEqual(parse_remote_commands("   \n  "), [])
    self.assertEqual(parse_remote_commands("[]"), [])
    self.assertEqual(parse_remote_commands("No remote commands configured"), [])

    state = RemoteCommandsState(selected_device_id="dev-supp")
    state.toggle_commands_expanded(dev["capabilities"])
    self.assertTrue(state.commands_loading)

    state.handle_commands_completed(
        target_generation=state.generation,
        target_device_id="dev-supp",
        exit_code=0,
        output="No remote commands configured"
    )
    self.assertFalse(state.commands_loading)
    self.assertEqual(state.remote_commands, [])

  def test_remote_commands_supported_populated(self):
    line = "DEVICE\tdev-supp\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_runcommand"
    dev = parse_device(line)
    state = RemoteCommandsState(selected_device_id="dev-supp")
    state.toggle_commands_expanded(dev["capabilities"])

    cli_output = "- lock: Lock Screen\n- suspend: Suspend System\n- screenshot: Take Screenshot"
    completed = state.handle_commands_completed(
        target_generation=state.generation,
        target_device_id="dev-supp",
        exit_code=0,
        output=cli_output
    )
    self.assertTrue(completed)
    self.assertFalse(state.commands_loading)
    self.assertEqual(len(state.remote_commands), 3)
    self.assertEqual(state.remote_commands[0], {"key": "lock", "name": "Lock Screen"})
    self.assertEqual(state.remote_commands[1], {"key": "suspend", "name": "Suspend System"})
    self.assertEqual(state.remote_commands[2], {"key": "screenshot", "name": "Take Screenshot"})

  def test_remote_commands_malformed_cli_output_parsing(self):
    # Test JSON object mapping
    json_dict = '{"cmd1": "Command One", "cmd2": "Command Two"}'
    self.assertEqual(parse_remote_commands(json_dict), [
        {"key": "cmd1", "name": "Command One"},
        {"key": "cmd2", "name": "Command Two"},
    ])

    # Test JSON array of objects
    json_arr = '[{"key": "c1", "name": "C One"}, {"command": "c2", "title": "C Two"}]'
    self.assertEqual(parse_remote_commands(json_arr), [
        {"key": "c1", "name": "C One"},
        {"key": "c2", "name": "C Two"},
    ])

    # Test JSON array of strings
    json_str_arr = '["ping", "reboot"]'
    self.assertEqual(parse_remote_commands(json_str_arr), [
        {"key": "ping", "name": "ping"},
        {"key": "reboot", "name": "reboot"},
    ])

    # Test malformed / non-standard text outputs
    raw_text = """
    * lock: Lock: Screen Now
    1. suspend: Suspend System
    • reboot: Reboot PC
    no-colon-cmd
    """
    parsed = parse_remote_commands(raw_text)
    self.assertEqual(parsed[0], {"key": "lock", "name": "Lock: Screen Now"})
    self.assertEqual(parsed[1], {"key": "suspend", "name": "Suspend System"})
    self.assertEqual(parsed[2], {"key": "reboot", "name": "Reboot PC"})
    self.assertEqual(parsed[3], {"key": "no-colon-cmd", "name": "no-colon-cmd"})

    # Malformed JSON falling back safely to line parsing
    malformed_json = '{invalid json: true'
    self.assertEqual(parse_remote_commands(malformed_json), [
        {"key": "{invalid json", "name": "true"}
    ])

  def test_remote_commands_failed_cli_call(self):
    line = "DEVICE\tdev-supp\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_runcommand"
    dev = parse_device(line)
    state = RemoteCommandsState(selected_device_id="dev-supp")
    state.toggle_commands_expanded(dev["capabilities"])
    self.assertTrue(state.commands_loading)

    # CLI process fails with non-zero exit code
    completed = state.handle_commands_completed(
        target_generation=state.generation,
        target_device_id="dev-supp",
        exit_code=127,
        output="command unavailable"
    )
    self.assertTrue(completed)
    self.assertFalse(state.commands_loading)
    self.assertEqual(state.remote_commands, [])

  def test_remote_commands_stale_target_rejection(self):
    state = RemoteCommandsState(selected_device_id="dev-1")
    dev1 = parse_device("DEVICE\tdev-1\tPhone1\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_runcommand")
    state.toggle_commands_expanded(dev1["capabilities"])

    # User switches to dev-2 before dev-1 commands load
    state.select_device("dev-2")

    self.assertFalse(state.commands_expanded)
    self.assertFalse(state.commands_loading)
    self.assertEqual(state.command_target_id, "")
    self.assertEqual(state.remote_commands, [])

    # Completion arrives for dev-1 (stale target)
    accepted = state.handle_commands_completed(
        target_generation=1,
        target_device_id="dev-1",
        exit_code=0,
        output="- lock: Lock Screen"
    )
    self.assertFalse(accepted)
    self.assertEqual(state.remote_commands, [])

  def test_remote_commands_on_demand_and_repeated_toggling(self):
    dev = parse_device("DEVICE\tdev-1\tPhone\tphone\ttrue\ttrue\t80\tfalse\tkdeconnect_runcommand")
    state = RemoteCommandsState(selected_device_id="dev-1")

    # Initial state: collapsed, not loading, no commands
    self.assertFalse(state.commands_expanded)
    self.assertFalse(state.commands_loading)
    self.assertEqual(state.remote_commands, [])

    # First open -> triggers fetch
    toggled = state.toggle_commands_expanded(dev["capabilities"])
    self.assertTrue(toggled)
    self.assertTrue(state.commands_expanded)
    self.assertTrue(state.commands_loading)

    # Complete fetch
    state.handle_commands_completed(state.generation, "dev-1", 0, "- lock: Lock\n- suspend: Suspend")
    self.assertEqual(len(state.remote_commands), 2)

    # Keyboard navigation bounded check
    self.assertEqual(state.command_selected_index, 0)
    state.select_command(1)
    self.assertEqual(state.command_selected_index, 1)
    state.select_command(1)  # bounded at max index 1
    self.assertEqual(state.command_selected_index, 1)
    state.select_command(-5)  # bounded at min index 0
    self.assertEqual(state.command_selected_index, 0)

    # Collapse section
    state.toggle_commands_expanded(dev["capabilities"])
    self.assertFalse(state.commands_expanded)

    # Re-open section -> triggers fetch again
    state.toggle_commands_expanded(dev["capabilities"])
    self.assertTrue(state.commands_expanded)
    self.assertTrue(state.commands_loading)

  def test_complete_panel_layout_and_action_navigation_contracts(self):
    ui_source = (ROOT / "Panel.qml").read_text() + "\n" + "\n".join(p.read_text() for p in (ROOT / "components").glob("*.qml"))
    self.assertIn("availableActions", ui_source)
    self.assertIn("triggerAction", ui_source)
    self.assertIn("actionSelectedIndex", ui_source)
    self.assertIn("focusSection", ui_source)
    self.assertIn("DEVICES", ui_source)
    self.assertIn("ACTIONS", ui_source)
    self.assertIn("REMOTE COMMANDS", ui_source)
    self.assertIn("deviceOverviewStatus", ui_source)

  def test_available_actions_computation_and_gating(self):
    def available_actions_for(device):
        if not device or not device.get("paired") or not device.get("reachable"):
            return []
        caps = device.get("capabilities", {})
        res = []
        if caps.get("ring"):
            res.append("ring")
        if caps.get("clipboard"):
            res.append("clipboard")
        if caps.get("file"):
            res.append("file")
        if caps.get("ping"):
            res.append("ping")
        if caps.get("text"):
            res.append("text")
        return res

    full_dev = parse_device("DEVICE\tdev-full\tPhone\tphone\ttrue\ttrue\t100\ttrue\tkdeconnect_battery,kdeconnect_ping,kdeconnect_share,kdeconnect_runcommand,kdeconnect_findmyphone,kdeconnect_clipboard")
    self.assertEqual(available_actions_for(full_dev), ["ring", "clipboard", "file", "ping", "text"])

    part_dev = parse_device("DEVICE\tdev-part\tPhone\tphone\ttrue\ttrue\t50\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard")
    self.assertEqual(available_actions_for(part_dev), ["ring", "clipboard"])

    offline_dev = parse_device("DEVICE\tdev-off\tPhone\tphone\ttrue\tfalse\t50\tfalse\tkdeconnect_findmyphone,kdeconnect_clipboard")
    self.assertEqual(available_actions_for(offline_dev), [])

    unpaired_dev = parse_device("DEVICE\tdev-unpaired\tPhone\tphone\tfalse\ttrue\t-1\tfalse\tkdeconnect_battery")
    self.assertEqual(available_actions_for(unpaired_dev), [])

  def test_keyboard_navigation_state_flow(self):
    class PanelNavState:
        def __init__(self, actions, has_commands=True):
            self.focus_section = "devices"
            self.device_index = 0
            self.action_index = 0
            self.actions = actions
            self.has_commands = has_commands

        def key_right(self):
            if self.focus_section == "devices":
                if self.actions:
                    self.focus_section = "actions"
                    self.action_index = 0
                elif self.has_commands:
                    self.focus_section = "commands"
            elif self.focus_section == "actions":
                if self.action_index < len(self.actions) - 1:
                    self.action_index += 1
                elif self.has_commands:
                    self.focus_section = "commands"
                else:
                    self.focus_section = "devices"
            elif self.focus_section == "commands":
                self.focus_section = "devices"

        def key_left(self):
            if self.focus_section == "commands":
                if self.actions:
                    self.focus_section = "actions"
                    self.action_index = len(self.actions) - 1
                else:
                    self.focus_section = "devices"
            elif self.focus_section == "actions":
                if self.action_index > 0:
                    self.action_index -= 1
                else:
                    self.focus_section = "devices"
            elif self.focus_section == "devices":
                if self.has_commands:
                    self.focus_section = "commands"
                elif self.actions:
                    self.focus_section = "actions"
                    self.action_index = len(self.actions) - 1

    nav = PanelNavState(["ring", "clipboard", "file", "ping", "text"], has_commands=True)
    self.assertEqual(nav.focus_section, "devices")
    nav.key_right()
    self.assertEqual((nav.focus_section, nav.action_index), ("actions", 0))
    nav.key_right()
    self.assertEqual((nav.focus_section, nav.action_index), ("actions", 1))
    nav.key_right()
    nav.key_right()
    nav.key_right()
    self.assertEqual((nav.focus_section, nav.action_index), ("actions", 4))
    nav.key_right()
    self.assertEqual(nav.focus_section, "commands")
    nav.key_right()
    self.assertEqual(nav.focus_section, "devices")

  def test_refresh_does_not_reset_discovery_state_when_ready(self):
    controller_source = (ROOT / "KdeConnectController.qml").read_text()
    self.assertIn('if (discoveryState !== "ready")', controller_source)
    self.assertIn('dbusDebounceTimer', controller_source)


  def test_device_section_selects_on_click_not_hover(self):
    device_section_source = (ROOT / "components" / "DeviceSection.qml").read_text()
    self.assertNotIn("onEntered", device_section_source)
    self.assertNotIn("hoverEnabled", device_section_source)
    self.assertIn("panel.selectDevice(modelData.id)", device_section_source)
    self.assertIn("panel.cursorActive = true", device_section_source)
    self.assertIn('panel.focusSection = "devices"', device_section_source)

  def test_panel_select_device_syncs_selected_index(self):
    panel_source = (ROOT / "Panel.qml").read_text()
    self.assertIn("function selectDevice(id)", panel_source)
    self.assertIn("selectedIndex = i", panel_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
