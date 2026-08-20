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
    visible: !!(panel && panel.device && panel.device.paired && panel.device.reachable)

    readonly property var bar: panel ? panel.bar : null
    readonly property var service: panel ? panel.service : null
    readonly property var device: panel ? panel.device : null
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"

    PanelSectionHeader {
        text: (root.device && root.device.type && root.device.type !== "unknown") ? (root.device.type.toUpperCase() + " ACTIONS") : "ACTIONS"
        foreground: root.foreground
        fontFamily: root.fontFamily
    }

    Flow {
        width: parent.width
        spacing: Style.space(6)
        Repeater {
            model: panel ? panel.availableActions : []
            delegate: CursorSurface {
                id: actionSurface
                required property string modelData
                required property int index
                readonly property string actionName: {
                    if (modelData === "ring") return "Ring"
                    if (modelData === "clipboard") return "Clipboard"
                    if (modelData === "file") return "File"
                    if (modelData === "sms") return "SMS"
                    if (modelData === "ping") return "Ping"
                    if (modelData === "text") return "Text"
                    return modelData
                }
                readonly property string actionTooltip: {
                    if (modelData === "ring") return "Ring device to locate it"
                    if (modelData === "clipboard") return "Send clipboard to device"
                    if (modelData === "file") return "Choose and send file to device"
                    if (modelData === "sms") return "Open SMS conversation app"
                    if (modelData === "ping") return "Send ping notification"
                    if (modelData === "text") return "Share text or link with device"
                    return modelData
                }
                readonly property string actionIcon: {
                    if (modelData === "ring") return "󰂚"
                    if (modelData === "clipboard") return "󰅌"
                    if (modelData === "file") return "󰈔"
                    if (modelData === "sms") return "󰍦"
                    if (modelData === "ping") return "󰵅"
                    if (modelData === "text") return "󰌹"
                    return ""
                }

                PanelToolTip {
                    visible: actionMouseArea.containsMouse
                    text: actionSurface.actionTooltip
                    fontFamily: root.fontFamily
                }

                implicitWidth: (actionIcon !== "" ? Style.space(16) : 0) + actionBtnText.implicitWidth + Style.space(16)
                implicitHeight: Math.max(actionBtnText.implicitHeight, Style.space(16)) + Style.space(8)
                hasCursor: panel.cursorActive && panel.focusSection === "actions" && panel.actionSelectedIndex === index
                current: (modelData === "ping" && panel.activeComposer === "ping") || (modelData === "text" && panel.activeComposer === "text")
                foreground: root.foreground
                fill: Style.hoverFillFor(root.foreground, Color.accent)
                currentFill: Style.selectedFillFor(root.foreground, Color.accent)
                enabled: !root.service || (root.service.actionState !== "running" && !root.service.fileBusy)

                MouseArea {
                    id: actionMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        panel.cursorActive = true
                        panel.focusSection = "actions"
                        panel.actionSelectedIndex = index
                    }
                    onClicked: panel.triggerAction(modelData)
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                        visible: actionSurface.actionIcon !== ""
                        text: actionSurface.actionIcon
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: actionBtnText
                        text: actionSurface.actionName
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
