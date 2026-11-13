// Loads CursorModel.js (a QML ".pragma library" script) as plain JS for tests.
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "CursorModel.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context)
module.exports = context
