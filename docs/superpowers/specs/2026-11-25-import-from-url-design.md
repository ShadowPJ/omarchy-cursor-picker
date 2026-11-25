# Import a cursor theme from a direct URL: design

Addendum to `2026-11-13-import-cursors-design.md`. It lifts that document's
"no network" non-goal for one case: the user pastes a direct link to an archive.

## Intent

The owner finds cursor themes on gnome-look, GitHub and elsewhere. Today they
download the archive in the browser and then import it from Downloads. Pasting
the link should skip that step: the plugin downloads the archive, installs it
with the same safe path, and the theme shows up in the grid.

## Goals

- A text field plus a **Download** button in the Import view; Enter also submits.
- `omarchy-shell shadowpj.cursorpicker importUrl <url>` does the same from a terminal.
- The downloaded file goes through `import.sh install` unchanged, so every
  existing check (formats, 50 MB, 2000 files, depth, links, skip/replace) applies.
- Same result messages as importing a file, plus download-specific errors.

## Non-goals

- GitHub repo pages and any site other than the gnome-look/pling/opendesktop
  family: only direct archive links and those store pages.
- Auto-applying the theme, background updates, any network use outside an explicit paste.
- Cookies, logins, proxies configuration, or resuming downloads.

## gnome-look page URLs (added 2026-11-25 at the owner's request)

Checked live on 2026-11-25: the old `www.gnome-look.org/ocs/v1/...` API answers
410, but `https://api.opendesktop.org/ocs/v1/content/data/<id>?format=json`
still works. Per item it returns `downloadnameN`, `downloadsizeN` (KB) and
`downloadlinkN` (a signed `https://files0X.pling.com/api/files/download/...`
link). A page can hold several files (variants, a Windows `.zip`, plain "link" entries).

- Accepted page URLs: `https://(www.)?(gnome-look.org|pling.com|opendesktop.org)/p/<digits>`,
  also with an `/s/<store>` prefix, query or fragment. The id is digits only and is the
  only part sent to the API (host fixed to `api.opendesktop.org`).
- `import.sh resolve <pageUrl>` prints candidate lines `name<TAB>sizeKB<TAB>link`:
  only entries whose name has a supported archive extension, size at most 50 MB, and a
  link on `https://files*.pling.com/` or `https://dl.opendesktop.org/`. Names containing
  "windows" sort last; otherwise the page's order is kept. Needs `jq`.
- One candidate: it is downloaded straight away through `fetch`. Several: the panel
  lists them (name, size) and the user clicks one. From the terminal, `importUrl`
  takes the first candidate and the result says nothing more.
- Download file names come from `downloadnameN`, not from the signed link, which has
  no extension. `fetch` therefore accepts an optional name.
- New error code: `no-download` (page has no usable archive, or the API call failed
  or the item does not exist).
- Failure is graceful: if the API changes or is down, the user gets `no-download`
  and can still paste a direct link.

## Anti-goals

- A pasted link must never reach anything but a plain HTTPS download into the
  plugin's own cache folder. No shell interpolation of the URL, no `http`
  downgrade through redirects, no credentials in the URL, no file outside the cache.

## Approaches

- **A. `curl` inside `import.sh fetch`, then reuse `install` (chosen).** One
  script owns every untrusted-input check; QML only passes strings as arguments.
- B. Download with QML's own networking. Harder to cap size, and checks would
  live in two languages.

## Decisions

- `import.sh fetch <url> <dest> <cache> <skip|replace>` downloads, then runs `install`
  on the file and prints the same `installed|skipped<TAB>name` / `error<TAB>code` lines.
- URL rules, checked before any request: `https://` only, at most 2048 chars,
  no whitespace or control characters, no `user@` credentials. The file name is taken
  from the final URL path (query removed) and must end in a supported archive extension.
- `curl -q` (ignores config files) with `--proto '=https' --proto-redir '=https'
  --max-redirs 5 --connect-timeout 15 --max-time 120`, output into a fresh
  `mktemp -d` under the cache folder, and `ulimit -f` so a response without a
  length header cannot exceed 50 MB. The temp folder is always removed.
- New error codes: `bad-url` (rejected before any request), `download-failed`
  (network, HTTP error or timeout), `not-archive` (name has no supported extension).
  Oversize downloads report `too-big`.
- **Replace** after a skipped result downloads again (the link is kept in the result).
- Tests use a local server and a test-only environment variable
  `CURSOR_PICKER_ALLOW_HTTP=1` that relaxes the protocol rule; the panel never sets it.
- Polish folded in: a second `importArchive`/`importUrl` while one is running now
  shows "Another import is already running" (`busy`) instead of being dropped silently.
- README gains a "Network" note; version becomes `0.3.0`.

## Left to the builder

Exact message wording in English and Spanish, field styling, and test fixtures.
Nothing is pushed: the marketplace listing is verified at `2a42884`, and publishing
`0.3.0` is a separate decision (it adds network access and needs new verification).
