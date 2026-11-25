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
tar -czf "$hs/dotdot.tar.gz" --transform 's,^,../,' -C "$src/a" Good
tar -czPf "$hs/abs.tar.gz" "$src/a/Good"
mktheme "$hs/l" Good/cursors/x; ln -s /etc "$hs/l/Good/cursors/out"
bsdtar -czf "$hs/symlink.tar.gz" -C "$hs/l" Good
mktheme "$hs/f" Good/cursors/x; mkfifo "$hs/f/Good/cursors/pipe"
bsdtar -czf "$hs/fifo.tar.gz" -C "$hs/f" Good
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

check "install: rejects a ../ entry" code_is "$hs/dotdot.tar.gz" unsafe
check "install: rejects an absolute entry" code_is "$hs/abs.tar.gz" unsafe
check "install: rejects a link leaving the theme" code_is "$hs/symlink.tar.gz" unsafe
check "install: rejects a FIFO" code_is "$hs/fifo.tar.gz" unsafe
check "install: rejects a huge unpacked size" code_is "$hs/bomb.tar.gz" too-big
check "install: rejects too many files" code_is "$hs/many.tar.gz" too-big
check "install: reports a truncated archive" code_is "$hs/truncated.tar.gz" unreadable
check "install: rejects a root-level cursors folder" code_is "$dl/rootcursors.tar.gz" no-cursors
check "install: rejects a bad theme folder name" code_is "$hs/badname.tar.gz" unsafe
fresh
out=$(install "$hs/relative.tar.gz")
check "install: accepts a relative link inside a theme" test "$out" = "installed	Good"

# ---- review fixes ----------------------------------------------------------
rv="$work/review"; mkdir -p "$rv"

# Links must stay inside their own theme once installed, not just inside the temp folder.
mktheme "$rv/w" w/Good/cursors/x; ln -s ../../../victim/key "$rv/w/w/Good/cursors/esc"
bsdtar -czf "$rv/escape-wrapped.tar.gz" -C "$rv/w" w
mktheme "$rv/u" Good/cursors/x; mktheme "$rv/u" Other/cursors/x; ln -s ../../Other/cursors/x "$rv/u/Good/cursors/esc"
bsdtar -czf "$rv/escape-sibling.tar.gz" -C "$rv/u" Good Other
check "install: rejects a link that escapes its theme (wrapped)" code_is "$rv/escape-wrapped.tar.gz" unsafe
check "install: rejects a link into a sibling theme" code_is "$rv/escape-sibling.tar.gz" unsafe

# A size header that lies (owner name with a space) must not let a big archive through.
mkdir -p "$rv/lie/Good/cursors"
for k in 1 2 3; do head -c 41943040 /dev/zero > "$rv/lie/Good/cursors/b$k"; done
tar --owner='a b' --group='c d' -cJf "$rv/lie.tar.xz" -C "$rv/lie" Good
check "install: rejects an archive whose size headers lie" code_is "$rv/lie.tar.xz" too-big

# Very deep folders create thousands of inodes from a few entries.
deep=$(printf 'd/%.0s' $(seq 1 1900)); mkdir -p "$rv/dp/Good/cursors/$deep"; : > "$rv/dp/Good/cursors/${deep}f"
bsdtar -czf "$rv/deep.tar.gz" -C "$rv/dp" Good
check "install: rejects absurdly deep paths" code_is "$rv/deep.tar.gz" unsafe

# A theme folder inside another theme is not a second theme.
mktheme "$rv/nest" A/cursors/x; mktheme "$rv/nest" A/B/cursors/y
bsdtar -czf "$rv/nested.tar.gz" -C "$rv/nest" A
fresh; out=$(install "$rv/nested.tar.gz")
check "install: nested theme folders install only the outer theme" test "$out" = "installed	A"
check "install: the inner folder stays inside the outer theme" test -f "$dest/A/B/cursors/y"

# install enforces the archive size and extension, not only list.
check "install: rejects an archive over 50 MB" code_is "$dl/big.tar.gz" too-big
check "install: rejects a non-archive extension" code_is "$dl/notes.txt" unreadable

