# Import Cursors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Cursor Picker install a cursor theme from an archive downloaded to `~/Downloads`, from an Import button in the panel or from an IPC command (`importArchive`).

**Architecture:** One shell script, `import.sh`, does everything that touches archives (`list` finds candidates, `install` extracts safely and moves themes into `~/.icons`) and prints tab-separated lines. `CursorModel.js` parses those lines (pure, node-tested). `CursorPicker.qml` runs the script and exposes state; a new `ImportView.qml` shows the list inside the panel.

**Tech Stack:** POSIX `sh`, `bsdtar` (libarchive), GNU `find`/`sort`/`timeout`, QML (Quickshell), node (`node --test`) for the pure JS.

**Spec:** `docs/superpowers/specs/2026-11-13-import-cursors-design.md`

## Global Constraints

- Formats: `.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`, `.tar.zst`, `.zip`, `.7z`, read with `bsdtar`; no new dependency.
- Look in `~/Downloads` (`$XDG_DOWNLOAD_DIR` when set) plus any path given to `importArchive`.
- Offer only archives up to 50 MB (52428800 bytes), inspected with `bsdtar -tf` (no extraction), and only if a `cursors/` folder sits one or two levels deep.
- Install to `~/.icons`. An archive with several themes installs all of them.
- Safe extraction: temp folder under `~/.cache/omarchy-cursor-picker`; reject absolute paths, `..`, links leaving the folder, non-regular files; unpacked size cap 50 MB (52428800 bytes); file-count cap 2000; theme folder names must pass `validId`.
- Existing theme: ask before replacing ("Replace" / "Skip"); keep the old folder until the new one is in place.
- No network access. XCursor themes only (a `cursors/` folder). Not applied automatically after import. The archive is never deleted or moved.
- Strings in `i18n/en.json` and `i18n/es.json`; README documents the import and the `~/.icons` write.
- Submission #14708 is pending on commit `2a42884`: commit locally, never push.

## Review Focus

