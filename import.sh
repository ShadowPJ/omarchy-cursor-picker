#!/bin/bash
# Cursor Picker: find and install cursor themes from downloaded archives.
#
#   import.sh list <dir>
#       One line per archive in <dir> that holds a cursor theme, newest first:
#       path<TAB>bytes<TAB>theme1,theme2
#   import.sh install <archive> <destDir> <cacheDir> <skip|replace>
#       "installed<TAB>name", "skipped<TAB>name" or "error<TAB>code" lines.
#   import.sh fetch <https-url> <name|-> <destDir> <cacheDir> <skip|replace>
#       Downloads an archive into the cache, then installs it like `install`.
#   import.sh resolve <gnome-look page url>
#       Candidate archives on that page: name<TAB>sizeKB<TAB>link, or "error<TAB>code".
#
# Archives are read with bsdtar and never executed. The network is used only by
# fetch and resolve, for a URL the user pasted (see README, "Network").

set -u

MAX_ARCHIVE_BYTES=52428800
MAX_UNPACKED_BYTES=52428800
MAX_FILES=2000
MAX_INSPECTED=30
tmp=""        # temp folder of an install; global so the EXIT trap can see it
fetchdir=""   # temp folder of a download, same reason

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

MAX_DEPTH=12   # path segments; deeper entries create folders the listing never shows

# Starts bsdtar in the background and stops it as soon as the temp folder grows
# past the size or entry limits, so a lying archive cannot fill the disk.
extract_bounded() {
  local archive=$1 dir=$2 pid
  (trap "" XFSZ; ulimit -f $((MAX_UNPACKED_BYTES / 1024)); exec bsdtar -xf "$archive" \
     --no-same-owner --no-same-permissions -C "$dir" 2>/dev/null) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(du -sb "$dir" | cut -f1)" -gt "$MAX_UNPACKED_BYTES" ] ||
       [ "$(find "$dir" | wc -l)" -gt "$((MAX_FILES + 1))" ]; then
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 2
    fi
    sleep 0.05
  done
  wait "$pid" || return 1
  return 0
}

