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

    readonly property var reachableDevices: devices.filter(function(device) { return device.reachable })
    readonly property var selectedDevice: deviceById(selectedDeviceId)
    readonly property bool connected: reachableDevices.length > 0

    function deviceById(id) {
        for (var i = 0; i < devices.length; i++)
            if (devices[i].id === String(id)) return devices[i]
        return null
    }

    function selectDevice(id) {
        var next = deviceById(id)
        if (!next) return
        if (selectedDeviceId !== next.id) {
            actionState = "idle"
            actionMessage = ""
            actionError = ""
            fileBusy = false
        }
        selectedDeviceId = next.id
        remoteCommands = []
        commandTargetId = ""
        commandsLoading = false
        if (commandsProcess.running) commandsProcess.running = false
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

    function getPickerScriptPath() {
        return scriptPath("scripts/pick_file.sh")
    }

    function getSmsScriptPath() {
        return scriptPath("scripts/open_sms.sh")
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
        if (batteryAllowed && device.capabilities && device.capabilities.battery) {
            if (device.battery < 0) {
                batteryText = "Battery unavailable"
            } else {
                var charging = !!(device.isCharging || device.charging)
                if (charging) batteryText = device.battery + "% • Charging"
                else if (device.battery <= 20) batteryText = device.battery + "% • Low battery"
                else batteryText = device.battery + "% • Discharging"
            }
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
        String(output || "").split("\n").forEach(function(line) {
            var device = root.parseScanLine(line)
            if (device) next.push(device)
        })
        devices = next
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

    Timer { id: dbusDebounceTimer; interval: 300; repeat: false; onTriggered: root.refresh() }

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

    Timer { id: signalRestart; repeat: false; onTriggered: if (!signalProcess.running) signalProcess.running = true }
    Timer { interval: 15000; running: !signalProcess.running; repeat: true; onTriggered: root.refresh() }
    Component.onCompleted: { root.refresh(); signalProcess.running = true }
    Component.onDestruction: { actionDismissTimer.stop(); dbusDebounceTimer.stop(); pairingWatchdogTimer.stop(); signalRestart.stop(); signalProcess.running = false; scanProcess.running = false; commandsProcess.running = false; actionProcess.running = false; pairProcess.running = false; filePickerProcess.running = false; firewallProcess.running = false; installProcess.running = false }
}
