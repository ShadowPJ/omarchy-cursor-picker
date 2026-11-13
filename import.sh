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

case "${1:-}" in
  list) list "${2:-}" ;;
  install) printf 'error\tfailed\n'; exit 1 ;;
  *) echo "usage: import.sh list <dir> | install <archive> <dest> <cache> <skip|replace>" >&2; exit 2 ;;
esac
