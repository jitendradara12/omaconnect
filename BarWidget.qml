pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "bridge" as OmaconnectBridge

BarWidget {
    id: root
    moduleName: "omaconnect"

    // Primary path: the bar host's scoped facade (service-capable under the
    // first-party bar). Fallback: the engine-wide bridge singleton -- under
    // replacement bars the facade's serviceFor() is a deliberate null stub,
    // so widgets they host would otherwise never see the service. The
    // binding re-evaluates on its own when the service publishes (or is
    // torn down). See bridge/Bridge.qml.
    readonly property var service: {
        var viaHost = bar && bar.shell && typeof bar.shell.serviceFor === "function"
            ? bar.shell.serviceFor("omaconnect") : null
        return viaHost || OmaconnectBridge.Bridge.service
    }
    readonly property var device: service ? service.selectedDevice : null
    readonly property string deviceName: device && typeof device.name === "string" ? device.name : "KDE Connect"
    readonly property bool hasBattery: !!(device && device.reachable && device.capabilities && device.capabilities.battery && device.battery >= 0)
    readonly property bool showBarBattery: !!(root.settings && root.settings.showBarBattery && root.hasBattery)
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
        slotSize: Style.bar.iconSlot * (root.showBarBattery && (!root.bar || !root.bar.vertical) ? 2 : 1)
        text: {
            var icon = root.device && root.service && root.settings && root.settings.showDeviceTypeIcons !== false
                ? root.service.deviceTypeIcon(root.device.type) : "󰄜"
            return root.showBarBattery ? (icon + " " + root.device.battery + "%") : icon
        }
        tooltipText: {
            var showBat = !root.settings || root.settings.showBatteryStats !== false
            if (showBat && root.hasBattery) {
                return root.deviceName + " (" + root.device.battery + "%)"
            }
            return root.deviceName
        }

        onPressed: function(b) {
            root.togglePanel()
        }
    }

    IpcHandler {
        target: "omaconnect"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }
        function refresh(): void { if (root.service) root.service.refresh(true) }
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
