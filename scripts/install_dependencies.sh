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

# ---------------------------------------------------------------------------
# Optional: contact names in the SMS app.
#
# KDE Connect's contacts plugin writes the phone's address book into
# ~/.local/share/kpeoplevcard/kdeconnect-<device-id>/ as vCards, but nothing
# reads them unless the kpeoplevcard KPeople backend is installed. Without it
# kdeconnect-sms has no way to map a number to a name, so every conversation is
# listed as a bare phone number.
#
# kpeoplevcard is not in the official repositories, so this step needs an AUR
# helper and is kept separate from the required packages above.
# ---------------------------------------------------------------------------

if pacman -Qq kpeoplevcard >/dev/null 2>&1; then
    echo ""
    echo "kpeoplevcard already installed; SMS contact names are supported."
    sleep 1.5
    exit 0
fi

aur_helper=""
for candidate in yay paru; do
    if command -v "$candidate" >/dev/null 2>&1; then
        aur_helper="$candidate"
        break
    fi
done

cat << 'EOF'

============================================================
      Optional: show contact names instead of numbers
============================================================
kdeconnect-sms lists every conversation by phone number unless the
kpeoplevcard KPeople backend is installed. It reads the vCards that
KDE Connect syncs from your phone and resolves them to names.

This package lives in the AUR, not the official repositories.
============================================================
EOF

if [[ -z $aur_helper ]]; then
    cat << 'EOF'
No AUR helper (yay or paru) was found, so this step is being skipped.
Install it later with, for example:

  yay -S kpeoplevcard

Then grant KDE Connect the Contacts permission on your phone and
re-pair or refresh so the vCards sync across.
EOF
    sleep 2.5
    exit 0
fi

if [[ -t 0 ]]; then
    printf 'Install kpeoplevcard with %s? [y/N]: ' "$aur_helper"
    read -r reply
    case "$reply" in
        [yY] | [yY][eE][sS]) ;;
        *)
            echo "Skipped. You can run '$aur_helper -S kpeoplevcard' later."
            sleep 1.5
            exit 0
            ;;
    esac
else
    # Non-interactive runs must not pull in an AUR package unprompted.
    echo "Non-interactive run; skipping the optional AUR step."
    echo "Run '$aur_helper -S kpeoplevcard' to enable SMS contact names."
    exit 0
fi

if "$aur_helper" -S --needed kpeoplevcard; then
    cat << 'EOF'

kpeoplevcard installed.

One more step happens on the phone: open KDE Connect on Android, make
sure the Contacts plugin is enabled, and grant the Contacts permission.
Names appear after the next sync; restart kdeconnect-sms to pick them up.
EOF
    sleep 2.5
else
    status=$?
    echo ""
    echo "kpeoplevcard installation failed or was cancelled (exit code: $status)."
    echo "OmaConnect still works; conversations stay listed by number."
    sleep 2.5
fi

exit 0
