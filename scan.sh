#!/bin/sh
# Lists installed cursor themes as "id<TAB>name<TAB>dir" and, when xcur2png is
# available, caches a PNG preview of each one's arrow in $1 (the cache dir).
cache="$1"
mkdir -p "$cache" 2>/dev/null
data="${XDG_DATA_HOME:-$HOME/.local/share}"
set -- "$HOME/.icons" "$data/icons"
oldifs="$IFS"; IFS=:
for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do set -- "$@" "$d/icons"; done
IFS="$oldifs"
set -- "$@" /usr/share/icons
for root in "$@"; do
  [ -d "$root" ] || continue
  for theme in "$root"/*/; do
    theme="${theme%/}"
    [ -d "$theme/cursors" ] || continue
    id="${theme##*/}"
    name=""
    [ -r "$theme/index.theme" ] && name=$(sed -n 's/^Name=//p' "$theme/index.theme" | head -n1)
    printf '%s\t%s\t%s\n' "$id" "${name:-$id}" "$theme"
    png="$cache/$id.png"
    if [ ! -s "$png" ] && command -v xcur2png >/dev/null 2>&1; then
      tmp=$(mktemp -d "$cache/.tmp.XXXXXX") || continue
      for shape in left_ptr default arrow; do
        [ -e "$theme/cursors/$shape" ] || continue
        xcur2png -q -d "$tmp" -c /dev/null "$theme/cursors/$shape" >/dev/null 2>&1
        best=$(ls -S "$tmp"/*.png 2>/dev/null | head -n1)
        [ -n "$best" ] && { mv "$best" "$png"; break; }
      done
      rm -rf "$tmp"
    fi
  done
done
