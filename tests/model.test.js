const { test } = require("node:test")
const assert = require("node:assert")
const M = require("./load-model.js")

test("limits", () => {
  assert.equal(M.MAX_ARCHIVE_BYTES, 52428800)
  assert.equal(M.MAX_UNPACKED_BYTES, 52428800)
  assert.equal(M.MAX_FILES, 2000)
})

test("parseArchives keeps a valid row", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(M.parseArchives("/d/a b.tar.gz\t1024\tFoo,Bar Baz\n"))),
    [{ path: "/d/a b.tar.gz", name: "a b.tar.gz", size: 1024, themes: ["Foo", "Bar Baz"] }])
})

test("parseArchives drops bad rows", () => {
  assert.deepEqual(M.parseArchives("x\tNaN\tFoo\n/d/y.zip\t10\t../evil\n/d/z.zip\t10\t\nnotabs\n"), [])
})

test("parseArchives keeps only the valid themes of a row", () => {
  const rows = JSON.parse(JSON.stringify(M.parseArchives("/d/p.zip\t5\tGood,../bad,Also Good\n")))
  assert.deepEqual(rows[0].themes, ["Good", "Also Good"])
})

test("parseInstallResult", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(M.parseInstallResult("installed\tA\nskipped\tB\n"))),
    { installed: ["A"], skipped: ["B"], error: "" })
  assert.equal(M.parseInstallResult("error\ttoo-big\n").error, "too-big")
  assert.equal(M.parseInstallResult("garbage").error, "")
})

test("formatBytes", () => {
  assert.equal(M.formatBytes(10), "10 B")
  assert.equal(M.formatBytes(226900), "222 KB")
  assert.equal(M.formatBytes(4785772), "4.6 MB")
  assert.equal(M.formatBytes(-1), "0 B")
})

test("isPageUrl accepts store pages only", () => {
  assert.equal(M.isPageUrl(" https://www.gnome-look.org/p/1197198/ "), true)
  assert.equal(M.isPageUrl("https://www.pling.com/s/Gnome/p/12?x=1"), true)
  assert.equal(M.isPageUrl("https://gnome-look.org.evil.com/p/1"), false)
  assert.equal(M.isPageUrl("http://www.gnome-look.org/p/1"), false)
  assert.equal(M.isPageUrl("https://example.com/Theme.tar.gz"), false)
  assert.equal(M.isPageUrl(""), false)
})

test("parseCandidates", () => {
  const r = JSON.parse(JSON.stringify(M.parseCandidates("A.tar.xz\t1662\thttps://files06.pling.com/x\nB.zip\t5\thttps://files06.pling.com/y\n")))
  assert.deepEqual(r, { candidates: [
    { name: "A.tar.xz", sizeKb: 1662, link: "https://files06.pling.com/x" },
    { name: "B.zip", sizeKb: 5, link: "https://files06.pling.com/y" }], error: "" })
  assert.equal(M.parseCandidates("error\tbad-url\n").error, "bad-url")
  assert.equal(M.parseCandidates("").error, "no-download")
})

test("every code import.sh can print has a message in both languages", () => {
  const fs = require("node:fs"), path = require("node:path")
  const root = path.join(__dirname, "..")
  const codes = new Set(["busy"])
  for (const m of fs.readFileSync(path.join(root, "import.sh"), "utf8").matchAll(/(?<![-\w])fail ([a-z][a-z-]*)/g)) codes.add(m[1])
  for (const lang of ["en", "es"]) {
    const strings = JSON.parse(fs.readFileSync(path.join(root, "i18n", lang + ".json"), "utf8"))
    for (const code of codes) assert.ok(strings["import.error." + code], lang + " lacks import.error." + code)
  }
})
