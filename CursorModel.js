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

var MAX_ARCHIVE_BYTES = 524288000
var MAX_UNPACKED_BYTES = 1073741824
var MAX_FILES = 20000

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
// "error<TAB>code" lines (codes: unreadable, unsafe, too-big, too-big-unpacked, too-many-files, no-cursors, failed, and the download ones).
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

// The same shape import.sh accepts for a gnome-look/pling page (it checks again).
function isPageUrl(text) {
  return /^https:\/\/(www\.)?(gnome-look\.org|pling\.com|opendesktop\.org)(\/s\/[A-Za-z0-9_-]+)?\/p\/[0-9]{1,12}\/?([?#].*)?$/.test(String(text || "").trim())
}

// Parses `import.sh resolve`: "name<TAB>sizeKB<TAB>link" lines, or "error<TAB>code".
function parseCandidates(text) {
  var result = { candidates: [], error: "" }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length === 2 && parts[0] === "error") result.error = parts[1]
    else if (parts.length === 3 && parts[0] && parts[2])
      result.candidates.push({ name: parts[0], sizeKb: Number(parts[1]) || 0, link: parts[2] })
  }
  if (!result.candidates.length && !result.error) result.error = "no-download"
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

// ---- Theme families (see docs/superpowers/specs/2026-11-25-theme-families-design.md) ----

function familyKey(id) { return String(id).split("-")[0].toLowerCase() }

// A "-Right" theme is the mirrored (left-handed) twin of the theme without the suffix.
function leftHandedIn(ids, id) {
  var lower = String(id).toLowerCase()
  if (!/-right$/.test(lower)) return false
  var twin = lower.slice(0, -6)
  for (var i = 0; i < ids.length; i++) if (String(ids[i]).toLowerCase() === twin) return true
  return false
}

// Groups themes (already sorted by name) into tiles: a family when two or more
// share the id's first dash-separated word, otherwise a plain theme.
// Returns [{kind:"theme", theme} | {kind:"family", key, name, themes, hasLeftHanded}].
function groupThemes(themes) {
  var byKey = {}
  var order = []
  for (var i = 0; i < themes.length; i++) {
    var key = familyKey(themes[i].id)
    if (!byKey[key]) { byKey[key] = []; order.push(key) }
    byKey[key].push(themes[i])
  }
  var items = []
  for (var k = 0; k < order.length; k++) {
    var list = byKey[order[k]]
    if (list.length < 2) { items.push({ kind: "theme", theme: list[0] }); continue }
    list.sort(function(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })
    var ids = list.map(function(t) { return t.id })
    items.push({ kind: "family", key: order[k], name: list[0].id.split("-")[0], themes: list,
                 hasLeftHanded: ids.some(function(id) { return leftHandedIn(ids, id) }) })
  }
  items.sort(function(a, b) {
    var an = (a.kind === "family" ? a.name : a.theme.name).toLowerCase()
    var bn = (b.kind === "family" ? b.name : b.theme.name).toLowerCase()
    return an.localeCompare(bn)
  })
  return items
}

function isLeftHandedIn(family, id) {
  return leftHandedIn(family.themes.map(function(t) { return t.id }), id)
}

// The variants shown inside a family: left-handed ones or the rest, depending on the
// toggle; a family without left-handed variants shows all of them.
function familyThemes(family, leftHanded) {
  if (!family.hasLeftHanded) return family.themes
  return family.themes.filter(function(t) { return isLeftHandedIn(family, t.id) === !!leftHanded })
}

function familyHas(family, id) {
  for (var i = 0; i < family.themes.length; i++) if (family.themes[i].id === id) return true
  return false
}

// Which variant a family tile previews: the active one, else the first right-handed one.
function familyPreviewId(family, currentId) {
  if (familyHas(family, currentId)) return currentId
  for (var i = 0; i < family.themes.length; i++)
    if (!isLeftHandedIn(family, family.themes[i].id)) return family.themes[i].id
  return family.themes[0].id
}
