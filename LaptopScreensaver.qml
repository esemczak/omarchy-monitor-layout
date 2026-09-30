pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// Shared by every bar instance. Registration also works when the bar is shown
// only on an external display, and releases the overlay when the widget unloads.
Scope {
  id: root

  property var owners: []
  property var cursorPosition: null
  property bool showing: false
  property string weatherText: ""
  property double weatherAttemptedAt: 0
  readonly property var service: owners.length ? owners[0].monitorService : null
  readonly property bool enabled: !!service && service.stateLoaded && service.state.laptopScreensaver
  readonly property int brightness: service ? service.state.screensaverBrightness : 0
  readonly property string targetName: Model.laptopScreensaverTarget(enabled, Quickshell.screens)
  readonly property var targetScreen: {
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i].name === targetName) return Quickshell.screens[i]
    }
    return null
  }
  readonly property bool panelOpen: {
    for (var i = 0; i < owners.length; i++) if (owners[i].opened) return true
    return false
  }
  readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  readonly property bool mayShow: Model.screensaverMayShow(targetScreen, cursorPosition, focusedName, panelOpen)

  function registerOwner(owner) {
    if (owners.indexOf(owner) < 0) owners = owners.concat([owner])
  }

  function unregisterOwner(owner) {
    owners = owners.filter(function(item) { return item !== owner })
  }

  function setEnabled(value) {
    if (service) service.setLaptopScreensaver(value)
  }

  function setBrightness(value) {
    if (service) service.setScreensaverBrightness(value)
  }

  onBrightnessChanged: {
    if (brightnessProcess.running && brightnessProcess.stdinEnabled)
      brightnessProcess.write("level:" + String(brightness) + "\n")
  }

  function dismiss() {
    showing = false
    returnTimer.stop()
    // A pointer-enter event arrives sooner than the next cursorpos poll.
    cursorPosition = null
    refreshCursor()
  }

  function refreshCursor() {
    if (targetScreen && !cursorProcess.running) cursorProcess.running = true
  }

  function refreshWeather() {
    if (!showing || weatherProcess.running || Date.now() - weatherAttemptedAt < 900000) return
    weatherAttemptedAt = Date.now()
    weatherProcess.running = true
  }

  function syncBrightness() {
    if (showing) {
      if (!brightnessProcess.running && service) {
        brightnessProcess.command = ["bash", service.pluginDir + "/bin/screensaver-brightness.sh", String(brightness)]
        brightnessProcess.stdinEnabled = true
        brightnessProcess.running = true
      }
    } else if (brightnessProcess.running) {
      // Closing the pipe lets the guard restore before it exits. Do not kill
      // the process here, or a rapid show/hide could lose the saved value.
      brightnessProcess.stdinEnabled = false
    }
  }

  onShowingChanged: {
    if (showing) refreshWeather()
    syncBrightness()
  }

  Process {
    id: brightnessProcess
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      // A new overlay may have appeared while the previous guard was restoring.
      // Failed dimming does not retry in a loop; the overlay still works.
      if (root.showing && code === 0) Qt.callLater(root.syncBrightness)
    }
  }

  Timer {
    interval: 900000
    repeat: true
    running: root.showing
    onTriggered: root.refreshWeather()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      root.weatherText = ""
      root.weatherAttemptedAt = 0
      weatherProcess.running = false
      Qt.callLater(root.refreshWeather)
    }
  }

  Process {
    id: weatherProcess
    // Reuse Omarchy's command and its location settings instead of maintaining
    // another weather provider, location picker, or network client here.
    command: ["omarchy", "weather", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.weatherText = Model.parseWeatherStatus(text)
    }
    onExited: function(code) { if (code !== 0) root.weatherText = "" }
  }

  onTargetScreenChanged: {
    showing = false
    cursorPosition = null
    returnTimer.stop()
    refreshCursor()
  }

  onMayShowChanged: {
    showing = false
    if (mayShow) returnTimer.restart()
    else returnTimer.stop()
  }

  Timer {
    id: returnTimer
    interval: 15000
    repeat: false
    onTriggered: if (root.mayShow) root.showing = true
  }

  // Focus alone does not tell us where the pointer is when focus-follows-mouse
  // is disabled. Poll only while the option has a valid laptop/external pair.
  Timer {
    interval: 750
    repeat: true
    running: root.targetScreen !== null
    onTriggered: root.refreshCursor()
  }

  Process {
    id: cursorProcess
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.cursorPosition = Model.parseCursorPosition(text)
    }
    onExited: function(code) { if (code !== 0) root.cursorPosition = null }
  }

  ScreensaverOverlay {
    weatherText: root.weatherText
    screen: root.targetScreen
    visible: root.showing && root.targetScreen !== null
    onDismissed: root.dismiss()
  }
}
