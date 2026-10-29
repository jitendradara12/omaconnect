"""Source-contract tests for Scope B: device-controlled strings render as plain text.

QML `Text` defaults to textFormat: Text.AutoText, which auto-detects rich text.
Device names, media metadata, remote command names, verification keys and
tailscale peer names all originate on remote devices, so a hostile peer could
send a name like "<a href=...>x</a>" and have markup interpreted by the panel.
These tests pin `textFormat: Text.PlainText` on the Text elements that bind
device-derived values (in practice: on every Text block in the owned files,
matching the upstream omarchy-connect hardening).
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]

OWNED_QML_FILES = [
    "components/DeviceSection.qml",
    "components/MediaPlayerSection.qml",
    "components/NetworkSection.qml",
    "components/RemoteCommandsSection.qml",
    "components/ComposerSection.qml",
    "components/ActionToolbar.qml",
    "BarWidget.qml",
]

PLAINTEXT_LINE = "textFormat: Text.PlainText"

# Identifiers that only ever appear in a text binding when the displayed string
# originates on (or is derived from) a remote device. Includes the service
# helper functions that format device fields (battery/network/type/overview).
DEVICE_DERIVED_TRIGGERS = [
    r"\bmodelData\b",
    r"\bdeviceName\b",
    r"\btrackTitle\b",
    r"\btrackArtist\b",
    r"\btrackAlbum\b",
    r"\bincomingRequest\b",
    r"\bverificationKey\b",
    r"\bnetworkType\b",
    r"\bdevice\.name\b",
    r"\bdevice\.type\b",
    r"\bdeviceBatteryText\b",
    r"\bdeviceOverviewStatus\b",
    r"\bdeviceTypeIcon\b",
    r"\bformatVerificationKey\b",
]

TEXT_BLOCK_START = re.compile(r"^\s*Text\s*\{")
# Also catch a Text nested on a property-binding line, e.g.
# `contentItem: Text { ... }` (patterns used by the Omarchy shell).
TEXT_BLOCK_START_INLINE = re.compile(r"\w[:.]\s*Text\s*\{")
PROPERTY_LINE = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_]*\s*:(?!:)")
# Commented-out lines (e.g. `// textFormat: Text.PlainText`) must not count
# as carrying the property; the property may sit on its own line or inline
# after `{`, `;` or `,` in a single-line Text block.
PLAINTEXT_PROPERTY = re.compile(r"(?:^\s*|[;,{]\s*)textFormat\s*:\s*Text\.PlainText\s*(?:[;}]|$)")


def strip_line_comment(line):
    """Remove a trailing // comment (ignoring // inside URLs such as https://)."""
    index = line.find("//")
    while index >= 0:
        if index == 0 or line[index - 1] != ":":
            return line[:index]
        index = line.find("//", index + 2)
    return line


def find_text_blocks(source):
    """Brace-tolerant scan: return every `Text { ... }` block in a QML source.

    Each block is reported as {"start", "end", "source"} with 1-based line
    numbers; `end` is the line whose closing brace returns the depth to the
    level the block started at. Braces inside // comments are ignored.
    Note: brace counting is not string-literal aware, so a literal "}" or
    "{" inside a string skews depth — no owned file contains one today.
    """
    lines = source.splitlines()
    blocks = []
    depth = 0
    index = 0
    while index < len(lines):
        if TEXT_BLOCK_START.match(lines[index]) or (
            TEXT_BLOCK_START_INLINE.search(strip_line_comment(lines[index]))
            and not lines[index].strip().startswith("//")
        ):
            base_depth = depth
            start = index
            end = index
            while index < len(lines):
                code = strip_line_comment(lines[index])
                depth += code.count("{") - code.count("}")
                end = index
                # depth returns to base either on the block's closing line
                # or on a same-line-open-and-close block (Text { ... } on one
                # line) — both end the block.
                if depth <= base_depth:
                    break
                index += 1
            blocks.append(
                {"start": start + 1, "end": end + 1, "source": "\n".join(lines[start : end + 1])}
            )
        else:
            code = strip_line_comment(lines[index])
            depth += code.count("{") - code.count("}")
        index += 1
    return blocks


