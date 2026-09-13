const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const laptop = {
  name: "eDP-1", description: "LG Display 0x07C6",
  width: 2880, height: 1800, physicalWidth: 300, physicalHeight: 190,
  scale: 2, disabled: false, x: 0, y: 0
}
const studio = {
  name: "DP-1", description: "Apple Computer Inc StudioDisplay 0xB65A586D",
  width: 5120, height: 2880, physicalWidth: 600, physicalHeight: 330,
  scale: 2, disabled: false, x: 1440, y: 0
}

test("classifyMonitors finds internal by name prefix and first enabled external", () => {
  const r = Model.classifyMonitors([studio, laptop])
  assert.equal(r.internal.name, "eDP-1")
  assert.equal(r.external.name, "DP-1")
})

test("classifyMonitors ignores disabled externals and tolerates junk", () => {
  const off = Object.assign({}, studio, { disabled: true })
  assert.equal(Model.classifyMonitors([laptop, off]).external, null)
  assert.equal(Model.classifyMonitors(null).internal, null)
  assert.equal(Model.classifyMonitors([{}, 5, "x"]).internal, null)
})

test("parseMonitors accepts hyprctl JSON and rejects garbage", () => {
  assert.equal(Model.parseMonitors(JSON.stringify([laptop])).length, 1)
  assert.deepEqual(Model.parseMonitors("nope"), [])
  assert.deepEqual(Model.parseMonitors('{"a":1}'), [])
})

test("defaultState and parseState round-trip, garbage yields defaults", () => {
  const d = Model.defaultState()
  assert.equal(d.version, 1)
  assert.deepEqual(d.profiles, {})
  assert.equal(Model.parseState("{{{").version, 1)
  assert.equal(Model.parseState("").generatedProfile, "")
  const s = Model.parseState(JSON.stringify({ version: 1, generatedProfile: "x", profiles: { x: { side: "left" } } }))
  assert.equal(s.generatedProfile, "x")
  assert.equal(s.profiles.x.side, "left")
  const again = Model.parseState(Model.serializeState(s))
  assert.deepEqual(again, s)
})

test("parseState drops invalid profile values", () => {
  const s = Model.parseState(JSON.stringify({
    version: 1,
    profiles: { k: { side: "diagonal", align: "weird", offsetMm: "abc", internalScale: 0, workspaces: { "1": "mars", "3": "internal", "99": "external" }, persistent: "yes" } }
  }))
  const p = Model.profileFor(s, "k")
  assert.equal(p.side, "right")
  assert.equal(p.align, "start")
  assert.equal(p.offsetMm, 0)
  assert.equal(p.internalScale, 2)
  assert.deepEqual(p.workspaces, { "3": "internal" })
  assert.equal(p.persistent, true)
})

test("profileFor returns a default profile for unknown keys without mutating state", () => {
  const s = Model.defaultState()
  const p = Model.profileFor(s, "new")
  assert.equal(p.side, "right")
  assert.equal(p.align, "start")
  assert.deepEqual(s.profiles, {})
})

test("withProfile stores an updated profile immutably", () => {
  const s = Model.defaultState()
  const next = Model.withProfile(s, "k", Object.assign(Model.defaultProfile(), { side: "left" }))
  assert.equal(next.profiles.k.side, "left")
  assert.deepEqual(s.profiles, {})
})

test("cycleAssignment goes unassigned -> external -> internal -> unassigned", () => {
  assert.equal(Model.cycleAssignment(undefined), "external")
  assert.equal(Model.cycleAssignment("external"), "internal")
  assert.equal(Model.cycleAssignment("internal"), "")
})

test("logicalSize divides by scale and rounds", () => {
  assert.deepEqual(Model.logicalSize(laptop, 2), { width: 1440, height: 900 })
  assert.deepEqual(Model.logicalSize(studio, 1.6), { width: 3200, height: 1800 })
})

test("computeLayout right + start puts external at internal width, top aligned", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "right", align: "start" })
  const l = Model.computeLayout(p, laptop, studio)
  assert.deepEqual(l.internal.position, { x: 0, y: 0 })
  assert.deepEqual(l.external.position, { x: 1440, y: 0 })
})

test("computeLayout left + end normalises to non-negative positions", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "left", align: "end" })
  const l = Model.computeLayout(p, laptop, studio)
  // external logical 2560x1440, internal 1440x900. end: ext bottom = int bottom
  // offsetMm = 190 - 330 = -140mm -> -140 * (900/190) = -663 px
  assert.deepEqual(l.external.position, { x: 0, y: 0 })
  assert.deepEqual(l.internal.position, { x: 2560, y: 663 })
})

