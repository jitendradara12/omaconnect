#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF'
============================================================
              OmaConnect Dependency Installer
============================================================
OmaConnect requires the following official Arch Linux packages:
  - kdeconnect : Core daemon, D-Bus interfaces, and CLI tools
  - glib2      : gdbus utility for desktop D-Bus communication
  - dbus       : Desktop message bus

Exact command that will be executed:
  sudo pacman -S --needed kdeconnect glib2 dbus
============================================================
EOF

if [[ -t 0 ]]; then
    printf 'Press Enter to proceed with installation, or Ctrl+C to cancel: '
    read -r _
fi

echo "Running pacman with root privileges..."
if sudo pacman -S --needed kdeconnect glib2 dbus; then
    echo ""
    echo "Dependencies installed successfully."
    sleep 1.5
else
    status=$?
    echo ""
    echo "Installation failed or was cancelled (exit code: $status)."
    sleep 2.5
    exit "$status"
fi
