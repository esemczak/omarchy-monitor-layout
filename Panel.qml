import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "esemczak.monitor-layout"
  ipcTarget: "esemczak.monitor-layout"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color panelBackground: bar ? bar.background : Color.background

  // Keyboard cursor: sections in visual order; h/l walks within a row.
  property string focusSection: "side"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var sideOptions: Model.SIDE_OPTIONS
  readonly property var alignOptions: Model.alignLabels(layoutService.profile.side)
  readonly property var scaleOptions: Model.SCALE_PRESETS
  readonly property bool arrangementVisible: !!layoutService.external && !!layoutService.internal
  readonly property var visibleSections: {
    var list = []
    if (arrangementVisible) {
      list.push("side")
      list.push("align")
      if (layoutService.profile.align === "custom") list.push("offset")
      list.push("scale")
      list.push("workspaces")
      list.push("persistent")
    }
    if (!layoutService.requireInstalled) list.push("install")
    if (arrangementVisible) list.push("apply")
    return list
  }

  function sectionCount(section) {
    if (section === "side") return sideOptions.length
    if (section === "align") return alignOptions.length
    if (section === "scale") return 2
    if (section === "workspaces") return Model.WORKSPACE_COUNT
    return 1
  }

  function indexOfValue(options, value) {
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
    return 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    var sections = visibleSections
    if (!sections.length) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = 0; return }
    if (dy !== 0) {
      var next = Math.max(0, Math.min(sections.length - 1, sIdx + dy))
      focusSection = sections[next]
      selectedIndex = defaultIndexFor(focusSection)
      return
    }
    if (dx !== 0) {
      var count = sectionCount(focusSection)
      selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + dx))
      if (focusSection === "offset") layoutService.setOffsetMm(layoutService.profile.offsetMm + dx * 5)
    }
  }

  function defaultIndexFor(section) {
    if (section === "side") return indexOfValue(sideOptions, layoutService.profile.side)
    if (section === "align") return indexOfValue(alignOptions, layoutService.profile.align)
    return 0
  }

  function activateCursor() {
    cursorActive = true
    if (focusSection === "side") layoutService.setSide(sideOptions[selectedIndex].value)
    else if (focusSection === "align") layoutService.setAlign(alignOptions[selectedIndex].value)
    else if (focusSection === "workspaces") layoutService.cycleWorkspace(selectedIndex + 1)
    else if (focusSection === "persistent") layoutService.setPersistent(!layoutService.profile.persistent)
    else if (focusSection === "install") layoutService.installRequire()
    else if (focusSection === "apply") layoutService.apply()
  }

  function hoverSection(section, index) {
    cursorActive = true
    focusSection = section
    selectedIndex = index
  }

  function fmtMm(v) { return String(Math.round(v)) }

  function overlapText() {
    var l = layoutService.layout
    if (!l || !l.overlap || !l.overlap.internalMm) return "Monitors do not share an edge; the cursor cannot cross."
    var i = l.overlap.internalMm
    var e = l.overlap.externalMm
    var axis = layoutService.profile.side === "left" || layoutService.profile.side === "right" ? "from the top" : "from the left"
    return "Cursor crosses " + fmtMm(i.from) + "–" + fmtMm(i.to) + " mm " + axis + " on the laptop ↔ "
      + fmtMm(e.from) + "–" + fmtMm(e.to) + " mm on the external."
  }

  function positionText() {
    var l = layoutService.layout
    if (!l) return ""
    return layoutService.internal.name + " at " + l.internal.position.x + "x" + l.internal.position.y
      + " · " + layoutService.external.name + " at " + l.external.position.x + "x" + l.external.position.y
  }

  Service {
    id: layoutService
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function apply(): string { layoutService.apply(); return "ok" }
    function install(): string { layoutService.installRequire(); return "ok" }
    function refresh(): string { layoutService.reload(); return "ok" }
    function setSide(side: string): string { layoutService.setSide(side); return layoutService.profile.side }
    function setAlign(align: string): string { layoutService.setAlign(align); return layoutService.profile.align }
    function setOffset(mm: string): string { layoutService.setOffsetMm(mm); return String(layoutService.profile.offsetMm) }
    function setWorkspace(id: string, target: string): string {
      layoutService.setWorkspace(id, target)
      return JSON.stringify(layoutService.profile.workspaces)
    }
    function lua(): string { return layoutService.renderedLua() }
    function status(): string {
      return JSON.stringify({
        internal: layoutService.internal ? layoutService.internal.name : "",
        external: layoutService.external ? layoutService.external.name : "",
        profileKey: layoutService.externalKey,
        profile: layoutService.profile,
        generatedProfile: layoutService.state.generatedProfile,
        requireInstalled: layoutService.requireInstalled,
        lastResult: layoutService.lastResult
      })
    }
  }

  onOpenedChanged: if (opened) {
    layoutService.refreshMonitors()
    cursorActive = false
    focusSection = visibleSections.length ? visibleSections[0] : "side"
    selectedIndex = defaultIndexFor(focusSection)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: layoutService.external ? "󰍺" : "󰌢"
    tooltipText: "Monitor layout · " + layoutService.summary
    onPressed: function(b) {
      if (b === Qt.RightButton) { layoutService.apply(); return }
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") layoutService.refreshMonitors()
        if (t === "a") layoutService.apply()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Monitor layout"
          meta: layoutService.summary
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: layoutService.external ? "󰍺" : "󰌢"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // ---- no external ---------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.arrangementVisible

          Text {
            width: parent.width
            text: layoutService.internal
              ? "Connect an external monitor to choose where it sits and which workspaces it owns. Saved layouts re-apply automatically when their monitor returns."
              : "No laptop panel detected. This plugin arranges one external monitor around an internal panel."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            text: "SAVED LAYOUTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
            visible: layoutService.savedProfileKeys.length > 0
          }

          Repeater {
            model: layoutService.savedProfileKeys
            delegate: Row {
              required property string modelData
              width: column.width
              spacing: Style.space(8)
              Text {
                width: parent.width - forget.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.replace(/\s+0x[0-9A-Fa-f]+$/, "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              Button {
                id: forget
                iconText: "󰆴"
                tooltipText: "Forget this layout"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: layoutService.forgetProfile(modelData)
              }
            }
          }
        }

        // ---- arrangement ---------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.arrangementVisible

          PanelSectionHeader {
            text: "EXTERNAL MONITOR IS … OF THE LAPTOP"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            width: parent.width
            foreground: root.foreground
            background: root.panelBackground
            accent: root.accent
            fontFamily: root.fontFamily
            value: layoutService.profile.side
            options: root.sideOptions
            cursorIndex: root.cursorActive && root.focusSection === "side" ? root.selectedIndex : -1
            onChanged: function(value) { if (root.opened) layoutService.setSide(value) }
            onHovered: function(index, hovered) { if (hovered) root.hoverSection("side", index) }
          }

          PanelSectionHeader {
            text: "ALIGNED BY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            width: parent.width
            foreground: root.foreground
            background: root.panelBackground
            accent: root.accent
            fontFamily: root.fontFamily
            value: layoutService.profile.align
            options: root.alignOptions
            cursorIndex: root.cursorActive && root.focusSection === "align" ? root.selectedIndex : -1
            onChanged: function(value) { if (root.opened) layoutService.setAlign(value) }
            onHovered: function(index, hovered) { if (hovered) root.hoverSection("align", index) }
          }

          NumberField {
            visible: layoutService.profile.align === "custom"
            label: (layoutService.profile.side === "left" || layoutService.profile.side === "right")
              ? "External top edge below laptop top edge (mm, negative = above)"
              : "External left edge right of laptop left edge (mm, negative = left)"
            from: -3000
            to: 3000
            stepSize: 5
            value: layoutService.profile.offsetMm
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.focusSection === "offset"
            onHovered: function(h) { if (h) root.hoverSection("offset", 0) }
            onModified: function(v) { if (root.opened) layoutService.setOffsetMm(v) }
          }

          LayoutPreview {
            width: parent.width
            height: Style.space(150)
          }

          Text {
            width: parent.width
            text: root.overlapText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.positionText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Dropdown {
              width: (parent.width - parent.spacing) / 2
              label: "Laptop scale"
              fontFamily: root.fontFamily
              options: root.scaleOptions
              value: String(layoutService.profile.internalScale)
              hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === 0
              onHovered: function(h) { if (h) root.hoverSection("scale", 0) }
              onChanged: function(v) { if (root.opened) layoutService.setInternalScale(v) }
            }

            Dropdown {
              width: (parent.width - parent.spacing) / 2
              label: "External scale"
              fontFamily: root.fontFamily
              options: root.scaleOptions
              value: String(layoutService.profile.externalScale)
              hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === 1
              onHovered: function(h) { if (h) root.hoverSection("scale", 1) }
              onChanged: function(v) { if (root.opened) layoutService.setExternalScale(v) }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "WORKSPACES · CLICK TO CYCLE EXTERNAL → LAPTOP → ANY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: workspaceRow
            width: parent.width
            spacing: Style.space(4)
            readonly property real cellWidth: (width - spacing * (Model.WORKSPACE_COUNT - 1)) / Model.WORKSPACE_COUNT

            Repeater {
              model: Model.WORKSPACE_COUNT
              delegate: Button {
                required property int index
                readonly property string wsId: String(index + 1)
                readonly property string assignment: layoutService.profile.workspaces[wsId] || ""
                width: workspaceRow.cellWidth
                text: wsId
                iconText: assignment === "external" ? "󰍹" : (assignment === "internal" ? "󰌢" : "")
                iconSize: Style.font.caption
                fontSize: Style.font.bodySmall
                selected: assignment !== ""
                bordered: true
                horizontalPadding: Style.space(2)
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                tooltipText: assignment === "external" ? "Workspace " + wsId + " → external"
                  : (assignment === "internal" ? "Workspace " + wsId + " → laptop" : "Workspace " + wsId + " → any monitor")
                hasCursor: root.cursorActive && root.focusSection === "workspaces" && root.selectedIndex === index
                onHovered: function(h) { if (h) root.hoverSection("workspaces", index) }
                onClicked: if (root.opened) layoutService.cycleWorkspace(index + 1)
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Keep workspaces persistent"
            description: "Assigned workspaces always exist on their monitor, even when empty."
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            checked: layoutService.profile.persistent
            hasCursor: root.cursorActive && root.focusSection === "persistent"
            onHovered: function(h) { if (h) root.hoverSection("persistent", 0) }
            onClicked: if (root.opened) layoutService.setPersistent(!layoutService.profile.persistent)
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- footer --------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            visible: !layoutService.requireInstalled
            text: "Hyprland does not load the generated file yet. Install adds require(\"hypr.monitor-layout\") to ~/.config/hypr/hyprland.lua after backing it up."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              visible: !layoutService.requireInstalled
              text: layoutService.installing ? "Installing…" : "Install into hyprland.lua"
              iconText: "󰐕"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "install"
              onHovered: function(h) { if (h) root.hoverSection("install", 0) }
              onClicked: layoutService.installRequire()
            }

            Button {
              visible: root.arrangementVisible
              text: layoutService.applying ? "Applying…" : "Apply layout"
              iconText: "󰄬"
              bordered: true
              selected: layoutService.state.generatedProfile === layoutService.externalKey && layoutService.lastResult.ok
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "apply"
              onHovered: function(h) { if (h) root.hoverSection("apply", 0) }
              onClicked: layoutService.apply()
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: layoutService.lastError ? layoutService.lastError
              : (layoutService.lastResult.message ? layoutService.lastResult.message : "")
            color: layoutService.lastError || (layoutService.lastResult.errors && layoutService.lastResult.errors.length) ? Color.urgent : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: layoutService.lastResult.errors || []
            delegate: Text {
              required property string modelData
              width: column.width
              text: modelData
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            width: parent.width
            text: "Alignment is exact at the anchor and drifts slightly along the edge because the panels have different pixel densities."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            visible: root.arrangementVisible
          }
        }
      }
    }
  }

  // To-scale physical preview of both panels with the shared edge highlighted.
  component LayoutPreview: Item {
    id: preview

    readonly property real pad: Style.space(6)
    readonly property var boxes: layoutService.internal
      ? Model.previewBoxes(layoutService.profile, layoutService.internal, layoutService.external, width - pad * 2, height - pad * 2)
      : []
    readonly property var internalBox: boxes.length ? boxes[0] : null
    readonly property var externalBox: boxes.length > 1 ? boxes[1] : null
    readonly property var edge: {
      if (!internalBox || !externalBox) return null
      var side = layoutService.profile.side
      var horizontal = side === "left" || side === "right"
      if (horizontal) {
        var top = Math.max(internalBox.y, externalBox.y)
        var bottom = Math.min(internalBox.y + internalBox.height, externalBox.y + externalBox.height)
        if (bottom <= top) return null
        var x = side === "right" ? internalBox.x + internalBox.width : internalBox.x
        return { x: x - 1, y: top, width: 2, height: bottom - top }
      }
      var left = Math.max(internalBox.x, externalBox.x)
      var right = Math.min(internalBox.x + internalBox.width, externalBox.x + externalBox.width)
      if (right <= left) return null
      var y = side === "below" ? internalBox.y + internalBox.height : internalBox.y
      return { x: left, y: y - 1, width: right - left, height: 2 }
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }

    Repeater {
      model: preview.boxes
      delegate: Rectangle {
        required property var modelData
        x: preview.pad + modelData.x
        y: preview.pad + modelData.y
        width: Math.max(2, modelData.width)
        height: Math.max(2, modelData.height)
        radius: 2
        color: modelData.role === "internal"
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        border.width: 1
        border.color: modelData.role === "internal" ? root.foreground : root.accent

        Column {
          anchors.centerIn: parent
          spacing: 0
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.role === "internal" ? "󰌢" : "󰍹"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.monitor ? modelData.monitor.name : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: modelData.width > Style.space(70)
            text: modelData.monitor ? Math.round(modelData.monitor.physicalWidth) + "×" + Math.round(modelData.monitor.physicalHeight) + " mm" : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Rectangle {
      visible: !!preview.edge
      x: preview.pad + (preview.edge ? preview.edge.x : 0)
      y: preview.pad + (preview.edge ? preview.edge.y : 0)
      width: preview.edge ? preview.edge.width : 0
      height: preview.edge ? preview.edge.height : 0
      color: root.accent
    }
  }
}
