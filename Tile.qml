import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The face-scan tile. Summoned by Service.qml with {phase: scanning|ok|fail|
// cancel|service}. Slides in under the bar, spins a ring around the face
// glyph while scanning, then settles on the result and slides away.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null   // injected by the host: the Service.qml singleton

  property bool opened: false
  property string phase: "scanning"   // scanning | ok | fail
  property string serviceName: ""
  property string similarity: ""

  readonly property bool scanning: phase === "scanning"
  readonly property color tone: phase === "ok" ? Color.accent : phase === "fail" ? Color.urgent : Color.popups.text
  readonly property string title: phase === "ok" ? "Face recognized" : phase === "fail" ? "No match" : "Scanning face"
  readonly property string subtitle: serviceName !== "" ? serviceName
    : phase === "scanning" ? "look at the camera"
    : phase === "ok" && similarity !== "" ? Math.round(parseFloat(similarity) * 100) + "% match"
    : "try again or use your password"

  readonly property int pad: Style.space(14)
  readonly property int ring: Style.space(44)

  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") } catch (e) {}
    var next = String(p.phase || "")
    if (next === "service") {
      // The lock screen has its own face flow; nothing to show over it.
      if (p.service === "omarchy-lock-face") { close(); return }
      serviceName = p.service === "polkit-1" ? "polkit" : String(p.service || "")
      return
    }
    if (next === "cancel") { close(); return }
    if (next === "scanning") { serviceName = ""; similarity = "" }
    if (next === "ok") similarity = String(p.similarity || "")
    phase = next === "ok" ? "ok" : next === "fail" ? "fail" : "scanning"
    opened = true
    hideTimer.interval = scanning ? 10000 : 1500
    hideTimer.restart()
  }

  function close() { opened = false; hideTimer.stop() }

  Connections {
    target: root.service
    function onEventSerialChanged() { root.open(root.service.lastEvent) }
  }

  Timer {
    id: hideTimer
    onTriggered: root.opened = false
  }

  IpcHandler {
    target: "face-unlock"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? root.phase : "closed" }
  }

  TextMetrics { id: titleMetrics; font.family: Style.font.family; font.bold: true; font.pixelSize: Style.font.title; text: "Face recognized" }
  TextMetrics { id: subtitleMetrics; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; text: "try again or use your password" }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "gruper-face-unlock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    BorderSurface {
      id: card
      readonly property int textWidth: Math.ceil(Math.max(titleMetrics.advanceWidth, subtitleMetrics.advanceWidth))
      width: card.borderLeft + root.pad + root.ring + root.pad + textWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + root.ring + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(52)
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0
      transform: Translate { y: root.opened ? 0 : -Style.space(16) ; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        spacing: root.pad

        // Ring + face glyph. Scanning: a 270° arc spins and the glyph breathes.
        // Result: the ring closes in the result colour and the glyph swaps.
        Item {
          width: root.ring
          height: root.ring

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, Style.space(2))
            border.color: Util.alpha(root.tone, root.scanning ? 0.18 : 1)
            Behavior on border.color { ColorAnimation { duration: 200 } }
          }

          Canvas {
            id: arc
            anchors.fill: parent
            visible: root.scanning
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var w = Math.max(2, Style.space(2))
              ctx.lineWidth = w
              ctx.strokeStyle = root.tone
              ctx.lineCap = "round"
              ctx.beginPath()
              ctx.arc(width / 2, height / 2, width / 2 - w / 2, 0, Math.PI * 1.5)
              ctx.stroke()
            }
            onVisibleChanged: requestPaint()
            Component.onCompleted: requestPaint()
            RotationAnimation on rotation {
              running: root.scanning && root.opened
              loops: Animation.Infinite
              from: 0; to: 360; duration: 1000
            }
          }

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.phase === "ok" ? "󰄬" : root.phase === "fail" ? "󰅖" : "󰱻"
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
            color: root.tone
            // Breathe while scanning; a plain binding so the result phases
            // always land at full opacity.
            property real pulse: 1
            opacity: root.scanning ? pulse : 1
            SequentialAnimation on pulse {
              running: root.scanning && root.opened
              loops: Animation.Infinite
              NumberAnimation { from: 1; to: 0.35; duration: 550; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.35; to: 1; duration: 550; easing.type: Easing.InOutSine }
            }
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: card.textWidth
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: root.title
            font: titleMetrics.font
            color: Color.popups.text
          }
          Text {
            textFormat: Text.PlainText
            text: root.subtitle
            font: subtitleMetrics.font
            color: Util.alpha(Color.popups.text, 0.6)
          }
        }
      }
    }
  }
}
