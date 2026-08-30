pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var panel

    width: parent ? parent.width : 0
    spacing: Style.space(6)
    visible: !!(panel && (!panel.getSetting || panel.getSetting("showTailscale", true)))

    readonly property var bar: panel ? panel.bar : null
    readonly property var service: panel ? panel.service : null
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"
    readonly property var filteredPeers: service ? service.filteredTailscalePeers(addressInput.text).slice(0, 8) : []

    readonly property bool hasCommandsAbove: !!(panel && panel.remoteCommandsVisible)
    readonly property bool hasMediaAbove: !!(panel && panel.mediaPlayerVisible)

    PanelSeparator {
        visible: (!root.hasCommandsAbove && !root.hasMediaAbove) || (panel && (panel.commandsExpanded || panel.mediaExpanded))
        foreground: root.foreground
    }

    Row {
        width: parent.width
        spacing: Style.space(6)

        CursorSurface {
            width: Math.max(1, parent.width - (panel.networkExpanded ? refreshNetBtn.implicitWidth + Style.space(6) : 0))
            implicitHeight: headerRow.implicitHeight + Style.space(6)
            hasCursor: panel.cursorActive && panel.focusSection === "network" && !panel.networkExpanded
            radius: Style.cornerRadius
            foreground: root.foreground
            fill: Style.hoverFillFor(root.foreground, Color.accent)
            currentFill: Style.selectedFillFor(root.foreground, Color.accent)

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    panel.cursorActive = true
                    panel.focusSection = "network"
                }
                onClicked: panel.toggleNetworkExpanded()
            }

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                    text: panel.networkExpanded ? "󰅀" : "󰅂"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                }

                PanelSectionHeader {
                    text: "NETWORK DISCOVERY"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    visible: !panel.networkExpanded && !!(root.service && root.service.tailscaleInstalled)
                    text: {
                        if (root.service.tailscaleLoading) return "Checking…"
                        return root.service.tailscaleStatus
                    }
                    color: root.service && root.service.tailscaleRunning ? Color.accent : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        PanelActionButton {
            id: refreshNetBtn
            visible: panel.networkExpanded
            iconText: "󰑐"
            tooltipText: "Refresh Tailscale peers"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !!root.service && !root.service.tailscaleLoading
            onClicked: if (root.service) root.service.refreshTailscale()
        }
    }

    Column {
        visible: panel.networkExpanded
        width: parent.width
        spacing: Style.space(8)

        Text {
            visible: !!(root.service && root.service.localTailscaleAddress)
            width: parent.width
            text: "This computer: " + (root.service ? root.service.localTailscaleAddress : "")
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
        }

        Text {
            visible: !!(root.service && !root.service.customAddressesReady && root.service.discoveryState === "ready")
            width: parent.width
            text: "KDE Connect's saved address list is unavailable. Refresh before adding or removing addresses."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }

        Text {
            visible: !!(root.service && !root.service.tailscaleLoading && !root.service.tailscaleInstalled)
            width: parent.width
            text: "Install Tailscale on both devices for simple connections across networks, or enter another VPN IP below."
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
                id: addressInput
                width: Math.max(1, parent.width - addButton.implicitWidth - Style.space(6))
                placeholderText: root.service && root.service.tailscaleRunning ? "Search peers or enter IP" : "Enter LAN or VPN IP"
                placeholderTextColor: Qt.darker(root.foreground, 1.5)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground
                background: Rectangle {
                    color: Style.hoverFillFor(root.foreground, Color.accent)
                    border.color: addressInput.activeFocus ? Color.accent : Qt.darker(root.foreground, 1.6)
                    border.width: 1
                    radius: Style.cornerRadius
                }
                onAccepted: {
                    if (root.service && root.service.addCustomAddress(text)) text = ""
                }
            }

            Button {
                id: addButton
                text: "Add"
                tooltipText: "Save this address in KDE Connect and discover devices"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                enabled: !!root.service && root.service.customAddressesReady && !root.service.addressBusy && addressInput.text.trim() !== ""
                onClicked: if (root.service && root.service.addCustomAddress(addressInput.text)) addressInput.text = ""
            }
        }

        Column {
            visible: !!(root.service && root.service.tailscaleRunning && root.filteredPeers.length > 0)
            width: parent.width
            spacing: Style.space(4)

            Repeater {
                model: root.filteredPeers
                delegate: Item {
                    required property var modelData
                    width: parent ? parent.width : 0
                    implicitHeight: peerRow.implicitHeight + Style.space(4)

                    Row {
                        id: peerRow
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                            text: "●"
                            color: (modelData && modelData.online) ? Color.accent : Qt.darker(root.foreground, 1.6)
                            font.pixelSize: Style.font.caption
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            width: Math.max(1, parent.width - peerButton.implicitWidth - Style.space(24))
                            text: modelData ? (modelData.name + "  " + modelData.address + (modelData.online ? "" : "  Offline")) : ""
                            color: (modelData && modelData.online) ? root.foreground : Qt.darker(root.foreground, 1.5)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Button {
                            id: peerButton
                            text: (root.service && modelData && root.service.customAddresses.indexOf(modelData.address) !== -1) ? "Saved" : "Add"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.bodySmall
                            enabled: !!root.service && root.service.customAddressesReady && !root.service.addressBusy && text !== "Saved"
                            onClicked: if (root.service && modelData) root.service.addCustomAddress(modelData.address)
                        }
                    }
                }
            }
        }

        Column {
            visible: !!(root.service && root.service.customAddresses.length > 0)
            width: parent.width
            spacing: Style.space(4)

            Text {
                text: "SAVED ADDRESSES"
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }

            Repeater {
                model: root.service ? root.service.customAddresses : []
                delegate: Row {
                    required property string modelData
                    width: parent ? parent.width : 0
                    spacing: Style.space(6)

                    Text {
                        width: Math.max(1, parent.width - removeButton.implicitWidth - Style.space(6))
                        text: modelData
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Button {
                        id: removeButton
                        text: "Remove"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fontSize: Style.font.bodySmall
                        enabled: !!root.service && root.service.customAddressesReady && !root.service.addressBusy
                        onClicked: if (root.service) root.service.removeCustomAddress(modelData)
                    }
                }
            }
        }
    }
}
