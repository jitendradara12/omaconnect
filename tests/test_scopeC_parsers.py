"""Unit tests for the Scope C structured busctl JSON parsers.

Imports scripts/media_status.py and scripts/discover_report.py directly and
feeds them the real-shape busctl --json=short fixtures in tests/fixtures/
(including hostile remote values), mirroring omarchy-connect's Model.js
tests. Also exercises script-level graceful failure: truncated/garbage JSON
must produce a clean nonzero exit (discover) or a valid empty JSON status
(media), never a python traceback on stdout.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
SCRIPTS = ROOT / "scripts"
FIXTURES = ROOT / "tests" / "fixtures"
PYTHON = sys.executable or "python3"

sys.path.insert(0, str(SCRIPTS))
import discover_report  # noqa: E402
import media_status  # noqa: E402


def fixture(name):
    return (FIXTURES / name).read_text()


def props(name):
    return media_status.parse_properties(fixture(name))


MALFORMED_INPUTS = [
    "",
    "not json",
    "{}",
    '{"data":42}',
    '{"type":"as"}',
    "null",
    '{"type":"as","data":[["dev-1"',
    "Call failed: unknown service",
]


class ParseCallResultTests(unittest.TestCase):
    def test_real_call_reply_shapes(self):
        # `call` replies wrap the return values: data is a list of them.
        self.assertEqual(media_status.parse_call_result(fixture("busctl-devices.json")), [["dev-1"]])
        self.assertEqual(media_status.parse_call_result(fixture("busctl-namehasowner-true.json")), [True])
        self.assertEqual(media_status.parse_call_result(fixture("busctl-namehasowner-false.json")), [False])
        # `get-property` replies carry the value directly (real capture).
        self.assertEqual(media_status.parse_call_result(fixture("busctl-custom-devices.json")), ["100.64.0.1"])

    def test_malformed_input_never_throws_and_yields_none(self):
        for bad in MALFORMED_INPUTS:
            self.assertIsNone(media_status.parse_call_result(bad), repr(bad))
            self.assertIsNone(media_status.parse_properties(bad), repr(bad))
            self.assertIsNone(discover_report.parse_string_list(bad), repr(bad))


class ParsePropertiesTests(unittest.TestCase):
    def test_device_getall_flattens_variants(self):
        device = props("busctl-device-getall.json")
        self.assertEqual(device["name"], "My Phone")
        self.assertIs(device["isPaired"], True)
        self.assertIs(device["isReachable"], True)
        self.assertIs(device["isPairRequested"], False)
        self.assertIsInstance(device["supportedPlugins"], list)
        self.assertIn("kdeconnect_battery", device["supportedPlugins"])

    def test_battery_getall_flattens_variants(self):
        battery = props("busctl-battery-getall.json")
        self.assertEqual(battery["charge"], 85)
        self.assertIs(battery["isCharging"], True)

    def test_mpris_getall_flattens_variants(self):
        mpris = props("busctl-mpris-getall.json")
        self.assertEqual(mpris["title"], "Track")
        self.assertEqual(mpris["playerList"], ["Music"])

    def test_empty_getall_dict_is_valid_empty_properties(self):
        self.assertEqual(media_status.parse_properties('{"type":"a{sv}","data":[{}]}'), {})


class ParseStringListTests(unittest.TestCase):
    def test_call_wrapped_and_get_property_direct_shapes(self):
        # `call` wraps the return value once; get-property returns it directly.
        self.assertEqual(discover_report.parse_string_list(fixture("busctl-devices.json")), ["dev-1"])
        self.assertEqual(discover_report.parse_string_list(fixture("busctl-custom-devices.json")), ["100.64.0.1"])

    def test_typed_empty_list_is_valid_and_empty(self):
        self.assertEqual(discover_report.parse_string_list(fixture("busctl-devices-empty.json")), [])
        self.assertEqual(discover_report.parse_string_list(fixture("busctl-custom-devices-empty.json")), [])

    def test_non_string_items_are_dropped(self):
        raw = json.dumps({"type": "as", "data": [["ok", 42, None, ""]]})
        self.assertEqual(discover_report.parse_string_list(raw), ["ok"])


class MediaStatusBuilderTests(unittest.TestCase):
    def test_clean_fixture_exact_contract(self):
        status, autoselect = media_status.build_status(props("busctl-mpris-getall.json"))
        self.assertEqual(status, {
            "isPlaying": True,
            "title": "Track",
            "artist": "The Artist",
            "album": "Greatest Hits",
            "player": "Music",
            "playerList": ["Music"],
            "albumArt": "file:///tmp/cover.jpg",
        })
        self.assertIsNone(autoselect)

    def test_hostile_metadata_survives_verbatim(self):
        status, autoselect = media_status.build_status(props("busctl-mpris-getall-hostile.json"))
        self.assertEqual(status["title"], 'Don\'t "Quit" <b>NOW</b>\n(Take 2)')
        self.assertEqual(status["artist"], "Guns N' Roses")
        self.assertEqual(status["album"], "Greatest Hits '86")
        self.assertEqual(status["playerList"], ["Spotify", "Don't Stop"])
        # albumArt falls through localAlbumArtUrl -> ... -> albumArt.
        self.assertEqual(status["albumArt"], "file:///tmp/dont cry.jpg")
        self.assertIsNone(autoselect)

    def test_empty_player_list(self):
        status, autoselect = media_status.build_status(props("busctl-mpris-getall-empty-players.json"))
        self.assertEqual(status, media_status.empty_status())
        self.assertIsNone(autoselect)

    def test_nowplaying_fallback_when_title_missing(self):
        status, _ = media_status.build_status(props("busctl-mpris-getall-nowplaying.json"))
        self.assertEqual(status["title"], "Fallback Now Playing")
        self.assertEqual(status["artist"], "")
        self.assertEqual(status["player"], "MPD")

    def test_first_player_autoselect(self):
        status, autoselect = media_status.build_status(props("busctl-mpris-getall-autoselect.json"))
        self.assertEqual(status["player"], "Spotify")
        self.assertEqual(status["playerList"], ["Spotify", "VLC"])
        self.assertEqual(autoselect, "Spotify")

    def test_known_player_missing_from_list_is_prepended(self):
        status, autoselect = media_status.build_status({
            "player": "Foobar",
            "playerList": ["Spotify"],
        })
        self.assertEqual(status["playerList"], ["Foobar", "Spotify"])
        self.assertIsNone(autoselect)

    def test_none_props_yield_empty_contract(self):
        status, autoselect = media_status.build_status(None)
        self.assertEqual(status, media_status.empty_status())
        self.assertIsNone(autoselect)

    def test_non_string_remote_values_are_coerced_safe(self):
        status, autoselect = media_status.build_status({
            "title": 42,
            "isPlaying": "true",
            "playerList": ["ok", 7],
            "player": True,
        })
        self.assertEqual(status["title"], "")
        self.assertIs(status["isPlaying"], False)
        self.assertEqual(status["playerList"], ["ok"])
        # Non-string player reads as unset, so the first valid entry wins.
        self.assertEqual(status["player"], "ok")
        self.assertEqual(autoselect, "ok")


class DeviceTsvFormatterTests(unittest.TestCase):
    EXPECTED_PLUGINS = ",".join([
        "kdeconnect_battery", "kdeconnect_ping", "kdeconnect_share",
        "kdeconnect_runcommand", "kdeconnect_findmyphone", "kdeconnect_clipboard",
        "kdeconnect_connectivity_report", "kdeconnect_sms", "kdeconnect_mprisremote",
        "kdeconnect_mpriscontrol",
    ])

    def test_clean_fixture_exact_14_field_line(self):
        line = discover_report.format_device(
            "dev-1",
            props("busctl-device-getall.json"),
            props("busctl-battery-getall.json"),
            props("busctl-connectivity-getall.json"),
        )
        self.assertEqual(line, "\t".join([
            "DEVICE", "dev-1", "My Phone", "phone", "true", "true",
            "85", "true", self.EXPECTED_PLUGINS, "LTE", "3",
            "false", "false", "82C4DD3C",
        ]))
        self.assertEqual(len(line.split("\t")), 14)

    def test_hostile_name_cannot_forge_tsv_records(self):
        line = discover_report.format_device(
            "evil-1", props("busctl-device-getall-hostile.json"), None, None)
        fields = line.split("\t")
        self.assertEqual(len(fields), 14)
        self.assertEqual(fields[2], "Evil <[]> Name Second Row")
        self.assertEqual(fields[13], "EVIL KEY !")
        for field in fields:
            self.assertNotIn("\t", field)
            self.assertNotIn("\n", field)

    def test_battery_reported_as_na(self):
        line = discover_report.format_device(
            "dev-1", props("busctl-device-getall.json"),
            props("busctl-battery-getall-na.json"), None)
        fields = line.split("\t")
        self.assertEqual(fields[6], "-1")
        self.assertEqual(fields[7], "false")

    def test_battery_values_gated_on_supported_plugin(self):
        # battery GetAll present but battery plugin not supported -> n/a.
        device = props("busctl-device-getall.json")
        device["supportedPlugins"] = ["kdeconnect_ping"]
        line = discover_report.format_device(
            "dev-1", device, props("busctl-battery-getall.json"),
            props("busctl-connectivity-getall.json"))
        fields = line.split("\t")
        self.assertEqual(fields[6], "-1")
        self.assertEqual(fields[7], "false")
        self.assertEqual(fields[8], "kdeconnect_ping")
        self.assertEqual(fields[9], "")
        self.assertEqual(fields[10], "-1")

    def test_connectivity_null_and_invalid_values(self):
        conn = {"cellularNetworkType": "null", "cellularNetworkStrength": "4"}
        line = discover_report.format_device(
            "dev-1", props("busctl-device-getall.json"),
            props("busctl-battery-getall.json"), conn)
        fields = line.split("\t")
        self.assertEqual(fields[9], "")
        self.assertEqual(fields[10], "-1")

    def test_non_boolean_flags_and_odd_types_fall_back(self):
        line = discover_report.format_device("d", {
            "name": None, "type": ["x"], "isPaired": "yes", "isReachable": False,
        }, None, None)
        fields = line.split("\t")
        self.assertEqual(fields[2], "")
        self.assertEqual(fields[3], "")
        self.assertEqual(fields[4], "false")

    def test_sanitize_folds_tabs_and_newlines_only(self):
        self.assertEqual(discover_report.sanitize("a\tb\nc"), "a b c")
        self.assertEqual(discover_report.sanitize("plain"), "plain")


class SanitizeParityTests(unittest.TestCase):
    def test_python_sanitize_matches_the_bash_field_sanitizer(self):
        bash = subprocess.run(
            [os.environ.get("SHELL", "bash"), "-c",
             'sanitize_field() { local field=$1; field=${field//$\'\\t\'/ }; field=${field//$\'\\n\'/ }; printf \'%s\' "$field"; };'
             ' sanitize_field "$(printf \'Evil\\t<[]> Name\\nrow2\')"'],
            capture_output=True, text=True, check=True)
        self.assertEqual(
            discover_report.sanitize("Evil\t<[]> Name\nrow2"), bash.stdout)


class ScriptLevelGracefulFailureTests(unittest.TestCase):
    def test_media_status_emits_valid_empty_json_on_garbage_busctl(self):
        with tempfile.TemporaryDirectory() as tmp:
            stub = Path(tmp) / "busctl"
            stub.write_text("#!/usr/bin/env bash\nprintf 'Call failed: garbage\\n'\nexit 1\n")
            stub.chmod(0o755)
            for bad in ("Call failed: garbage", '{"type":"a{sv}","data":[{"title"', ""):
                stub.write_text("#!/usr/bin/env bash\nprintf '%%s' %s\n" % json.dumps(bad))
                res = subprocess.run(
                    [PYTHON, str(SCRIPTS / "media_status.py"), "dev-1"],
                    capture_output=True, text=True,
                    env={**os.environ, "PATH": f"{tmp}:{os.environ['PATH']}"},
                )
                self.assertEqual(res.returncode, 0, res)
                self.assertNotIn("Traceback", res.stdout)
                self.assertNotIn("Traceback", res.stderr)
                self.assertEqual(json.loads(res.stdout), media_status.empty_status())

    def test_discover_report_device_rejects_garbage_without_traceback(self):
        for bad in ('{"type":"a{sv}","data":[{"name"', "not json", ""):
            res = subprocess.run(
                [PYTHON, str(SCRIPTS / "discover_report.py"), "device", "dev-1", bad, "", ""],
                capture_output=True, text=True,
            )
            self.assertNotEqual(res.returncode, 0, repr(bad))
            self.assertEqual(res.stdout, "")
            self.assertNotIn("Traceback", res.stdout)
            self.assertNotIn("Traceback", res.stderr)

    def test_discover_report_ids_rejects_garbage_without_traceback(self):
        for name in ("busctl-devices-truncated.json", "busctl-devices-garbage.txt"):
            res = subprocess.run(
                [PYTHON, str(SCRIPTS / "discover_report.py"), "ids"],
                input=fixture(name), capture_output=True, text=True,
            )
            self.assertEqual(res.returncode, 3, name)
            self.assertEqual(res.stdout, "")
            self.assertNotIn("Traceback", res.stderr)

    def test_discover_report_truthy_rejects_garbage(self):
        res = subprocess.run(
            [PYTHON, str(SCRIPTS / "discover_report.py"), "truthy"],
            input='{"type":"b","data":[tru', capture_output=True, text=True,
        )
        self.assertEqual(res.returncode, 1)
        self.assertNotIn("Traceback", res.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
