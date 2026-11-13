#!/bin/bash
# Cursor Picker: find and install cursor themes from downloaded archives.
#
#   import.sh list <dir>
#       One line per archive in <dir> that holds a cursor theme, newest first:
#       path<TAB>bytes<TAB>theme1,theme2
#   import.sh install <archive> <destDir> <cacheDir> <skip|replace>
#       "installed<TAB>name", "skipped<TAB>name" or "error<TAB>code" lines.
#
# Archives are read with bsdtar and never executed. Nothing here uses the network.

set -u

MAX_ARCHIVE_BYTES=52428800
MAX_UNPACKED_BYTES=52428800
MAX_FILES=2000
MAX_INSPECTED=30
tmp=""   # temp folder of an install; global so the EXIT trap can see it

has_archive_extension() {
  case "${1,,}" in
    *.tar.gz|*.tgz|*.tar.xz|*.tar.bz2|*.tar.zst|*.zip|*.7z) return 0 ;;
  esac
  return 1
}

# Reads `bsdtar -tf` output on stdin and prints the theme folders found one or
# two levels deep ("Theme/cursors/..." or "wrapper/Theme/cursors/..."), comma
# separated. An unsafe entry (absolute path, ".." segment) prints nothing.
themes_in_listing() {
  awk '
    {
      entry = $0
      sub(/^\.\//, "", entry)
      if (entry ~ /^\// || entry ~ /(^|\/)\.\.(\/|$)/) { unsafe = 1; exit }
      n = split(entry, f, "/")
      name = ""
      if (n >= 3 && f[2] == "cursors") name = f[1]
      else if (n >= 4 && f[3] == "cursors") name = f[2]
      if (name == "" || name ~ /[,\t]/ || seen[name]++) next
      order[++count] = name
    }
    END {
      if (unsafe || count == 0) exit
      for (i = 1; i <= count; i++) printf "%s%s", (i > 1 ? "," : ""), order[i]
      printf "\n"
    }'
}

list() {
  local dir=$1 stamp size path themes inspected=0
  [ -d "$dir" ] || return 0
  while IFS=$'\t' read -r -d '' stamp size path; do
    [ "$inspected" -ge "$MAX_INSPECTED" ] && break
    has_archive_extension "$path" || continue
    case "$path" in *$'\t'*|*$'\n'*) continue ;; esac
    inspected=$((inspected + 1))
    themes=$(timeout 5 bsdtar -tf "$path" 2>/dev/null | themes_in_listing)
    [ -n "$themes" ] && printf '%s\t%s\t%s\n' "$path" "$size" "$themes"
  done < <(find "$dir" -maxdepth 1 -type f -size -$((MAX_ARCHIVE_BYTES + 1))c \
             -printf '%T@\t%s\t%p\0' 2>/dev/null | sort -z -rn)
  return 0
}

fail() {
  printf 'error\t%s\n' "$1"
  exit 1
}

# Same rule as validId in CursorModel.js.
valid_theme_name() {
  [ "${#1}" -le 200 ] && [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+\ -]*$ ]]
}

install() {
  local archive=${1:-} dest=${2:-} cache=${3:-} mode=${4:-}
  local listing tmpreal entry link target name src old count total moved=0
  local -a themes=()

  [ -f "$archive" ] && [ -n "$dest" ] && [ -n "$cache" ] || fail failed
  case "$mode" in skip|replace) ;; *) fail failed ;; esac

  # 1. Judge the archive from its listing, before extracting anything.
  listing=$(bsdtar -tf "$archive" 2>/dev/null) || fail unreadable
  while IFS= read -r entry; do
    entry=${entry#./}
    case "$entry" in /*|..|../*|*/..|*/../*) fail unsafe ;; esac
  done <<< "$listing"
  count=$(printf '%s\n' "$listing" | grep -c .)
  [ "$count" -le "$MAX_FILES" ] || fail too-big
  total=$(bsdtar -tvf "$archive" 2>/dev/null | awk '$5 ~ /^[0-9]+$/ { sum += $5 } END { print sum + 0 }')
  [ "$total" -le "$MAX_UNPACKED_BYTES" ] || fail too-big

  # 2. Extract into a private temp folder; never with -P, so bsdtar refuses
  # paths that climb out and links that redirect writes.
  mkdir -p "$cache" || fail failed
  tmp=$(mktemp -d "$cache/import.XXXXXX") || fail failed
  trap 'rm -rf "${tmp:-}"' EXIT
  tmpreal=$(realpath "$tmp")
  (ulimit -f $((MAX_UNPACKED_BYTES / 512)); \
    bsdtar -xf "$archive" --no-same-owner --no-same-permissions -C "$tmp" 2>/dev/null) || fail unreadable

  # 3. Check what actually landed on disk.
  [ -z "$(find "$tmp" ! -type f ! -type d ! -type l -print -quit)" ] || fail unsafe
  while IFS= read -r -d '' link; do
    target=$(realpath -m -- "$link")
    case "$target" in "$tmpreal"/*) ;; *) fail unsafe ;; esac
  done < <(find "$tmp" -type l -print0)
  [ "$(du -sb "$tmp" | cut -f1)" -le "$MAX_UNPACKED_BYTES" ] || fail too-big
  [ "$(find "$tmp" | wc -l)" -le "$((MAX_FILES + 1))" ] || fail too-big

  # 4. Theme folders: a "cursors" folder one or two levels down.
  while IFS= read -r -d '' src; do
    name=${src##*/}
    valid_theme_name "$name" || fail unsafe
    for entry in "${themes[@]:-}"; do [ "${entry##*/}" = "$name" ] && continue 2; done
    themes+=("$src")
  done < <(find "$tmp" -mindepth 2 -maxdepth 3 -type d -name cursors -printf '%h\0')
  [ "${#themes[@]}" -gt 0 ] || fail no-cursors

  # 5. Move them in. An existing theme is kept on skip; on replace the old
  # folder stays until the new one is in place.
  mkdir -p "$dest" || fail failed
  for src in "${themes[@]}"; do
    name=${src##*/}
    if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
      if [ "$mode" = skip ]; then printf 'skipped\t%s\n' "$name"; moved=1; continue; fi
      old="$dest/.$name.old.$$"
      mv -- "$dest/$name" "$old" || fail failed
      mv -- "$src" "$dest/$name" || { mv -- "$old" "$dest/$name"; fail failed; }
      rm -rf -- "$old"
    else
      mv -- "$src" "$dest/$name" || fail failed
    fi
    chmod -R u+rwX,go+rX -- "$dest/$name"
    printf 'installed\t%s\n' "$name"
    moved=1
  done
  [ "$moved" -eq 1 ] || fail failed
  return 0
}

case "${1:-}" in
  list) list "${2:-}" ;;
  install) shift; install "$@" ;;
  *) echo "usage: import.sh list <dir> | install <archive> <dest> <cache> <skip|replace>" >&2; exit 2 ;;
esac
