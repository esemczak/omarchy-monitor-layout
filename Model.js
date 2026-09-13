// Pure helpers for the monitor-layout plugin. No Qt or Quickshell access here so
// the same file runs under `node --test` and inside the shell's QML engine.

var PLUGIN_ID = "esemczak.monitor-layout"
var STATE_PATH_SUFFIX = "/.local/state/omarchy/settings/monitor-layout.json"
var LUA_PATH_SUFFIX = "/.config/hypr/monitor-layout.lua"
var WORKSPACE_COUNT = 10
var MAX_OUTPUT_CHARS = 262144
var MAX_STATE_CHARS = 65536
var MAX_PROFILES = 32
var MAX_OFFSET_MM = 3000

var SIDES = ["left", "right", "above", "below"]
var ALIGNS = ["start", "center", "end", "custom"]
var ASSIGNMENTS = ["external", "internal"]
var SCALE_PRESETS = ["1", "1.25", "1.5", "1.6", "2", "2.5", "3"]

var INTERNAL_NAME = /^(eDP|LVDS|DSI)-/

function statePath(home) { return String(home || "") + STATE_PATH_SUFFIX }
function luaPath(home) { return String(home || "") + LUA_PATH_SUFFIX }

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

function finiteNumber(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

function cleanScale(v, fallback) {
  var n = Number(v)
  if (!isFinite(n) || n <= 0 || n > 10) return fallback
  return Math.round(n * 100) / 100
}

// ---------------------------------------------------------------------------
// Monitors (hyprctl monitors all -j)

function parseMonitors(text) {
  var raw = String(text || "")
  if (raw.length > MAX_OUTPUT_CHARS) return []
  try {
    var parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    return parsed.filter(isObject).map(normalizeMonitor).filter(function(m) { return m.name !== "" })
  } catch (e) {
    return []
  }
}

function normalizeMonitor(m) {
  return {
    name: String(m.name || ""),
    description: String(m.description || ""),
    width: finiteNumber(m.width, 0),
    height: finiteNumber(m.height, 0),
    physicalWidth: finiteNumber(m.physicalWidth, 0),
    physicalHeight: finiteNumber(m.physicalHeight, 0),
    scale: cleanScale(m.scale, 1),
    disabled: m.disabled === true,
    x: finiteNumber(m.x, 0),
    y: finiteNumber(m.y, 0)
  }
}

function isInternal(monitor) {
  return !!monitor && INTERNAL_NAME.test(String(monitor.name || ""))
}

function classifyMonitors(list) {
  var result = { internal: null, external: null }
  if (!Array.isArray(list)) return result
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!isObject(m) || typeof m.name !== "string" || m.name === "") continue
    if (isInternal(m)) {
      if (!result.internal) result.internal = m
    } else if (m.disabled !== true && !result.external) {
      result.external = m
    }
  }
  return result
}

function profileKey(monitor) {
  if (!monitor) return ""
  return String(monitor.description || monitor.name || "")
}

function monitorSelector(monitor) {
  if (!monitor) return ""
  if (isInternal(monitor)) return String(monitor.name)
  var desc = String(monitor.description || "")
  return desc ? "desc:" + desc : String(monitor.name || "")
}

function shortLabel(monitor) {
  if (!monitor) return ""
  var desc = String(monitor.description || "").trim()
  if (!desc) return String(monitor.name || "")
  // Drop a trailing hex serial like "0xB65A586D" so the label stays readable.
  return desc.replace(/\s+0x[0-9A-Fa-f]+$/, "")
}

// ---------------------------------------------------------------------------
// State

function defaultProfile() {
  return {
    side: "right",
    align: "start",
    offsetMm: 0,
    internalScale: 2,
    externalScale: 2,
    workspaces: {},
    persistent: true
  }
}

function defaultState() {
  return { version: 1, generatedProfile: "", profiles: {} }
}

function cleanWorkspaces(raw) {
  var out = {}
  if (!isObject(raw)) return out
  for (var i = 1; i <= WORKSPACE_COUNT; i++) {
    var key = String(i)
    var value = raw[key]
    if (ASSIGNMENTS.indexOf(value) >= 0) out[key] = value
  }
  return out
}

