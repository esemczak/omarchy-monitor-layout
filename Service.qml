import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// Owns plugin state, monitor discovery and the apply pipeline. Panel.qml is a
// view over this object; nothing here touches the UI.
Item {
  id: root

  property var settings: ({})
  property var state: Model.defaultState()
  property bool stateLoaded: false
  property var monitors: []
  property bool requireInstalled: false
  property bool luaExists: false
  property bool applying: false
  property bool installing: false
  property var lastResult: ({ ok: false, message: "", errors: [] })
  property string lastError: ""
  property bool autoApplyPending: false
  // A scaling-log read finished before the state loaded.
  property bool scalingCheckPending: false
  // Apply waiting for the monitors.lua sync and state write it depends on.
  property var queuedApply: null
  // What the running apply is for, so its result lands on the right profile.
  property string applyKey: ""
  property var applyExternal: null

  readonly property string pluginDir: {
    var scriptUrl = Qt.resolvedUrl("bin/lib.sh")
    var path = String(scriptUrl || "")
    if (path.indexOf("file://") === 0) path = path.substring(7)
    var slash = path.lastIndexOf("/bin/")
    return slash >= 0 ? path.substring(0, slash) : Quickshell.env("HOME") + "/.config/omarchy/plugins/" + Model.PLUGIN_ID
  }

  readonly property string stateFilePath: Model.stateFilePath(Quickshell.env("HOME"), Quickshell.env("XDG_STATE_HOME"))
  readonly property string stateDirPath: stateFilePath.substring(0, stateFilePath.lastIndexOf("/"))

  readonly property var classified: Model.classifyMonitors(monitors)
  readonly property var internal: classified.internal
  readonly property var external: classified.external
  readonly property string externalKey: Model.profileKey(external)
  readonly property bool hasProfile: externalKey !== "" && !!state.profiles[externalKey]
  readonly property var profile: Model.profileFor(state, externalKey)
  readonly property var layout: internal && external ? Model.computeLayout(profile, internal, external) : null
  readonly property string summary: Model.summarizeMonitors(internal, external)
  readonly property bool canApply: !!internal && !!external && !applying
  readonly property var savedProfileKeys: Object.keys(state.profiles || {})

  signal applied(bool ok)

  // ---- state -------------------------------------------------------------

  function updateProfile(patch) {
    if (!externalKey || !stateLoaded) return
    var next = Object.assign({}, profile, patch || {})
    state = Model.withProfile(state, externalKey, next)
    scheduleStateSave()
  }

  function setSide(side) { updateProfile({ side: side }) }
  function setAlign(align) { updateProfile({ align: align }) }
  function setOffsetMm(value) { updateProfile({ offsetMm: Number(value) }) }
  function setInternalScale(value) { updateProfile({ internalScale: Number(value) }) }
  function setExternalScale(value) { updateProfile({ externalScale: Number(value) }) }
  function setPersistent(enabled) { updateProfile({ persistent: !!enabled }) }

  function setLaptopScreensaver(enabled) {
    if (!stateLoaded) return
    var next = Model.parseState(JSON.stringify(state))
    next.laptopScreensaver = !!enabled
    state = next
    scheduleStateSave()
  }

  function setScreensaverBrightness(value) {
    if (!stateLoaded) return
    var next = Model.parseState(JSON.stringify(state))
    next.screensaverBrightness = Model.cleanScreensaverBrightness(value)
    state = next
    scheduleStateSave()
  }

  function setWorkspace(id, target) {
    var key = String(Number(id))
    if (Number(key) < 1 || Number(key) > Model.WORKSPACE_COUNT) return
    var next = Object.assign({}, profile.workspaces)
    if (target === "external" || target === "internal") next[key] = target
    else delete next[key]
    updateProfile({ workspaces: next })
  }

  function cycleWorkspace(id) {
    var key = String(id)
    var next = Object.assign({}, profile.workspaces)
    var value = Model.cycleAssignment(next[key])
    if (value) next[key] = value
    else delete next[key]
    updateProfile({ workspaces: next })
  }

  function forgetProfile(key) {
    var next = Model.parseState(JSON.stringify(state))
    delete next.profiles[key]
    if (next.generatedProfile === key) next.generatedProfile = ""
    state = next
    scheduleStateSave()
  }

  // The bar hosts one Service per monitor and IPC lands on whichever registered
  // first, so the state file is the source of truth: every instance re-adopts it
  // when it changes. A pending local save wins over what is on disk until it lands.
  function adoptStateText(text) {
    if (stateSaveTimer.running || stateWriter.running) return
    var next = Model.parseState(text)
    if (JSON.stringify(next) !== JSON.stringify(state)) state = next
  }

  function scheduleStateSave() {
    if (!stateLoaded) return
    stateSaveTimer.restart()
  }

  function flushState() {
    if (!stateLoaded || stateWriter.running) { if (stateLoaded) stateSaveTimer.restart(); return }
    var payload = Model.serializeState(state)
    stateWriter.command = ["bash", "-c", "printf '%s' " + shellQuote(payload) + " | bash " + shellQuote(pluginDir + "/bin/safe-write-state.sh")]
    stateWriter.running = true
  }

  // ---- discovery ---------------------------------------------------------

  function reload() {
    if (bootstrapProc.running) return
    bootstrapProc.running = true
  }

  function refreshMonitors() {
    if (monitorsProc.running) { monitorsRefreshTimer.restart(); return }
    monitorsProc.running = true
  }

  function onMonitorsRefreshed() {
    // A monitor with a saved profile that differs from what the Lua file was
    // last generated for: regenerate so its placement and workspaces follow it.
    // Also regenerate once for profiles saved before the external's geometry
    // was remembered, or after a laptop-only regeneration dropped its rule.
    if (external && hasProfile && requireInstalled
        && (state.generatedProfile !== externalKey || !Model.rememberedExternal(profile)))
      apply()
  }

  // ---- scale changes from Omarchy's Display panel --------------------------

  function checkScalingLog() {
    if (scalingProc.running) { scalingCheckTimer.restart(); return }
    scalingProc.running = true
  }

  // One Service runs per bar and a scale change rebuilds the bar, so decide
  // from what is on disk: the state text in the payload says which audit entry
  // was handled last, and adoption patches that on-disk state rather than a
  // copy another instance may have overtaken.
  function onScalingLogRead(payload) {
    if (!stateLoaded) { scalingCheckPending = true; return }
    var disk = Model.parseState(payload.state)
    var request = Model.scalingRequest(payload, disk.scalingLogMtime)
    if (!request) {
      // Nothing to adopt, but remember an unhandled (e.g. stale) entry so a
      // later reload does not keep re-evaluating it.
      if (payload.logMtime > 0 && payload.logMtime !== disk.scalingLogMtime && !stateSaveTimer.running && !stateWriter.running) {
        state = Model.withScalingLogMtime(disk, payload.logMtime)
        flushState()
      }
      return
    }
    if (!stateSaveTimer.running && !stateWriter.running) state = disk
    state = Model.withScalingLogMtime(state, payload.logMtime)
    adoptScale(request.monitor, request.scale)
  }

  // Set the scale Omarchy's tool applied to a monitor on the current profile
  // and regenerate the Lua. With the external unplugged the target is the
  // profile the file was last generated for, using its remembered geometry.
  function adoptScale(monitorName, scale) {
    var key = externalKey || state.generatedProfile
    if (!key || !state.profiles[key] || !internal) { flushState(); return }
    var target = Model.profileFor(state, key)
    var ext = external || Model.rememberedExternal(target)
    var patch = Model.scalePatchForMonitor(target, internal, ext, monitorName, scale)
    if (!patch) { flushState(); return }
    state = Model.withProfile(state, key, Object.assign({}, target, patch))
    // Without any external geometry renderLua keeps only the laptop rule; the
    // full layout comes back on hotplug via onMonitorsRefreshed.
    var updated = Model.profileFor(state, key)
    if (requireInstalled && !applying) queueApply(Model.renderLua(updated, internal, ext), key, external, updated.internalScale)
    else flushState()
  }

  // ---- apply -------------------------------------------------------------

  function renderedLua() {
    if (!internal || !external) return Model.renderLua(null, null, null)
    return Model.renderLua(profile, internal, external)
  }

  function apply() {
    if (!canApply) return
    if (applyProc.running) { autoApplyPending = true; return }
    queueApply(renderedLua(), externalKey, external, layout.internal.scale)
  }

  // Apply in three steps: persist the laptop scale into monitors.lua, land the
  // state on disk, then write the layout and reload. The state must be saved
  // first because applying can change a scale, which rebuilds the bar and this
  // Service with it before a deferred save could run.
  function queueApply(lua, key, liveExternal, laptopScale) {
    if (applying || syncProc.running) return
    applying = true
    lastError = ""
    queuedApply = { lua: lua, key: key, external: liveExternal || null }
    syncProc.command = ["bash", pluginDir + "/bin/sync-monitors-lua.sh", Model.luaNumber(laptopScale)]
    syncProc.running = true
  }

  function onMonitorsLuaSynced() {
    if (stateLoaded) { flushState(); return }
    var pending = queuedApply
    queuedApply = null
    if (pending) applyLua(pending.lua, pending.key, pending.external)
  }

  function applyLua(lua, key, liveExternal) {
    if (applyProc.running) return
    applying = true
    lastError = ""
    applyKey = key
    applyExternal = liveExternal || null
    applyProc.command = ["bash", "-c", "printf '%s' " + shellQuote(lua) + " | bash " + shellQuote(pluginDir + "/bin/apply-layout.sh")]
    applyProc.running = true
  }

  function installRequire() {
    if (installProc.running) return
    installing = true
    lastError = ""
    installProc.running = true
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function stdoutOverLimit(text, limit) {
    return String(text || "").length > limit
  }

  // ---- processes ---------------------------------------------------------

  Timer {
    id: stateSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushState()
  }

  Timer {
    id: stateReloadTimer
    interval: 150
    repeat: false
    onTriggered: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.stateFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.adoptStateText(text())
    onFileChanged: stateReloadTimer.restart()
  }

  // Atomic writes replace the inode, so also watch the directory.
  FileView {
    path: root.stateDirPath
    watchChanges: true
    printErrors: false
    onFileChanged: stateReloadTimer.restart()
  }

  Timer {
    id: monitorsRefreshTimer
    interval: 600
    repeat: false
    onTriggered: root.refreshMonitors()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name === "monitoradded" || name === "monitorremoved"
          || name === "monitoraddedv2" || name === "monitorremovedv2"
          || name === "configreloaded")
        monitorsRefreshTimer.restart()
      if (name === "configreloaded") scalingCheckTimer.restart()
    }
  }

  // omarchy-hyprland-monitor-scaling appends to its audit log, then rewrites
  // monitors.lua, which makes Hyprland reload and undo its live change. Read
  // the log after every append or reload and adopt the entry it recorded.
  Timer {
    id: scalingCheckTimer
    interval: 300
    repeat: false
    onTriggered: root.checkScalingLog()
  }

  readonly property string omarchyStateDir: stateDirPath.substring(0, stateDirPath.lastIndexOf("/"))

  FileView {
    path: root.omarchyStateDir + "/monitor-scaling.log"
    watchChanges: true
    printErrors: false
    onFileChanged: scalingCheckTimer.restart()
  }

  // The log is appended in place, but may not exist yet: watch its directory
  // for it to appear (Hyprland's configreloaded covers the append itself).
  FileView {
    path: root.omarchyStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: scalingCheckTimer.restart()
  }

  Process {
    id: scalingProc
    command: ["bash", root.pluginDir + "/bin/read-scaling-log.sh"]
    stdout: StdioCollector {
      id: scalingStdout
      waitForEnd: true
      onStreamFinished: {
        if (root.stdoutOverLimit(scalingStdout.text, Model.MAX_OUTPUT_CHARS)) return
        root.onScalingLogRead(Model.parseScalingPayload(scalingStdout.text))
      }
    }
  }

  Process {
    id: bootstrapProc
    command: ["bash", root.pluginDir + "/bin/bootstrap-state.sh"]
    stdout: StdioCollector {
      id: bootstrapStdout
      waitForEnd: true
      onStreamFinished: {
        if (root.stdoutOverLimit(bootstrapStdout.text, Model.MAX_OUTPUT_CHARS)) {
          root.lastError = "Startup data too large"
          root.stateLoaded = true
          return
        }
        var payload = Model.parseBootstrapPayload(bootstrapStdout.text)
        root.state = Model.parseState(payload.state)
        root.monitors = payload.monitors
        root.requireInstalled = payload.requireInstalled
        root.luaExists = payload.luaExists
        root.stateLoaded = true
        root.onMonitorsRefreshed()
        if (root.scalingCheckPending) { root.scalingCheckPending = false; root.checkScalingLog() }
      }
    }
    onExited: function(code) {
      if (code !== 0 && !root.stateLoaded) {
        root.stateLoaded = true
        root.lastError = "Could not read plugin state"
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      id: monitorsStdout
      waitForEnd: true
      onStreamFinished: {
        if (root.stdoutOverLimit(monitorsStdout.text, Model.MAX_OUTPUT_CHARS)) return
        var list = Model.parseMonitors(monitorsStdout.text)
        if (list.length) root.monitors = list
        root.onMonitorsRefreshed()
      }
    }
  }

  Process {
    id: stateWriter
    onExited: function(code) {
      if (code !== 0) root.lastError = "Failed to save settings"
      var pending = root.queuedApply
      root.queuedApply = null
      if (pending) root.applyLua(pending.lua, pending.key, pending.external)
    }
  }

  Process {
    id: syncProc
    onExited: root.onMonitorsLuaSynced()
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      id: applyStdout
      waitForEnd: true
      onStreamFinished: {
        var result = Model.parseApplyResult(applyStdout.text)
        root.lastResult = result
        root.requireInstalled = result.requireInstalled
        root.luaExists = root.luaExists || result.ok
        if (result.ok) {
          var next = Model.parseState(JSON.stringify(root.state))
          next.generatedProfile = root.applyKey
          // Remember the external's geometry so the file can be regenerated
          // for this profile while the monitor is unplugged.
          if (root.applyExternal && next.profiles[root.applyKey])
            next.profiles[root.applyKey].monitor = root.applyExternal
          root.state = next
          root.scheduleStateSave()
        } else {
          root.lastError = result.message || "Apply failed"
        }
        root.applying = false
        root.applied(result.ok)
        if (root.autoApplyPending) {
          root.autoApplyPending = false
          root.apply()
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) {
        root.applying = false
        root.lastError = "Apply script failed"
      }
    }
  }

  Process {
    id: installProc
    command: ["bash", root.pluginDir + "/bin/install-require.sh"]
    onExited: function(code) {
      root.installing = false
      if (code === 0) {
        root.requireInstalled = true
        root.lastResult = { ok: true, message: "hyprland.lua now loads monitor-layout.lua", errors: [] }
        if (root.canApply) root.apply()
      } else {
        root.lastError = "Could not edit hyprland.lua"
      }
    }
  }

  Component.onCompleted: { reload(); checkScalingLog() }
}
