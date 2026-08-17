#!/usr/bin/env bash
set -Eeuo pipefail

# Keep the QML process boundary stable: one tab-separated record per device,
# and a non-zero exit for missing dependencies, D-Bus errors, or bad replies.
base=/modules/kdeconnect

for command in gdbus sed grep tr kdeconnect-cli; do
    command -v "$command" >/dev/null 2>&1 || exit 127
done

is_daemon_running() {
    gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner org.kde.kdeconnect 2>/dev/null \
        | grep -q '(true,)'
}

ensure_daemon() {
    if ! is_daemon_running; then
        gdbus call --session --dest org.freedesktop.DBus \
            --object-path /org/freedesktop/DBus \
            --method org.freedesktop.DBus.StartServiceByName org.kde.kdeconnect 0 >/dev/null 2>&1 || true
        sleep 0.5
    fi
}

if [[ "${1:-}" == "--refresh" || "${1:-}" == "-r" ]]; then
    ensure_daemon
    if command -v kdeconnect-cli >/dev/null 2>&1; then
        kdeconnect-cli --refresh >/dev/null 2>&1 || true
    fi
    gdbus call --session --dest org.kde.kdeconnect \
        --object-path /modules/kdeconnect \
        --method org.kde.kdeconnect.daemon.forceOnNetworkChange >/dev/null 2>&1 || true
    sleep 1.2
fi

is_daemon_running || exit 69

property() {
    local path=$1 interface=$2 name=$3
    gdbus call --session --dest org.kde.kdeconnect \
        --object-path "$path" --method org.freedesktop.DBus.Properties.Get \
        "$interface" "$name" 2>/dev/null || return 69
}

sanitize_field() {
    local field=$1
    field=${field//$'\t'/ }
    field=${field//$'\n'/ }
    printf '%s' "$field"
}

value() {
    # gdbus quotes strings as <'value'> and scalar values as <value>.
    printf '%s' "$1" | sed -E "s/^\((true|false),\)$/\1/; s/^\(<('([^']|\\\\')*'|[^>]+)>.*$/\1/; s/^<'(.*)'>,?$/\1/; s/^<([^>]*)>,?$/\1/; s/^'(.*)'$/\1/"
}

ids=$(gdbus call --session --dest org.kde.kdeconnect --object-path "$base" \
    --method org.kde.kdeconnect.daemon.devices false false) || exit 69
entries=$(printf '%s' "$ids" | sed -E 's/.*\[//; s/\].*//' | tr ',' '\n' \
    | sed -nE "s/^[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\1/p")
[[ -n "$entries" || "$ids" =~ ^\((@as[[:space:]]+)?\[[[:space:]]*\],[[:space:]]*\)$ ]] || exit 70

is_address_reachable() {
    local addr=$1
    [[ -n "$addr" ]] || return 1
    # Pass the address as data; interpolating it into the shell program allows
    # a malformed or compromised D-Bus response to inject shell syntax.
    if timeout 0.4 bash -c '>/dev/tcp/$1/1716' -- "$addr" 2>/dev/null; then
        return 0
    fi
    if ping -c 1 -W 1 "$addr" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    path="$entry"
    [[ "$path" == /* ]] || path="$base/devices/$entry"
    id=${path##*/}
    name=$(value "$(property "$path" org.kde.kdeconnect.device name)") || continue
    type=$(value "$(property "$path" org.kde.kdeconnect.device type)") || continue
    paired=$(value "$(property "$path" org.kde.kdeconnect.device isPaired)") || continue
    reachable=$(value "$(property "$path" org.kde.kdeconnect.device isReachable)") || continue
    if [[ "$reachable" == "true" ]]; then
        providers_raw=$(property "$path" org.kde.kdeconnect.device activeProviderNames 2>/dev/null) || providers_raw=""
        addrs_raw=$(property "$path" org.kde.kdeconnect.device reachableAddresses 2>/dev/null) || addrs_raw=""
        addrs=$(printf '%s' "$addrs_raw" | sed -E 's/.*\[//; s/\].*//' | tr ',' '\n' | sed -nE "s/^[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\1/p")
        if [[ -n "$addrs" || "$providers_raw" == *"LAN"* ]]; then
            has_alive_addr=false
            if [[ -n "$addrs" ]]; then
                while IFS= read -r addr; do
                    [[ -n "$addr" ]] || continue
                    if is_address_reachable "$addr"; then
                        has_alive_addr=true
                        break
                    fi
                done <<< "$addrs"
            fi
            if [[ "$has_alive_addr" != true ]]; then
                reachable=false
            fi
        fi
    fi
    supported=$(property "$path" org.kde.kdeconnect.device supportedPlugins) || continue
    plugins=
    for plugin in kdeconnect_battery kdeconnect_ping kdeconnect_share kdeconnect_runcommand kdeconnect_findmyphone kdeconnect_clipboard kdeconnect_connectivity_report kdeconnect_sms; do
        if [[ "$supported" == *"'$plugin'"* || "$supported" == *"<$plugin>"* ]]; then
            plugins="${plugins:+$plugins,}$plugin"
        fi
    done

    charge=-1
    charging=false
    if [[ "$plugins" == *kdeconnect_battery* ]]; then
        battery="$path/battery"
        charge_raw=$(value "$(property "$battery" org.kde.kdeconnect.device.battery charge)") || charge_raw=""
        [[ "$charge_raw" =~ ^[0-9]+$ ]] && charge=$charge_raw
        charging_raw=$(value "$(property "$battery" org.kde.kdeconnect.device.battery isCharging)") || charging_raw=false
        [[ "$charging_raw" == true ]] && charging=true
    fi
    net_type=
    net_strength=-1
    if [[ "$plugins" == *kdeconnect_connectivity_report* ]]; then
        conn="$path/connectivity_report"
        type_raw=$(value "$(property "$conn" org.kde.kdeconnect.device.connectivity_report cellularNetworkType)") || type_raw=""
        strength_raw=$(value "$(property "$conn" org.kde.kdeconnect.device.connectivity_report cellularNetworkStrength)") || strength_raw=""
        [[ -n "$type_raw" && "$type_raw" != "null" ]] && net_type=$type_raw
        [[ "$strength_raw" =~ ^[0-9]+$ ]] && net_strength=$strength_raw
    fi
    printf 'DEVICE\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(sanitize_field "$id")" "$(sanitize_field "$name")" "$(sanitize_field "$type")" "$paired" "$reachable" "$charge" "$charging" "$plugins" "$(sanitize_field "$net_type")" "$net_strength"
done <<< "$entries"
