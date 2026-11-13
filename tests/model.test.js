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
