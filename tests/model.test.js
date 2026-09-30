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

test("calendar starts weeks on Monday and highlights today in the displayed month", () => {
  const days = Model.calendarDays(2026, 8, 30)
  assert.equal(days.length, 42)
  assert.deepEqual(days[0], { day: 31, currentMonth: false, today: false })
  assert.deepEqual(days[1], { day: 1, currentMonth: true, today: false })
  assert.deepEqual(days[30], { day: 30, currentMonth: true, today: true })
  assert.deepEqual(days[31], { day: 1, currentMonth: false, today: false })
  assert.equal(days.filter(day => day.today).length, 1)
})

test("calendar includes leap day and handles Sunday starts and year boundaries", () => {
  const leap = Model.calendarDays(2024, 1, 29)
  assert.deepEqual(leap[31], { day: 29, currentMonth: true, today: true })
  assert.deepEqual(leap[32], { day: 1, currentMonth: false, today: false })
  const sunday = Model.calendarDays(2026, 1, 1)
  assert.deepEqual(sunday[5], { day: 31, currentMonth: false, today: false })
  assert.deepEqual(sunday[6], { day: 1, currentMonth: true, today: true })
  const january = Model.calendarDays(2027, 0, 1)
  assert.deepEqual(january[0], { day: 28, currentMonth: false, today: false })
  assert.deepEqual(january[4], { day: 1, currentMonth: true, today: true })
  assert.deepEqual(january[41], { day: 7, currentMonth: false, today: false })
})

test("screensaver weather accepts the Omarchy status and hides unavailable responses", () => {
  assert.equal(Model.parseWeatherStatus("Adelaide  ·  Temp 18°C  ·  Wind 12 km/h\n"), "Adelaide · Temp 18°C · Wind 12 km/h")
  assert.equal(Model.parseWeatherStatus("Weather unavailable\n"), "")
  assert.equal(Model.parseWeatherStatus(" \n"), "")
  assert.equal(Model.parseWeatherStatus("x".repeat(4097)), "")
})

test("laptop screensaver preference survives saves and defaults off for existing state", () => {
  assert.equal(Model.parseState('{"profiles":{}}').laptopScreensaver, false)
  const state = Model.parseState('{"laptopScreensaver":true,"profiles":{"desk":{"side":"left"}}}')
  const updated = Model.withProfile(state, "desk", { side: "right" })
  assert.equal(Model.parseState(Model.serializeState(updated)).laptopScreensaver, true)
  assert.equal(Model.parseState('{"laptopScreensaver":"true"}').laptopScreensaver, false)
})

test("screensaver brightness is saved globally, defaults to minimum and clamps invalid values", () => {
  assert.equal(Model.parseState("{}").screensaverBrightness, 0)
  const state = Model.parseState('{"screensaverBrightness":12.6}')
  const updated = Model.withProfile(state, "desk", { side: "left" })
  assert.equal(Model.parseState(Model.serializeState(updated)).screensaverBrightness, 13)
  assert.equal(Model.parseState('{"screensaverBrightness":-5}').screensaverBrightness, 0)
  assert.equal(Model.parseState('{"screensaverBrightness":120}').screensaverBrightness, 100)
  assert.equal(Model.parseState('{"screensaverBrightness":"bad"}').screensaverBrightness, 0)
})

test("screensaver targets only an active laptop with an active external display", () => {
  assert.equal(Model.laptopScreensaverTarget(true, [studio, laptop]), "eDP-1")
  assert.equal(Model.laptopScreensaverTarget(false, [studio, laptop]), "")
  assert.equal(Model.laptopScreensaverTarget(true, [laptop]), "")
  assert.equal(Model.laptopScreensaverTarget(true, [studio]), "")
  assert.equal(Model.laptopScreensaverTarget(true, [laptop, { ...studio, disabled: true }]), "")
  assert.equal(Model.laptopScreensaverTarget(true, [{ ...laptop, disabled: true }, studio]), "")
  assert.equal(Model.laptopScreensaverTarget(true, null), "")
  // QML exposes a sequence, which need not be a native JavaScript Array.
  assert.equal(Model.laptopScreensaverTarget(true, { 0: studio, 1: laptop, length: 2 }), "eDP-1")
})