test("computeLayout center aligns physical centres using internal density", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "right", align: "center" })
  const l = Model.computeLayout(p, laptop, studio)
  // offsetMm = (190 - 330)/2 = -70 -> -70 * 900/190 = -331.6 -> -332
  assert.deepEqual(l.external.position, { x: 1440, y: 0 })
  assert.deepEqual(l.internal.position, { x: 0, y: 332 })
})

test("computeLayout above uses horizontal cross axis and custom offset", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "above", align: "custom", offsetMm: 50 })
  const l = Model.computeLayout(p, laptop, studio)
  // 50mm * (1440/300) = 240 px to the right; external above => internal y = 1440
  assert.deepEqual(l.external.position, { x: 240, y: 0 })
  assert.deepEqual(l.internal.position, { x: 0, y: 1440 })
})

test("computeLayout below places external under the internal", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "below", align: "start" })
  const l = Model.computeLayout(p, laptop, studio)
  assert.deepEqual(l.internal.position, { x: 0, y: 0 })
  assert.deepEqual(l.external.position, { x: 0, y: 900 })
})

test("computeLayout honours profile scales", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "right", align: "start", internalScale: 1, externalScale: 1 })
  const l = Model.computeLayout(p, laptop, studio)
  assert.deepEqual(l.external.position, { x: 2880, y: 0 })
  assert.equal(l.internal.scale, 1)
})

test("computeLayout reports the shared edge overlap in mm on both monitors", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "right", align: "start" })
  const l = Model.computeLayout(p, laptop, studio)
  // internal height 190mm fully overlaps the external's top 190mm
  assert.deepEqual(l.overlap.internalMm, { from: 0, to: 190 })
  assert.equal(l.overlap.externalMm.from, 0)
  assert.ok(Math.abs(l.overlap.externalMm.to - 190 * (330 / 1440) * (900 / 190)) < 0.01)
})

test("computeLayout overlap is empty when monitors do not touch along the edge", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "right", align: "custom", offsetMm: 500 })
  const l = Model.computeLayout(p, laptop, studio)
  assert.equal(l.overlap.internalMm, null)
})

test("luaString escapes quotes, backslashes and newlines", () => {
  assert.equal(Model.luaString('a"b\\c\nd'), '"a\\"b\\\\c\\nd"')
})

test("renderLua emits monitor rules and workspace rules for the profile", () => {
  const p = Object.assign(Model.defaultProfile(), {
    side: "right", align: "start", persistent: true,
    workspaces: { "1": "external", "2": "external", "5": "internal" }
  })
  const lua = Model.renderLua(p, laptop, studio)
  const lines = lua.trim().split("\n")
  assert.match(lines[0], /^-- Generated by esemczak\.monitor-layout/)
  assert.ok(lines.includes('hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })'))
  assert.ok(lines.includes('hl.monitor({ output = "desc:Apple Computer Inc StudioDisplay 0xB65A586D", mode = "preferred", position = "1440x0", scale = 2 })'))
  assert.ok(lines.includes('hl.workspace_rule({ workspace = "1", monitor = "desc:Apple Computer Inc StudioDisplay 0xB65A586D", persistent = true })'))
  assert.ok(lines.includes('hl.workspace_rule({ workspace = "5", monitor = "eDP-1", persistent = true })'))
  assert.ok(!lua.includes('workspace = "3"'))
})

test("renderLua without persistent omits the flag and sorts workspaces numerically", () => {
  const p = Object.assign(Model.defaultProfile(), { persistent: false, workspaces: { "10": "internal", "2": "external" } })
  const lua = Model.renderLua(p, laptop, studio)
  const ws = lua.split("\n").filter(l => l.startsWith("hl.workspace_rule"))
  assert.equal(ws.length, 2)
  assert.match(ws[0], /workspace = "2"/)
  assert.match(ws[1], /workspace = "10"/)
  assert.ok(!ws[0].includes("persistent"))
})

test("renderLua with no external renders header only", () => {
  const lua = Model.renderLua(null, laptop, null)
  assert.match(lua, /^-- Generated by esemczak\.monitor-layout/)
  assert.ok(!lua.includes("hl.monitor"))
})

test("alignLabels adapt to the axis", () => {
  assert.deepEqual(Model.alignLabels("right").map(o => o.label), ["Top", "Center", "Bottom", "Custom"])
  assert.deepEqual(Model.alignLabels("above").map(o => o.label), ["Left", "Center", "Right", "Custom"])
})

test("previewBoxes scales both monitors into a bounding box in mm", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "right", align: "center" })
  const boxes = Model.previewBoxes(p, laptop, studio, 300, 150)
  assert.equal(boxes.length, 2)
  const ext = boxes.find(b => b.role === "external")
  const int = boxes.find(b => b.role === "internal")
  assert.ok(ext.width > int.width)
  assert.ok(ext.x + ext.width <= 300.01 && ext.y + ext.height <= 150.01)
  assert.ok(int.x >= 0 && int.y >= 0)
})
