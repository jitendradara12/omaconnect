pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./components"

KeyboardPanel {
    id: root

    property var hostWidget: null
    anchorItem: hostWidget && hostWidget.button ? hostWidget.button : null
    bar: hostWidget ? hostWidget.bar : null
    property var settings: hostWidget ? hostWidget.settings : null
    readonly property var barIdentity: hostWidget || root
    owner: barIdentity
    property bool opened: false
    open: opened
    property Item focusTarget: keyCatcher

    readonly property var service: hostWidget && hostWidget.service ? hostWidget.service : (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("omaconnect") : null)
    readonly property var device: service ? service.selectedDevice : null
    readonly property string deviceName: device && typeof device.name === "string" ? device.name : "KDE Connect"

    property string activeComposer: "none"
    property string draftPing: ""
    property string draftText: ""
    property string composerError: ""
    property string focusSection: "devices"
    property int selectedIndex: 0
    property int actionSelectedIndex: 0
    property bool cursorActive: false
    property bool commandsExpanded: false
    property int commandSelectedIndex: 0
    property string unpairConfirmingId: ""

    function open() {
        if (unpairConfirmingId) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        opened = true
    }
    function close() {
        if (unpairConfirmingId) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        opened = false
    }
    function toggle() { opened = !opened }
    function closeForPopoutSwitch() { opened = false }

    function getSetting(key, defaultValue) {
        if (!settings || typeof settings !== "object") return defaultValue
        if (key in settings && settings[key] !== undefined && settings[key] !== null) {
            return settings[key]
        }
        return defaultValue
    }

    readonly property var availableActions: {
        if (!root.device || !root.device.paired || !root.device.reachable) return []
        var caps = root.device.capabilities || {}
        var res = []
        if (caps.ring && root.getSetting("showActionRing", true)) res.push("ring")
        if (caps.clipboard && root.getSetting("showActionClipboard", true)) res.push("clipboard")
        if (caps.file && root.getSetting("showActionFile", true)) res.push("file")
        if (caps.sms && root.getSetting("showActionSms", true)) res.push("sms")
        if (caps.ping && root.getSetting("showActionPing", false)) res.push("ping")
        if (caps.text && root.getSetting("showActionText", true)) res.push("text")
        return res
    }

    onAvailableActionsChanged: {
        var acts = availableActions
        if (acts.length > 0) {
            actionSelectedIndex = Math.max(0, Math.min(acts.length - 1, actionSelectedIndex))
        } else {
            actionSelectedIndex = 0
            if (focusSection === "actions") focusSection = "devices"
        }
    }

    function triggerAction(actionId) {
        if (!service || !device) return
        if (actionId === "ring") service.ringDevice(device.id)
        else if (actionId === "clipboard") service.sendClipboard(device.id)
        else if (actionId === "file") service.startFileSelection(device.id)
        else if (actionId === "sms") service.openSmsApp(device.id)
        else if (actionId === "ping") {
            if (activeComposer === "ping") closeComposer()
            else openComposer("ping")
        }
        else if (actionId === "text") {
            if (activeComposer === "text") closeComposer()
            else openComposer("text")
        }
    }



    function requestUnpairConfirm(id) {
        unpairConfirmingId = id
        if (service && typeof service.setPendingPairing === "function") service.setPendingPairing(id, "unpair_confirm")
    }

    function cancelUnpairConfirm(id) {
        if (!id || unpairConfirmingId === id) unpairConfirmingId = ""
        if (service && id && typeof service.setPendingPairing === "function") service.setPendingPairing(id, "")
    }

    function selectDevice(id) {
        if (!service) return
        if (unpairConfirmingId && unpairConfirmingId !== id) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        service.selectDevice(id)
        var list = service.devices || []
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === String(id)) {
                selectedIndex = i
                break
            }
        }
        var acts = availableActions
        if (acts.length > 0) {
            actionSelectedIndex = Math.max(0, Math.min(acts.length - 1, actionSelectedIndex))
        } else {
            actionSelectedIndex = 0
            if (focusSection === "actions") focusSection = "devices"
        }
    }

    function confirmUnpair(id) {
        unpairConfirmingId = ""
        if (service) service.unpairDevice(id)
    }

    function openComposer(type) {
        composerError = ""
        activeComposer = type
        if (type === "ping") {
            if (!draftPing) {
                var defPing = root.getSetting("defaultPingMessage", "")
                if (defPing) draftPing = defPing
            }
            focusSection = "ping"
            Qt.callLater(function() { if (composerSection && composerSection.pingInput) composerSection.pingInput.forceActiveFocus() })
        } else if (type === "text") {
            focusSection = "text"
            Qt.callLater(function() { if (composerSection && composerSection.textInput) composerSection.textInput.forceActiveFocus() })
        }
    }

    function closeComposer() {
        activeComposer = "none"
        composerError = ""
        focusSection = "actions"
        if (keyCatcher) keyCatcher.forceActiveFocus()
    }

    function resetComposer() {
        activeComposer = "none"
        draftPing = ""
        draftText = ""
        composerError = ""
    }

    function submitPing() {
        var val = draftPing.trim()
        if (!val) {
            composerError = "Message cannot be empty"
            if (service) {
                service.actionState = "blocked"
                service.actionError = "Message cannot be empty"
                service.actionMessage = ""
            }
            return false
        }
        if (service && device) {
            var success = service.pingDevice(device.id, val)
            if (success) {
                draftPing = ""
                closeComposer()
            } else {
                composerError = (service && service.actionError) ? service.actionError : "Failed to send ping"
            }
            return success
        }
        composerError = "Service unavailable"
        return false
    }

    function submitText() {
        var val = draftText.trim()
        if (!val) {
            composerError = "Message cannot be empty"
            if (service) {
                service.actionState = "blocked"
                service.actionError = "Message cannot be empty"
                service.actionMessage = ""
            }
            return false
        }
        if (service && device) {
            var success = service.shareText(device.id, val)
            if (success) {
                draftText = ""
                closeComposer()
            } else {
                composerError = (service && service.actionError) ? service.actionError : "Failed to share text"
            }
            return success
        }
        composerError = "Service unavailable"
        return false
    }

    function select(delta) {
        var list = service ? service.devices : []
        if (!list.length) return
        selectedIndex = Math.max(0, Math.min(list.length - 1, selectedIndex + delta))
        if (cursorActive) selectDevice(list[selectedIndex].id)
    }

    function toggleCommandsExpanded() {
        commandsExpanded = !commandsExpanded
        if (commandsExpanded && service && device && device.capabilities && device.capabilities.commands) {
            service.fetchRemoteCommands(device.id)
        }
    }

    function selectCommand(delta) {
        var list = (service && service.remoteCommands) ? service.remoteCommands : []
        if (!list.length) return
        commandSelectedIndex = Math.max(0, Math.min(list.length - 1, commandSelectedIndex + delta))
    }

    function activate() {
        if (focusSection === "devices") {
            var list = service ? service.devices : []
            var dev = list[selectedIndex]
            if (dev && service) {
                selectDevice(dev.id)
                var pending = (service.pendingPairing && service.pendingPairing[dev.id]) ? service.pendingPairing[dev.id] : ""
                if (root.unpairConfirmingId === dev.id || pending === "unpair_confirm") {
                    root.confirmUnpair(dev.id)
                } else if (!dev.paired) {
                    if (pending === "requesting") {
                        service.setPendingPairing(dev.id, "")
                        if (typeof service.clearActionState === "function") service.clearActionState()
                    } else {
                        service.pairDevice(dev.id)
                    }
                } else {
                    if (pending !== "removing") root.requestUnpairConfirm(dev.id)
                }
            }
        } else if (focusSection === "refresh") { if (service) service.refresh(true) }
        else if (focusSection === "actions") {
            var acts = availableActions
            if (acts.length > 0) {
                var actIdx = Math.max(0, Math.min(acts.length - 1, actionSelectedIndex))
                triggerAction(acts[actIdx])
            }
        } else if (focusSection === "ring" && service && device) service.ringDevice(device.id)
        else if (focusSection === "clipboard" && service && device) service.sendClipboard(device.id)
        else if (focusSection === "file" && service && device) service.startFileSelection(device.id)
        else if (focusSection === "ping") {
            if (activeComposer === "ping") submitPing()
            else openComposer("ping")
        } else if (focusSection === "text") {
            if (activeComposer === "text") submitText()
            else openComposer("text")
        } else if (focusSection === "commands" && service && device) {
            if (!commandsExpanded) {
                toggleCommandsExpanded()
            } else if (service.remoteCommands.length > 0) {
                var idx = Math.max(0, Math.min(service.remoteCommands.length - 1, commandSelectedIndex))
                var cmd = service.remoteCommands[idx]
                if (cmd) service.executeRemoteCommand(device.id, cmd.key)
            } else {
                service.fetchRemoteCommands(device.id)
            }
        }
    }

    contentWidth: root.fittedContentWidth(Style.space(380))
    contentHeight: root.fittedContentHeight(scrollView.implicitHeight)

    PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent

        blocked: root.activeComposer !== "none" || !!(composerSection && ((composerSection.pingInput && composerSection.pingInput.activeFocus) || (composerSection.textInput && composerSection.textInput.activeFocus)))
        onMoveRequested: function(dx, dy) {
            if (!root.cursorActive) root.cursorActive = true
        }
        onActivateRequested: root.activate()
        onCloseRequested: {
            if (root.unpairConfirmingId) root.cancelUnpairConfirm(root.unpairConfirmingId)
            else if (root.activeComposer !== "none") root.closeComposer()
            else root.close()
        }
        onTabRequested: function(direction) { if (root.bar && typeof root.bar.switchPanelFrom === "function") root.bar.switchPanelFrom(root.barIdentity, direction) }
        onTextKey: function(value) {
            if (root.activeComposer !== "none") return
            var key = String(value).toLowerCase()
            if (key === "r" && root.service) root.service.refresh(true)
            else if (key === "j" || key === "down") {
                if (root.focusSection === "commands" && root.commandsExpanded) {
                    var cmdsD = (root.service && root.service.remoteCommands) ? root.service.remoteCommands : []
                    if (cmdsD.length > 0 && root.commandSelectedIndex < cmdsD.length - 1) root.selectCommand(1)
                    else root.focusSection = "devices"
                }
                else if (root.focusSection === "commands") root.focusSection = "devices"
                else if (root.focusSection === "actions") {
                    var actsD = root.availableActions
                    if (actsD.length > 0 && root.actionSelectedIndex < actsD.length - 1) root.actionSelectedIndex++
                    else if (root.device && root.device.capabilities && root.device.capabilities.commands) root.focusSection = "commands"
                    else root.focusSection = "devices"
                }
                else root.select(1)
            }
            else if (key === "k" || key === "up") {
                if (root.focusSection === "commands" && root.commandsExpanded) {
                    if (root.commandSelectedIndex > 0) root.selectCommand(-1)
                    else {
                        var actsU = root.availableActions
                        if (actsU.length > 0) {
                            root.focusSection = "actions"
                            root.actionSelectedIndex = actsU.length - 1
                        } else root.focusSection = "devices"
                    }
                }
                else if (root.focusSection === "commands") {
                    var actsUC = root.availableActions
                    if (actsUC.length > 0) {
                        root.focusSection = "actions"
                        root.actionSelectedIndex = actsUC.length - 1
                    } else root.focusSection = "devices"
                }
                else if (root.focusSection === "actions") {
                    if (root.actionSelectedIndex > 0) root.actionSelectedIndex--
                    else root.focusSection = "devices"
                }
                else root.select(-1)
            }
            else if (key === "l" || key === "right") {
                if (root.focusSection === "devices") {
                    var availableL0 = root.availableActions
                    if (availableL0.length > 0) {
                        root.focusSection = "actions"
                        root.actionSelectedIndex = 0
                    } else if (root.device && root.device.capabilities && root.device.capabilities.commands) {
                        root.focusSection = "commands"
                    }
                }
                else if (root.focusSection === "actions") {
                    var availableL = root.availableActions
                    if (root.actionSelectedIndex < availableL.length - 1) {
                        root.actionSelectedIndex++
                    } else if (root.device && root.device.capabilities && root.device.capabilities.commands) {
                        root.focusSection = "commands"
                    } else {
                        root.focusSection = "devices"
                    }
                }
                else if (root.focusSection === "commands") root.focusSection = "devices"
            }
            else if (key === "h" || key === "left") {
                if (root.focusSection === "commands") {
                    var availableCmdH = root.availableActions
                    if (availableCmdH.length > 0) {
                        root.focusSection = "actions"
                        root.actionSelectedIndex = availableCmdH.length - 1
                    } else {
                        root.focusSection = "devices"
                    }
                }
                else if (root.focusSection === "actions") {
                    if (root.actionSelectedIndex > 0) {
                        root.actionSelectedIndex--
                    } else {
                        root.focusSection = "devices"
                    }
                }
                else if (root.focusSection === "devices") {
                    if (root.device && root.device.capabilities && root.device.capabilities.commands) root.focusSection = "commands"
                    else {
                        var availableDevH = root.availableActions
                        if (availableDevH.length > 0) {
                            root.focusSection = "actions"
                            root.actionSelectedIndex = availableDevH.length - 1
                        }
                    }
                }
            }
            else if (key === "p" && root.focusSection === "devices") {
                var listP = root.service ? root.service.devices : []
                var devP = listP[root.selectedIndex]
                if (devP && !devP.paired && root.service) {
                    var pendP = (root.service.pendingPairing && root.service.pendingPairing[devP.id]) ? root.service.pendingPairing[devP.id] : ""
                    if (pendP !== "requesting") root.service.pairDevice(devP.id)
                }
            }
            else if (key === "u" && root.focusSection === "devices") {
                var listU = root.service ? root.service.devices : []
                var devU = listU[root.selectedIndex]
                if (devU && devU.paired && root.service) {
                    var pendU = (root.service.pendingPairing && root.service.pendingPairing[devU.id]) ? root.service.pendingPairing[devU.id] : ""
                    if (pendU !== "removing") root.requestUnpairConfirm(devU.id)
                }
            }
            else if (key === "y" && root.service && root.service.selectedDeviceId && (root.unpairConfirmingId === root.service.selectedDeviceId || (root.service.pendingPairing && root.service.pendingPairing[root.service.selectedDeviceId] === "unpair_confirm"))) {
                var targetIdY = root.service.selectedDeviceId
                if (targetIdY) root.confirmUnpair(targetIdY)
            }
            else if ((key === "c" || key === "escape")) {
                var targetIdC = root.unpairConfirmingId || (root.service ? root.service.selectedDeviceId : "")
                if (root.unpairConfirmingId || (root.service && targetIdC && root.service.pendingPairing && root.service.pendingPairing[targetIdC] === "unpair_confirm")) {
                    root.cancelUnpairConfirm(targetIdC)
                } else if (root.service && targetIdC && root.service.pendingPairing && root.service.pendingPairing[targetIdC] === "requesting") {
                    root.service.setPendingPairing(targetIdC, "")
                    if (typeof root.service.clearActionState === "function") root.service.clearActionState()
                }
            }
        }

        ScrollView {
            id: scrollView
            anchors.fill: parent
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            Column {
                id: contentColumn
                width: scrollView.width
                spacing: Style.space(12)

                DeviceSection {
                    id: deviceSection
                    panel: root
                }

                ActionToolbar {
                    id: actionToolbar
                    panel: root
                }

                ComposerSection {
                    id: composerSection
                    panel: root
                }

                RemoteCommandsSection {
                    id: remoteCommandsSection
                    panel: root
                }
            }
        }
    }
}
