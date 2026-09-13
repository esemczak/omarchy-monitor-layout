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
    if (external && hasProfile && state.generatedProfile !== externalKey && requireInstalled)
      apply()
  }

  // ---- apply -------------------------------------------------------------

  function renderedLua() {
    if (!internal || !external) return Model.renderLua(null, null, null)
    return Model.renderLua(profile, internal, external)
  }

  function apply() {
    if (!canApply) return
    if (applyProc.running) { autoApplyPending = true; return }
    applying = true
    lastError = ""
    var lua = renderedLua()
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
    }
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
          next.generatedProfile = root.externalKey
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

  Component.onCompleted: reload()
}
