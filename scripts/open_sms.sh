#!/usr/bin/env bash
set -Eeuo pipefail

# Opens the KDE Connect SMS app. The device id crosses to kdeconnect-sms as a
# single argv element, so it is validated first with the same rules as
# media_control.sh (no tabs/newlines/spaces/slashes): an id carrying
# whitespace or slashes could otherwise be read as extra flags. An empty id
# launches the app without --device (previous behavior). Validation precedes
# the kdeconnect-sms existence check: a malformed id is a usage error (64)
# even when the binary is missing (127).

device_id="${1:-}"
if [[ -n "$device_id" ]]; then
    [[ "$device_id" != *$'\t'* && "$device_id" != *$'\n'* && "$device_id" != *' '* && "$device_id" != */* ]] || exit 64
fi
command -v kdeconnect-sms >/dev/null 2>&1 || exit 127
if [[ -n "$device_id" ]]; then
    nohup kdeconnect-sms --device "$device_id" >/dev/null 2>&1 &
else
    nohup kdeconnect-sms >/dev/null 2>&1 &
fi
exit 0
