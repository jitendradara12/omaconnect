pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool daemonAvailable: false
    property bool sessionBusAvailable: false
    property bool scanning: false
    property string discoveryState: "starting"
    property string discoveryMessage: "Checking KDE Connect"
    property string pluginPath: ""
    property string actionState: "idle"
    property string actionMessage: ""
    property string actionError: ""

    Timer {
        id: actionDismissTimer
        interval: 4000
        repeat: false
        onTriggered: {
            root.actionMessage = ""
            root.actionError = ""
        }
    }

    onActionMessageChanged: {
        if (actionMessage !== "" || actionError !== "") actionDismissTimer.restart()
        else actionDismissTimer.stop()
    }

    onActionErrorChanged: {
        if (actionMessage !== "" || actionError !== "") actionDismissTimer.restart()
        else actionDismissTimer.stop()
    }
    property string selectedDeviceId: ""
    property var devices: []
    property var remoteCommands: []
    property bool commandsLoading: false
    property string commandTargetId: ""
    property int generation: 0
    property int actionGeneration: 0
    property var pendingPairing: ({})
    property var pairingRequestTimes: ({})
    property bool fileBusy: false
    property var capabilities: ({})
    property int monitorRestartCount: 0
    property bool tailscaleInstalled: false
    property bool tailscaleRunning: false
    property bool tailscaleLoading: false
    property string tailscaleStatus: "Checking Tailscale"
    property string localTailscaleAddress: ""
    property var tailscalePeers: []
    property var customAddresses: []
    property bool customAddressesReady: false
    property bool addressBusy: false
    property var mediaState: ({
        isPlaying: false,
        title: "",
        artist: "",
        album: "",
        player: "",
        playerList: [],
        albumArt: ""
    })
    property bool mediaLoading: false
    property bool mediaRefreshPending: false

    readonly property var reachableDevices: devices.filter(function(device) { return device.reachable })
    readonly property var selectedDevice: deviceById(selectedDeviceId)
    readonly property var incomingPairRequest: {
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].pairRequestedByPeer) return devices[i]
        }
        return null
    }
    readonly property bool connected: reachableDevices.length > 0

    function deviceById(id) {
        for (var i = 0; i < devices.length; i++)
            if (devices[i].id === String(id)) return devices[i]
        return null
    }

    function emptyMediaState() {
        return ({ isPlaying: false, title: "", artist: "", album: "", player: "", playerList: [], albumArt: "" })
    }

    function selectDevice(id) {
        var next = deviceById(id)
        if (!next) return
        if (selectedDeviceId !== next.id) {
            actionState = "idle"
            actionMessage = ""
            actionError = ""
            fileBusy = false
            mediaState = emptyMediaState()
            mediaLoading = false
            mediaRefreshPending = false
            if (mediaStatusProcess.running) mediaStatusProcess.running = false
            if (mediaActionProcess.running) mediaActionProcess.running = false
            if (mediaPlayerProcess.running) mediaPlayerProcess.running = false
        }
        selectedDeviceId = next.id
        remoteCommands = []
        commandTargetId = ""
        commandsLoading = false
        if (commandsProcess.running) commandsProcess.running = false
        if (next.paired && next.reachable && next.capabilities && next.capabilities.media) {
            fetchMediaStatus(next.id)
        }
    }

    function clearActionState() {
        actionState = "idle"
        actionMessage = ""
        actionError = ""
        fileBusy = false
    }

    function safeError(exitCode, operation) {
        if (exitCode === 127 || exitCode === 69) return operation + " unavailable"
        if (exitCode === 2) return operation + " rejected"
        if (exitCode === 3) return operation + " timed out"
        return operation + " failed"
    }

    function setPendingPairing(id, state) {
        var copy = Object.assign({}, pendingPairing)
        if (state) {
            copy[String(id)] = state
        } else {
            delete copy[String(id)]
        }
        pendingPairing = copy
    }

    function canAct(id) {
        var device = deviceById(id)
        return !!(device && device.paired && device.reachable)
    }

    function scriptPath(relativePath) {
        var resolved = Qt.resolvedUrl(relativePath).toString().replace(/^file:\/\//, "")
        try {
            return decodeURIComponent(resolved)
        } catch (error) {
            return resolved
        }
    }

    function getScriptPath() {
        return scriptPath("scripts/discover_devices.sh")
    }

    function formatVerificationKey(key) {
        var value = String(key || "").trim()
        return value.length === 8 ? value.slice(0, 4) + " " + value.slice(4) : value
    }

    function addressError(address) {
        var value = String(address || "").trim()
        if (!value) return "Enter an IP address"
        if (/\s|\/|\[|\]|%/.test(value)) return "Enter a literal IPv4 or IPv6 address"
        var ipv4 = value.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
        if (ipv4) {
            for (var i = 1; i <= 4; i++) if (Number(ipv4[i]) > 255) return "Invalid IPv4 address"
            return ""
        }
        if (/^[0-9a-fA-F:]+$/.test(value) && value.indexOf(":::") === -1) {
            var halves = value.split("::")
            if (halves.length === 1) {
                var fullGroups = value.split(":")
                if (fullGroups.length === 8 && fullGroups.every(function(group) { return /^[0-9a-fA-F]{1,4}$/.test(group) })) return ""
            } else if (halves.length === 2) {
                var leftGroups = halves[0] ? halves[0].split(":") : []
                var rightGroups = halves[1] ? halves[1].split(":") : []
                var compressedGroups = leftGroups.concat(rightGroups)
                if (compressedGroups.length < 8 && compressedGroups.every(function(group) { return /^[0-9a-fA-F]{1,4}$/.test(group) })) return ""
            }
        }
        return "Enter a literal IPv4 or IPv6 address"
    }

    function isAddressSaved(address) {
        return customAddresses.indexOf(String(address || "").trim()) !== -1
    }

    function filteredTailscalePeers(query) {
        var needle = String(query || "").trim().toLowerCase()
        if (!needle) return tailscalePeers
        return tailscalePeers.filter(function(peer) {
            return [peer.name, peer.hostName, peer.dnsName, peer.address, peer.os].some(function(field) {
                return String(field || "").toLowerCase().indexOf(needle) !== -1
            })
        })
    }

    function extractIPv4(addresses) {
        var list = addresses || []
        for (var i = 0; i < list.length; i++) {
            if (/^\d+\.\d+\.\d+\.\d+$/.test(String(list[i]))) return String(list[i])
        }
        return ""
    }

    function parseTailscaleStatus(output) {
        var data = JSON.parse(String(output || "{}"))
        var backend = String(data.BackendState || "")
        var running = backend === "Running"
        var localAddresses = (data.Self && data.Self.TailscaleIPs) || data.TailscaleIPs || []
        var local = extractIPv4(localAddresses)
        var peers = []
        var rawPeers = data.Peer || {}
        Object.keys(rawPeers).forEach(function(key) {
            var raw = rawPeers[key] || {}
            var address = extractIPv4(raw.TailscaleIPs || [])
            if (!address) return
            var dns = String(raw.DNSName || "").replace(/\.$/, "")
            var host = String(raw.HostName || "")
            peers.push({
                id: String(raw.ID || key),
                name: host || (dns ? dns.split(".")[0] : address),
                hostName: host,
                dnsName: dns,
                os: String(raw.OS || ""),
                address: address,
                online: raw.Online === true
            })
        })
        peers.sort(function(a, b) {
            if (a.online !== b.online) return a.online ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        return { running: running, backend: backend, localAddress: local, peers: peers }
    }

    function refreshTailscale() {
        if (tailscaleProcess.running) return
        tailscaleLoading = true
        tailscaleProcess.command = ["sh", "-c", "command -v tailscale >/dev/null 2>&1 || exit 127; exec tailscale status --json"]
        tailscaleProcess.running = true
    }

    function addCustomAddress(address) {
        var value = String(address || "").trim()
        if (!customAddressesReady) {
            actionState = "blocked"
            actionMessage = ""
            actionError = "KDE Connect address list is not ready"
            return false
        }
        var error = addressError(value)
        if (error) {
            actionState = "blocked"
            actionMessage = ""
            actionError = error
            return false
        }
        if (isAddressSaved(value)) {
            actionState = "accepted"
            actionMessage = "Address already saved; discovering devices"
            actionError = ""
            refresh(true)
            return true
        }
        return writeCustomAddress(value, false)
    }

    function removeCustomAddress(address) {
        var value = String(address || "").trim()
        if (!customAddressesReady || !isAddressSaved(value)) return false
        return writeCustomAddress(value, true)
    }

    function getAddressScriptPath() {
        return scriptPath("scripts/update_custom_address.sh")
    }

    function writeCustomAddress(address, removal) {
        if (!customAddressesReady || addressProcess.running) return false
        addressBusy = true
        addressProcess.targetAddress = address
        addressProcess.removal = removal
        addressProcess.command = ["bash", getAddressScriptPath(), removal ? "remove" : "add", address]
        actionState = "running"
        actionMessage = removal ? "Removing saved address" : "Saving address"
        actionError = ""
        addressProcess.running = true
        return true
    }

    function getPickerScriptPath() {
        return scriptPath("scripts/pick_file.sh")
    }

    function getSmsScriptPath() {
        return scriptPath("scripts/open_sms.sh")
    }

    function getAppScriptPath() {
        return scriptPath("scripts/open_app.sh")
    }

    function openKdeConnectApp() {
        if (appProcess.running) return false
        actionState = "running"
        actionMessage = "Opening KDE Connect"
        actionError = ""
        appProcess.command = ["bash", getAppScriptPath()]
        appProcess.running = true
        return true
    }

    function getFirewallScriptPath() {
        return scriptPath("scripts/setup_firewall.sh")
    }

    function configureFirewall() {
        if (firewallProcess.running) return
        var script = getFirewallScriptPath()
        firewallProcess.command = ["bash", "-c", "if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then omarchy-launch-floating-terminal-with-presentation \"bash '" + script + "'\"; else xdg-terminal-exec bash '" + script + "'; fi"]
        firewallProcess.running = true
    }

    function getInstallScriptPath() {
        return scriptPath("scripts/install_dependencies.sh")
    }

    function installDependencies() {
        if (installProcess.running) return
        var script = getInstallScriptPath()
        installProcess.command = ["bash", "-c", "if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then omarchy-launch-floating-terminal-with-presentation \"bash '" + script + "'\"; else xdg-terminal-exec bash '" + script + "'; fi"]
        installProcess.running = true
    }

    function refresh(forceNetwork) {
        if (forceNetwork) refreshTailscale()
        if (scanProcess.running) {
            if (!forceNetwork) return
            scanProcess.running = false
        }
        if (forceNetwork) {
            var now = Date.now()
            var copy = Object.assign({}, pendingPairing)
            var changed = false
            for (var devId in copy) {
                if (copy[devId] === "requesting") {
                    var reqTime = pairingRequestTimes[devId] || 0
                    if (!reqTime || (now - reqTime >= 10000)) {
                        delete copy[devId]
                        changed = true
                    }
                }
            }
            if (changed) pendingPairing = copy
        }
        var nextGeneration = generation + 1
        generation = nextGeneration
        scanning = true
        if (discoveryState !== "ready") {
            discoveryState = "checking"
            discoveryMessage = "Checking KDE Connect"
        }
        scanProcess.targetGeneration = nextGeneration
        var cmd = ["bash", getScriptPath()]
        if (forceNetwork) cmd.push("--refresh")
        scanProcess.command = cmd
        scanProcess.running = true
    }

    function deviceOverviewStatus(device) {
        if (!device) return "No devices found"
        if (!device.paired) return "Not paired"
        if (!device.reachable) return "Paired, offline"
        return "Paired & reachable"
    }

    function deviceTypeIcon(type) {
        var t = String(type || "").toLowerCase().trim()
        if (t === "phone") return "󰄜"
        if (t === "tablet") return "󰓹"
        if (t === "laptop") return "󰌢"
        if (t === "desktop") return "󰍹"
        if (t === "tv") return "󰵔"
        return "󰄜"
    }

    function deviceBatteryText(device, showBattery, showNetwork) {
        if (!device || !device.reachable) return ""
        var batteryAllowed = showBattery !== false
        var networkAllowed = showNetwork !== false
        var batteryText = ""
        if (batteryAllowed && device.capabilities && device.capabilities.battery && device.battery >= 0) {
            var charging = !!(device.isCharging || device.charging)
            if (charging) batteryText = device.battery + "% • Charging"
            else if (device.battery <= 20) batteryText = device.battery + "% • Low battery"
            else batteryText = device.battery + "% • Discharging"
        }
        var netText = ""
        if (networkAllowed && device.networkType) {
            var type = String(device.networkType).trim()
            if (type && type !== "null") {
                var str = device.networkStrength
                if (typeof str === "number" && str >= 0) netText = type + " (" + str + "/4)"
                else netText = type
            }
        }
        if (batteryText && netText) return batteryText + " • " + netText
        if (batteryText) return batteryText
        if (netText) return netText
        return ""
    }

    function deviceBatteryIcon(device) {
        if (!device || !device.capabilities || !device.capabilities.battery || device.battery < 0) return "󰂑"
        var charging = !!(device.isCharging || device.charging)
        if (charging) return "󰂄"
        if (device.battery <= 20) return "󰂃"
        if (device.battery <= 50) return "󰁽"
        return "󰁹"
    }

    function deviceNetworkText(device) {
        if (!device || !device.networkType) return ""
        var type = String(device.networkType).trim()
        if (!type || type === "null") return ""
        var str = device.networkStrength
        if (typeof str === "number" && str >= 0) return type + " (" + str + "/4)"
        return type
    }

    function deviceNetworkIcon(device) {
        if (!device || !device.networkType) return "󰀂"
        var str = device.networkStrength
        if (str === 4) return "󰤨"
        if (str === 3) return "󰤥"
        if (str === 2) return "󰤢"
        if (str === 1) return "󰤟"
        if (str === 0) return "󰤯"
        return "󰀂"
    }

    function parseScanLine(line) {
        var cleanLine = String(line || "").trim()
        var parts = cleanLine.split("\t")
        if (parts.length < 9 || parts[0] !== "DEVICE") return null
        var plugins = String(parts[8] || "").split(",")
        function hasPlugin(name) { return plugins.indexOf(name) !== -1 }
        var netType = parts.length > 9 ? String(parts[9] || "").trim() : ""
        var netStrengthRaw = parts.length > 10 ? String(parts[10] || "").trim() : ""
        var netStrength = /^\d+$/.test(netStrengthRaw) ? Number(netStrengthRaw) : -1
        return {
            id: parts[1],
            name: parts[2] || parts[1],
            type: parts[3] || "unknown",
            paired: parts[4] === "true",
            reachable: parts[5] === "true",
            battery: /^\d+$/.test(parts[6]) ? Number(parts[6]) : -1,
            isCharging: parts[7] === "true",
            charging: parts[7] === "true",
            networkType: netType,
            networkStrength: netStrength,
            pairRequested: parts.length > 11 && parts[11] === "true",
            pairRequestedByPeer: parts.length > 12 && parts[12] === "true",
            verificationKey: parts.length > 13 ? String(parts[13] || "").trim() : "",
            capabilities: {
                battery: hasPlugin("kdeconnect_battery"),
                ping: hasPlugin("kdeconnect_ping"),
                ring: hasPlugin("kdeconnect_findmyphone"),
                text: hasPlugin("kdeconnect_share"),
                clipboard: hasPlugin("kdeconnect_clipboard"),
                file: hasPlugin("kdeconnect_share"),
                commands: hasPlugin("kdeconnect_runcommand"),
                network: hasPlugin("kdeconnect_connectivity_report"),
                sms: hasPlugin("kdeconnect_sms"),
                media: hasPlugin("kdeconnect_mprisremote") || hasPlugin("kdeconnect_mpriscontrol") || hasPlugin("kdeconnect_mpris"),
                pair: true
            }
        }
    }

    function openSmsApp(id) {
        var device = deviceById(id)
        if (!device || !canAct(id)) return false
        return startAction(id, ["bash", getSmsScriptPath(), String(id)], "SMS app opened", "SMS app")
    }

    function applyScan(output, targetGeneration) {
        scanning = false
        if (targetGeneration !== generation) return
        var next = []
        var nextAddresses = []
        var addressesReady = false
        String(output || "").split("\n").forEach(function(line) {
            var clean = String(line || "").trim()
            if (clean === "CUSTOM_ADDRESSES_READY") {
                addressesReady = true
                return
            }
            if (clean.indexOf("CUSTOM_ADDRESS\t") === 0) {
                var address = clean.slice(15).trim()
                if (address && nextAddresses.indexOf(address) === -1) nextAddresses.push(address)
                return
            }
            var device = root.parseScanLine(line)
            if (device) next.push(device)
        })
        devices = next
        customAddressesReady = addressesReady
        if (addressesReady) customAddresses = nextAddresses
        next.forEach(function(dev) {
            if (dev.paired) {
                if (root.pendingPairing[dev.id] === "requesting") {
                    root.setPendingPairing(dev.id, "")
                    pairingWatchdogTimer.stop()
                    if (root.selectedDeviceId === dev.id || !root.selectedDeviceId) {
                        root.actionState = "accepted"
                        root.actionMessage = "Device paired"
                        root.actionError = ""
                    }
                } else if (root.pendingPairing[dev.id]) {
                    root.setPendingPairing(dev.id, "")
                }
            } else {
                if (root.pendingPairing[dev.id] === "removing" || root.pendingPairing[dev.id] === "unpair_confirm") {
                    root.setPendingPairing(dev.id, "")
                }
            }
        })
        if (!deviceById(selectedDeviceId)) {
            if (next.length) selectDevice(next[0].id)
            else clearActionState()
        }
        daemonAvailable = scanProcess.exitCode === 0
        sessionBusAvailable = scanProcess.exitCode !== 127
        if (scanProcess.exitCode === 127) {
            discoveryState = "not_installed"
            discoveryMessage = "KDE Connect not installed"
        } else if (scanProcess.exitCode === 0) {
            discoveryState = "ready"
            discoveryMessage = next.length ? "Device state is current" : "No KDE Connect devices"
        } else {
            discoveryState = "unavailable"
            discoveryMessage = "KDE Connect unavailable"
        }
    }

    function startAction(id, command, acceptedMessage, operation) {
        if (actionProcess.running || pairProcess.running || !canAct(id)) {
            actionState = "blocked"
            actionError = "Device must be paired and reachable"
            actionMessage = ""
            fileBusy = false
            return false
        }
        actionGeneration += 1
        actionProcess.targetGeneration = actionGeneration
        actionProcess.targetDeviceId = String(id)
        actionProcess.command = command
        actionProcess.acceptedMessage = acceptedMessage
        actionProcess.operation = operation
        actionState = "running"
        actionMessage = "Requesting " + operation
        actionError = ""
        fileBusy = operation === "file transfer"
        actionProcess.running = true
        return true
    }

    function pingDevice(id, message) {
        var text = String(message || "").trim()
        if (!text) {
            actionState = "blocked"
            actionError = "Message cannot be empty"
            actionMessage = ""
            return false
        }
        var device = deviceById(id)
        if (!device || !device.capabilities.ping || !canAct(id)) return false
        return startAction(id, ["kdeconnect-cli", "-d", String(id), "--ping-msg", text], "Ping sent", "ping")
    }

    function shareText(id, text) {
        var value = String(text || "").trim()
        if (!value) {
            actionState = "blocked"
            actionError = "Message cannot be empty"
            actionMessage = ""
            return false
        }
        var device = deviceById(id)
        if (!device || !device.capabilities.text || !canAct(id)) return false
        return startAction(id, ["kdeconnect-cli", "-d", String(id), "--share-text", value], "Text sent", "text share")
    }

    function ringDevice(id) {
        var device = deviceById(id)
        if (!device || !device.capabilities.ring) return false
        return startAction(id, ["kdeconnect-cli", "-d", String(id), "--ring"], "Ringing device...", "ring")
    }

    function sendClipboard(id) {
        var device = deviceById(id)
        if (!device || !device.capabilities.clipboard) return false
        return startAction(id, ["kdeconnect-cli", "-d", String(id), "--send-clipboard"], "Clipboard synced", "clipboard")
    }

    function startFileSelection(id) {
        var device = deviceById(id)
        if (!device || !device.capabilities.file || !canAct(id)) return false
        if (filePickerProcess.running) return false
        fileBusy = true
        actionState = "busy"
        actionMessage = "Selecting file"
        actionError = ""
        filePickerProcess.targetDeviceId = String(id)
        filePickerProcess.running = true
        return true
    }

    function cancelFileSelection() {
        if (filePickerProcess.running) filePickerProcess.running = false
        fileBusy = false
        actionState = "cancelled"
        actionMessage = "File selection cancelled"
        actionError = ""
    }

    function sendFile(id, path) {
        var value = String(path || "").trim()
        if (value.indexOf("file://") === 0) {
            value = value.replace(/^file:\/\//, "")
            try {
                value = decodeURIComponent(value)
            } catch (e) {}
        }
        var device = deviceById(id)
        if (!value || value.indexOf("\u0000") !== -1 || !device || !device.capabilities.file) {
            fileBusy = false
            return false
        }
        return startAction(id, ["kdeconnect-cli", "-d", String(id), "--share", value], "File sent", "file transfer")
    }

    function fetchRemoteCommands(id) {
        var device = deviceById(id)
        if (commandsProcess.running || pairProcess.running || !canAct(id) || !device.capabilities.commands) return false
        commandsLoading = true
        commandTargetId = String(id)
        commandsProcess.targetGeneration = generation
        commandsProcess.targetDeviceId = String(id)
        commandsProcess.command = ["kdeconnect-cli", "-d", String(id), "--list-commands"]
        commandsProcess.running = true
        return true
    }

    function parseRemoteCommands(text) {
        var source = String(text || "").trim()
        if (!source) return []
        var result = []
        try {
            var json = JSON.parse(source)
            if (json === null || typeof json !== "object") return []
            var values = Array.isArray(json) ? json : Object.keys(json).map(function(key) {
                return { key: key, name: json[key] }
            })
            values.forEach(function(item) {
                if (typeof item === "string" && item.trim()) {
                    result.push({ key: item.trim(), name: item.trim() })
                } else if (item && typeof item === "object") {
                    var k = item.key || item.id || item.command
                    if (k !== undefined && k !== null) {
                        var kStr = String(k).trim()
                        if (kStr) {
                            var n = item.name || item.label || item.title || kStr
                            result.push({ key: kStr, name: String(n).trim() || kStr })
                        }
                    }
                }
            })
            return result
        } catch (error) {
            source.split("\n").forEach(function(line) {
                var value = String(line || "").trim()
                value = value.replace(/^[-*•]\s*|^\d+\.\s*/, "").trim()
                if (!value || /no.*commands/i.test(value)) return
                var split = value.indexOf(":")
                if (split > 0) {
                    var k = value.slice(0, split).trim()
                    var n = value.slice(split + 1).trim()
                    if (k) result.push({ key: k, name: n || k })
                } else if (value) {
                    result.push({ key: value, name: value })
                }
            })
            return result
        }
    }

    function executeRemoteCommand(id, key) {
        var value = String(key || "").trim()
        var device = deviceById(id)
        if (!value || !device || !device.capabilities.commands) return false
        return startAction(id, ["kdeconnect-cli", "-d", String(id), "--execute-command", value], "Command executed", "remote command")
    }

    function pairDevice(id) {
        var device = deviceById(id)
        if (!device || pairProcess.running || actionProcess.running || !device.capabilities.pair) return false
        setPendingPairing(id, "requesting")
        var times = Object.assign({}, pairingRequestTimes)
        times[String(id)] = Date.now()
        pairingRequestTimes = times
        actionState = "accepted"
        actionMessage = "Pair request sent"
        actionError = ""
        pairingWatchdogTimer.restart()
        pairProcess.targetDeviceId = String(id)
        pairProcess.targetGeneration = generation
        pairProcess.command = ["kdeconnect-cli", "-d", String(id), "--pair"]
        pairProcess.running = true
        return true
    }

    function respondToPairingRequest(id, accept) {
        var device = deviceById(id)
        if (!device || !device.pairRequestedByPeer || pairResponseProcess.running || pairProcess.running) return false
        selectDevice(id)
        setPendingPairing(id, accept ? "accepting" : "rejecting")
        pairResponseProcess.targetDeviceId = String(id)
        pairResponseProcess.accepting = accept
        pairResponseProcess.command = ["gdbus", "call", "--session", "--dest", "org.kde.kdeconnect", "--object-path", "/modules/kdeconnect/devices/" + String(id), "--method", accept ? "org.kde.kdeconnect.device.acceptPairing" : "org.kde.kdeconnect.device.cancelPairing"]
        actionState = "running"
        actionMessage = accept ? "Accepting pairing request" : "Rejecting pairing request"
        actionError = ""
        pairResponseProcess.running = true
        return true
    }

    function acceptPairing(id) {
        return respondToPairingRequest(id, true)
    }

    function rejectPairing(id) {
        return respondToPairingRequest(id, false)
    }

    function unpairDevice(id) {
        var device = deviceById(id)
        if (!device || pairProcess.running || actionProcess.running || !device.capabilities.pair) return false
        setPendingPairing(id, "removing")
        actionState = "accepted"
        actionMessage = "Device unpaired"
        actionError = ""
        pairProcess.targetDeviceId = String(id)
        pairProcess.targetGeneration = generation
        pairProcess.command = ["kdeconnect-cli", "-d", String(id), "--unpair"]
        pairProcess.running = true
        return true
    }

    function getMediaScriptPath() {
        return scriptPath("scripts/media_control.sh")
    }

    function fetchMediaStatus(id) {
        var devId = id || selectedDeviceId
        var device = deviceById(devId)
        if (!device || !canAct(devId) || !device.capabilities || !device.capabilities.media) return false
        if (mediaStatusProcess.running) {
            mediaRefreshPending = true
            return false
        }
        mediaLoading = true
        mediaRefreshPending = false
        mediaStatusProcess.targetDeviceId = String(devId)
        mediaStatusProcess.command = ["bash", getMediaScriptPath(), "status", String(devId)]
        mediaStatusProcess.running = true
        return true
    }

    function sendMediaAction(id, actionName) {
        var devId = id || selectedDeviceId
        var device = deviceById(devId)
        if (!device || !canAct(devId) || !device.capabilities || !device.capabilities.media) return false
        if (mediaActionProcess.running) return false
        mediaActionProcess.targetDeviceId = String(devId)
        mediaActionProcess.command = ["bash", getMediaScriptPath(), "action", String(devId), String(actionName)]
        mediaActionProcess.running = true
        return true
    }

    function mediaPlayPause(id) {
        return sendMediaAction(id, "PlayPause")
    }

    function mediaNext(id) {
        return sendMediaAction(id, "Next")
    }

    function mediaPrevious(id) {
        return sendMediaAction(id, "Previous")
    }

    function mediaSelectPlayer(id, playerName) {
        var devId = id || selectedDeviceId
        var device = deviceById(devId)
        if (!device || !canAct(devId) || !device.capabilities || !device.capabilities.media) return false
        if (mediaPlayerProcess.running) return false
        mediaPlayerProcess.targetDeviceId = String(devId)
        mediaPlayerProcess.command = ["bash", getMediaScriptPath(), "player", String(devId), String(playerName)]
        mediaPlayerProcess.running = true
        return true
    }

    function handleMediaProcessExit(code, targetDeviceId) {
        if (code === 0 && targetDeviceId === root.selectedDeviceId) {
            root.fetchMediaStatus(targetDeviceId)
        }
    }

    Process {
        id: scanProcess
        property int targetGeneration: 0
        property int exitCode: -1
        command: ["bash", getScriptPath()]
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            exitCode = code
            root.applyScan(stdout.text, targetGeneration)
        }
    }

    Process {
        id: commandsProcess
        property string targetDeviceId: ""
        property int targetGeneration: 0
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            root.commandsLoading = false
            if (targetGeneration !== root.generation || targetDeviceId !== root.selectedDeviceId) return
            root.remoteCommands = code === 0 ? root.parseRemoteCommands(stdout.text) : []
        }
    }

    Process {
        id: actionProcess
        property string targetDeviceId: ""
        property int targetGeneration: 0
        property string acceptedMessage: "Action completed"
        property string operation: "action"
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            if (targetGeneration !== root.actionGeneration || targetDeviceId !== root.selectedDeviceId) return
            root.fileBusy = false
            root.actionState = code === 0 ? "accepted" : "failed"
            root.actionMessage = code === 0 ? acceptedMessage : ""
            root.actionError = code === 0 ? "" : root.safeError(code, operation)
        }
    }

    Process {
        id: pairProcess
        property string targetDeviceId: ""
        property int targetGeneration: 0
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            var isPair = pairProcess.command && pairProcess.command.indexOf("--pair") !== -1
            var op = isPair ? "pairing" : "unpairing"
            if (code === 0) {
                root.setPendingPairing(targetDeviceId, isPair ? "requesting" : "accepted")
            } else {
                if (isPair) pairingWatchdogTimer.stop()
                root.setPendingPairing(targetDeviceId, isPair ? "" : "failed")
            }
            if (targetGeneration !== root.generation || targetDeviceId !== root.selectedDeviceId) {
                root.refresh()
                return
            }
            if (code === 0) {
                root.actionState = "accepted"
                root.actionMessage = isPair ? "Pair request sent" : "Device unpaired"
                root.actionError = ""
            } else {
                root.actionState = "failed"
                root.actionMessage = ""
                root.actionError = root.safeError(code, op)
            }
            root.refresh()
        }
    }

    Process {
        id: pairResponseProcess
        property string targetDeviceId: ""
        property bool accepting: false
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            root.setPendingPairing(targetDeviceId, "")
            root.actionState = code === 0 ? "accepted" : "failed"
            root.actionMessage = code === 0 ? (accepting ? "Pairing response sent" : "Pairing request rejected") : ""
            root.actionError = code === 0 ? "" : root.safeError(code, accepting ? "pairing" : "pairing rejection")
            root.refresh()
        }
    }

    Timer { id: dbusDebounceTimer; interval: 300; repeat: false; onTriggered: root.refresh() }
    Timer { id: mediaDebounceTimer; interval: 300; repeat: false; onTriggered: if (root.selectedDeviceId) root.fetchMediaStatus(root.selectedDeviceId) }

    Timer {
        id: pairingWatchdogTimer
        interval: 30000
        repeat: false
        onTriggered: {
            var hadPending = false
            for (var devId in root.pendingPairing) {
                if (root.pendingPairing[devId] === "requesting") {
                    root.setPendingPairing(devId, "")
                    hadPending = true
                }
            }
            if (hadPending || root.actionMessage === "Pair request sent") {
                root.actionState = "failed"
                root.actionMessage = ""
                root.actionError = "Pairing timed out or rejected"
            }
        }
    }

    Process {
        id: signalProcess
        command: ["dbus-monitor", "--session", "type='signal',sender='org.kde.kdeconnect'"]
        stdout: SplitParser { onRead: function(line) {
            var value = String(line || "")
            if (value.indexOf("device") !== -1 || value.indexOf("chargeChanged") !== -1 || value.indexOf("stateChanged") !== -1 || value.indexOf("refreshed") !== -1)
                dbusDebounceTimer.restart()
            if (value.indexOf("mpris") !== -1 || value.indexOf("PropertiesChanged") !== -1)
                mediaDebounceTimer.restart()
        } }
        onExited: {
            signalRestart.interval = Math.min(30000, 1000 * Math.pow(2, monitorRestartCount))
            monitorRestartCount += 1
            signalRestart.start()
        }
    }

    Process {
        id: filePickerProcess
        property string targetDeviceId: ""
        command: ["bash", getPickerScriptPath()]
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            var selectedPath = stdout.text.trim()
            if (code === 0 && selectedPath) {
                root.sendFile(targetDeviceId, selectedPath)
            } else {
                root.cancelFileSelection()
            }
        }
    }

    Process {
        id: tailscaleProcess
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            root.tailscaleLoading = false
            if (code === 127) {
                root.tailscaleInstalled = false
                root.tailscaleRunning = false
                root.tailscaleStatus = "Not installed (optional)"
                root.localTailscaleAddress = ""
                root.tailscalePeers = []
                return
            }
            root.tailscaleInstalled = true
            if (code !== 0) {
                root.tailscaleRunning = false
                root.tailscaleStatus = "Not connected"
                root.localTailscaleAddress = ""
                root.tailscalePeers = []
                return
            }
            try {
                var status = root.parseTailscaleStatus(stdout.text)
                root.tailscaleRunning = status.running
                root.tailscaleStatus = status.running ? "Connected" : (status.backend || "Not connected")
                root.localTailscaleAddress = status.localAddress
                root.tailscalePeers = status.peers
            } catch (error) {
                root.tailscaleRunning = false
                root.tailscaleStatus = "Invalid status response"
                root.localTailscaleAddress = ""
                root.tailscalePeers = []
            }
        }
    }

    Process {
        id: addressProcess
        property string targetAddress: ""
        property bool removal: false
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            root.addressBusy = false
            if (code === 0) {
                root.actionState = "accepted"
                root.actionMessage = removal ? "Saved address removed" : "Address saved; discovering devices"
                root.actionError = ""
                root.refresh(true)
            } else {
                root.actionState = "failed"
                root.actionMessage = ""
                root.actionError = root.safeError(code, removal ? "address removal" : "address save")
            }
        }
    }

    Process {
        id: firewallProcess
        onExited: function(code) {
            root.refresh(true)
        }
    }

    Process {
        id: installProcess
        onExited: function(code) {
            root.refresh(true)
        }
    }

    Process {
        id: appProcess
        onExited: function(code) {
            if (code === 0) {
                root.actionState = "accepted"
                root.actionMessage = "KDE Connect opened"
                root.actionError = ""
            } else {
                root.actionState = "failed"
                root.actionMessage = ""
                root.actionError = root.safeError(code, "KDE Connect app")
            }
        }
    }

    Process {
        id: mediaStatusProcess
        property string targetDeviceId: ""
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            var currentDevice = root.deviceById(targetDeviceId)
            var isCurrent = targetDeviceId === root.selectedDeviceId
                && currentDevice
                && root.canAct(targetDeviceId)
                && currentDevice.capabilities
                && currentDevice.capabilities.media

            if (isCurrent && code === 0 && stdout.text.trim()) {
                try {
                    var parsed = JSON.parse(stdout.text.trim())
                    root.mediaState = {
                        isPlaying: parsed.isPlaying === true,
                        title: String(parsed.title || ""),
                        artist: String(parsed.artist || ""),
                        album: String(parsed.album || ""),
                        player: String(parsed.player || ""),
                        playerList: Array.isArray(parsed.playerList) ? parsed.playerList : [],
                        albumArt: String(parsed.albumArt || "")
                    }
                } catch (e) {
                    root.mediaState = root.emptyMediaState()
                }
            } else if (isCurrent) {
                root.mediaState = root.emptyMediaState()
            }

            root.mediaLoading = false
            if (root.mediaRefreshPending && root.selectedDeviceId) {
                root.mediaRefreshPending = false
                Qt.callLater(function() { root.fetchMediaStatus(root.selectedDeviceId) })
            }
        }
    }

    Process {
        id: mediaActionProcess
        property string targetDeviceId: ""
        onExited: function(code) {
            root.handleMediaProcessExit(code, targetDeviceId)
        }
    }

    Process {
        id: mediaPlayerProcess
        property string targetDeviceId: ""
        onExited: function(code) {
            root.handleMediaProcessExit(code, targetDeviceId)
        }
    }

    Timer { id: signalRestart; repeat: false; onTriggered: if (!signalProcess.running) signalProcess.running = true }
    Timer { interval: 15000; running: !signalProcess.running; repeat: true; onTriggered: root.refresh() }
    Component.onCompleted: { root.refresh(); root.refreshTailscale(); signalProcess.running = true }
    Component.onDestruction: { actionDismissTimer.stop(); dbusDebounceTimer.stop(); mediaDebounceTimer.stop(); pairingWatchdogTimer.stop(); signalRestart.stop(); signalProcess.running = false; scanProcess.running = false; commandsProcess.running = false; actionProcess.running = false; pairProcess.running = false; pairResponseProcess.running = false; filePickerProcess.running = false; tailscaleProcess.running = false; addressProcess.running = false; firewallProcess.running = false; installProcess.running = false; appProcess.running = false; mediaStatusProcess.running = false; mediaActionProcess.running = false; mediaPlayerProcess.running = false }
}
