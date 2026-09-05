#!/usr/bin/env bash
set -Eeuo pipefail

# Make KDE Frameworks apps follow the active Omarchy theme.
#
# OmaConnect's own panel is drawn with Omarchy's qs.Ui components, so it is
# themed already. The apps it launches are not: kdeconnect-sms and
# kdeconnect-app are Kirigami apps, and Kirigami takes its palette from
# KColorScheme, which reads ~/.config/kdeglobals. QT_QPA_PLATFORMTHEME never
# reaches that palette. With no kdeglobals present, KColorScheme falls back to
# Breeze *light* defaults -- a bright window on a dark desktop.
#
# This installs two files into the user's Omarchy config:
#
#   ~/.config/omarchy/themed/kdeglobals.tpl        renders the active palette
#   ~/.config/omarchy/hooks/theme-set.d/kde-globals installs it on theme change
#
# Both are plain Omarchy extension points, so the scheme is regenerated for
# whatever theme is set afterwards. Nothing here is specific to KDE Connect;
# dolphin, gwenview, okular and ark pick it up too.

plugin_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="$HOME/.config/omarchy"
themed_dir="$config_dir/themed"
hooks_dir="$config_dir/hooks/theme-set.d"
kdeglobals="$HOME/.config/kdeglobals"

template_src="$plugin_dir/assets/themed/kdeglobals.tpl"
hook_src="$plugin_dir/assets/hooks/theme-set.d/kde-globals"

cat <<'BANNER'
============================================================
        OmaConnect: match KDE apps to your Omarchy theme
============================================================
kdeconnect-sms and kdeconnect-app are KDE (Kirigami) apps. They
read their colors from ~/.config/kdeglobals, not from the Omarchy
theme, so without that file they render in Breeze light.

This installs an Omarchy theme template and a theme-set hook that
generate that file from your active theme, and keep it in sync
whenever you switch themes.

Files written:
  ~/.config/omarchy/themed/kdeglobals.tpl
  ~/.config/omarchy/hooks/theme-set.d/kde-globals
  ~/.config/kdeglobals            (generated; existing file backed up)

No root privileges are used.
============================================================
BANNER

if [[ ! -f $template_src || ! -f $hook_src ]]; then
    printf 'error: plugin assets missing under %s/assets\n' "$plugin_dir" >&2
    exit 1
fi

if [[ ! -x "$(command -v omarchy-theme-set 2>/dev/null || true)" ]]; then
    printf 'error: omarchy-theme-set not found; this needs Omarchy on PATH\n' >&2
    exit 1
fi

if [[ -t 0 ]]; then
    printf 'Press Enter to install, or Ctrl+C to cancel: '
    read -r _
fi

# An existing kdeglobals is almost always hand-written or Plasma-managed.
# Keep a dated copy rather than silently replacing someone's color scheme.
if [[ -f $kdeglobals && ! -L $kdeglobals ]]; then
    backup="$kdeglobals.omaconnect-backup.$(date +%Y%m%d%H%M%S)"
    cp -p "$kdeglobals" "$backup"
    printf 'Backed up existing kdeglobals to %s\n' "$backup"
fi

mkdir -p "$themed_dir" "$hooks_dir"
install -m 0644 "$template_src" "$themed_dir/kdeglobals.tpl"
install -m 0755 "$hook_src" "$hooks_dir/kde-globals"
printf 'Installed template and theme-set hook.\n'

# Templates are rendered by omarchy-theme-set, so re-apply the current theme to
# generate kdeglobals now instead of waiting for the next theme switch.
theme_name_file="$HOME/.local/state/omarchy/current/theme.name"
if [[ -r $theme_name_file ]]; then
    current_theme="$(tr -d '[:space:]' <"$theme_name_file")"
else
    current_theme=""
fi

if [[ -n $current_theme ]]; then
    printf 'Re-applying theme "%s" to render the color scheme...\n' "$current_theme"
    if omarchy-theme-set "$current_theme"; then
        printf 'Done.\n'
    else
        printf 'warning: could not re-apply the theme; switch themes once to generate the file\n' >&2
    fi
else
    printf 'Could not read the current theme name; switch themes once to generate the file.\n'
fi

if [[ -f $kdeglobals ]]; then
    printf '\nColor scheme active at %s\n' "$kdeglobals"
    printf 'Restart any open KDE app -- they read the palette once at startup.\n'
else
    printf '\nwarning: %s was not generated; check that your theme ships a colors.toml\n' "$kdeglobals" >&2
fi

if [[ -t 0 ]]; then
    sleep 2
fi

exit 0
