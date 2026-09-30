pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Model.js" as Model

PanelWindow {
  id: root

  signal dismissed()
  property date now: new Date()
  property real drift: 0
  property string weatherText: ""
  readonly property int calendarYear: now.getFullYear()
  readonly property int calendarMonth: now.getMonth()
  readonly property int calendarDay: now.getDate()
  readonly property var monthDays: Model.calendarDays(calendarYear, calendarMonth, calendarDay)
  readonly property real cellSize: Math.max(20, Math.min(root.width / 50, root.height / 30, 28))

  color: "#080a0e"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "esemczak-laptop-screensaver"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // No idle inhibitor: Omarchy's normal lock and display sleep still run.
  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.now = new Date()
  }

  NumberAnimation on drift {
    from: 0
    to: Math.PI * 2
    duration: 144000
    loops: Animation.Infinite
    running: root.visible
  }

  Row {
    id: content
    x: (parent.width - width) / 2 + Math.sin(root.drift) * Math.max(0, (parent.width - width) * 0.25)
    y: (parent.height - height) / 2 + Math.cos(root.drift) * Math.max(0, (parent.height - height) * 0.25)
    spacing: 8

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(root.now, "MMMM yyyy")
        color: "#a0a9ba"
        font.family: "sans-serif"
        font.pixelSize: 16
      }

      Row {
        spacing: 3
        Repeater {
          model: ["M", "T", "W", "T", "F", "S", "S"]
          Text {
            required property string modelData
            width: root.cellSize
            height: 18
            text: modelData
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: "#727b8e"
            font.family: "sans-serif"
            font.pixelSize: 11
          }
        }
      }

      Grid {
        columns: 7
        spacing: 3
        Repeater {
          model: root.monthDays
          Rectangle {
            required property var modelData
            width: root.cellSize
            height: root.cellSize
            radius: width / 2
            color: modelData.today ? "#c6ccd8" : "transparent"

            Text {
              anchors.fill: parent
              text: parent.modelData.day
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              color: parent.modelData.today ? "#080a0e" : (parent.modelData.currentMonth ? "#a0a9ba" : "#353b47")
              font.family: "sans-serif"
              font.pixelSize: Math.max(12, root.cellSize * 0.4)
              font.weight: parent.modelData.today ? Font.DemiBold : Font.Normal
            }
          }
        }
      }
    }

    Column {
      id: timeWeather
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.width * 0.43, 560)
      spacing: 18

      Text {
        width: parent.width
        text: Qt.formatDateTime(root.now, "HH:mm")
        horizontalAlignment: Text.AlignLeft
        color: "#c6ccd8"
        font.family: "sans-serif"
        font.pixelSize: Math.max(64, Math.min(root.width / 8.5, timeWeather.width / 3.1, 172))
        font.weight: Font.Light
      }

      Text {
        width: parent.width
        visible: root.weatherText !== ""
        text: root.weatherText
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignLeft
        color: "#a0a9ba"
        font.family: "sans-serif"
        font.pixelSize: Math.max(18, Math.min(root.width / 60, 26))
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    onEntered: root.dismissed()
    onPressed: root.dismissed()
  }
}
