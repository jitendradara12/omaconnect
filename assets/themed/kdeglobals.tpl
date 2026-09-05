# Omarchy user template: KDE / Kirigami color scheme (installed by OmaConnect)
#
# Qt apps built on KDE Frameworks (kdeconnect-sms, kdeconnect-app, dolphin,
# gwenview, okular, ark, ...) do NOT take their colors from QT_QPA_PLATFORMTHEME.
# Kirigami and KColorScheme read ~/.config/kdeglobals, and when that file is
# missing they fall back to Breeze *light* defaults -- which is why a KDE app
# shows up as a bright window on an otherwise dark Omarchy desktop.
#
# This template renders the active Omarchy palette into that file's format, so
# KDE apps track whatever theme is set. The companion hook
# ~/.config/omarchy/hooks/theme-set.d/kde-globals copies the rendered result
# into place on every theme change.
#
# Everything is derived from colors.toml keys that omarchy-theme-color resolves
# for every theme, and surfaces are mixed between background and foreground
# rather than hardcoded, so the scheme stays correct for light themes too.

[General]
ColorScheme=Omarchy
shadeSortColumn=true

[KDE]
contrast=4

[Colors:Window]
BackgroundNormal={{ background_rgb }}
BackgroundAlternate={{ mix_rgb background foreground 7 }}
ForegroundNormal={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:View]
BackgroundNormal={{ mix_rgb background foreground 4 }}
BackgroundAlternate={{ mix_rgb background foreground 8 }}
ForegroundNormal={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:Button]
BackgroundNormal={{ mix_rgb background foreground 12 }}
BackgroundAlternate={{ mix_rgb background foreground 18 }}
ForegroundNormal={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:Selection]
BackgroundNormal={{ accent_rgb }}
BackgroundAlternate={{ accent_rgb }}
ForegroundNormal={{ background_rgb }}
ForegroundInactive={{ mix_rgb background accent 30 }}
ForegroundActive={{ background_rgb }}
ForegroundLink={{ background_rgb }}
ForegroundVisited={{ background_rgb }}
ForegroundNegative={{ background_rgb }}
ForegroundNeutral={{ background_rgb }}
ForegroundPositive={{ background_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:Tooltip]
BackgroundNormal={{ mix_rgb background foreground 14 }}
BackgroundAlternate={{ mix_rgb background foreground 20 }}
ForegroundNormal={{ bright_foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:Complementary]
BackgroundNormal={{ mix_rgb background foreground 6 }}
BackgroundAlternate={{ mix_rgb background foreground 12 }}
ForegroundNormal={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:Header]
BackgroundNormal={{ mix_rgb background foreground 6 }}
BackgroundAlternate={{ mix_rgb background foreground 10 }}
ForegroundNormal={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[Colors:Header][Inactive]
BackgroundNormal={{ mix_rgb background foreground 4 }}
BackgroundAlternate={{ mix_rgb background foreground 8 }}
ForegroundNormal={{ muted_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundActive={{ accent_rgb }}
ForegroundLink={{ blue_rgb }}
ForegroundVisited={{ magenta_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ yellow_rgb }}
ForegroundPositive={{ green_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}

[WM]
activeBackground={{ mix_rgb background foreground 6 }}
activeForeground={{ bright_foreground_rgb }}
activeBlend={{ accent_rgb }}
inactiveBackground={{ background_rgb }}
inactiveForeground={{ muted_rgb }}
inactiveBlend={{ background_rgb }}

[ColorEffects:Disabled]
Color={{ muted_rgb }}
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color={{ muted_rgb }}
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0
