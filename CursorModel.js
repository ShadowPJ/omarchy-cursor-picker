.pragma library

// Pure helpers for the cursor picker.

var MIN_SIZE = 16
var MAX_SIZE = 96
var SIZE_STEP = 4
var DEFAULT_SIZE = 24

// A theme id is a directory name; refuse anything that is not a plain one so
// it can never smuggle path pieces or options into a command.
function validId(id) {
  return typeof id === "string" && id.length > 0 && id.length <= 200 &&
    /^[A-Za-z0-9][A-Za-z0-9._+ -]*$/.test(id)
}

function clampSize(value, fallback) {
  var n = Math.round(Number(value))
  if (value === undefined || value === null || !isFinite(n)) return fallback
  return Math.max(MIN_SIZE, Math.min(MAX_SIZE, n))
}

// Parses the scan script's output: one "id<TAB>name<TAB>dir" per line.
// The first entry for an id wins (user dirs are scanned before system ones).
function parseThemes(text) {
  var seen = {}
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 3 || !validId(parts[0]) || seen[parts[0]]) continue
    seen[parts[0]] = true
    out.push({ id: parts[0], name: parts[1] || parts[0], dir: parts[2] })
  }
  out.sort(function(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })
  return out
}

function parseObject(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed
  } catch (e) {}
  return null
}

// The saved choice: { theme: string, size: int }; theme is "" when unset.
function parseSaved(text) {
  var raw = parseObject(text) || {}
  return {
    theme: validId(raw.theme) ? raw.theme : "",
    size: clampSize(raw.size, DEFAULT_SIZE)
  }
}

function serialize(theme, size) {
  return JSON.stringify({ theme: theme, size: clampSize(size, DEFAULT_SIZE) }, null, 2) + "\n"
}

// gsettings prints strings quoted ('Name') and ints bare.
function unquote(text) {
  return String(text || "").trim().replace(/^'(.*)'$/, "$1")
}

function filter(themes, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return themes
  return themes.filter(function(t) {
    return t.name.toLowerCase().indexOf(needle) >= 0 || t.id.toLowerCase().indexOf(needle) >= 0
  })
}

// ---- Importing themes from archives ---------------------------------------

var MAX_ARCHIVE_BYTES = 52428800
var MAX_UNPACKED_BYTES = 52428800
var MAX_FILES = 2000

// Parses `import.sh list`: one "path<TAB>bytes<TAB>theme1,theme2" per line.
// Rows that are malformed, or whose themes are all invalid, are dropped.
function parseArchives(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length !== 3 || !parts[0]) continue
    var size = Number(parts[1])
    if (!isFinite(size) || size < 0) continue
    var themes = parts[2].split(",").filter(validId)
    if (themes.length === 0) continue
    out.push({ path: parts[0], name: parts[0].replace(/^.*\//, ""), size: size, themes: themes })
  }
  return out
}

// Parses `import.sh install`: "installed<TAB>name", "skipped<TAB>name" and
// "error<TAB>code" lines (codes: unreadable, unsafe, too-big, no-cursors, failed).
function parseInstallResult(text) {
  var result = { installed: [], skipped: [], error: "" }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2) continue
    if (parts[0] === "installed") result.installed.push(parts[1])
    else if (parts[0] === "skipped") result.skipped.push(parts[1])
    else if (parts[0] === "error") result.error = parts[1]
  }
  return result
}

// "10 B", "222 KB", "4.6 MB": sizes as shown in the import list.
function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1048576) return Math.round(n / 1024) + " KB"
  return (n / 1048576).toFixed(1) + " MB"
}
