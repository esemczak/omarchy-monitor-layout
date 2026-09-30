pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC

Column {
  id: root
  property int value: 0
  property color foreground: "white"
  property color accent: "white"
  property string fontFamily: "monospace"
  property bool hasCursor: false
  signal modified(int value)
  signal hovered(bool hovered)
  spacing: 6

  Item {
    width: parent.width
    height: 20
    Text {
      text: "Screensaver brightness"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 13
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: root.value + "%"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 14
      font.bold: true
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  QQC.Slider {
    id: dial
    width: parent.width
    height: 66
    from: 0
    to: 100
    stepSize: 1
    value: root.value
    leftPadding: 9
    rightPadding: 9
    activeFocusOnTab: true
    Accessible.name: "Screensaver brightness"
    onMoved: root.modified(Math.round(value))

    HoverHandler { onHoveredChanged: root.hovered(hovered) }

    background: Rectangle {
      x: dial.leftPadding
      width: dial.availableWidth
      height: 62
      radius: 5
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                            root.hasCursor || dial.activeFocus ? 0.35 : 0.12)
      Item {
        id: scale
        x: 5
        width: parent.width - 10
        height: parent.height
        Rectangle {
          y: 27
          width: parent.width
          height: 1
          color: root.foreground
          opacity: 0.25
        }
        Repeater {
          model: 21
          delegate: Item {
            required property int index
            readonly property bool major: index % 4 === 0
            x: index / 20 * scale.width
            width: 0
            height: scale.height
            Rectangle {
              x: -width / 2
              y: 27 - height
              width: parent.major ? 2 : 1
              height: parent.major ? 18 : (parent.index % 2 === 0 ? 11 : 6)
              color: root.foreground
              opacity: parent.major ? 0.8 : 0.35
            }
            Text {
              visible: parent.major
              text: parent.index * 5
              x: parent.index === 0 ? 0 : (parent.index === 20 ? -width : -width / 2)
              y: 37
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: 11
            }
          }
        }
      }
    }

    handle: Item {
      x: dial.leftPadding + dial.visualPosition * (dial.availableWidth - width)
      y: 3
      width: 10
      height: 31
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: dial.pressed ? 4 : 3
        height: parent.height
        radius: 1
        color: root.accent
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: 10
        height: 5
        radius: 1
        color: root.accent
      }
    }
  }
}
