#!/usr/bin/env bash
set -Eeuo pipefail

if command -v kdeconnect-app >/dev/null 2>&1; then
    nohup kdeconnect-app >/dev/null 2>&1 &
    exit 0
elif command -v kdeconnect-settings >/dev/null 2>&1; then
    nohup kdeconnect-settings >/dev/null 2>&1 &
    exit 0
elif command -v kcmshell6 >/dev/null 2>&1; then
    nohup kcmshell6 kcm_kdeconnect >/dev/null 2>&1 &
    exit 0
fi
exit 127
