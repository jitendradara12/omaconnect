pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "omaconnect"

    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
        ? bar.shell.serviceFor("omaconnect") : null
    readonly property var device: service ? service.selectedDevice : null
    readonly property string deviceName: device && typeof device.name === "string" ? device.name : "KDE Connect"
    readonly property Item button: buttonItem

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("hostWidget" in target) target.hostWidget = root
        if ("anchorItem" in target) target.anchorItem = buttonItem
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
    }

    function toggle() {
        if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
    }

    function togglePanel() {
        toggle()
    }

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() {
        if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
    }

    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function closeForPopoutSwitch() {
        if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch()
    }

    implicitWidth: buttonItem.implicitWidth
    implicitHeight: barSize

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    BarIconButton {
        id: buttonItem
        anchors.fill: parent
        bar: root.bar
        text: "󰄜"
        tooltipText: {
            if (!root.device || !root.device.reachable) return root.deviceName
            var showBat = !root.settings || root.settings.showBatteryStats !== false
            if (showBat && root.device.battery >= 0) {
                return root.deviceName + " (" + root.device.battery + "%)"
            }
            return root.deviceName
        }

        onPressed: function(b) {
            root.togglePanel()
        }
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }
}
