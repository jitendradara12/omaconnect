import QtQuick

Item {
    id: root
    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null

    KdeConnectController { id: controller }

    property alias daemonAvailable: controller.daemonAvailable
    property alias sessionBusAvailable: controller.sessionBusAvailable
    property alias scanning: controller.scanning
    property alias discoveryState: controller.discoveryState
    property alias discoveryMessage: controller.discoveryMessage
    property alias actionState: controller.actionState
    property alias actionMessage: controller.actionMessage
    property alias actionError: controller.actionError
    property alias devices: controller.devices
    property alias reachableDevices: controller.reachableDevices
    property alias selectedDeviceId: controller.selectedDeviceId
    property alias selectedDevice: controller.selectedDevice
    property alias incomingPairRequest: controller.incomingPairRequest
    property alias remoteCommands: controller.remoteCommands
    property alias commandsLoading: controller.commandsLoading
    property alias pendingPairing: controller.pendingPairing
    property alias capabilities: controller.capabilities
    property alias fileBusy: controller.fileBusy
    property alias tailscaleInstalled: controller.tailscaleInstalled
    property alias tailscaleRunning: controller.tailscaleRunning
    property alias tailscaleLoading: controller.tailscaleLoading
    property alias tailscaleStatus: controller.tailscaleStatus
    property alias localTailscaleAddress: controller.localTailscaleAddress
    property alias tailscalePeers: controller.tailscalePeers
    property alias customAddresses: controller.customAddresses
    property alias customAddressesReady: controller.customAddressesReady
    property alias addressBusy: controller.addressBusy

    function refresh(forceNetwork) { controller.refresh(forceNetwork) }
    function selectDevice(id) { controller.selectDevice(id) }
    function clearActionState() { controller.clearActionState() }
    function setPendingPairing(id, state) { controller.setPendingPairing(id, state) }
    function pingDevice(id, text) { return controller.pingDevice(id, text) }
    function shareText(id, text) { return controller.shareText(id, text) }
    function fetchRemoteCommands(id) { return controller.fetchRemoteCommands(id) }
    function executeRemoteCommand(id, key) { return controller.executeRemoteCommand(id, key) }
    function pairDevice(id) { return controller.pairDevice(id) }
    function unpairDevice(id) { return controller.unpairDevice(id) }
    function acceptPairing(id) { return controller.acceptPairing(id) }
    function rejectPairing(id) { return controller.rejectPairing(id) }
    function ringDevice(id) { return controller.ringDevice(id) }
    function sendClipboard(id) { return controller.sendClipboard(id) }
    function startFileSelection(id) { return controller.startFileSelection(id) }
    function cancelFileSelection() { return controller.cancelFileSelection() }
    function sendFile(id, path) { return controller.sendFile(id, path) }
    function openSmsApp(id) { return controller.openSmsApp(id) }
    function openKdeConnectApp() { return controller.openKdeConnectApp() }
    function configureFirewall() { controller.configureFirewall() }
    function installDependencies() { controller.installDependencies() }
    function refreshTailscale() { controller.refreshTailscale() }
    function addCustomAddress(address) { return controller.addCustomAddress(address) }
    function removeCustomAddress(address) { return controller.removeCustomAddress(address) }
    function filteredTailscalePeers(query) { return controller.filteredTailscalePeers(query) }
    function addressError(address) { return controller.addressError(address) }
    function formatVerificationKey(key) { return controller.formatVerificationKey(key) }
    function deviceOverviewStatus(device) { return controller.deviceOverviewStatus(device) }
    function deviceTypeIcon(type) { return controller.deviceTypeIcon(type) }
    function deviceBatteryText(device, showBattery, showNetwork) { return controller.deviceBatteryText(device, showBattery, showNetwork) }
    function deviceBatteryIcon(device) { return controller.deviceBatteryIcon(device) }
    function deviceNetworkIcon(device) { return controller.deviceNetworkIcon(device) }
}
