pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var panel

    width: parent ? parent.width : 0
    spacing: Style.space(12)

    readonly property var bar: panel ? panel.bar : null
    readonly property var service: panel ? panel.service : null
    readonly property var device: panel ? panel.device : null
    readonly property string deviceName: panel ? panel.deviceName : "KDE Connect"
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"

    readonly property bool showBattery: !panel || (typeof panel.getSetting === "function" ? panel.getSetting("showBatteryStats", true) : true)
    readonly property bool showNetwork: !panel || (typeof panel.getSetting === "function" ? panel.getSetting("showNetworkStats", true) : true)
    readonly property bool showDeviceTypeIcons: !panel || (typeof panel.getSetting === "function" ? panel.getSetting("showDeviceTypeIcons", true) : true)
    readonly property bool showTroubleshooting: !panel || (typeof panel.getSetting === "function" ? panel.getSetting("showTroubleshooting", true) : true)

    Item {
        width: parent.width
        implicitHeight: heroLayout.implicitHeight

        Item {
            id: heroLayout
            width: parent.width
            implicitHeight: Math.max(hero.implicitHeight, refreshButton.implicitHeight)

            Button {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                enabled: !root.service || !root.service.scanning
                opacity: (root.service && root.service.scanning) ? 0.6 : 1.0
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.refresh(true)
            }

            Column {
                id: hero
                anchors.left: parent.left
                anchors.right: refreshButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                    spacing: Style.space(6)
                    width: parent.width

                    Text {
                        visible: root.showDeviceTypeIcons && !!(root.device && root.device.type && root.device.type !== "unknown")
                        text: root.service ? root.service.deviceTypeIcon(root.device ? root.device.type : "") : ""
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.device ? root.deviceName : "KDE Connect"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                        elide: Text.ElideRight
                        width: Math.max(1, parent.width - (root.showDeviceTypeIcons && !!(root.device && root.device.type && root.device.type !== "unknown") ? Style.space(24) : 0))
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    width: parent.width
                    text: {
                        if (!root.service) return "Service unavailable"
                        if (root.service.discoveryState !== "ready") return root.service.discoveryMessage
                        return root.service.deviceOverviewStatus(root.device)
                    }
                    color: (root.service && root.service.discoveryState === "ready" && root.device && root.device.reachable)
                        ? root.foreground
                        : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }

                Row {
                    visible: !!(root.device && root.device.reachable && root.service && root.service.deviceBatteryText(root.device, root.showBattery, root.showNetwork) !== "")
                    spacing: Style.space(6)

                    Text {
                        text: root.service ? ((root.showBattery && root.device && root.device.capabilities && root.device.capabilities.battery && root.device.battery >= 0) ? root.service.deviceBatteryIcon(root.device) : root.service.deviceNetworkIcon(root.device)) : ""
                        color: (root.showBattery && root.device && root.device.capabilities && root.device.capabilities.battery && root.device.battery >= 0 && root.device.battery <= 20 && !(root.device.isCharging || root.device.charging))
                            ? Color.urgent
                            : ((root.device && (root.device.isCharging || root.device.charging)) ? Color.accent : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.service ? root.service.deviceBatteryText(root.device, root.showBattery, root.showNetwork) : ""
                        color: (root.showBattery && root.device && root.device.battery >= 0 && root.device.battery <= 20 && !(root.device.isCharging || root.device.charging))
                            ? Color.urgent
                            : ((root.device && (root.device.isCharging || root.device.charging)) ? Color.accent : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: !!(root.showBattery && root.device && root.device.battery >= 0 && root.device.battery <= 20 && !(root.device.isCharging || root.device.charging))
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    Rectangle {
        id: statusBanner
        visible: !!((root.service && (root.service.actionError || root.service.actionMessage)) || (root.panel && root.panel.composerError))
        width: parent.width
        implicitHeight: Math.max(bannerText.implicitHeight, Style.space(18)) + Style.space(8)
        radius: Style.cornerRadius
        color: ((root.service && root.service.actionError) || (root.panel && root.panel.composerError))
            ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15)
            : Style.hoverFillFor(root.foreground, Color.accent)

        Text {
            id: bannerText
            anchors.left: parent.left
            anchors.right: dismissButton.left
            anchors.leftMargin: Style.space(24)
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (root.service && root.service.actionError) return root.service.actionError
                if (root.panel && root.panel.composerError) return root.panel.composerError
                if (root.service && root.service.actionMessage) return root.service.actionMessage
                return ""
            }
            color: ((root.service && root.service.actionError) || (root.panel && root.panel.composerError)) ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        MouseArea {
            id: dismissButton
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: Style.space(18)
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.service) {
                    root.service.actionMessage = ""
                    root.service.actionError = ""
                }
                if (root.panel) {
                    root.panel.composerError = ""
                }
            }

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: ((root.service && root.service.actionError) || (root.panel && root.panel.composerError)) ? Color.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: parent.pressed ? 0.6 : 0.85
            }
        }
    }

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader { text: "DEVICES"; foreground: root.foreground; fontFamily: root.fontFamily }

    ListView {
        id: deviceList
        width: parent.width
        implicitHeight: contentHeight
        height: Math.min(contentHeight, Style.space(220))
        clip: true
        interactive: contentHeight > height
        model: root.service ? root.service.devices : []
        currentIndex: panel.cursorActive ? panel.selectedIndex : -1
        delegate: CursorSurface {
            required property var modelData
            required property int index
            readonly property string devicePendingState: (root.service && root.service.pendingPairing && root.service.pendingPairing[modelData.id]) ? root.service.pendingPairing[modelData.id] : ""
            readonly property bool isUnpairConfirming: panel.unpairConfirmingId === modelData.id || devicePendingState === "unpair_confirm"

            width: deviceList.width
            implicitHeight: row.implicitHeight + Style.space(8)
            hasCursor: panel.cursorActive && panel.focusSection === "devices" && panel.selectedIndex === index
            current: root.service && root.service.selectedDeviceId === modelData.id
            foreground: root.foreground
            fill: Style.hoverFillFor(root.foreground, Color.accent)
            currentFill: Style.selectedFillFor(root.foreground, Color.accent)
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    panel.cursorActive = true
                    panel.focusSection = "devices"
                    panel.selectedIndex = index
                    panel.selectDevice(modelData.id)
                }
            }
            Item {
                id: row
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8)
                implicitHeight: Math.max(nameText.implicitHeight, rightActionItem.implicitHeight) + Style.space(4)

                Row {
                    id: rightActionItem
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                        id: statusText
                        text: !modelData.paired ? "" : (!modelData.reachable ? "Offline" : "●")
                        color: modelData.paired && modelData.reachable ? Color.accent : Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                    }

                    Row {
                        id: actionRow
                        spacing: Style.space(4)
                        visible: !!(modelData && modelData.capabilities && modelData.capabilities.pair)

                        Row {
                            visible: isUnpairConfirming
                            spacing: Style.space(4)
                            Text {
                                text: "Confirm?"
                                color: Color.urgent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Button {
                                text: "Confirm"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: panel.confirmUnpair(modelData.id)
                            }
                            Button {
                                text: "Cancel"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: panel.cancelUnpairConfirm(modelData.id)
                            }
                        }

                        Button {
                            visible: !isUnpairConfirming && devicePendingState === "requesting"
                            text: "Pairing..."
                            tooltipText: "Click to cancel request"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                                if (root.service) {
                                    root.service.setPendingPairing(modelData.id, "")
                                    if (typeof root.service.clearActionState === "function") root.service.clearActionState()
                                }
                            }
                        }
                        Button {
                            visible: !isUnpairConfirming && devicePendingState === "removing"
                            enabled: false
                            text: "Unpairing..."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }

                        Button {
                            visible: !isUnpairConfirming && !modelData.paired && devicePendingState !== "requesting"
                            text: "Pair"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                                panel.selectDevice(modelData.id)
                                if (root.service) root.service.pairDevice(modelData.id)
                            }
                        }

                        Button {
                            visible: !isUnpairConfirming && modelData.paired && devicePendingState !== "removing"
                            text: "Unpair"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                                panel.selectDevice(modelData.id)
                                panel.requestUnpairConfirm(modelData.id)
                            }
                        }
                    }
                }

                Row {
                    id: leftInfoRow
                    anchors.left: parent.left
                    anchors.right: rightActionItem.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                        visible: root.showDeviceTypeIcons
                        text: root.service ? root.service.deviceTypeIcon(modelData.type) : "󰄜"
                        color: (root.service && root.service.selectedDeviceId === modelData.id) ? Color.accent : Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: nameText
                        text: modelData.name
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        width: Math.max(1, leftInfoRow.width - (root.showDeviceTypeIcons ? Style.space(20) : 0))
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    Column {
        visible: !root.service || root.service.devices.length === 0
        spacing: Style.space(6)
        width: parent.width

        Text {
            text: {
                if (root.service && root.service.scanning) return "Scanning..."
                if (root.service && root.service.discoveryState === "not_installed") return "Required packages missing"
                if (root.service && root.service.discoveryState === "unavailable") return "KDE Connect daemon stopped"
                return "No devices found"
            }
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

        Row {
            visible: !(root.service && root.service.scanning) && (root.service && root.service.discoveryState === "not_installed") && root.showTroubleshooting
            spacing: Style.space(6)

            Text {
                text: "kdeconnect needed"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                text: "Install Dependencies"
                tooltipText: "Runs: sudo pacman -S --needed kdeconnect glib2 dbus"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.installDependencies()
            }
        }

        Row {
            visible: !(root.service && root.service.scanning) && (root.service && root.service.discoveryState === "unavailable") && root.showTroubleshooting
            spacing: Style.space(6)

            Text {
                text: "daemon not running"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                text: "Start Service"
                tooltipText: "Attempts to start KDE Connect background service"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.refresh(true)
            }
        }

        Row {
            visible: !(root.service && root.service.scanning) && (!root.service || (root.service.discoveryState !== "not_installed" && root.service.discoveryState !== "unavailable")) && root.showTroubleshooting
            spacing: Style.space(6)

            Text {
                text: "Firewall blocking?"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                text: "Allow in Firewall"
                tooltipText: "Runs: sudo ufw allow 1714:1764/tcp & udp (or firewalld)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.configureFirewall()
            }
        }
    }
}
