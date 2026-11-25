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

  // ---- Importing themes from downloaded archives (see import.sh) -----------
  readonly property string importScript: localPath(Qt.resolvedUrl("import.sh"))
  readonly property string iconsDir: home + "/.icons"
  // The user's real Downloads folder (it may be "Descargas", say): asked from
  // xdg-user-dir at startup, with ~/Downloads as the fallback.
  property string downloadsDir: Quickshell.env("XDG_DOWNLOAD_DIR") || (home + "/Downloads")

  Process {
    id: downloadsProc
    command: ["xdg-user-dir", "DOWNLOAD"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var dir = String(text).trim()
        if (dir && dir.charAt(0) === "/" && dir !== root.home) root.downloadsDir = dir
      }
    }
  }

  property var archives: []
  property bool archivesScanned: false
  property bool importBusy: false
  property var importResult: ({ archive: "", installed: [], skipped: [], error: "" })

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.archives = CursorModel.parseArchives(text)
        root.archivesScanned = true
      }
    }
  }

  Process {
    id: installProc
    property string archive: ""
    // Never leave the panel stuck on "Installing…", whatever happened to the process.
    onExited: root.importBusy = false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = CursorModel.parseInstallResult(text)
        if (!result.error && result.installed.length === 0 && result.skipped.length === 0) result.error = "failed"
        result.archive = installProc.archive
        root.importResult = result
        root.importBusy = false
        if (result.installed.length > 0) root.rescan()
      }
    }
  }

  // A page URL is first resolved to the archives it offers (see import.sh resolve).
  property var candidates: []
  property string candidatesPage: ""
  property var lastImport: null

  Process {
    id: resolveProc
    property string page: ""
    property bool auto: false
    property bool handled: false
    property string mode: "skip"
    // If the process never reported, do not leave the panel on "Installing…".
    onExited: if (!resolveProc.handled) root.finishWith(resolveProc.page, "failed")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        resolveProc.handled = true
        var parsed = CursorModel.parseCandidates(text)
        if (parsed.error) { root.finishWith(resolveProc.page, parsed.error); return }
        if (parsed.candidates.length === 1 || resolveProc.auto) {
          root.importBusy = false
          root.downloadCandidate(parsed.candidates[0], resolveProc.mode)
        } else {
          root.candidates = parsed.candidates
          root.candidatesPage = resolveProc.page
          root.importBusy = false
        }
      }
    }
  }

  function clearImportResult() {
    root.importResult = { archive: "", installed: [], skipped: [], error: "" }
    root.candidates = []
  }

  function finishWith(source, code) {
    root.importResult = { archive: source, installed: [], skipped: [], error: code }
    root.importBusy = false
  }

  function scanArchives() {
    listProc.running = false
    listProc.command = ["bash", root.importScript, "list", root.downloadsDir]
    listProc.running = true
  }

  // A rejected request must not touch importBusy: the import in flight still owns it.
  function reportBusy(source) {
    root.importResult = { archive: source, installed: [], skipped: [], error: "busy" }
  }

  function beginImport(source) {
    if (root.importBusy) { root.reportBusy(source); return false }
    root.importBusy = true
    root.candidates = []
    root.importResult = { archive: "", installed: [], skipped: [], error: "" }
    return true
  }

  // mode "skip" keeps a theme that is already installed; "replace" overwrites it.
  function importArchive(path, mode) {
    if (!path) return false
    if (!root.beginImport(String(path))) return false
    mode = mode === "replace" ? "replace" : "skip"
    root.lastImport = { kind: "file", path: String(path) }
    installProc.archive = String(path)
    installProc.command = ["bash", root.importScript, "install", String(path), root.iconsDir, root.cacheDir, mode]
    installProc.running = true
    return true
  }

  // Downloads and installs a pasted link: a direct archive link, or a gnome-look
  // page (one archive installs at once; several are listed in `candidates` for the
  // user to pick, unless `auto` is set, which takes the first one).
  function importUrl(url, mode, auto) {
    url = String(url || "").trim()
    if (!url) return false
    if (!root.beginImport(url)) return false
    mode = mode === "replace" ? "replace" : "skip"
    if (CursorModel.isPageUrl(url)) {
      resolveProc.running = false
      resolveProc.handled = false
      resolveProc.page = url
      resolveProc.auto = auto === true
      resolveProc.mode = mode
      resolveProc.command = ["bash", root.importScript, "resolve", url]
      resolveProc.running = true
    } else {
      root.startFetch(url, "-", url, mode)
    }
    return true
  }

  function downloadCandidate(candidate, mode) {
    if (root.importBusy) { root.reportBusy(candidate.name); return false }
    root.importBusy = true
    root.candidates = []
    root.importResult = { archive: "", installed: [], skipped: [], error: "" }
    root.startFetch(candidate.link, candidate.name, candidate.name, mode === "replace" ? "replace" : "skip")
    return true
  }

  function startFetch(link, name, label, mode) {
    root.lastImport = { kind: "url", link: link, name: name, label: label }
    installProc.archive = label
    installProc.command = ["bash", root.importScript, "fetch", link, name, root.iconsDir, root.cacheDir, mode]
    installProc.running = true
  }

  // "Replace" after a skipped result: the same import again, overwriting.
  function replaceLast() {
    var last = root.lastImport
    if (!last || root.importBusy) return false
    if (last.kind === "file") return root.importArchive(last.path, "replace")
    root.importBusy = true
    root.importResult = { archive: "", installed: [], skipped: [], error: "" }
    root.startFetch(last.link, last.name, last.label, "replace")
    return true
  }

  function rescan() { scanProc.running = false; scanProc.running = true }

  Component.onCompleted: {
    downloadsProc.running = true
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
  //   omarchy-shell shadowpj.cursorpicker importArchive <file>  installs themes from an archive
  //   omarchy-shell shadowpj.cursorpicker importUrl <url>       downloads and installs (archive link or gnome-look page)
  ShellIpc {
    target: "shadowpj.cursorpicker"
    function panel(): void { root.togglePanel() }
    function set(theme: string): void { root.select(theme) }
    function size(px: int): void { root.setSize(px) }
    function refresh(): void { root.rescan() }
    function importArchive(path: string): void { root.importArchive(path, "skip") }
    function importUrl(url: string): void { root.importUrl(url, "skip", true) }
  }

  PickerPanel {
    id: panel
    picker: root
  }
}
