# OmaConnect

Control phones and connected devices from the Omarchy bar using KDE Connect.

![OmaConnect panel](preview.png)

## Install

```bash
omarchy plugin add https://github.com/jitendradara12/omaconnect.git --enable --yes
```

## Features

- **Device status.** Battery level, charging state, cellular network type, signal strength, and reachability.
- **Quick actions.** Ring phone, sync clipboard, send files, share text or links, and ping devices.
- **SMS launcher.** Open `kdeconnect-sms` for paired devices.
- **Media playback.** Track metadata, playback controls, and player switching.
- **File picker.** Pick recent files with `omarchy-menu-select`.
- **Remote commands.** Run custom commands configured on paired devices.
- **Pairing.** Manage requests, verification keys, and unpairing.
- **Network discovery.** Add Tailscale peers or custom LAN and VPN IP addresses.
- **Bar widget.** Show connection and battery status directly in the Omarchy bar.

## Preferences

Configure OmaConnect in Omarchy bar widget settings.

| Setting | Default | Description |
|---|---|---|
| `showBatteryStats` | `true` | Battery percentage and charging state |
| `showNetworkStats` | `true` | Cellular network type and signal strength |
| `showTailscale` | `true` | Tailscale and custom IP discovery |
| `showDeviceTypeIcons` | `true` | Device type icons in bar and panel |
| `showMediaPlayer` | `true` | Media player controls and track metadata |
| `showRemoteCommands` | `true` | Remote commands section |
| `showTroubleshooting` | `true` | Setup and firewall helpers when offline |
| `showActionRing` | `true` | Ring device button |
| `showActionClipboard` | `true` | Clipboard sync button |
| `showActionFile` | `true` | File transfer button |
| `showActionSms` | `true` | SMS launcher button |
| `showActionPing` | `false` | Ping button |
| `showActionText` | `true` | Text and link share button |
| `defaultPingMessage` | `""` | Default ping message draft |

## Shortcuts

Add to `~/.config/omarchy/shortcuts.lua`:

```lua
o.bind("SUPER + SHIFT + C", "Toggle OmaConnect", "omarchy-shell shell toggle omaconnect")
```

## Dependencies

Requires `kdeconnect`, `glib2`, `dbus`, and `omarchy-menu-select` (for file sharing). `tailscale` and `kdeconnect-sms` are optional, as is `kpeoplevcard` (AUR) for [contact names in SMS](#contact-names-in-sms).

```bash
sudo pacman -S --needed kdeconnect glib2 dbus
```

### Tailscale and custom IPs

Expand **Network Discovery** to add detected Tailscale peers, or enter custom LAN and VPN IP addresses directly.

### Firewall

KDE Connect requires ports `1714:1764` (TCP and UDP). Click **Allow in Firewall** in the panel when devices are offline, or allow them manually:

![Firewall setup in OmaConnect](preview1.png)

```bash
sudo ufw allow 1714:1764/tcp comment 'KDE Connect'
sudo ufw allow 1714:1764/udp comment 'KDE Connect'
sudo ufw reload
```

### Matching your Omarchy theme

OmaConnect's own panel is drawn with Omarchy's `qs.Ui` components, so it follows your theme already. The windows it opens do not: `kdeconnect-sms` and `kdeconnect-app` are Kirigami apps, and Kirigami takes its palette from `KColorScheme`, which reads `~/.config/kdeglobals`. `QT_QPA_PLATFORMTHEME` never reaches that palette, so with no `kdeglobals` present those apps fall back to Breeze *light* — a bright window on a dark desktop.

Click **Match Omarchy Theme** in the panel, or run it directly:

```bash
bash ~/.config/omarchy/plugins/omaconnect/scripts/setup_kde_theme.sh
```

It installs two ordinary Omarchy extension points and needs no root:

| File | Purpose |
| --- | --- |
| `~/.config/omarchy/themed/kdeglobals.tpl` | renders the active palette into KDE's color-scheme format |
| `~/.config/omarchy/hooks/theme-set.d/kde-globals` | installs the rendered file on every theme change |

Colors are derived from `colors.toml` keys that `omarchy-theme-color` resolves for every theme, and surfaces are mixed between `background` and `foreground` rather than hardcoded, so light themes stay light. Any existing `kdeglobals` is backed up first. Restart an open KDE app to pick up a new scheme — they read the palette once at startup.

Nothing here is specific to KDE Connect; Dolphin, Gwenview, Okular and Ark follow the theme too.

### Contact names in SMS

`kdeconnect-sms` lists every conversation by phone number unless the `kpeoplevcard` KPeople backend is installed. KDE Connect syncs your phone's address book into `~/.local/share/kpeoplevcard/kdeconnect-<device-id>/` as vCards, but nothing reads them without that backend.

It is an AUR package, so it is offered as an optional step by **Install Dependencies** rather than bundled with the required ones:

```bash
yay -S kpeoplevcard
```

Then enable the Contacts plugin in KDE Connect on Android and grant it the Contacts permission. Names appear after the next sync; restart `kdeconnect-sms` to pick them up.

## Update

```bash
omarchy plugin update omaconnect
```

## Remove

```bash
omarchy plugin remove omaconnect
```
