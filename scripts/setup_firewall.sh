#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF'
============================================================
                OmaConnect Firewall Setup
============================================================
KDE Connect requires network ports 1714-1764 (both TCP and UDP)
open on your local network to discover devices and exchange
messages, clipboard data, and files.
============================================================
EOF

if command -v ufw >/dev/null 2>&1; then
    cat << 'EOF'
Detected firewall: UFW (Uncomplicated Firewall)

Commands that will be executed:
  sudo ufw allow 1714:1764/tcp comment 'KDE Connect'
  sudo ufw allow 1714:1764/udp comment 'KDE Connect'
  sudo ufw reload
============================================================
EOF

    if [[ -t 0 ]]; then
        printf 'Press Enter to apply UFW rules, or Ctrl+C to cancel: '
        read -r _
    fi

    echo "Applying UFW firewall rules with root privileges..."
    if sudo ufw allow 1714:1764/tcp comment 'KDE Connect' && \
       sudo ufw allow 1714:1764/udp comment 'KDE Connect' && \
       sudo ufw reload; then
        echo ""
        echo "Firewall rules applied successfully."
        sleep 1.5
    else
        status=$?
        echo ""
        echo "Failed to configure UFW rules (exit code: $status)."
        sleep 2.5
        exit "$status"
    fi

elif command -v firewall-cmd >/dev/null 2>&1; then
    cat << 'EOF'
Detected firewall: firewalld

Commands that will be executed:
  sudo firewall-cmd --permanent --add-service=kdeconnect
  sudo firewall-cmd --reload
============================================================
EOF

    if [[ -t 0 ]]; then
        printf 'Press Enter to apply firewalld rules, or Ctrl+C to cancel: '
        read -r _
    fi

    echo "Applying firewalld rules with root privileges..."
    if sudo firewall-cmd --permanent --add-service=kdeconnect && \
       sudo firewall-cmd --reload; then
        echo ""
        echo "Firewall rules applied successfully."
        sleep 1.5
    else
        status=$?
        echo ""
        echo "Failed to configure firewalld rules (exit code: $status)."
        sleep 2.5
        exit "$status"
    fi

else
    echo "No supported firewall service (ufw / firewalld) detected."
    echo "If you use a custom firewall (like iptables/nftables), allow ports 1714-1764 TCP/UDP manually."
    sleep 2
fi