function cleanProfile(raw) {
  var base = defaultProfile()
  if (!isObject(raw)) return base
  if (SIDES.indexOf(raw.side) >= 0) base.side = raw.side
  if (ALIGNS.indexOf(raw.align) >= 0) base.align = raw.align
  var offset = Number(raw.offsetMm)
  if (isFinite(offset)) base.offsetMm = Math.max(-MAX_OFFSET_MM, Math.min(MAX_OFFSET_MM, Math.round(offset)))
  base.internalScale = cleanScale(raw.internalScale, base.internalScale)
  base.externalScale = cleanScale(raw.externalScale, base.externalScale)
  base.workspaces = cleanWorkspaces(raw.workspaces)
  if (typeof raw.persistent === "boolean") base.persistent = raw.persistent
  return base
}

function parseState(text) {
  var state = defaultState()
  var raw = String(text || "")
  if (!raw || raw.length > MAX_STATE_CHARS) return state
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return state }
  if (!isObject(parsed)) return state
  if (typeof parsed.generatedProfile === "string") state.generatedProfile = parsed.generatedProfile
  if (isObject(parsed.profiles)) {
    var keys = Object.keys(parsed.profiles).slice(0, MAX_PROFILES)
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] === "") continue
      state.profiles[keys[i]] = cleanProfile(parsed.profiles[keys[i]])
    }
  }
  return state
}

function serializeState(state) {
  var clean = parseState(JSON.stringify(state || {}))
  return JSON.stringify(clean, null, 2)
}

function profileFor(state, key) {
  if (!state || !isObject(state.profiles) || !key) return defaultProfile()
  var stored = state.profiles[key]
  return stored ? cleanProfile(stored) : defaultProfile()
}

function withProfile(state, key, profile) {
  var next = parseState(JSON.stringify(state || {}))
  if (key) next.profiles[key] = cleanProfile(profile)
  return next
}

function cycleAssignment(current) {
  if (current === "external") return "internal"
  if (current === "internal") return ""
  return "external"
}

// ---------------------------------------------------------------------------
// Layout math

function logicalSize(monitor, scale) {
  var s = cleanScale(scale, monitor && monitor.scale ? monitor.scale : 1)
  return {
    width: Math.round(finiteNumber(monitor && monitor.width, 0) / s),
    height: Math.round(finiteNumber(monitor && monitor.height, 0) / s)
  }
}

function isHorizontal(side) { return side === "left" || side === "right" }

// Offset of the external's leading edge from the internal's leading edge along
// the shared (cross) axis, in millimetres. Positive means down or right.
function crossOffsetMm(profile, internal, external) {
  var horizontal = isHorizontal(profile.side)
  var iMm = horizontal ? internal.physicalHeight : internal.physicalWidth
  var eMm = horizontal ? external.physicalHeight : external.physicalWidth
  if (profile.align === "center") return (iMm - eMm) / 2
  if (profile.align === "end") return iMm - eMm
  if (profile.align === "custom") return finiteNumber(profile.offsetMm, 0)
  return 0
}

function computeLayout(profile, internal, external) {
  var p = cleanProfile(profile)
  var iSize = logicalSize(internal, p.internalScale)
  var eSize = logicalSize(external, p.externalScale)
  var horizontal = isHorizontal(p.side)

  var iCrossMm = horizontal ? internal.physicalHeight : internal.physicalWidth
  var iCrossPx = horizontal ? iSize.height : iSize.width
  var pxPerMm = iCrossMm > 0 ? iCrossPx / iCrossMm : 0
  var crossPx = Math.round(crossOffsetMm(p, internal, external) * pxPerMm)

  var iPos = { x: 0, y: 0 }
  var ePos = { x: 0, y: 0 }
  if (p.side === "right") ePos = { x: iSize.width, y: crossPx }
  else if (p.side === "left") ePos = { x: -eSize.width, y: crossPx }
  else if (p.side === "below") ePos = { x: crossPx, y: iSize.height }
  else ePos = { x: crossPx, y: -eSize.height }

  var minX = Math.min(iPos.x, ePos.x)
  var minY = Math.min(iPos.y, ePos.y)
  iPos = { x: iPos.x - minX, y: iPos.y - minY }
  ePos = { x: ePos.x - minX, y: ePos.y - minY }

  return {
    internal: { monitor: internal, selector: monitorSelector(internal), position: iPos, size: iSize, scale: p.internalScale },
    external: { monitor: external, selector: monitorSelector(external), position: ePos, size: eSize, scale: p.externalScale },
    overlap: sharedEdgeOverlap(p.side, internal, external, iPos, iSize, ePos, eSize)
  }
}