def text_binding(block_source):
    """Extract the source of the `text:` binding (including multi-line bindings).

    A single-line `Text { text: ... }` carries the binding inline, so the
    collection trigger also matches `text:` after `{` or `,`.
    """
    lines = block_source.splitlines()
    binding_lines = []
    collecting = False
    for line in lines:
        if not collecting and re.search(r"(?:^\s*|[,{]\s*)text\s*:", line):
            collecting = True
            binding_lines.append(line)
            continue
        if collecting:
            # A new property assignment at the same or lower indentation ends
            # the binding; continuation lines of a `text: { ... }` block are
            # statements and never match this pattern.
            if PROPERTY_LINE.match(line) and not line.strip().startswith("//"):
                break
            binding_lines.append(line)
    return "\n".join(binding_lines)


def binds_device_derived_value(block_source):
    binding = text_binding(block_source)
    return any(re.search(trigger, binding) for trigger in DEVICE_DERIVED_TRIGGERS)


def has_plaintext_property(block_source):
    """True when a real (non-commented) textFormat: Text.PlainText line exists."""
    for line in block_source.splitlines():
        if PLAINTEXT_PROPERTY.search(strip_line_comment(line).rstrip()):
            return True
    return False


def find_missing_plaintext(source):
    """Text blocks that bind device-derived values but lack textFormat: PlainText."""
    missing = []
    for block in find_text_blocks(source):
        if binds_device_derived_value(block["source"]) and not has_plaintext_property(block["source"]):
            missing.append(block)
    return missing


def load(path):
    return (ROOT / path).read_text()


class PlainTextScannerTests(unittest.TestCase):
    def test_scanner_negative_self_test_flags_unhardened_device_name_snippet(self):
        """The scanner itself must work: an embedded snippet binding a device
        name without textFormat is flagged, the hardened twin is not."""
        snippet = """
import QtQuick

Column {
    Text {
        text: root.deviceName
    }

    Text {
        text: root.deviceName
        textFormat: Text.PlainText
    }
}
"""
        missing = find_missing_plaintext(snippet)
        self.assertEqual(len(missing), 1)
        self.assertIn("deviceName", text_binding(missing[0]["source"]))
        self.assertNotIn(PLAINTEXT_LINE, missing[0]["source"])

    def test_scanner_flags_commented_out_property_and_inline_blocks(self):
        """A commented-out textFormat line must not count as the property, a
        single-line Text block must be scanned as a block, and a Text nested
        on a property line (contentItem: Text {...}) must be found."""
        snippet = """
Column {
    Text {
        text: root.deviceName
        // textFormat: Text.PlainText
    }

    Text { text: root.trackTitle }

    contentItem: Text { text: root.trackArtist }
}
"""
        blocks = find_text_blocks(snippet)
        self.assertEqual(len(blocks), 3)
        missing = find_missing_plaintext(snippet)
        self.assertEqual(len(missing), 3)
        self.assertFalse(has_plaintext_property(missing[0]["source"]))
        # Hardened twins of the same three shapes must not be flagged.
        hardened = """
Column {
    Text {
        text: root.deviceName
        textFormat: Text.PlainText
    }

    Text { text: root.trackTitle; textFormat: Text.PlainText }

    contentItem: Text { text: root.trackArtist; textFormat: Text.PlainText }
}
"""
        self.assertEqual(find_missing_plaintext(hardened), [])

    def test_scanner_handles_nested_braces_and_multiline_bindings(self):
        """Brace tracking must survive a multi-line JS binding: the unhardened
        block is flagged exactly once and the following block is not swallowed."""
        snippet = """
Column {
    Text {
        text: {
            var label = root.trackTitle
            return label
        }
    }

    Text {
        text: "static"
    }
}
"""
        missing = find_missing_plaintext(snippet)
        self.assertEqual(len(missing), 1)
        self.assertIn("trackTitle", text_binding(missing[0]["source"]))

    def test_scanner_finds_expected_text_block_inventory(self):
        """Sanity: the owned files expose the Text blocks these contracts pin."""
        total = sum(len(find_text_blocks(load(path))) for path in OWNED_QML_FILES)
        self.assertEqual(total, 48)


