# Cursor Picker

An Omarchy shell plugin to choose the mouse cursor from the cursor themes you
have installed, with a preview of each one, and apply it instantly.

![The cursor picker panel](preview.png)

- Finds every theme with a `cursors/` folder in `~/.icons`, `~/.local/share/icons`
  and the system icon directories.
- Searchable grid; click a theme to apply it at once, no restart.
- Size control (16–96 px).
- Your choice is saved and re-applied each time the shell starts.
- Imports cursor themes from archives you downloaded (see below).
- A bar button opens the panel; you can also bind the IPC command to a key.
- Follows the Omarchy theme and language (English and Spanish included).

## Install

```bash
omarchy plugin add https://github.com/ShadowPJ/omarchy-cursor-picker.git --enable
```

For development, link a checkout:

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/shadowpj.cursorpicker
omarchy-shell shell rescanPlugins
omarchy plugin enable shadowpj.cursorpicker
```

## Use

```bash
omarchy-shell shadowpj.cursorpicker panel        # open / close the picker
omarchy-shell shadowpj.cursorpicker set Adwaita  # apply a theme by id
omarchy-shell shadowpj.cursorpicker size 32      # change the size
omarchy-shell shadowpj.cursorpicker refresh      # rescan installed themes
omarchy-shell shadowpj.cursorpicker importArchive ~/Downloads/Theme.tar.gz
```

Bind `panel` to a key in your Hyprland config to open it quickly.

The plugin also ships a bar widget (a cursor icon). Add it with
`omarchy bar put shadowpj.cursorpicker --section right`, or let `--enable` place
it. It works as a plain bar widget and inside bar-drawer plugins such as
[Pocket](https://github.com/jrmmhm/omarchy-pocket); it was not usable inside Den
or Tray on Omarchy 4.5.

## Import a cursor theme

Download a cursor theme (from gnome-look, GitHub, anywhere) and let the plugin
unpack and install it:

1. Open the panel and click **Import…** (or press `Ctrl+I` in the search box).
2. Pick an archive from the list and press Enter or click it. The list shows
   the archives in `~/Downloads` (or `$XDG_DOWNLOAD_DIR`) that hold a cursor
   theme: up to 50 MB, one `cursors/` folder one or two levels deep.
3. The theme is installed into `~/.icons` and appears in the grid. It is not
   applied until you pick it.

If a theme with the same name is already in `~/.icons` it is left alone and the
panel offers **Replace**. An archive with several themes installs all of them.
From a script: `omarchy-shell shadowpj.cursorpicker importArchive <archive>`.

Supported: `.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`, `.tar.zst`, `.zip`, `.7z`
(read with `bsdtar`, part of libarchive). Archives are unpacked into a temporary
folder first and rejected if they hold absolute or `..` paths, links that leave
the folder, special files, more than 2000 files or more than 50 MB unpacked.
Your original archive is never changed or deleted. Only XCursor themes are
supported (a `cursors/` folder), not hyprcursor themes. The plugin does not use
the network.

## How it applies a cursor

`hyprctl setcursor <theme> <size>` for Hyprland and Xwayland apps, plus the
`org.gnome.desktop.interface` `cursor-theme` / `cursor-size` settings for GTK
apps. The choice lives in `~/.config/omarchy/cursor-picker.json` and is
re-applied three seconds after the shell starts, so it wins over the
`hyprctl setcursor` line in `hyprland.conf`. Delete the file to stop that.

Previews are optional: if `xcur2png` is installed they are cached in
`~/.cache/omarchy-cursor-picker`; otherwise a placeholder is shown.

## Remove

```bash
omarchy plugin remove shadowpj.cursorpicker
rm -f ~/.config/omarchy/cursor-picker.json
```
