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

                Text {
                    text: root.device ? root.deviceName : "KDE Connect"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width
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
                    visible: !!(root.device && root.service && root.service.deviceBatteryText(root.device) !== "")
                    spacing: Style.space(6)

                    Text {
                        text: root.service ? ((root.device.capabilities && root.device.capabilities.battery) ? root.service.deviceBatteryIcon(root.device) : root.service.deviceNetworkIcon(root.device)) : ""
                        color: (root.device && root.device.capabilities && root.device.capabilities.battery && root.device.battery >= 0 && root.device.battery <= 20 && !(root.device.isCharging || root.device.charging))
                            ? Color.urgent
                            : ((root.device && (root.device.isCharging || root.device.charging)) ? Color.accent : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.service ? root.service.deviceBatteryText(root.device) : ""
                        color: (root.device && root.device.battery >= 0 && root.device.battery <= 20 && !(root.device.isCharging || root.device.charging))
                            ? Color.urgent
                            : ((root.device && (root.device.isCharging || root.device.charging)) ? Color.accent : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: !!(root.device && root.device.battery >= 0 && root.device.battery <= 20 && !(root.device.isCharging || root.device.charging))
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }


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
                            enabled: false
                            text: "Pairing..."
                            foreground: root.foreground
                            fontFamily: root.fontFamily
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

                Text {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: rightActionItem.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                }
            }
        }
    }

    Column {
        visible: !root.service || root.service.devices.length === 0
        spacing: Style.space(6)
        width: parent.width

        Text {
            text: root.service && root.service.scanning ? "Scanning..." : "No devices found"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

        Row {
            visible: !(root.service && root.service.scanning)
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
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.configureFirewall()
            }
        }
    }
}