class DeviceDerivedBindingsArePlainTextTests(unittest.TestCase):
    def test_device_derived_text_bindings_have_plaintext_format(self):
        """Every Text block whose text binding references a device-derived value
        (modelData, deviceName, track*, incomingRequest, verificationKey,
        networkType, device.name/type or the service helpers fed by them) must
        set textFormat: Text.PlainText."""
        for path in OWNED_QML_FILES:
            with self.subTest(file=path):
                missing = find_missing_plaintext(load(path))
                self.assertEqual(
                    missing,
                    [],
                    f"{path}: Text blocks at lines {[b['start'] for b in missing]} "
                    "bind device-derived values without textFormat: Text.PlainText",
                )

    def test_every_text_block_in_owned_files_is_plaintext(self):
        """Regression pin for the blanket approach: ALL Text blocks in the owned
        files carry the property, so a future edit cannot silently add a
        device-derived string with default AutoText formatting."""
        for path in OWNED_QML_FILES:
            with self.subTest(file=path):
                for block in find_text_blocks(load(path)):
                    self.assertTrue(
                        has_plaintext_property(block["source"]),
                        f"{path}: Text block at line {block['start']} lacks {PLAINTEXT_LINE}",
                    )

    def test_no_device_derived_binding_without_plaintext_anywhere_in_repo(self):
        """The trigger layer guards every QML file in the repo, not only the
        files this PR hardened — a new file or an inline contentItem Text
        binding a device value without the property fails here."""
        qml_files = sorted(str(p.relative_to(ROOT)) for p in ROOT.glob("**/*.qml"))
        self.assertTrue(qml_files, "no QML files found — scanner is broken")
        for path in qml_files:
            with self.subTest(file=path):
                missing = find_missing_plaintext(load(path))
                self.assertEqual(
                    missing,
                    [],
                    f"{path}: Text blocks at lines {[b['start'] for b in missing]} "
                    "bind device-derived values without textFormat: Text.PlainText",
                )


class StrictRegressionPinsTests(unittest.TestCase):
    def test_device_section_pairing_request_label_block_is_pinned_plaintext(self):
        blocks = [
            b for b in find_text_blocks(load("components/DeviceSection.qml"))
            if "Pairing request from" in b["source"]
        ]
        self.assertEqual(len(blocks), 1)
        self.assertTrue(has_plaintext_property(blocks[0]["source"]))

    def test_device_section_verification_key_block_is_pinned_plaintext(self):
        blocks = [
            b for b in find_text_blocks(load("components/DeviceSection.qml"))
            if "verificationKey" in text_binding(b["source"])
        ]
        self.assertEqual(len(blocks), 1)
        self.assertTrue(has_plaintext_property(blocks[0]["source"]))

    def test_device_section_model_data_name_block_is_pinned_plaintext(self):
        blocks = [
            b for b in find_text_blocks(load("components/DeviceSection.qml"))
            if re.search(r"\bmodelData\.name\b", text_binding(b["source"]))
        ]
        self.assertEqual(len(blocks), 1)
        self.assertTrue(has_plaintext_property(blocks[0]["source"]))

    def test_media_player_track_title_block_is_pinned_plaintext(self):
        blocks = [
            b for b in find_text_blocks(load("components/MediaPlayerSection.qml"))
            if re.search(r"\broot\.trackTitle\b", text_binding(b["source"]))
        ]
        self.assertEqual(len(blocks), 2)  # collapsed bar title + expanded card title
        for block in blocks:
            self.assertTrue(has_plaintext_property(block["source"]))

    def test_media_player_track_artist_and_album_block_is_pinned_plaintext(self):
        blocks = [
            b for b in find_text_blocks(load("components/MediaPlayerSection.qml"))
            if re.search(r"\broot\.trackArtist\b", text_binding(b["source"]))
        ]
        self.assertEqual(len(blocks), 2)  # collapsed bar "title • artist" + expanded artist/album
        for block in blocks:
            self.assertTrue(has_plaintext_property(block["source"]))
            self.assertRegex(text_binding(block["source"]), r"trackAlbum|trackArtist")


if __name__ == "__main__":
    unittest.main()