# Odd names, other formats, empty and corrupt folders.
od="$rv/odd"; mkdir -p "$od"; mktheme "$rv/o" Odd/cursors/x
bsdtar -czf "$od/it's \"q\" \$(id) *.tar.gz" -C "$rv/o" Odd
bsdtar -c --format 7zip -f "$od/-rf ñandú.(ES).[x].7z" -C "$rv/o" Odd
bsdtar --zstd -cf "$od/z.tar.zst" -C "$rv/o" Odd
bsdtar -cjf "$od/b.tar.bz2" -C "$rv/o" Odd
bsdtar -a -cf "$od/z.zip" -C "$rv/o" Odd
listed=$(bash "$script" list "$od")
check "list: finds every format and odd name" test "$(printf '%s\n' "$listed" | grep -c .)" = 5
for f in "it's \"q\" \$(id) *.tar.gz" "-rf ñandú.(ES).[x].7z" z.tar.zst b.tar.bz2 z.zip; do
  fresh; out=$(install "$od/$f")
  check "install: $f" test "$out" = "installed	Odd"
done
mkdir -p "$rv/empty"
check "list: an empty folder prints nothing" test -z "$(bash "$script" list "$rv/empty")"
mkdir -p "$rv/corrupt"; head -c 100 "$dl/Good.tar.gz" > "$rv/corrupt/c.tar.gz"
check "list: a corrupt archive is skipped without failing" test -z "$(bash "$script" list "$rv/corrupt")"

# ---- fetch / resolve (network code, tested against a local server) ----------
web="$work/web"; mkdir -p "$web/ocs/v1/content/data"
mktheme "$work/n" Net/cursors/left_ptr; bsdtar -czf "$web/Net.tar.gz" -C "$work/n" Net
mktheme "$work/m" Win/cursors/x; bsdtar -a -cf "$web/Net-Windows.zip" -C "$work/m" Win
head -c 60000000 /dev/zero > "$web/huge.tar.gz"
printf 'not an archive' > "$web/page.html"
python3 -I "$here/tests/serve.py" "$web" > "$work/port" 2>/dev/null &
srv=$!; trap 'kill $srv 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
base="http://127.0.0.1:$(cat "$work/port")"
net() { CURSOR_PICKER_ALLOW_HTTP=1 CURSOR_PICKER_API_BASE="$base" bash "$script" "$@"; }
fetch() { net fetch "$1" "${2:--}" "$dest" "$cache" "${3:-skip}"; }
fcode_is() { out=$(fetch "$@") ; [ "$out" = "error	$FCODE" ]; }

fresh; out=$(fetch "$base/Net.tar.gz")
check "fetch: downloads and installs a direct link" test "$out" = "installed	Net"
check "fetch: the theme is in the destination" test -f "$dest/Net/cursors/left_ptr"
check "fetch: leaves nothing in the cache" test -z "$(ls -A "$cache")"
fresh; out=$(fetch "$base/Net.tar.gz?token=abc&x=1#frag")
check "fetch: ignores query and fragment when naming the file" test "$out" = "installed	Net"
out=$(fetch "$base/Net.tar.gz")
check "fetch: second time is skipped" test "$out" = "skipped	Net"
fresh; out=$(fetch "$base/Net.tar.gz" - replace); fresh
check "fetch: replace mode works" test "$out" = "installed	Net"
cp "$web/Net.tar.gz" "$web/download"
fresh; out=$(fetch "$base/download?id=1" "Net.tar.gz")
check "fetch: uses the given name when the URL has none" test "$out" = "installed	Net"
FCODE=not-archive;      check "fetch: rejects a URL whose name is not an archive" fcode_is "$base/page.html"
FCODE=download-failed;  check "fetch: a 404 is download-failed" fcode_is "$base/missing.tar.gz"
FCODE=too-big;          check "fetch: rejects a download over 50 MB" fcode_is "$base/huge.tar.gz"
FCODE=bad-url
for u in "$base/Net.tar.gz?a={1,2,3}" "$base/Net.tar.gz?a=[1-4]" "https://{a,b}.example.com/x.tar.gz" "ftp://example.com/a.tar.gz" "https://user:pw@example.com/a.tar.gz" "https://example.com/a b.tar.gz" \
         "https:///a.tar.gz" "$(printf 'https://example.com/a\n.tar.gz')" "-o/etc/x" "file:///etc/passwd" \
         "https://example.com/$(head -c 3000 /dev/zero | tr '\0' a).tar.gz"; do
  fresh; out=$(bash "$script" fetch "$u" - "$dest" "$cache" skip)
  check "fetch: rejects URL ${u:0:40}" test "$out" = "error	bad-url"
