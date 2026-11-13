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

# ---- install ---------------------------------------------------------------
n=0
fresh() { # fresh: new empty dest and cache dirs
  n=$((n + 1)); dest="$work/dest$n"; cache="$work/cache$n"; mkdir -p "$dest" "$cache"
}
install() { bash "$script" install "$1" "$dest" "$cache" "${2:-skip}"; }
empty_dest() { [ -z "$(ls -A "$dest")" ]; }
no_leftovers() { [ -z "$(ls -A "$cache")" ]; }
code_is() { # code_is <archive> <code> [mode]: install fails with that error code
  fresh
  out=$(install "$1" "${3:-skip}"); status=$?
  [ "$status" -eq 1 ] && [ "$out" = "error	$2" ] && empty_dest && no_leftovers
}

fresh
out=$(install "$dl/Good.tar.gz")
check "install: installs a theme" test "$out" = "installed	Good"
check "install: files land in place" test -f "$dest/Good/cursors/left_ptr"
check "install: leaves no temp folder" no_leftovers

fresh
out=$(install "$dl/wrap.zip" | sort | tr '\n' ' ')
check "install: both themes of a wrapped zip" test "$out" = "installed	One installed	Two "

fresh
out=$(install "$dl/My Theme (v2) [x].tar.xz")
check "install: odd archive path works" test "$out" = "installed	T"

fresh
install "$dl/Good.tar.gz" >/dev/null; : > "$dest/Good/marker"
out=$(install "$dl/Good.tar.gz" skip)
check "install: skip reports the existing theme" test "$out" = "skipped	Good"
check "install: skip leaves it untouched" test -f "$dest/Good/marker"
out=$(install "$dl/Good.tar.gz" replace)
check "install: replace installs over it" test "$out" = "installed	Good"
check "install: replace drops the old files" test ! -e "$dest/Good/marker"
check "install: replace leaves no old copy" test "$(ls -A "$dest")" = "Good"

# Hostile or broken archives.
hs="$work/hostile"; mkdir -p "$hs"
tar -cf "$hs/dotdot.tar" --transform 's,^,../,' -C "$src/a" Good
tar -cPf "$hs/abs.tar" "$src/a/Good"
mktheme "$hs/l" Good/cursors/x; ln -s /etc "$hs/l/Good/cursors/out"
bsdtar -cf "$hs/symlink.tar" -C "$hs/l" Good
mktheme "$hs/f" Good/cursors/x; mkfifo "$hs/f/Good/cursors/pipe"
bsdtar -cf "$hs/fifo.tar" -C "$hs/f" Good
mktheme "$hs/r" Good/cursors/arrow; ln -s arrow "$hs/r/Good/cursors/left_ptr"
bsdtar -czf "$hs/relative.tar.gz" -C "$hs/r" Good
mktheme "$hs/z" Good/cursors/x; head -c 52428801 /dev/zero > "$hs/z/Good/cursors/big"
bsdtar -czf "$hs/bomb.tar.gz" -C "$hs/z" Good
mktheme "$hs/m" Good/cursors/x
i=0; while [ "$i" -le 2000 ]; do : > "$hs/m/Good/cursors/f$i"; i=$((i + 1)); done
bsdtar -czf "$hs/many.tar.gz" -C "$hs/m" Good
head -c 100 "$dl/Good.tar.gz" > "$hs/truncated.tar.gz"
mktheme "$hs/n" 'bad;name/cursors/x'
bsdtar -czf "$hs/badname.tar.gz" -C "$hs/n" 'bad;name'

check "install: rejects a ../ entry" code_is "$hs/dotdot.tar" unsafe
check "install: rejects an absolute entry" code_is "$hs/abs.tar" unsafe
check "install: rejects a link leaving the theme" code_is "$hs/symlink.tar" unsafe
check "install: rejects a FIFO" code_is "$hs/fifo.tar" unsafe
check "install: rejects a huge unpacked size" code_is "$hs/bomb.tar.gz" too-big
check "install: rejects too many files" code_is "$hs/many.tar.gz" too-big
check "install: reports a truncated archive" code_is "$hs/truncated.tar.gz" unreadable
check "install: rejects a root-level cursors folder" code_is "$dl/rootcursors.tar.gz" no-cursors
check "install: rejects a bad theme folder name" code_is "$hs/badname.tar.gz" unsafe
fresh
out=$(install "$hs/relative.tar.gz")
check "install: accepts a relative link inside a theme" test "$out" = "installed	Good"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
