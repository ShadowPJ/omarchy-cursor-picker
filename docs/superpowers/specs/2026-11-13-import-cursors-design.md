# Import cursors from downloaded archives — design

Status: awaiting approval. Size: small change.

## Intent and why

The owner downloads cursor themes from gnome-look in the browser and unpacks
them by hand into `~/.icons`. The manual unpack-and-place step is the pain;
downloading is not. Cursor Picker should take a downloaded archive and install
it so it shows up in the panel.

## Goals

- An **Import** button in the panel lists archives in `~/Downloads` that contain
  a cursor theme; picking one installs it and refreshes the theme list.
- The same from a script: `omarchy-shell shadowpj.cursorpicker importArchive <archive>` (`import` is a
  reserved word in QML, so the IPC method cannot use it).
- Formats: `.tar.gz/.tgz`, `.tar.xz`, `.tar.bz2`, `.tar.zst`, `.zip`, `.7z`,
  read with `bsdtar` (already installed; no new dependency).
- An archive with several themes installs all of them.

## Non-goals

- No network access: no URLs, no gnome-look browsing (approaches B and C stay
  possible later).
- No hyprcursor themes (`hyprcursors/` + `manifest.hl`); only XCursor themes
  (a `cursors/` folder), which is what the picker lists today.
- Not applied automatically after import; the user picks it as usual.
- The archive is not deleted or moved.

## Anti-goals

An archive must never write outside the theme folder, replace a theme without
the user knowing, or hang the panel while it inspects big files.

## Approaches considered

- **A. Import a downloaded archive (chosen).** Fits the owner's flow, no network,
  no new dependency.
- B. Paste a URL. Needs network, and gnome-look download links are redirects
  with signatures, so the page URL is not enough.
- C. Browse gnome-look inside the panel. Best experience but a separate project:
  remote content, more security surface and marketplace review.

## Decisions (my calls, open to correction)

- **Where to look:** `~/Downloads` (XDG download dir), plus any path given to the
  `importArchive` command.
- **Which archives are offered:** known extensions only, up to 50 MB, listed with
  `bsdtar -tf` (no extraction); offered only if the listing has a `cursors/`
  folder one or two levels deep. The owner's Downloads mixes games and a
  600 MB package, so unfiltered listing would be slow and noisy.
- **Install location:** `~/.icons` (the owner's habit; the scanner already reads it).
- **Safe extraction:** unpack into a temporary folder under
  `~/.cache/omarchy-cursor-picker`, reject absolute paths, `..`, links that leave
  the folder and non-regular files, cap the unpacked size (50 MB) and file
  count, then move each theme folder to `~/.icons/<name>`. Theme folder names
  must pass the same `validId` check the picker already uses.
- **Existing theme:** if `~/.icons/<name>` exists, ask before replacing it
  ("Replace" / "Skip"); the old folder is kept until the new one is in place.
- **UI:** an Import button beside the size controls opens a list inside the
  panel (archive name, size, themes found); Enter or click installs;
  Esc goes back. Result shown as a short line ("Installed 2 themes" / the reason
  it failed). Strings in `en.json` and `es.json`.
- **Docs:** README documents the import and that the plugin writes to
  `~/.icons`; notes for the marketplace listing will mention it.

## Constraints

- Submission #14708 is pending on commit `2a42884`. Work stays local and is
  not pushed until it is approved; afterwards it goes out as an update with a
  new verification.
- The installed copy comes from GitHub, so testing needs a temporary link to the
  working folder (and a rescan after the disk mounts).

## Left to the builder

Exact layout and wording of the import list, how errors from `bsdtar` are
summarised, the unpacked-size and file-count limits' final values, and the
tests (small fixture archives for good, hostile and multi-theme cases).