done
fresh; out=$(bash "$script" fetch "http://127.0.0.1:1/a.tar.gz" - "$dest" "$cache" skip)
check "fetch: plain http is rejected without the test switch" test "$out" = "error	bad-url"
fresh; out=$(fetch "$base/Net.tar.gz" "../evil.tar.gz")
check "fetch: a glob URL sent no request" test -z "$(ls "$cache")"
check "resolve: the API base override is ignored without the test switch" \
  test "$(CURSOR_PICKER_API_BASE="$base" bash "$script" resolve https://www.gnome-look.org/p/111 2>/dev/null | grep -c Net.tar.gz)" = 0
check "fetch: a name with a slash is rejected" test "$out" = "error	bad-url"
check "fetch: nothing was written outside the cache" test ! -e "$dest/../evil.tar.gz"

# resolve: a gnome-look page → candidate archives from the (fake) OCS API
api() { printf '%s' "$2" > "$web/ocs/v1/content/data/$1"; }
api 111 "{\"data\":[{\"downloadname1\":\"Info\",\"downloadsize1\":\"1\",\"downloadlink1\":\"$base/page.html\",
 \"downloadname2\":\"Net-Windows.zip\",\"downloadsize2\":\"5\",\"downloadlink2\":\"$base/Net-Windows.zip\",
 \"downloadname3\":\"Net.tar.gz\",\"downloadsize3\":\"2\",\"downloadlink3\":\"$base/Net.tar.gz\",
 \"downloadname4\":\"Big.tar.xz\",\"downloadsize4\":\"60000\",\"downloadlink4\":\"$base/Net.tar.gz\",
 \"downloadname5\":\"Evil.tar.gz\",\"downloadsize5\":\"2\",\"downloadlink5\":\"https://evil.example.com/x.tar.gz\",
 \"downloadname7\":\"Glob.tar.gz\",\"downloadsize7\":\"2\",\"downloadlink7\":\"$base/Net.tar.gz?a=[1-9]\",
 \"downloadname6\":\"../up.tar.gz\",\"downloadsize6\":\"2\",\"downloadlink6\":\"$base/Net.tar.gz\"}]}"
api 222 '{"data":[{"downloadname1":"Readme.txt","downloadsize1":"1","downloadlink1":"x"}]}'
api 333 'this is not json'
res=$(net resolve "https://www.gnome-look.org/p/111/")
check "resolve: keeps archives, drops info, big, foreign-host and odd names" test "$(printf '%s\n' "$res" | wc -l)" = 2
check "resolve: puts the Windows archive last" test "$(printf '%s\n' "$res" | head -1 | cut -f1)" = "Net.tar.gz"
check "resolve: prints name, size in KB and link" test "$(printf '%s\n' "$res" | head -1)" = "Net.tar.gz	2	$base/Net.tar.gz"
check "resolve: accepts the /s/Gnome prefix and a query" test -n "$(net resolve 'https://www.pling.com/s/Gnome/p/111?x=1#y' | grep Net.tar.gz)"
check "resolve: a page with no archives is no-download" test "$(net resolve https://www.gnome-look.org/p/222)" = "error	no-download"
check "resolve: invalid JSON is no-download" test "$(net resolve https://www.gnome-look.org/p/333)" = "error	no-download"
check "resolve: an unknown item is no-download" test "$(net resolve https://www.gnome-look.org/p/999)" = "error	no-download"
for u in "https://example.com/p/111" "https://www.gnome-look.org/p/abc" "https://www.gnome-look.org/p/111/../../x" \
         "https://gnome-look.org.evil.com/p/111" "http://www.gnome-look.org/p/111" "https://www.gnome-look.org/browse"; do
  check "resolve: rejects $u" test "$(CURSOR_PICKER_API_BASE="$base" bash "$script" resolve "$u")" = "error	bad-url"
done

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
