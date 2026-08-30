pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var panel

    width: parent ? parent.width : 0
    spacing: Style.space(8)
    visible: !!(panel && panel.mediaPlayerVisible)

    readonly property var bar: panel ? panel.bar : null
    readonly property var service: panel ? panel.service : null
    readonly property var device: panel ? panel.device : null
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"

    readonly property var media: (service && service.mediaState) ? service.mediaState : null
    readonly property bool hasMedia: !!(media && (media.title || media.artist || media.album || media.isPlaying || (media.player && media.player !== "")))
    readonly property bool isPlaying: !!(media && media.isPlaying)
    readonly property string trackTitle: (media && media.title) ? media.title : (hasMedia ? "Unknown Title" : "No active media")
    readonly property string trackArtist: (media && media.artist) ? media.artist : ""
    readonly property string trackAlbum: (media && media.album) ? media.album : ""
    readonly property string trackPlayer: (media && media.player) ? media.player : ""
    readonly property int currentVolume: (media && typeof media.volume === "number") ? media.volume : -1
    readonly property int trackPosition: (media && typeof media.position === "number") ? media.position : 0
    readonly property int trackLength: (media && typeof media.length === "number") ? media.length : 0

    PanelSeparator { foreground: root.foreground }

    Row {
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader {
            text: "MEDIA CONTROLS"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - refreshMediaBtn.implicitWidth - Style.space(6)
        }

        PanelActionButton {
            id: refreshMediaBtn
            iconText: "󰑐"
            tooltipText: "Refresh media player"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.service || !root.service.mediaLoading
            onClicked: if (root.service && root.device) root.service.fetchMediaStatus(root.device.id)
        }
    }

    Rectangle {
        id: mediaCard
        width: parent.width
        implicitHeight: cardContent.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Style.hoverFillFor(root.foreground, Color.accent)
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
        border.width: 1

        Column {
            id: cardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Row {
                width: parent.width
                spacing: Style.space(10)

                Rectangle {
                    width: Style.space(36)
                    height: Style.space(36)
                    radius: Style.cornerRadius
                    color: root.isPlaying ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "󰝚" : "󰎈"
                        color: root.isPlaying ? "#000000" : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                    }
                }

                Column {
                    width: Math.max(1, parent.width - Style.space(46) - (playerTag.visible ? playerTag.implicitWidth + Style.space(8) : 0))
                    spacing: Style.space(2)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: root.trackTitle
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.trackArtist !== "" || root.trackAlbum !== ""
                        width: parent.width
                        text: {
                            if (root.trackArtist && root.trackAlbum) return root.trackArtist + " • " + root.trackAlbum
                            if (root.trackArtist) return root.trackArtist
                            return root.trackAlbum
                        }
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: !root.hasMedia
                        width: parent.width
                        text: (root.device && root.device.name) ? ("Nothing playing on " + root.device.name) : "Ready for media"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: playerTag
                    visible: root.trackPlayer !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: playerTagText.implicitWidth + Style.space(10)
                    implicitHeight: playerTagText.implicitHeight + Style.space(4)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                    Text {
                        id: playerTagText
                        anchors.centerIn: parent
                        text: root.trackPlayer
                        color: Qt.darker(root.foreground, 1.2)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }
                }
            }

            Column {
                visible: root.trackLength > 0
                width: parent.width
                spacing: Style.space(3)

                Rectangle {
                    width: parent.width
                    height: Style.space(4)
                    radius: Style.space(2)
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: Color.accent
                        width: Math.max(0, Math.min(parent.width, parent.width * (root.trackPosition / Math.max(1, root.trackLength))))
                    }
                }

                Item {
                    width: parent.width
                    implicitHeight: posText.implicitHeight

                    Text {
                        id: posText
                        anchors.left: parent.left
                        text: root.service ? root.service.formatMediaTime(root.trackPosition) : "0:00"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Text {
                        anchors.right: parent.right
                        text: root.service ? root.service.formatMediaTime(root.trackLength) : "0:00"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(12)

                CursorSurface {
                    id: prevBtn
                    implicitWidth: Style.space(34)
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    foreground: root.foreground
                    fill: Style.hoverFillFor(root.foreground, Color.accent)
                    currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                    PanelToolTip {
                        visible: prevMouseArea.containsMouse
                        text: "Previous track"
                        fontFamily: root.fontFamily
                    }

                    MouseArea {
                        id: prevMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service && root.device) root.service.mediaPrevious(root.device.id)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                    }
                }

                CursorSurface {
                    id: playPauseBtn
                    implicitWidth: Style.space(42)
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    foreground: root.foreground
                    fill: root.isPlaying ? Color.accent : Style.hoverFillFor(root.foreground, Color.accent)
                    currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                    PanelToolTip {
                        visible: playMouseArea.containsMouse
                        text: root.isPlaying ? "Pause playback" : "Play track"
                        fontFamily: root.fontFamily
                    }

                    MouseArea {
                        id: playMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service && root.device) root.service.mediaPlayPause(root.device.id)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "󰏤" : "󰐊"
                        color: root.isPlaying ? "#000000" : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }
                }

                CursorSurface {
                    id: nextBtn
                    implicitWidth: Style.space(34)
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    foreground: root.foreground
                    fill: Style.hoverFillFor(root.foreground, Color.accent)
                    currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                    PanelToolTip {
                        visible: nextMouseArea.containsMouse
                        text: "Next track"
                        fontFamily: root.fontFamily
                    }

                    MouseArea {
                        id: nextMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service && root.device) root.service.mediaNext(root.device.id)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                    }
                }
            }

            Row {
                visible: root.currentVolume >= 0
                width: parent.width
                spacing: Style.space(8)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (root.currentVolume === 0) return "󰖁"
                        if (root.currentVolume <= 33) return "󰕿"
                        if (root.currentVolume <= 66) return "󰖀"
                        return "󰕾"
                    }
                    color: root.currentVolume === 0 ? Color.urgent : Qt.darker(root.foreground, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                }

                CursorSurface {
                    id: volDownBtn
                    implicitWidth: Style.space(26)
                    implicitHeight: Style.space(22)
                    radius: Style.cornerRadius
                    foreground: root.foreground
                    fill: Style.hoverFillFor(root.foreground, Color.accent)
                    currentFill: Style.selectedFillFor(root.foreground, Color.accent)
                    anchors.verticalCenter: parent.verticalCenter

                    PanelToolTip {
                        visible: volDownMouseArea.containsMouse
                        text: "Decrease volume"
                        fontFamily: root.fontFamily
                    }

                    MouseArea {
                        id: volDownMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service && root.device) root.service.mediaSetVolume(root.device.id, Math.max(0, root.currentVolume - 5))
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰝤"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }

                Rectangle {
                    id: volBar
                    width: Math.max(1, parent.width - Style.space(120))
                    height: Style.space(4)
                    radius: Style.space(2)
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: Color.accent
                        width: Math.max(0, Math.min(parent.width, parent.width * (root.currentVolume / 100)))
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            if (root.service && root.device && volBar.width > 0) {
                                var newVol = Math.max(0, Math.min(100, Math.round((mouse.x / volBar.width) * 100)))
                                root.service.mediaSetVolume(root.device.id, newVol)
                            }
                        }
                    }
                }

                CursorSurface {
                    id: volUpBtn
                    implicitWidth: Style.space(26)
                    implicitHeight: Style.space(22)
                    radius: Style.cornerRadius
                    foreground: root.foreground
                    fill: Style.hoverFillFor(root.foreground, Color.accent)
                    currentFill: Style.selectedFillFor(root.foreground, Color.accent)
                    anchors.verticalCenter: parent.verticalCenter

                    PanelToolTip {
                        visible: volUpMouseArea.containsMouse
                        text: "Increase volume"
                        fontFamily: root.fontFamily
                    }

                    MouseArea {
                        id: volUpMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service && root.device) root.service.mediaSetVolume(root.device.id, Math.min(100, root.currentVolume + 5))
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰝝"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.currentVolume + "%"
                    color: Qt.darker(root.foreground, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    width: Style.space(32)
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