function sharedEdgeOverlap(side, internal, external, iPos, iSize, ePos, eSize) {
  var horizontal = isHorizontal(side)
  var iStart = horizontal ? iPos.y : iPos.x
  var iLen = horizontal ? iSize.height : iSize.width
  var eStart = horizontal ? ePos.y : ePos.x
  var eLen = horizontal ? eSize.height : eSize.width
  var from = Math.max(iStart, eStart)
  var to = Math.min(iStart + iLen, eStart + eLen)
  if (to <= from) return { internalMm: null, externalMm: null }
  var iMm = horizontal ? internal.physicalHeight : internal.physicalWidth
  var eMm = horizontal ? external.physicalHeight : external.physicalWidth
  var iRatio = iLen > 0 ? iMm / iLen : 0
  var eRatio = eLen > 0 ? eMm / eLen : 0
  return {
    internalMm: { from: (from - iStart) * iRatio, to: (to - iStart) * iRatio },
    externalMm: { from: (from - eStart) * eRatio, to: (to - eStart) * eRatio }
  }
}

// Physical arrangement (mm) fitted into a box of the given pixel size.
function previewBoxes(profile, internal, external, boxWidth, boxHeight) {
  var p = cleanProfile(profile)
  var iw = finiteNumber(internal && internal.physicalWidth, 0)
  var ih = finiteNumber(internal && internal.physicalHeight, 0)
  var rects = [{ role: "internal", x: 0, y: 0, w: iw, h: ih, monitor: internal }]
  if (external) {
    var ew = finiteNumber(external.physicalWidth, 0)
    var eh = finiteNumber(external.physicalHeight, 0)
    var cross = crossOffsetMm(p, internal, external)
    var rect = { role: "external", x: 0, y: 0, w: ew, h: eh, monitor: external }
    if (p.side === "right") { rect.x = iw; rect.y = cross }
    else if (p.side === "left") { rect.x = -ew; rect.y = cross }
    else if (p.side === "below") { rect.x = cross; rect.y = ih }
    else { rect.x = cross; rect.y = -eh }
    rects.push(rect)
  }
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var i = 0; i < rects.length; i++) {
    minX = Math.min(minX, rects[i].x); minY = Math.min(minY, rects[i].y)
    maxX = Math.max(maxX, rects[i].x + rects[i].w); maxY = Math.max(maxY, rects[i].y + rects[i].h)
  }
  var spanX = Math.max(1, maxX - minX)
  var spanY = Math.max(1, maxY - minY)
  var k = Math.min(boxWidth / spanX, boxHeight / spanY)
  var offX = (boxWidth - spanX * k) / 2
  var offY = (boxHeight - spanY * k) / 2
  return rects.map(function(r) {
    return {
      role: r.role,
      monitor: r.monitor,
      x: offX + (r.x - minX) * k,
      y: offY + (r.y - minY) * k,
      width: r.w * k,
      height: r.h * k
    }
  })
}

function alignLabels(side) {
  var horizontal = isHorizontal(side)
  return [
    { value: "start", label: horizontal ? "Top" : "Left" },
    { value: "center", label: "Center" },
    { value: "end", label: horizontal ? "Bottom" : "Right" },
    { value: "custom", label: "Custom" }
  ]
}

var SIDE_OPTIONS = [
  { value: "left", label: "Left" },
  { value: "right", label: "Right" },
  { value: "above", label: "Above" },
  { value: "below", label: "Below" }
]

// ---------------------------------------------------------------------------
// Lua rendering

function luaString(value) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n")
  // Control characters have no place in a monitor description; strip them.
  s = s.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
  return '"' + s + '"'
}

function luaNumber(n) {
  var v = Number(n)
  if (!isFinite(v)) return "0"
  return String(Math.round(v * 100) / 100)
}

function monitorRule(entry) {
  return "hl.monitor({ output = " + luaString(entry.selector)
    + ", mode = \"preferred\", position = " + luaString(entry.position.x + "x" + entry.position.y)
    + ", scale = " + luaNumber(entry.scale) + " })"
}

