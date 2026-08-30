# OmaConnect

Control your phone and other devices from the Omarchy bar with KDE Connect.

KDE Connect is the cross-device layer underneath. It pairs your Linux desktop with Android, iPhone, Windows, and macOS devices for clipboard sharing, file transfer, messaging, and notifications. OmaConnect puts the most useful controls in one quick bar panel instead of making you open a separate app.

![OmaConnect screenshot](preview.png)

## Install

```bash
omarchy plugin add https://github.com/jitendradara12/omaconnect.git --enable --yes
```

## Features

- **Device status**: Battery charge, charging state, cellular network type, signal strength, and reachability.
- **Device actions**: Ring phone, sync clipboard, send files, share text or links, and send pings.
- **SMS launcher**: Open `kdeconnect-sms` for a paired device.
- **File picker**: Select recent files from user directories with Omarchy's menu picker.
- **Remote commands**: View and trigger commands defined on paired devices.
- **Pairing controls**: Start pairing, verify and accept/reject incoming requests, and unpair with inline confirmation safeguards.
- **Tailscale discovery**: Find tailnet peers without an API token and add their stable IP to KDE Connect with one click.
- **VPN and manual addresses**: Save or remove literal LAN/VPN addresses using KDE Connect's own persisted address list.
- **At-a-glance bar status**: Show the selected device status icon directly in the bar.
- **Modular preferences**: Toggle specific actions, telemetry fields, or panel sections to match your workflow.

## Preferences and configuration

You can customize OmaConnect via your Omarchy bar widget settings. All options default to `true` unless noted otherwise.

| Option | Type | Default | Description |
|---|---|---|---|
| `showBatteryStats` | boolean | `true` | Display battery percentage and charging indicator |
| `showNetworkStats` | boolean | `true` | Display cellular network type and signal strength |
| `showTailscale` | boolean | `true` | Display optional Tailscale and custom-address discovery |
| `showDeviceTypeIcons` | boolean | `true` | Display device type icons (phone, tablet, laptop, desktop) |
| `showRemoteCommands` | boolean | `true` | Display remote commands section |
| `showTroubleshooting` | boolean | `true` | Display setup and firewall helpers when devices are offline |
| `showActionRing` | boolean | `true` | Include the Ring action button |
| `showActionClipboard` | boolean | `true` | Include the Clipboard sync button |
| `showActionFile` | boolean | `true` | Include the File send button |
| `showActionSms` | boolean | `true` | Include the SMS launcher button |
| `showActionPing` | boolean | `false` | Include the Ping button |
| `showActionText` | boolean | `true` | Include the Text and link sharing button |
| `defaultPingMessage` | string | `""` | Default draft text for ping composer |

## Security and permissions

OmaConnect does not run arbitrary commands or download unverified scripts.

- **Dependency installation**: The installer helper uses your system's package manager (`pacman`). It displays the exact command (`sudo pacman -S --needed kdeconnect glib2 dbus`) and asks for confirmation before requesting root privileges.
- **Firewall setup**: The firewall helper detects UFW or firewalld, displays the exact rules before applying them, and prompts for confirmation before running `sudo`.
- **Tailscale privacy**: Peer information is read locally from `tailscale status --json`; OmaConnect uses no Tailscale API token or remote service.
- **Address ownership**: Added addresses are written to KDE Connect's own `customDevices` D-Bus property. OmaConnect does not maintain a second trust or connection database.
- **UI tooltips**: Hovering over troubleshooting buttons displays the exact command that will execute.

## Shortcuts

Add to `~/.config/omarchy/shortcuts.lua`:

```lua
o.bind("SUPER + SHIFT + C", "Toggle OmaConnect", "omarchy-shell shell toggle omaconnect")
```

## Dependencies

Requires `kdeconnect`, `glib2`, `dbus`, and Omarchy's `omarchy-menu-select` command for file sharing. Tailscale is optional and only needed for cross-network peer discovery.

To install dependencies manually:

```bash
sudo pacman -S --needed kdeconnect glib2 dbus
```

### Connect across networks with Tailscale

1. Install Tailscale on both devices and join them to the same tailnet.
2. Open OmaConnect and find **Network Discovery**.
3. Select **Add** beside the other device. OmaConnect saves its stable Tailscale IPv4 address in KDE Connect and starts discovery.
4. Keep KDE Connect open on the other device, then compare the verification key and accept pairing on both devices.

You can also type any literal LAN or VPN IPv4/IPv6 address. Tailscale is optional; normal KDE Connect LAN discovery continues to work without it.

### Firewall configuration

Omarchy blocks incoming ports by default. Allow KDE Connect discovery and transfer ports on the network interface you use, including the Tailscale interface for cross-network connections:

![OmaConnect screenshot of allow in firewall](preview1.png)

_Click **Allow in Firewall** inside the panel, or run manually:_

For UFW:
```bash
sudo ufw allow 1714:1764/tcp comment 'KDE Connect'
sudo ufw allow 1714:1764/udp comment 'KDE Connect'
sudo ufw reload
```

For firewalld:
```bash
sudo firewall-cmd --permanent --add-service=kdeconnect
sudo firewall-cmd --reload
```

## Update

```bash
omarchy plugin update omaconnect
```

## Uninstall

```bash
omarchy plugin remove omaconnect
```