test("screensaver waits for a known cursor outside the laptop and laptop focus to leave", () => {
  const screen = { name: "eDP-1", x: -1440, y: 100, width: 1440, height: 900 }
  assert.equal(Model.screensaverMayShow(screen, { x: 20, y: 150 }, "DP-1", false), true)
  assert.equal(Model.screensaverMayShow(screen, { x: -100, y: 150 }, "DP-1", false), false)
  assert.equal(Model.screensaverMayShow(screen, { x: -1440, y: 100 }, "DP-1", false), false)
  assert.equal(Model.screensaverMayShow(screen, { x: 0, y: 150 }, "DP-1", false), true)
  assert.equal(Model.screensaverMayShow(screen, { x: 20, y: 150 }, "eDP-1", false), false)
  assert.equal(Model.screensaverMayShow(screen, { x: 20, y: 150 }, "DP-1", true), false)
  assert.equal(Model.screensaverMayShow(screen, null, "DP-1", false), false)
  assert.equal(Model.screensaverMayShow(null, { x: 20, y: 150 }, "DP-1", false), false)
})

test("invalid cursor responses cannot arm the screensaver", () => {
  assert.deepEqual(Model.parseCursorPosition('{"x":-120,"y":350}'), { x: -120, y: 350 })
  for (const text of ["", "oops", "{}", '{"x":null,"y":0}', '{"x":"20","y":0}']) {
    assert.equal(Model.parseCursorPosition(text), null)
  }
})

test("stateFilePath honours XDG_STATE_HOME", () => {
  assert.equal(Model.stateFilePath("/home/u", ""), "/home/u/.local/state/omarchy/settings/monitor-layout.json")
  assert.equal(Model.stateFilePath("/home/u", "/tmp/st"), "/tmp/st/omarchy/settings/monitor-layout.json")
})

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

// ---------------------------------------------------------------------------
// Adopting scale changes made by omarchy-hyprland-monitor-scaling

test("parseScalingPayload reads the audit entry, log age and state text", () => {
  const raw = '{"logMtime":1700000000.5,"age":3.2,"scaling":{"at":1700000000,"monitor":"DP-1","scale":1.6},"state":"{\\"version\\":1}"}'
  assert.deepEqual(Model.parseScalingPayload(raw), {
    logMtime: 1700000000.5, age: 3.2, scaling: { at: 1700000000, monitor: "DP-1", scale: 1.6 }, state: '{"version":1}'
  })
})

test("parseScalingPayload tolerates a missing log and garbage", () => {
  const empty = { logMtime: 0, age: 0, scaling: null, state: "" }
  assert.deepEqual(Model.parseScalingPayload('{"logMtime":0,"age":0,"scaling":null,"state":""}'), empty)
  assert.deepEqual(Model.parseScalingPayload("nope"), empty)
  assert.deepEqual(Model.parseScalingPayload(""), empty)
  assert.deepEqual(Model.parseScalingPayload('{"logMtime":"x","age":"y","scaling":{"at":1,"monitor":"","scale":2},"state":5}'), empty)
  assert.equal(Model.parseScalingPayload('{"logMtime":5,"scaling":{"at":"x","monitor":"DP-1","scale":1.6}}').scaling, null)
  assert.equal(Model.parseScalingPayload('{"logMtime":5,"scaling":{"at":1,"monitor":"DP-1","scale":0}}').scaling, null)
  assert.equal(Model.parseScalingPayload('{"logMtime":5,"scaling":"junk"}').scaling, null)
})

test("parseState keeps the handled scaling log mtime and withScalingLogMtime replaces it", () => {
  assert.equal(Model.defaultState().scalingLogMtime, 0)
  const s = Model.withScalingLogMtime(Model.defaultState(), 1700000000.5)
  assert.equal(s.scalingLogMtime, 1700000000.5)
  assert.equal(Model.parseState(Model.serializeState(s)).scalingLogMtime, 1700000000.5)
  assert.equal(Model.parseState('{"scalingLogMtime":"x"}').scalingLogMtime, 0)
  assert.equal(Model.parseState('{"scalingLogMtime":-4}').scalingLogMtime, 0)
})

test("scalingRequest accepts a fresh, unhandled audit entry", () => {
  const payload = { logMtime: 100.5, age: 2, scaling: { at: 100, monitor: "DP-1", scale: 1.6 }, state: "" }
  assert.deepEqual(Model.scalingRequest(payload, 90), { monitor: "DP-1", scale: 1.6 })
  assert.deepEqual(Model.scalingRequest(payload, 0), { monitor: "DP-1", scale: 1.6 })
})