install() {
  local archive=${1:-} dest=${2:-} cache=${3:-} mode=${4:-}
  local listing tmpreal entry link target name src other old stage count slashes status moved=0
  local -a candidates=() themes=()

  [ -f "$archive" ] && [ -n "$dest" ] && [ -n "$cache" ] || fail failed
  case "$mode" in skip|replace) ;; *) fail failed ;; esac
  has_archive_extension "$archive" || fail unreadable
  [ "$(stat -c %s "$archive")" -le "$MAX_ARCHIVE_BYTES" ] || fail too-big

  # 1. Judge the archive from its listing, before extracting anything.
  listing=$(bsdtar -tf "$archive" 2>/dev/null) || fail unreadable
  while IFS= read -r entry; do
    entry=${entry#./}
    case "$entry" in /*|..|../*|*/..|*/../*) fail unsafe ;; esac
    slashes=${entry//[^\/]/}
    [ "${#slashes}" -le "$MAX_DEPTH" ] || fail unsafe
  done <<< "$listing"
  count=$(printf '%s\n' "$listing" | grep -c .)
  [ "$count" -le "$MAX_FILES" ] || fail too-big

  # 2. Extract into a private temp folder; never with -P, so bsdtar refuses
  # paths that climb out and links that redirect writes. The extraction is
  # watched and cut off if it outgrows the limits.
  mkdir -p "$cache" || fail failed
  tmp=$(mktemp -d "$cache/import.XXXXXX") || fail failed
  trap 'rm -rf "${tmp:-}" "${fetchdir:-}"' EXIT
  tmpreal=$(realpath "$tmp")
  extract_bounded "$archive" "$tmp"; status=$?
  [ "$status" -eq 2 ] && fail too-big
  if [ "$status" -ne 0 ]; then
    # A file cut off at the size limit means the archive was too big, not broken.
    [ -z "$(find "$tmp" -type f -size +$((MAX_UNPACKED_BYTES - 1))c -print -quit)" ] || fail too-big
    fail unreadable
  fi

  # 3. Check what actually landed on disk.
  [ -z "$(find "$tmp" ! -type f ! -type d ! -type l -print -quit)" ] || fail unsafe
  [ "$(du -sb "$tmp" | cut -f1)" -le "$MAX_UNPACKED_BYTES" ] || fail too-big
  [ "$(find "$tmp" | wc -l)" -le "$((MAX_FILES + 1))" ] || fail too-big

  # 4. Theme folders: a "cursors" folder one or two levels down. A folder
  # inside another theme is part of it, not a second theme.
  while IFS= read -r -d '' src; do candidates+=("$src"); done \
    < <(find "$tmp" -mindepth 2 -maxdepth 3 -type d -name cursors -printf '%h\0')
  for src in "${candidates[@]:-}"; do
    [ -n "$src" ] || continue
    for other in "${candidates[@]}"; do
      case "$src" in "$other"/*) continue 2 ;; esac
    done
    name=${src##*/}
    valid_theme_name "$name" || fail unsafe
    for entry in "${themes[@]:-}"; do [ "${entry##*/}" = "$name" ] && continue 2; done
    themes+=("$src")
  done
  [ "${#themes[@]}" -gt 0 ] || fail no-cursors

  # Every link must still point inside its own theme once the folder has moved.
  for src in "${themes[@]}"; do
    while IFS= read -r -d '' link; do
      target=$(realpath -m -- "$link")
      case "$target" in "$(realpath "$src")"/*) ;; *) fail unsafe ;; esac
    done < <(find "$src" -type l -print0)
  done

  # 5. Move them in. Each theme is staged next to its destination first, so the
  # final swap is a rename on one filesystem. An existing theme is kept on
  # skip; on replace the old folder stays until the new one is in place.
  mkdir -p "$dest" || fail failed
  for src in "${themes[@]}"; do
    name=${src##*/}
    if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
      if [ "$mode" = skip ]; then printf 'skipped\t%s\n' "$name"; moved=1; continue; fi
    fi
    stage="$dest/.$name.new.$$"
    rm -rf -- "$stage"
    mv -- "$src" "$stage" || { rm -rf -- "$stage"; fail failed; }
    chmod -R u+rwX,go+rX -- "$stage"
    if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
      old="$dest/.$name.old.$$"
      mv -- "$dest/$name" "$old" || { rm -rf -- "$stage"; fail failed; }
      mv -- "$stage" "$dest/$name" || { mv -- "$old" "$dest/$name"; rm -rf -- "$stage"; fail failed; }
      rm -rf -- "$old"
    else
      mv -- "$stage" "$dest/$name" || { rm -rf -- "$stage"; fail failed; }
    fi
    printf 'installed\t%s\n' "$name"
    moved=1
  done
  [ "$moved" -eq 1 ] || fail failed
  return 0
}


# ---- network: fetch and resolve -------------------------------------------
# CURSOR_PICKER_ALLOW_HTTP and CURSOR_PICKER_API_BASE (honoured only with ALLOW_HTTP) exist for the tests only:
# the panel never sets them, and without ALLOW_HTTP only https is accepted.
API_BASE=https://api.opendesktop.org
[ "${CURSOR_PICKER_ALLOW_HTTP:-}" = 1 ] && API_BASE=${CURSOR_PICKER_API_BASE:-$API_BASE}
SAFE_NAME='^[A-Za-z0-9][A-Za-z0-9._+ ()-]*$'

curl_safe() {
  local proto='=https'
  [ "${CURSOR_PICKER_ALLOW_HTTP:-}" = 1 ] && proto='=http,https'
  curl -q --silent --show-error --globoff --location --fail --proto "$proto" --proto-redir "$proto" \
       --max-redirs 5 --connect-timeout 15 "$@"
}

