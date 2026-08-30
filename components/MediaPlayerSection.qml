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
    readonly property var playerList: (media && Array.isArray(media.playerList)) ? media.playerList : []
    readonly property string albumArt: (media && media.albumArt) ? media.albumArt : ""

    PanelSeparator { foreground: root.foreground }

    Row {
        width: parent.width
        spacing: Style.space(6)

        CursorSurface {
            width: parent.width
            implicitHeight: headerRow.implicitHeight + Style.space(6)
            hasCursor: panel.cursorActive && panel.focusSection === "media" && !panel.mediaExpanded
            radius: Style.cornerRadius
            foreground: root.foreground
            fill: Style.hoverFillFor(root.foreground, Color.accent)
            currentFill: Style.selectedFillFor(root.foreground, Color.accent)

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    panel.cursorActive = true
                    panel.focusSection = "media"
                }
                onClicked: panel.toggleMediaExpanded()
            }

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                    text: panel.mediaExpanded ? "󰅀" : "󰅂"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.isPlaying ? "󰝚" : "󰎈"
                    color: root.isPlaying ? Color.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                }

                PanelSectionHeader {
                    text: "MEDIA CONTROLS"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    visible: !panel.mediaExpanded && root.isPlaying && root.trackTitle !== "" && root.trackTitle !== "No active media"
                    text: "• " + root.trackTitle
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: Math.max(1, parent.width - Style.space(160))
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Rectangle {
        id: mediaCard
        visible: panel.mediaExpanded
        width: parent.width
        implicitHeight: cardContent.implicitHeight + Style.space(18)
        radius: Style.cornerRadius
        color: Style.hoverFillFor(root.foreground, Color.accent)
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
        border.width: 1
        clip: true

        Image {
            id: bgArt
            visible: root.albumArt !== ""
            anchors.fill: parent
            source: root.albumArt
            fillMode: Image.PreserveAspectCrop
            opacity: 0.16
            asynchronous: true
        }

        Rectangle {
            visible: root.albumArt !== ""
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
        }

        Column {
            id: cardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            Row {
                width: parent.width
                spacing: Style.space(8)

                Column {
                    width: Math.max(1, parent.width - (playerControlsRow.visible ? playerControlsRow.implicitWidth + Style.space(8) : 0))
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

                Row {
                    id: playerControlsRow
                    visible: root.playerList.length > 0 || root.trackPlayer !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Repeater {
                        model: root.playerList.length > 1 ? root.playerList : (root.trackPlayer !== "" ? [root.trackPlayer] : [])
                        delegate: CursorSurface {
                            required property string modelData
                            required property int index
                            readonly property bool isCurrent: modelData === root.trackPlayer
                            implicitWidth: pText.implicitWidth + Style.space(8)
                            implicitHeight: pText.implicitHeight + Style.space(4)
                            radius: Style.cornerRadius
                            foreground: root.foreground
                            fill: isCurrent ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                            currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.playerList.length > 1
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.service && root.device && modelData) root.service.mediaSelectPlayer(root.device.id, modelData)
                            }

                            Text {
                                id: pText
                                anchors.centerIn: parent
                                text: modelData
                                color: isCurrent ? root.foreground : Qt.darker(root.foreground, 1.3)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: isCurrent
                            }
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(16)

                CursorSurface {
                    id: prevBtn
                    implicitWidth: Style.space(38)
                    implicitHeight: Style.space(32)
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
                        font.pixelSize: Style.font.bodyLarge
                    }
                }

                CursorSurface {
                    id: playPauseBtn
                    implicitWidth: Style.space(48)
                    implicitHeight: Style.space(32)
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
                    implicitWidth: Style.space(38)
                    implicitHeight: Style.space(32)
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
                        font.pixelSize: Style.font.bodyLarge
                    }
                }
            }
        }
    }
}