test("scalingRequest ignores handled, stale or missing entries", () => {
  const scaling = { at: 100, monitor: "DP-1", scale: 1.6 }
  assert.equal(Model.scalingRequest({ logMtime: 100.5, age: 2, scaling: scaling, state: "" }, 100.5), null)
  assert.equal(Model.scalingRequest({ logMtime: 100.5, age: 600, scaling: scaling, state: "" }, 90), null)
  assert.equal(Model.scalingRequest({ logMtime: 0, age: 0, scaling: null, state: "" }, 0), null)
  assert.equal(Model.scalingRequest({ logMtime: 100.5, age: 2, scaling: null, state: "" }, 90), null)
})

test("scalePatchForMonitor targets the profile field for the named monitor", () => {
  const p = Object.assign(Model.defaultProfile(), { internalScale: 1.6, externalScale: 2 })
  assert.deepEqual(Model.scalePatchForMonitor(p, laptop, studio, "eDP-1", 2), { internalScale: 2 })
  assert.deepEqual(Model.scalePatchForMonitor(p, laptop, studio, "DP-1", 1.6), { externalScale: 1.6 })
})

test("scalePatchForMonitor is null when nothing would change or the monitor is unknown", () => {
  const p = Object.assign(Model.defaultProfile(), { internalScale: 1.6, externalScale: 2 })
  assert.equal(Model.scalePatchForMonitor(p, laptop, studio, "eDP-1", 1.6), null)
  assert.equal(Model.scalePatchForMonitor(p, laptop, studio, "HDMI-A-1", 1), null)
  assert.equal(Model.scalePatchForMonitor(p, laptop, studio, "", 1), null)
  assert.equal(Model.scalePatchForMonitor(p, null, studio, "eDP-1", 1), null)
  assert.equal(Model.scalePatchForMonitor(p, laptop, studio, "eDP-1", 0), null)
  assert.equal(Model.scalePatchForMonitor(p, laptop, studio, "eDP-1", "nope"), null)
})

test("cleanProfile keeps a remembered external monitor snapshot", () => {
  const p = Object.assign(Model.defaultProfile(), { monitor: studio })
  const clean = Model.cleanProfile(p)
  assert.deepEqual(Model.rememberedExternal(clean), Model.parseMonitors(JSON.stringify([studio]))[0])
  const round = Model.profileFor(Model.withProfile(Model.defaultState(), "k", p), "k")
  assert.equal(Model.rememberedExternal(round).description, studio.description)
})

test("cleanProfile drops an unusable monitor snapshot", () => {
  assert.equal(Model.rememberedExternal(Model.cleanProfile(Model.defaultProfile())), null)
  assert.equal(Model.rememberedExternal(Model.cleanProfile({ monitor: "DP-1" })), null)
  assert.equal(Model.rememberedExternal(Model.cleanProfile({ monitor: { description: "no name" } })), null)
  assert.equal(Model.rememberedExternal(Model.cleanProfile({ monitor: { name: "DP-1", width: 0, height: 0 } })), null)
  assert.equal(Model.rememberedExternal(null), null)
})

test("renderLua from a remembered external matches the live render", () => {
  const p = Object.assign(Model.defaultProfile(), { side: "left", internalScale: 1.6, workspaces: { "1": "external" } })
  const remembered = Model.rememberedExternal(Model.cleanProfile(Object.assign({}, p, { monitor: studio })))
  assert.equal(Model.renderLua(p, laptop, remembered), Model.renderLua(p, laptop, studio))
})

test("renderLua with internal only emits the laptop rule and laptop-bound workspaces", () => {
  const p = Object.assign(Model.defaultProfile(), { internalScale: 1.25, workspaces: { "1": "external", "5": "internal" } })
  const lua = Model.renderLua(p, laptop, null)
  assert.ok(lua.includes('hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.25 })'))
  assert.ok(!lua.includes("desc:"))
  assert.ok(lua.includes('hl.workspace_rule({ workspace = "5", monitor = "eDP-1", persistent = true })'))
  assert.ok(!lua.includes('workspace = "1"'))
})

test("renderLua with no profile or no internal renders header only", () => {
  assert.ok(!Model.renderLua(null, laptop, null).includes("hl.monitor"))
  assert.ok(!Model.renderLua(Model.defaultProfile(), null, studio).includes("hl.monitor"))
})
