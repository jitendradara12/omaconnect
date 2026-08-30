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
    readonly property bool hasMedia: !!(media && (media.title || media.artist || media.album || media.player))
    readonly property bool isPlaying: !!(media && media.isPlaying)
    readonly property string trackTitle: (media && media.title) ? media.title : "Nothing playing"
    readonly property string trackArtist: (media && media.artist) ? media.artist : ""
    readonly property string trackAlbum: (media && media.album) ? media.album : ""
    readonly property string trackPlayer: (media && media.player) ? media.player : ""
    readonly property var playerList: (media && Array.isArray(media.playerList)) ? media.playerList : []
    readonly property string albumArt: (media && media.albumArt) ? media.albumArt : ""

    function cyclePlayer() {
        if (!root.service || !root.device || root.playerList.length < 2) return
        var currentIndex = root.playerList.indexOf(root.trackPlayer)
        var nextIndex = (currentIndex + 1) % root.playerList.length
        root.service.mediaSelectPlayer(root.device.id, root.playerList[nextIndex])
    }

    PanelSeparator { foreground: root.foreground }

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
                text: "MEDIA"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                width: Math.max(1, parent.width - Style.space(112))
                visible: !panel.mediaExpanded
                text: root.service && root.service.mediaLoading ? "Syncing…" : root.trackTitle
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Rectangle {
        id: mediaCard
        visible: panel.mediaExpanded
        width: parent.width
        implicitHeight: cardContent.implicitHeight + Style.space(20)
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
            spacing: Style.space(10)

            Row {
                width: parent.width
                spacing: Style.space(10)

                Rectangle {
                    id: coverFrame
                    width: Style.space(72)
                    height: width
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    border.width: 1
                    clip: true

                    Image {
                        id: bgArt
                        anchors.fill: parent
                        source: root.albumArt
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: bgArt.status !== Image.Ready
                        text: "󰎈"
                        color: root.hasMedia ? Color.accent : Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.display
                    }
                }

                Column {
                    width: Math.max(1, parent.width - coverFrame.width - Style.space(10))
                    spacing: Style.space(4)
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
                        width: parent.width
                        visible: root.trackArtist !== "" || root.trackAlbum !== ""
                        text: {
                            if (root.trackArtist && root.trackAlbum) return root.trackArtist + "  •  " + root.trackAlbum
                            return root.trackArtist || root.trackAlbum
                        }
                        color: Qt.darker(root.foreground, 1.3)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: !root.hasMedia
                        text: root.device && root.device.name ? "Open media on " + root.device.name : "No active player"
                        color: Qt.darker(root.foreground, 1.45)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Flow {
                        id: playerControlsRow
                        visible: root.playerList.length > 0 || root.trackPlayer !== ""
                        width: parent.width
                        spacing: Style.space(6)

                        Repeater {
                            model: root.playerList.length > 0 ? root.playerList : (root.trackPlayer !== "" ? [root.trackPlayer] : [])
                            delegate: CursorSurface {
                                id: playerChipSurface
                                required property string modelData
                                required property int index
                                readonly property bool isCurrent: modelData === root.trackPlayer

                                implicitWidth: chipContent.implicitWidth + Style.space(14)
                                implicitHeight: Style.space(22)
                                radius: Style.cornerRadius
                                foreground: root.foreground
                                fill: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                                currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                                PanelToolTip {
                                    visible: chipMouseArea.containsMouse && !isCurrent
                                    text: "Switch to " + modelData
                                    fontFamily: root.fontFamily
                                }

                                MouseArea {
                                    id: chipMouseArea
                                    anchors.fill: parent
                                    enabled: !isCurrent && root.playerList.length > 1
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (root.service && root.device && modelData) root.service.mediaSelectPlayer(root.device.id, modelData)
                                }

                                Row {
                                    id: chipContent
                                    anchors.centerIn: parent
                                    spacing: Style.space(5)

                                    Text {
                                        text: "󰐌"
                                        color: isCurrent ? Color.accent : Qt.darker(root.foreground, 1.4)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        id: playerNameText
                                        text: modelData
                                        color: isCurrent ? root.foreground : Qt.darker(root.foreground, 1.3)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        font.bold: isCurrent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(12)

                CursorSurface {
                    id: prevBtn
                    implicitWidth: Style.space(40)
                    implicitHeight: Style.space(34)
                    enabled: root.hasMedia
                    opacity: enabled ? 1 : 0.4
                    hasCursor: panel.cursorActive && panel.focusSection === "media" && panel.mediaExpanded && panel.mediaControlIndex === 0
                    radius: width / 2
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
                        enabled: prevBtn.enabled
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: {
                            panel.cursorActive = true
                            panel.focusSection = "media"
                            panel.mediaControlIndex = 0
                        }
                        onClicked: if (root.service && root.device) root.service.mediaPrevious(root.device.id)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                    }
                }

                CursorSurface {
                    id: playPauseBtn
                    implicitWidth: Style.space(48)
                    implicitHeight: Style.space(40)
                    enabled: root.hasMedia
                    opacity: enabled ? 1 : 0.4
                    hasCursor: panel.cursorActive && panel.focusSection === "media" && panel.mediaExpanded && panel.mediaControlIndex === 1
                    radius: width / 2
                    foreground: root.foreground
                    fill: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                    currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                    PanelToolTip {
                        visible: playMouseArea.containsMouse
                        text: root.isPlaying ? "Pause playback" : "Resume playback"
                        fontFamily: root.fontFamily
                    }

                    MouseArea {
                        id: playMouseArea
                        anchors.fill: parent
                        enabled: playPauseBtn.enabled
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: {
                            panel.cursorActive = true
                            panel.focusSection = "media"
                            panel.mediaControlIndex = 1
                        }
                        onClicked: if (root.service && root.device) root.service.mediaPlayPause(root.device.id)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "󰏤" : "󰐊"
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                    }
                }

                CursorSurface {
                    id: nextBtn
                    implicitWidth: Style.space(40)
                    implicitHeight: Style.space(34)
                    enabled: root.hasMedia
                    opacity: enabled ? 1 : 0.4
                    hasCursor: panel.cursorActive && panel.focusSection === "media" && panel.mediaExpanded && panel.mediaControlIndex === 2
                    radius: width / 2
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
                        enabled: nextBtn.enabled
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: {
                            panel.cursorActive = true
                            panel.focusSection = "media"
                            panel.mediaControlIndex = 2
                        }
                        onClicked: if (root.service && root.device) root.service.mediaNext(root.device.id)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                    }
                }
            }
        }
    }
}
