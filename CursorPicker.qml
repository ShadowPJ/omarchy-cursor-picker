import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "CursorModel.js" as CursorModel

// Cursor Picker: lists the cursor themes installed on the machine and applies
// the chosen one (and size) live through Hyprland and GTK settings.
//
// The choice is saved to ~/.config/omarchy/cursor-picker.json and re-applied
// when the shell starts, since the session's own startup also sets a cursor.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property var themes: []
  property string current: ""
  property int size: CursorModel.DEFAULT_SIZE
  property bool scanned: false
  property bool savedLoaded: false
  property bool startupApplied: false
  property string savedTheme: ""

  function localPath(url) {
    var value = String(url)
    return value.indexOf("file://") === 0 ? decodeURIComponent(value.slice(7)) : value
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy/cursor-picker.json"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/omarchy-cursor-picker"
  readonly property string scanScript: localPath(Qt.resolvedUrl("scan.sh"))
  readonly property string applyScript: localPath(Qt.resolvedUrl("apply.sh"))

  function previewSource(id) {
    return "file://" + root.cacheDir + "/" + id + ".png"
  }

  FileView {
    id: savedFile
    path: root.configPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var saved = CursorModel.parseSaved(text())
      root.size = saved.size
      root.savedTheme = saved.theme
      if (saved.theme) root.current = saved.theme
      root.savedLoaded = true
      root.maybeApplyStartup()
    }
    onLoadFailed: {
      root.savedLoaded = true
      root.maybeApplyStartup()
    }
  }

  Process {
    id: scanProc
    command: ["sh", root.scanScript, root.cacheDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.themes = CursorModel.parseThemes(text)
        root.scanned = true
        root.maybeApplyStartup()
      }
    }
  }

  // Reads the cursor theme the desktop currently uses, for when nothing was
  // saved yet.
  Process {
    id: currentProc
    command: ["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var id = CursorModel.unquote(text)
        if (!root.savedTheme && CursorModel.validId(id)) root.current = id
      }
    }
  }

  Process { id: applyProc }

  function rescan() { scanProc.running = false; scanProc.running = true }

  Component.onCompleted: {
    currentProc.running = true
    rescan()
  }

  // Waits a moment so the session's own cursor setup has finished first.
  function maybeApplyStartup() {
    if (root.startupApplied || !root.scanned || !root.savedLoaded) return
    root.startupApplied = true
    if (root.savedTheme && root.hasTheme(root.savedTheme)) startupTimer.start()
  }

  Timer {
    id: startupTimer
    interval: 3000
    onTriggered: root.apply(root.savedTheme, root.size, false)
  }

  function hasTheme(id) {
    for (var i = 0; i < root.themes.length; i++) if (root.themes[i].id === id) return true
    return false
  }

  function apply(id, size, save) {
    if (!CursorModel.validId(id) || !root.hasTheme(id)) return false
    size = CursorModel.clampSize(size, root.size)
    root.current = id
    root.size = size
    applyProc.running = false
    applyProc.command = ["sh", root.applyScript, id, String(size)]
    applyProc.running = true
    if (save !== false) {
      root.savedTheme = id
      savedFile.setText(CursorModel.serialize(id, size))
    }
    return true
  }

  function select(id) { root.apply(id, root.size, true) }

  function setSize(size) {
    size = CursorModel.clampSize(size, root.size)
    if (size === root.size && root.savedTheme) return
    if (root.current) root.apply(root.current, size, true)
    else root.size = size
  }

  function openPanel() { root.rescan(); panel.shown = true }
  function togglePanel() { if (panel.shown) panel.shown = false; else root.openPanel() }

  //   omarchy-shell shadowpj.cursorpicker panel        toggles the picker
  //   omarchy-shell shadowpj.cursorpicker set <theme>  applies a theme by id
  //   omarchy-shell shadowpj.cursorpicker size <px>    changes the size
  //   omarchy-shell shadowpj.cursorpicker refresh      rescans installed themes
  ShellIpc {
    target: "shadowpj.cursorpicker"
    function panel(): void { root.togglePanel() }
    function set(theme: string): void { root.select(theme) }
    function size(px: int): void { root.setSize(px) }
    function refresh(): void { root.rescan() }
  }

  PickerPanel {
    id: panel
    picker: root
  }
}
