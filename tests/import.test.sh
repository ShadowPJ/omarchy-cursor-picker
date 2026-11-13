#!/bin/sh
# Tests for import.sh. Run: bash tests/import.test.sh
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/import.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

ok()   { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { # check <name> <command...>: passes when the command succeeds
  name=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
mktheme() { # mktheme <root> <path-under-root>: a file at <root>/<path>
  mkdir -p "$1/$(dirname "$2")" && printf 'x' > "$1/$2"
}

# ---- list ------------------------------------------------------------------
dl="$work/dl"; mkdir -p "$dl"
src="$work/src"; mkdir -p "$src"

mktheme "$src/a" Good/cursors/left_ptr
bsdtar -czf "$dl/Good.tar.gz" -C "$src/a" Good

mktheme "$src/b" pack/One/cursors/x
mktheme "$src/b" pack/Two/cursors/x
bsdtar -a -cf "$dl/wrap.zip" -C "$src/b" pack

mktheme "$src/c" T/cursors/x
bsdtar -cJf "$dl/My Theme (v2) [x].tar.xz" -C "$src/c" T

mktheme "$src/d" other/readme
bsdtar -a -cf "$dl/nocursors.zip" -C "$src/d" other

mktheme "$src/e" cursors/x
bsdtar -czf "$dl/rootcursors.tar.gz" -C "$src/e" cursors

printf 'hi' > "$dl/notes.txt"
truncate -s 51M "$dl/big.tar.gz"

out=$(bash "$script" list "$dl")

check "list: finds Good.tar.gz with its theme" sh -c 'printf "%s\n" "$1" | grep -q "^.*/Good.tar.gz	[0-9]*	Good$"' _ "$out"
check "list: finds both themes of a wrapped zip" sh -c 'printf "%s\n" "$1" | grep -q "/wrap.zip	[0-9]*	One,Two$"' _ "$out"
check "list: keeps an odd path intact" sh -c 'printf "%s\n" "$1" | grep -qF "/My Theme (v2) [x].tar.xz	"' _ "$out"
check "list: skips archives without cursors" sh -c '! printf "%s\n" "$1" | grep -q "nocursors.zip"' _ "$out"
check "list: skips a root-level cursors folder" sh -c '! printf "%s\n" "$1" | grep -q "rootcursors"' _ "$out"
check "list: skips non-archives" sh -c '! printf "%s\n" "$1" | grep -q "notes.txt"' _ "$out"
check "list: skips archives over 50 MB" sh -c '! printf "%s\n" "$1" | grep -q "big.tar.gz"' _ "$out"
check "list: three candidates in all" test "$(printf '%s\n' "$out" | grep -c .)" = 3
missing=$(bash "$script" list "$work/nope"; echo "exit=$?")
check "list: missing dir prints nothing and exits 0" test "$missing" = "exit=0"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
