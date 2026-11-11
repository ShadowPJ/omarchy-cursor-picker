#!/bin/sh
# apply.sh <theme> <size>: switch the cursor everywhere it can be switched live.
theme="$1"; size="$2"
hyprctl setcursor "$theme" "$size" >/dev/null 2>&1
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface cursor-theme "$theme" 2>/dev/null
  gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null
fi
exit 0
