pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./components"
import "bridge" as OmaconnectBridge

Panel {
    id: root
    moduleName: "omaconnect"
    ipcTarget: "omaconnect"
    manageIpc: false

    property var anchorItem: hostWidget && hostWidget.button ? hostWidget.button : null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root
    readonly property Item focusTarget: keyCatcher

    readonly property var service: hostWidget && hostWidget.service ? hostWidget.service : (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? (bar.shell.serviceFor("omaconnect") || OmaconnectBridge.Bridge.service) : OmaconnectBridge.Bridge.service)
    readonly property var device: service ? service.selectedDevice : null
    readonly property string deviceName: device && typeof device.name === "string" ? device.name : "KDE Connect"
    readonly property var incomingRequest: service ? service.incomingPairRequest : null
    readonly property bool remoteCommandsVisible: !!(device && device.paired && device.reachable && device.capabilities && device.capabilities.commands && (!getSetting || getSetting("showRemoteCommands", true)))
    readonly property bool mediaPlayerVisible: !!(device && device.paired && device.reachable && device.capabilities && device.capabilities.media && (!getSetting || getSetting("showMediaPlayer", true)))
    readonly property bool networkVisible: (!getSetting || getSetting("showTailscale", true))

    property string focusSection: "devices"
    property int selectedIndex: 0
    property int actionSelectedIndex: 0
    property bool cursorActive: false
    property bool mediaExpanded: true
    property int mediaControlIndex: 1
    property bool commandsExpanded: false
    property int commandSelectedIndex: 0
    property bool networkExpanded: false
    property int networkSelectedIndex: 0
    property string unpairConfirmingId: ""

    property string activeComposer: "none"
    property string draftPing: ""
    property string draftText: ""
    property string composerError: ""

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

    readonly property var visibleSections: {
        var list = ["devices"]
        if (availableActions.length > 0) list.push("actions")
        if (mediaPlayerVisible) list.push("media")
        if (remoteCommandsVisible) list.push("commands")
        if (networkVisible) list.push("network")
        return list
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

    onVisibleSectionsChanged: {
        if (visibleSections.indexOf(focusSection) === -1) {
            focusSection = visibleSections.length > 0 ? visibleSections[0] : "devices"
        }
    }

    onMediaPlayerVisibleChanged: {
        if (!mediaPlayerVisible && focusSection === "media") {
            focusSection = availableActions.length > 0 ? "actions" : "devices"
        }
    }

    onRemoteCommandsVisibleChanged: {
        if (!remoteCommandsVisible && focusSection === "commands") {
            focusSection = availableActions.length > 0 ? "actions" : "devices"
        }
    }

    onNetworkVisibleChanged: {
        if (!networkVisible && focusSection === "network") {
            focusSection = availableActions.length > 0 ? "actions" : "devices"
        }
    }

    onDraftPingChanged: {
        if (composerSection && composerSection.pingInput && composerSection.pingInput.text !== draftPing) {
            composerSection.pingInput.text = draftPing
        }
    }

    onDraftTextChanged: {
        if (composerSection && composerSection.textInput && composerSection.textInput.text !== draftText) {
            composerSection.textInput.text = draftText
        }
    }

    Connections {
        target: root.service
        function onDevicesChanged() {
            var list = root.service ? root.service.devices : []
            if (!list.length) {
                root.selectedIndex = 0
                return
            }
            root.selectedIndex = Math.max(0, Math.min(list.length - 1, root.selectedIndex))
        }
    }

    function open() {
        if (unpairConfirmingId) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        root.controller.show()
        if (service && device && device.paired && device.reachable && device.capabilities && device.capabilities.media) {
            service.fetchMediaStatus(device.id)
            if (typeof service.requestPlayerList === "function") service.requestPlayerList(device.id)
        }
    }

    function close() {
        if (unpairConfirmingId) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        root.controller.hide()
    }

    function toggle() {
        root.opened ? close() : open()
    }

    function closeForPopoutSwitch() {
        if (unpairConfirmingId) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        root.popoutSwitchClosing = true
        root.close()
        Qt.callLater(function() { root.popoutSwitchClosing = false })
    }

    function getSetting(key, defaultValue) {
        if (!settings || typeof settings !== "object") return defaultValue
        if (key in settings && settings[key] !== undefined && settings[key] !== null) {
            return settings[key]
        }
        return defaultValue
    }

    function getNetworkItemCount() {
        if (!networkExpanded) return 1
        var peers = (service && service.tailscaleRunning && networkSection) ? networkSection.filteredPeers.length : 0
        var saved = (service && service.customAddresses) ? service.customAddresses.length : 0
        return 1 + peers + saved
    }

    function navigateNextSection() {
        var idx = visibleSections.indexOf(focusSection)
        if (idx === -1) idx = 0
        var nextIdx = (idx + 1) % visibleSections.length
        root.focusSection = visibleSections[nextIdx]
        if (root.focusSection === "actions") actionSelectedIndex = 0
        else if (root.focusSection === "media") mediaControlIndex = mediaExpanded ? 0 : 1
        else if (root.focusSection === "commands") commandSelectedIndex = 0
        else if (root.focusSection === "network") networkSelectedIndex = 0
    }

    function navigatePrevSection() {
        var idx = visibleSections.indexOf(focusSection)
        if (idx === -1) idx = 0
        var prevIdx = (idx - 1 + visibleSections.length) % visibleSections.length
        root.focusSection = visibleSections[prevIdx]
        if (root.focusSection === "actions") actionSelectedIndex = Math.max(0, availableActions.length - 1)
        else if (root.focusSection === "media") mediaControlIndex = mediaExpanded ? 2 : 1
        else if (root.focusSection === "commands") {
            var cmds = (service && service.remoteCommands) ? service.remoteCommands : []
            commandSelectedIndex = commandsExpanded ? Math.max(0, cmds.length - 1) : 0
        } else if (root.focusSection === "network") {
            networkSelectedIndex = networkExpanded ? Math.max(0, getNetworkItemCount() - 1) : 0
        }
    }

    function triggerAction(actionId) {
        if (!service || !device) return
        if (actionId === "ring") service.ringDevice(device.id)
        else if (actionId === "clipboard") service.sendClipboard(device.id)
        else if (actionId === "file") {
            if (service.fileBusy) service.cancelFileTransfer()
            else service.startFileSelection(device.id)
        }
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
        if (unpairConfirmingId && unpairConfirmingId !== id) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = id
        if (service && typeof service.setPendingPairing === "function") service.setPendingPairing(id, "unpair_confirm")
    }

    function cancelUnpairConfirm(id) {
        if (!id || unpairConfirmingId === id) unpairConfirmingId = ""
        if (service && id && typeof service.setPendingPairing === "function") service.setPendingPairing(id, "")
    }

    function confirmUnpair(id) {
        if (unpairConfirmingId && unpairConfirmingId !== id) return
        unpairConfirmingId = ""
        if (service) service.unpairDevice(id)
    }

    function selectDevice(id) {
        if (!service) return
        if (unpairConfirmingId && unpairConfirmingId !== id) cancelUnpairConfirm(unpairConfirmingId)
        unpairConfirmingId = ""
        resetComposer()
        commandSelectedIndex = 0
        commandsExpanded = false
        mediaControlIndex = 1
        if (focusSection === "ping" || focusSection === "text") focusSection = availableActions.length > 0 ? "actions" : "devices"
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

    function select(delta) {
        var list = service ? service.devices : []
        if (!list.length) return
        selectedIndex = Math.max(0, Math.min(list.length - 1, selectedIndex + delta))
        if (cursorActive) selectDevice(list[selectedIndex].id)
    }

    function openComposer(type) {
        if (type !== "ping" && type !== "text") return
        if (!service || !device || !device.paired || !device.reachable) {
            composerError = "Device must be paired and reachable"
            if (service) {
                service.actionState = "blocked"
                service.actionError = "Device must be paired and reachable"
                service.actionMessage = ""
            }
            return
        }
        var caps = device.capabilities || {}
        if (type === "ping" && !caps.ping) {
            composerError = "Ping not supported by device"
            if (service) {
                service.actionState = "blocked"
                service.actionError = "Ping not supported by device"
                service.actionMessage = ""
            }
            return
        }
        if (type === "text" && !caps.text) {
            composerError = "Text share not supported by device"
            if (service) {
                service.actionState = "blocked"
                service.actionError = "Text share not supported by device"
                service.actionMessage = ""
            }
            return
        }
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
        focusSection = availableActions.length > 0 ? "actions" : "devices"
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

    function toggleMediaExpanded() {
        mediaExpanded = !mediaExpanded
        mediaControlIndex = 1
        if (mediaExpanded && service && device && device.capabilities && device.capabilities.media) {
            service.fetchMediaStatus(device.id)
            if (typeof service.requestPlayerList === "function") service.requestPlayerList(device.id)
        }
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

    function toggleNetworkExpanded() {
        networkExpanded = !networkExpanded
        networkSelectedIndex = 0
        if (networkExpanded && service) {
            service.refreshTailscale()
        }
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
        } else if (focusSection === "refresh") {
            if (service) service.refresh(true)
        } else if (focusSection === "actions") {
            var acts = availableActions
            if (acts.length > 0) {
                var actIdx = Math.max(0, Math.min(acts.length - 1, actionSelectedIndex))
                triggerAction(acts[actIdx])
            }
        } else if (focusSection === "ring" && service && device) {
            service.ringDevice(device.id)
        } else if (focusSection === "clipboard" && service && device) {
            service.sendClipboard(device.id)
        } else if (focusSection === "file" && service && device) {
            service.startFileSelection(device.id)
        } else if (focusSection === "ping") {
            if (activeComposer === "ping") submitPing()
            else openComposer("ping")
        } else if (focusSection === "text") {
            if (activeComposer === "text") submitText()
            else openComposer("text")
        } else if (focusSection === "media" && service && device) {
            if (!device.paired || !device.reachable || !device.capabilities || !device.capabilities.media) return
            if (!mediaExpanded) toggleMediaExpanded()
            else if (!mediaPlayerSection.hasMedia) return
            else if (mediaControlIndex === 0) service.mediaPrevious(device.id)
            else if (mediaControlIndex === 2) service.mediaNext(device.id)
            else service.mediaPlayPause(device.id)
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
        } else if (focusSection === "network" && service) {
            if (!networkExpanded || networkSelectedIndex === 0) {
                toggleNetworkExpanded()
            } else {
                var peers = (service.tailscaleRunning && networkSection) ? networkSection.filteredPeers : []
                if (networkSelectedIndex <= peers.length) {
                    var peer = peers[networkSelectedIndex - 1]
                    if (peer && service) service.addCustomAddress(peer.address)
                } else {
                    var savedIdx = networkSelectedIndex - 1 - peers.length
                    var saved = service.customAddresses ? service.customAddresses : []
                    if (savedIdx < saved.length && service) service.removeCustomAddress(saved[savedIdx])
                }
            }
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(380))
        contentHeight: panel.fittedContentHeight(scrollView.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            blocked: root.activeComposer !== "none" || !!(composerSection && ((composerSection.pingInput && composerSection.pingInput.activeFocus) || (composerSection.textInput && composerSection.textInput.activeFocus))) || !!(networkSection && networkSection.addressInput && networkSection.addressInput.activeFocus)
            onMoveRequested: function(dx, dy) {
                if (!root.cursorActive) root.cursorActive = true
            }
            onActivateRequested: root.activate()
            onCloseRequested: {
                if (root.unpairConfirmingId) root.cancelUnpairConfirm(root.unpairConfirmingId)
                else if (root.activeComposer !== "none") root.closeComposer()
                else root.close()
            }
            onTabRequested: function(direction) {
                if (root.bar && typeof root.bar.switchPanelFrom === "function") {
                    root.bar.switchPanelFrom(root.barIdentity, direction)
                }
            }
            onTextKey: function(value) {
                if (root.activeComposer !== "none") return
                var key = String(value).toLowerCase()
                if (key === "r" && root.service) {
                    root.service.refresh(true)
                } else if (key === "j" || key === "down") {
                    if (root.focusSection === "devices") {
                        var devList = (root.service && root.service.devices) ? root.service.devices : []
                        if (devList.length > 0 && root.selectedIndex < devList.length - 1) root.select(1)
                        else root.navigateNextSection()
                    } else if (root.focusSection === "commands" && root.commandsExpanded) {
                        var cmdList = (root.service && root.service.remoteCommands) ? root.service.remoteCommands : []
                        if (cmdList.length > 0 && root.commandSelectedIndex < cmdList.length - 1) root.selectCommand(1)
                        else root.navigateNextSection()
                    } else if (root.focusSection === "network" && root.networkExpanded) {
                        if (root.networkSelectedIndex < root.getNetworkItemCount() - 1) root.networkSelectedIndex++
                        else root.navigateNextSection()
                    } else {
                        root.navigateNextSection()
                    }
                } else if (key === "k" || key === "up") {
                    if (root.focusSection === "devices") {
                        if (root.selectedIndex > 0) root.select(-1)
                        else root.navigatePrevSection()
                    } else if (root.focusSection === "commands" && root.commandsExpanded) {
                        if (root.commandSelectedIndex > 0) root.selectCommand(-1)
                        else root.navigatePrevSection()
                    } else if (root.focusSection === "network" && root.networkExpanded) {
                        if (root.networkSelectedIndex > 0) root.networkSelectedIndex--
                        else root.navigatePrevSection()
                    } else {
                        root.navigatePrevSection()
                    }
                } else if (key === "l" || key === "right") {
                    if (root.focusSection === "actions") {
                        if (root.actionSelectedIndex < root.availableActions.length - 1) root.actionSelectedIndex++
                        else root.navigateNextSection()
                    } else if (root.focusSection === "media") {
                        if (root.mediaExpanded && root.mediaControlIndex < 2) root.mediaControlIndex++
                        else root.navigateNextSection()
                    } else {
                        root.navigateNextSection()
                    }
                } else if (key === "h" || key === "left") {
                    if (root.focusSection === "actions") {
                        if (root.actionSelectedIndex > 0) root.actionSelectedIndex--
                        else root.navigatePrevSection()
                    } else if (root.focusSection === "media") {
                        if (root.mediaExpanded && root.mediaControlIndex > 0) root.mediaControlIndex--
                        else root.navigatePrevSection()
                    } else {
                        root.navigatePrevSection()
                    }
                } else if (key === "p" && root.focusSection === "devices") {
                    var listP = root.service ? root.service.devices : []
                    var devP = listP[root.selectedIndex]
                    if (devP && !devP.paired && root.service) {
                        var pendP = (root.service.pendingPairing && root.service.pendingPairing[devP.id]) ? root.service.pendingPairing[devP.id] : ""
                        if (pendP !== "requesting") root.service.pairDevice(devP.id)
                    }
                } else if (key === "u" && root.focusSection === "devices") {
                    var listU = root.service ? root.service.devices : []
                    var devU = listU[root.selectedIndex]
                    if (devU && devU.paired && root.service) {
                        var pendU = (root.service.pendingPairing && root.service.pendingPairing[devU.id]) ? root.service.pendingPairing[devU.id] : ""
                        if (pendU !== "removing") root.requestUnpairConfirm(devU.id)
                    }
                } else if (key === "y" && root.unpairConfirmingId) {
                    var listY = root.service ? root.service.devices : []
                    var devY = listY[root.selectedIndex]
                    if (devY && devY.id === root.unpairConfirmingId) root.confirmUnpair(root.unpairConfirmingId)
                } else if (key === "c" || key === "escape") {
                    var targetIdC = root.unpairConfirmingId || (root.service ? root.service.selectedDeviceId : "")
                    if (root.unpairConfirmingId || (root.service && targetIdC && root.service.pendingPairing && root.service.pendingPairing[targetIdC] === "unpair_confirm")) {
                        root.cancelUnpairConfirm(targetIdC)
                    } else if (root.service && targetIdC && root.service.pendingPairing && root.service.pendingPairing[targetIdC] === "requesting") {
                        root.service.setPendingPairing(targetIdC, "")
                        if (typeof root.service.clearActionState === "function") root.service.clearActionState()
                    }
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
                bottomPadding: Style.space(8)

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

                MediaPlayerSection {
                    id: mediaPlayerSection
                    panel: root
                }

                RemoteCommandsSection {
                    id: remoteCommandsSection
                    panel: root
                }

                NetworkSection {
                    id: networkSection
                    panel: root
                }
            }
        }
    }
}