- Archive names with spaces, brackets, parentheses, quotes and non-ASCII (the owner's Downloads has names like `x.(ES).(Game Boy Advance).[site].7z`): listed and installed correctly, never split or interpreted by the shell.
- Archive with `cursors/` at its root (no theme folder): not offered; `install` fails with `no-cursors`.
- Corrupt or truncated archive: `unreadable`, nothing left half-installed in `~/.icons`, panel stays usable.
- Theme already installed: untouched on `skip`; on `replace` the old folder survives until the new one is in place.
- Downloads missing, empty or without candidates: empty list and a clear "no archives" line, no error.

---

### Task 1: Parse the script's output

**Files:**
- Modify: `CursorModel.js` (append)
- Create: `tests/load-model.js`, `tests/model.test.js`

**Interfaces:**
- Produces: `MAX_ARCHIVE_BYTES = 52428800`, `MAX_UNPACKED_BYTES = 52428800`, `MAX_FILES = 2000`;
  `parseArchives(text: string): Array<{path: string, name: string, size: number, themes: string[]}>`
  (input lines `path<TAB>bytes<TAB>theme1,theme2`; drops malformed rows, non-finite sizes, themes failing `validId`, and archives left with no theme);
  `parseInstallResult(text: string): {installed: string[], skipped: string[], error: string}`
  (lines `installed<TAB>name`, `skipped<TAB>name`, `error<TAB>code`; codes: `unreadable`, `unsafe`, `too-big`, `no-cursors`, `failed`).

- [ ] **Step 1: Write the failing tests** in `tests/model.test.js` (`node:test`). `tests/load-model.js` evaluates `CursorModel.js` with the `.pragma library` line stripped and returns its functions.

```js
test("parseArchives keeps a valid row", () => {
  assert.deepEqual(M.parseArchives("/d/a b.tar.gz\t1024\tFoo,Bar Baz\n"),
    [{ path: "/d/a b.tar.gz", name: "a b.tar.gz", size: 1024, themes: ["Foo", "Bar Baz"] }])
})
test("parseArchives drops bad rows", () => {
  assert.deepEqual(M.parseArchives("x\tNaN\tFoo\n/d/y.zip\t10\t../evil\n/d/z.zip\t10\t\nnotabs\n"), [])
})
test("parseInstallResult", () => {
  assert.deepEqual(M.parseInstallResult("installed\tA\nskipped\tB\n"), { installed: ["A"], skipped: ["B"], error: "" })
  assert.equal(M.parseInstallResult("error\ttoo-big\n").error, "too-big")
  assert.equal(M.parseInstallResult("garbage").error, "")
})
```

- [ ] **Step 2: Run** `node --test tests/` — Expected: FAIL (`parseArchives is not a function`).
- [ ] **Step 3: Implement** the three constants and two functions in `CursorModel.js`, reusing `validId`.
- [ ] **Step 4: Run** `node --test tests/` — Expected: all PASS.
- [ ] **Step 5: Commit** `git add CursorModel.js tests && git commit -m "Parse import script output"`.

### Task 2: `import.sh list`

**Files:**
- Create: `import.sh`, `tests/import.test.sh`

**Interfaces:**
- Produces: `sh import.sh list <dir>` prints one line per candidate, newest first, at most 30 inspected: `path<TAB>bytes<TAB>theme1,theme2`. Exit 0 always; a missing dir prints nothing.

- [ ] **Step 1: Write the failing test script.** `tests/import.test.sh` builds fixtures in a `mktemp -d` and checks stdout with `grep`/`wc`, using `bsdtar -a -cf` to make `.tar.gz`/`.zip`/`.tar.xz`/`.7z`. Fixtures and expectations:
  - `Good.tar.gz` (`Good/cursors/left_ptr`) → line with theme `Good`.
  - `wrap.zip` (`pack/One/cursors/x`, `pack/Two/cursors/x`) → themes `One,Two`.
  - `My Theme (v2) [x].tar.xz` (`T/cursors/x`) → listed with the full path intact.
  - `nocursors.zip`, `rootcursors.tar.gz` (`cursors/x` at the root), `notes.txt` → absent.
  - `big.tar.gz` made with `truncate -s 51M` → absent (size gate).
  - missing dir → empty output, exit 0.
- [ ] **Step 2: Run** `sh tests/import.test.sh` — Expected: FAIL (`import.sh` missing).
- [ ] **Step 3: Implement `list`** in `import.sh` (`set -u`, one `case "$1"` dispatch). Enumerate with `find "$dir" -maxdepth 1 -type f -size -52428801c -printf '%T@\t%s\t%p\0' | sort -z -rn`, read NUL-separated, skip paths containing a tab or newline and names without an allowed extension. For each (first 30) run `timeout 5 bsdtar -tf "$path"` and pipe through `awk` to collect theme folder names whose entries match `^([^/]+/)?([^/]+)/cursors/` (depth one or two), unsafe entries (`..` segment, leading `/`) disqualify the archive. Always quote `"$path"`.
- [ ] **Step 4: Run** `sh tests/import.test.sh` — Expected: `ok` for every case.
- [ ] **Step 5: Commit** `git add import.sh tests/import.test.sh && git commit -m "List cursor archives in a folder"`.

### Task 3: `import.sh install`

**Files:**
- Modify: `import.sh`, `tests/import.test.sh`

**Interfaces:**
- Consumes: `import.sh` dispatch from Task 2.
- Produces: `sh import.sh install <archive> <destDir> <cacheDir> <skip|replace>`; stdout lines `installed<TAB>name` / `skipped<TAB>name`; on failure one `error<TAB>code` line and exit 1. Exit 0 when at least one theme was installed or skipped.

- [ ] **Step 1: Write the failing tests** (append to `tests/import.test.sh`, each with a fresh dest and cache dir):
  - Good archive → `installed	Good`, `$dest/Good/cursors/left_ptr` exists.
  - `My Theme (v2) [x].tar.xz` (`T/cursors/x`) installs from its odd path → `installed	T`.
  - `wrap.zip` → both themes installed.
  - Install twice with `skip` → second run prints `skipped	Good` and leaves a marker file in `$dest/Good` untouched; with `replace` → `installed	Good` and the marker is gone.
  - Hostile, each expecting `error	unsafe` and an empty `$dest`: entry `../evil` (GNU `tar --transform 's,^,../,'`), absolute entry (`tar -P`), symlink `Good/cursors/out -> /etc`, a FIFO made with `mkfifo`.
  - Relative symlink inside a theme (`left_ptr -> arrow`) is accepted.
  - 51 MB of zeros inside a small `.tar.gz` → `error	too-big`; 2001 tiny files → `too-big`.
  - Truncated archive (`head -c 100`) → `error	unreadable`; `rootcursors.tar.gz` → `error	no-cursors`; theme folder named `bad;name` → `error	unsafe`.
  - After every failure `$cache` holds no `import.*` folder.
- [ ] **Step 2: Run** `sh tests/import.test.sh` — Expected: the new cases FAIL.
- [ ] **Step 3: Implement `install`** in this order: list entries and reject unsafe ones (`unsafe`); `mktemp -d "$cache/import.XXXXXX"` with a `trap` that removes it; extract with `bsdtar -xf "$archive" --no-same-owner --no-same-permissions -C "$tmp"` (never `-P`; failure → `unreadable`); inside `$tmp` reject any entry that is not a regular file, directory or symlink, and any symlink whose `realpath -m` target is outside `$tmp` (`unsafe`); apply `MAX_UNPACKED_BYTES` via `du -sb` and `MAX_FILES` via `find | wc -l` (`too-big`); theme folders are directories at depth one or two holding a `cursors/` directory (none → `no-cursors`); each folder name must match `^[A-Za-z0-9][A-Za-z0-9._+ -]*$` and be at most 200 chars (`unsafe`). Move each into `$dest` (create it if missing); if it exists, `skip` prints `skipped` and `replace` renames the old folder aside, moves the new one in, then deletes the old one. Finish with `chmod -R u+rwX,go+rX` on what was installed.
- [ ] **Step 4: Run** `sh tests/import.test.sh` — Expected: all cases `ok`.
- [ ] **Step 5: Commit** `git add import.sh tests/import.test.sh && git commit -m "Install cursor themes from archives safely"`.

### Task 4: Service state and panel UI

**Files:**
- Modify: `CursorPicker.qml`, `PickerPanel.qml`, `i18n/en.json`, `i18n/es.json`
- Create: `ImportView.qml`

**Interfaces:**
- Consumes: Task 1 parsers; `import.sh` `list`/`install`.
- Produces on `CursorPicker.qml`: `property var archives` (result of `parseArchives`), `property bool importBusy`, `property var importResult` (`parseInstallResult` plus `archive: string`), `function scanArchives(): void`, `function importArchive(path: string, mode: string): void`, and IPC `function importArchive(path: string): void` under target `shadowpj.cursorpicker` (mode `skip`). A successful install calls `rescan()`.
- `ImportView.qml`: `property var picker`, `signal closed()`; rows show name, size, themes; Enter or click installs with `skip`; a "Replace" button appears when `importResult.skipped` is non-empty; `Esc` emits `closed()`.
- New i18n keys (both languages): `import.button`, `import.title`, `import.empty` ("No cursor archives found in Downloads"), `import.installed` (plural), `import.skipped` (plural), `import.replace`, `import.back`, and `import.error.unreadable|unsafe|too-big|no-cursors|failed`.

- [ ] **Step 1: Wire the service.** Two `Process` objects (`list`, `install`) with `StdioCollector`; the downloads dir is `$XDG_DOWNLOAD_DIR` or `$HOME/Downloads`; `importArchive` IPC validates only that the path is non-empty (the script validates the rest).
- [ ] **Step 2: Build `ImportView.qml`** in the style of `PickerPanel.qml` (same `PlainLabel`, `Style` tokens, rows ≈ `window.rowHeight`); add the Import button beside the size controls in `PickerPanel.qml`, with `importOpen` swapping the grid for the view and `Esc` closing the view before the panel.
- [ ] **Step 3: Add the i18n strings** in both languages.
- [ ] **Step 4: Try it in the shell.** Replace the installed copy with a temporary link: `rm -rf ~/.config/omarchy/plugins/shadowpj.cursorpicker && ln -s "$PWD" ~/.config/omarchy/plugins/shadowpj.cursorpicker && omarchy-shell shell rescanPlugins`. Copy a fixture archive containing theme `Cursor-Picker-Test` into `~/Downloads`, open the panel (`omarchy-shell shadowpj.cursorpicker panel`), click Import, install it, confirm it appears in the grid; install again and use Replace; run `omarchy-shell shadowpj.cursorpicker importArchive <path>` too. Expected: no errors in `journalctl --user -n 50 | grep -i cursorpicker`.
- [ ] **Step 5: Clean up the trial.** Delete `~/.icons/Cursor-Picker-Test`, the fixture in `~/Downloads` and `~/.config/omarchy/cursor-picker.json` changes made by the test; remove the temporary link and reinstall the published copy: `omarchy plugin add https://github.com/ShadowPJ/omarchy-cursor-picker.git --enable --yes`.
- [ ] **Step 6: Commit** `git add CursorPicker.qml PickerPanel.qml ImportView.qml i18n && git commit -m "Add an Import view to the panel"`.

### Task 5: Docs and version

**Files:**
- Modify: `README.md`, `manifest.json`

- [ ] **Step 1: README** — add an "Import a cursor theme" section (Import button, `importArchive <archive>` command, formats, `~/Downloads` → `~/.icons`, size limit, safe extraction, replace prompt) and list `bsdtar` as the only extra tool; keep "no network".
- [ ] **Step 2: Bump** `manifest.json` version to `0.2.0`, then run `omarchy plugin validate "$PWD"` — Expected: exit 0.
- [ ] **Step 3: Run** `node --test tests/ && sh tests/import.test.sh` — Expected: all pass.
- [ ] **Step 4: Commit locally** `git add README.md manifest.json && git commit -m "Document cursor import and bump to 0.2.0"`. Do not push: #14708 is pending.