valid_url() {
  local url=$1 rest authority
  [ "${#url}" -le 2048 ] || return 1
  [[ $url =~ [[:space:][:cntrl:]] ]] && return 1
  [[ $url == *[\{\}\[\]\\]* ]] && return 1   # no globbing, no backslashes
  if [ "${CURSOR_PICKER_ALLOW_HTTP:-}" = 1 ]; then
    [[ $url == http://* || $url == https://* ]] || return 1
    rest=${url#*://}
  else
    [[ $url == https://* ]] || return 1
    rest=${url#https://}
  fi
  authority=${rest%%[/?#]*}
  [ -n "$authority" ] && [[ $authority != *@* && $authority != -* ]]
}

# The file name for a download: the given one, or the last path segment of the URL.
download_name() {
  local url=$1 given=$2 path name
  if [ "$given" != "-" ]; then name=$given; else
    path=${url#*://}; path=${path#*/}; path=${path%%[?#]*}; name=${path##*/}
    name=${name//%20/ }
  fi
  [ "${#name}" -le 150 ] && [[ $name =~ $SAFE_NAME ]] || return 1
  printf '%s' "$name"
}

fetch() {
  local url=${1:-} given=${2:--} dest=${3:-} cache=${4:-} mode=${5:-} name file status
  [ -n "$dest" ] && [ -n "$cache" ] || fail failed
  case "$mode" in skip|replace) ;; *) fail failed ;; esac
  valid_url "$url" || fail bad-url
  if [ "$given" != "-" ]; then name=$(download_name "$url" "$given") || fail bad-url
  else name=$(download_name "$url" "-") || fail not-archive; fi
  has_archive_extension "$name" || fail not-archive
  command -v curl >/dev/null || fail download-failed

  mkdir -p "$cache" || fail failed
  fetchdir=$(mktemp -d "$cache/fetch.XXXXXX") || fail failed
  trap 'rm -rf "${tmp:-}" "${fetchdir:-}"' EXIT
  file="$fetchdir/$name"
  # --max-filesize needs a Content-Length; ulimit -f stops a response without one.
  # XFSZ is ignored so the write just fails (no kill, no core dump, no crash popup).
  (trap "" XFSZ; ulimit -f $((MAX_ARCHIVE_BYTES / 1024 + 1)); curl_safe --max-time 120 \
     --max-filesize "$MAX_ARCHIVE_BYTES" -o "$file" -- "$url") 2>/dev/null
  status=$?
  case "$status" in
    0) ;;
    23|63|152|153) fail too-big ;;
    *) fail download-failed ;;
  esac
  [ -s "$file" ] || fail download-failed
  install "$file" "$dest" "$cache" "$mode"
}

resolve() {
  local url=${1:-} id json line name size link low
  local -a good=() last=()
  local re='^https://(www\.)?(gnome-look\.org|pling\.com|opendesktop\.org)(/s/[A-Za-z0-9_-]+)?/p/([0-9]{1,12})/?([?#].*)?$'
  [[ $url =~ $re ]] || fail bad-url
  id=${BASH_REMATCH[4]}
  command -v jq >/dev/null && command -v curl >/dev/null || fail no-download

  json=$(trap "" XFSZ; ulimit -f 4096; curl_safe --max-time 30 --max-filesize 2097152 -- \
           "$API_BASE/ocs/v1/content/data/$id?format=json" 2>/dev/null) || fail no-download
  # Up to 30 numbered download entries; tab-separated, one per line.
  json=$(printf '%s' "$json" | jq -r '
      (.data[0] // empty) as $d | range(1; 31) |
      [($d["downloadname\(.)"] // ""), (($d["downloadsize\(.)"] // "0") | tostring), ($d["downloadlink\(.)"] // "")] | @tsv' \
      2>/dev/null) || fail no-download

  while IFS=$'\t' read -r name size link; do
    [ -n "$name" ] && [ -n "$link" ] || continue
    [ "${#name}" -le 150 ] && [[ $name =~ $SAFE_NAME ]] || continue
    has_archive_extension "$name" || continue
    [[ $size =~ ^[0-9]{1,9}$ ]] && [ "$size" -le $((MAX_ARCHIVE_BYTES / 1024)) ] || continue
    if [ "${CURSOR_PICKER_ALLOW_HTTP:-}" = 1 ]; then
      [[ $link =~ ^https?://(127\.0\.0\.1:[0-9]+|files[0-9]*\.pling\.com|dl\.opendesktop\.org)/ ]] || continue
    else
      [[ $link =~ ^https://(files[0-9]*\.pling\.com|dl\.opendesktop\.org)/ ]] || continue
    fi
    valid_url "$link" || continue
    low=${name,,}
    if [[ $low == *windows* || $low == *win32* || $low == *win64* ]]; then last+=("$name"$'\t'"$size"$'\t'"$link")
    else good+=("$name"$'\t'"$size"$'\t'"$link"); fi
  done <<< "$json"

  [ "$(( ${#good[@]} + ${#last[@]} ))" -gt 0 ] || fail no-download
  for line in "${good[@]}" "${last[@]}"; do printf '%s\n' "$line"; done
}

case "${1:-}" in
  list) list "${2:-}" ;;
  install) shift; install "$@" ;;
  fetch) shift; fetch "$@" ;;
  resolve) resolve "${2:-}" ;;
  *) echo "usage: import.sh list <dir> | install <archive> <dest> <cache> <skip|replace> | fetch <url> <name|-> <dest> <cache> <mode> | resolve <page url>" >&2; exit 2 ;;
esac