function renderLua(profile, internal, external) {
  var lines = [
    "-- Generated by " + PLUGIN_ID + ". Edits are overwritten on apply.",
    "-- Placement and workspace binding for the external monitor; see the plugin panel."
  ]
  if (!profile || !internal || !external) return lines.join("\n") + "\n"

  var layout = computeLayout(profile, internal, external)
  var p = cleanProfile(profile)
  lines.push("")
  lines.push(monitorRule(layout.internal))
  lines.push(monitorRule(layout.external))

  var ids = Object.keys(p.workspaces).map(Number).filter(isFinite).sort(function(a, b) { return a - b })
  if (ids.length) lines.push("")
  for (var i = 0; i < ids.length; i++) {
    var id = String(ids[i])
    var target = p.workspaces[id] === "internal" ? layout.internal.selector : layout.external.selector
    var rule = "hl.workspace_rule({ workspace = " + luaString(id) + ", monitor = " + luaString(target)
    if (p.persistent) rule += ", persistent = true"
    rule += " })"
    lines.push(rule)
  }
  return lines.join("\n") + "\n"
}

// ---------------------------------------------------------------------------
// Bootstrap payload from bin/bootstrap-state.sh

function parseBootstrapPayload(text) {
  var out = { state: "", monitors: [], requireInstalled: false, luaExists: false }
  var raw = String(text || "")
  if (!raw || raw.length > MAX_OUTPUT_CHARS) return out
  try {
    var parsed = JSON.parse(raw)
    if (!isObject(parsed)) return out
    if (typeof parsed.state === "string") out.state = parsed.state
    if (Array.isArray(parsed.monitors)) out.monitors = parsed.monitors.filter(isObject).map(normalizeMonitor)
    out.requireInstalled = parsed.requireInstalled === true
    out.luaExists = parsed.luaExists === true
  } catch (e) {}
  return out
}

function parseApplyResult(text) {
  var out = { ok: false, requireInstalled: false, reloaded: false, errors: [], message: "" }
  var raw = String(text || "")
  if (!raw || raw.length > MAX_OUTPUT_CHARS) { out.message = "Apply produced no result"; return out }
  try {
    var parsed = JSON.parse(raw)
    if (!isObject(parsed)) { out.message = "Apply produced no result"; return out }
    out.ok = parsed.ok === true
    out.requireInstalled = parsed.requireInstalled === true
    out.reloaded = parsed.reloaded === true
    if (Array.isArray(parsed.errors)) out.errors = parsed.errors.map(function(e) { return String(e) }).slice(0, 20)
    if (typeof parsed.message === "string") out.message = parsed.message
  } catch (e) {
    out.message = "Apply produced unreadable output"
  }
  return out
}

function summarizeMonitors(internal, external) {
  if (!internal && !external) return "No monitors detected"
  if (!external) return "Laptop only · connect an external monitor to arrange it"
  var extLabel = shortLabel(external)
  var intLabel = internal ? internal.name : "no laptop panel"
  return extLabel + " · " + intLabel
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID, WORKSPACE_COUNT: WORKSPACE_COUNT, SIDES: SIDES, ALIGNS: ALIGNS,
    SCALE_PRESETS: SCALE_PRESETS, SIDE_OPTIONS: SIDE_OPTIONS, MAX_OUTPUT_CHARS: MAX_OUTPUT_CHARS,
    statePath: statePath, luaPath: luaPath,
    parseMonitors: parseMonitors, classifyMonitors: classifyMonitors, isInternal: isInternal,
    profileKey: profileKey, monitorSelector: monitorSelector, shortLabel: shortLabel,
    defaultProfile: defaultProfile, defaultState: defaultState, parseState: parseState,
    serializeState: serializeState, profileFor: profileFor, withProfile: withProfile,
    cycleAssignment: cycleAssignment, logicalSize: logicalSize, computeLayout: computeLayout,
    previewBoxes: previewBoxes, alignLabels: alignLabels, luaString: luaString, renderLua: renderLua,
    parseBootstrapPayload: parseBootstrapPayload, parseApplyResult: parseApplyResult,
    summarizeMonitors: summarizeMonitors
  }
}
