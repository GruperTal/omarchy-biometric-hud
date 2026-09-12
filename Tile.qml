import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Biometric scan HUD in Omarchy's own dress: theme border and corner radius,
// theme font, the same Nerd Font icons the lock screen uses. Service.qml feeds
// it {phase: scanning|ok|fail|cancel|service, modality?, service?, similarity?}.
// Scanning: the icon breathes under a sweeping beam. Recognized: a frame traces
// itself — a square scan frame for a face, a ring for a fingerprint — and a
// check is drawn. Not recognized: the icon turns red and the card shakes.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null   // injected by the host: the Service.qml singleton

  property bool opened: false
  property string phase: "scanning"   // scanning | ok | fail
  property string modality: "face"    // face | finger
  property string serviceName: ""
  property string similarity: ""

  readonly property bool scanning: phase === "scanning"
  readonly property bool finger: modality === "finger"
  readonly property string uiFont: Style.font.family
  property color green: "#34c759"     // replaced by the theme's green below
  readonly property color tone: phase === "ok" ? green : phase === "fail" ? Color.urgent : Color.accent

  // The face icon Omarchy's lock screen uses, and the fingerprint icon it pins
  // inside the password field, so a tile never disagrees with the lock screen.
  readonly property string glyphIcon: finger ? "\u{F0237}" : "\u{F0C7B}"
  readonly property string subject: finger ? "Fingerprint" : "Face"

  readonly property string title: phase === "ok" ? subject + " Recognized"
    : phase === "fail" ? "Not Recognized" : "Scanning " + subject
  readonly property string subtitle: phase === "ok"
    ? (similarity !== "" ? Math.round(parseFloat(similarity) * 100) + "% match" : "Welcome back")
    : phase === "fail" ? "Use your password instead"
    : finger ? "Touch the sensor" : "Look at the camera"
  readonly property string badgeIcon: serviceName === "polkit" ? "\u{F0483}" : "\u{F018D}"

  readonly property int hudWidth: Style.space(206)
  readonly property int glyphSize: Style.space(78)

  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") } catch (e) {}
    var next = String(p.phase || "")

    // pam_fprintd starts the next verify the instant one fails, which would
    // wipe the shake off the screen before it can be read. Let a rejection
    // stand for a moment, then run the scan that was waiting.
    if (next === "scanning" && phase === "fail" && opened) {
      var left = failHold - (Date.now() - failAt)
      if (left > 0) {
        pending = payloadJson
        holdTimer.interval = left
        holdTimer.restart()
        return
      }
    }
    pending = ""
    holdTimer.stop()
    if (!opened && next !== "service") serviceName = ""
    // A new scan that does not name a modality is a face one. Without the
    // reset, a fingerprint scan would leave the next face scan showing a
    // fingerprint; ok and fail keep whatever the scan in flight set.
    if (p.modality !== undefined) modality = p.modality === "finger" ? "finger" : "face"
    else if (next === "scanning") modality = "face"
    if (p.service !== undefined) {
      // The lock screen has its own face flow; nothing to show over it.
      if (p.service === "omarchy-lock-face") { close(); return }
      serviceName = p.service === "polkit-1" ? "polkit" : String(p.service || "")
    }
    if (next === "cancel") { close(); return }
    if (next === "scanning") {
      successAnim.stop(); failAnim.stop()
      frame.morph = 0; frame.check = 0; hud.shakeX = 0; hud.pop = 1; ripple.progress = 0
      similarity = ""
      phase = "scanning"
    } else if (next === "ok") {
      similarity = String(p.similarity || "")
      phase = "ok"
      successAnim.restart()
    } else if (next === "fail") {
      successAnim.stop()
      frame.morph = 0; frame.check = 0
      phase = "fail"
      failAt = Date.now()
      failAnim.restart()
    } else {
      return
    }
    opened = true
    hideTimer.interval = phase === "scanning" ? 10000 : phase === "ok" ? 1600 : 2200
    hideTimer.restart()
  }

  function close() {
    opened = false
    pending = ""
    hideTimer.stop()
    holdTimer.stop()
  }

  // How long a rejection owns the tile before the next scan may replace it:
  // the shake is 355ms, and the rest is reading time.
  readonly property int failHold: 900
  property double failAt: 0
  property string pending: ""

  Timer {
    id: holdTimer
    onTriggered: {
      var payload = root.pending
      root.pending = ""
      if (payload !== "") root.open(payload)
    }
  }

  Connections {
    target: root.service
    function onEventSerialChanged() { root.open(root.service.lastEvent) }
  }

  Timer {
    id: hideTimer
    onTriggered: root.opened = false
  }

  IpcHandler {
    target: "facelock"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? root.phase : "closed" }
  }

  FileView {
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = String(text()).match(/^\s*(?:green|color2)\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
      if (m) root.green = m[1]
    }
  }

  // ---- animation ---------------------------------------------------------

  SequentialAnimation {
    running: root.opened && root.scanning
    loops: Animation.Infinite
    NumberAnimation { target: glyph; property: "beam"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { target: glyph; property: "beam"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
  }

  SequentialAnimation {
    running: root.opened && root.scanning
    loops: Animation.Infinite
    NumberAnimation { target: glyph; property: "breathe"; from: 0; to: 1; duration: 650; easing.type: Easing.InOutSine }
    NumberAnimation { target: glyph; property: "breathe"; from: 1; to: 0; duration: 650; easing.type: Easing.InOutSine }
  }

  SequentialAnimation {
    id: successAnim
    NumberAnimation { target: glyph; property: "breathe"; to: 0; duration: 80 }
    ParallelAnimation {
      NumberAnimation { target: frame; property: "morph"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
      NumberAnimation { target: ripple; property: "progress"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
      SequentialAnimation {
        NumberAnimation { target: hud; property: "pop"; to: 1.05; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: hud; property: "pop"; to: 1; duration: 320; easing.type: Easing.OutBack }
      }
      SequentialAnimation {
        PauseAnimation { duration: 220 }
        NumberAnimation { target: frame; property: "check"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
      }
    }
  }

  // The macOS wrong-password shake.
  SequentialAnimation {
    id: failAnim
    NumberAnimation { target: hud; property: "shakeX"; to: -14; duration: 55; easing.type: Easing.OutQuad }
    NumberAnimation { target: hud; property: "shakeX"; to: 12; duration: 70; easing.type: Easing.InOutQuad }
    NumberAnimation { target: hud; property: "shakeX"; to: -9; duration: 65; easing.type: Easing.InOutQuad }
    NumberAnimation { target: hud; property: "shakeX"; to: 6; duration: 60; easing.type: Easing.InOutQuad }
    NumberAnimation { target: hud; property: "shakeX"; to: -3; duration: 55; easing.type: Easing.InOutQuad }
    NumberAnimation { target: hud; property: "shakeX"; to: 0; duration: 50; easing.type: Easing.OutQuad }
  }

  // ---- surface -----------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened || hud.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "facelock-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Item {
      id: hud
      property real pop: 1
      property real shakeX: 0

      width: root.hudWidth
      height: content.implicitHeight + Style.space(24) + Style.space(20)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(64)

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.9
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
      transform: [
        Scale { origin.x: hud.width / 2; origin.y: hud.height / 2; xScale: hud.pop; yScale: hud.pop },
        Translate { x: hud.shakeX }
      ]

      // Card: the theme's popup border and corner radius, a soft gradient and
      // a deep, blurred shadow.
      BorderSurface {
        id: card
        anchors.fill: parent
        radius: Style.cornerRadius
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        gradient: Gradient {
          GradientStop { position: 0; color: Util.alpha(Qt.lighter(Color.popups.background, 1.3), 0.97) }
          GradientStop { position: 1; color: Util.alpha(Color.popups.background, 0.97) }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: "#000000"
          shadowOpacity: 0.6
          shadowBlur: 1.0
          blurMax: 48
          shadowVerticalOffset: Style.space(10)
        }
      }

      // Top sheen, like light catching the glass.
      Rectangle {
        anchors {
          left: parent.left; right: parent.right; top: parent.top
          leftMargin: card.borderLeft; rightMargin: card.borderRight; topMargin: card.borderTop
        }
        height: parent.height * 0.5
        radius: Math.max(0, Style.cornerRadius - card.borderTop)
        gradient: Gradient {
          GradientStop { position: 0; color: Util.alpha(Color.foreground, 0.06) }
          GradientStop { position: 1; color: Util.alpha(Color.foreground, 0) }
        }
      }

      Column {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(24)
        spacing: 0

        Item {
          id: stage
          width: root.glyphSize * 1.5
          height: root.glyphSize * 1.3
          anchors.horizontalCenter: parent.horizontalCenter

          // Success ripple: the frame's outline pushing outwards.
          Rectangle {
            id: ripple
            property real progress: 0
            anchors.centerIn: parent
            width: root.glyphSize * (0.86 + 0.5 * progress)
            height: width
            radius: root.finger ? width / 2 : Style.cornerRadius
            color: "transparent"
            border.width: Math.max(1, Style.space(2))
            border.color: root.green
            opacity: progress > 0 && progress < 1 ? 0.6 * (1 - progress) : 0
          }

          // The face: the same Nerd Font icon Omarchy's lock screen uses.
          Item {
            id: face
            anchors.centerIn: parent
            width: root.glyphSize
            height: root.glyphSize
            opacity: 1 - frame.morph
            scale: (1 - 0.06 * glyph.breathe) * (1 - 0.2 * frame.morph)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.glyphIcon
              font.family: Style.font.family
              font.pixelSize: root.glyphSize
              color: root.tone
              Behavior on color { ColorAnimation { duration: 220 } }
            }

            // Scan beam: a hard line with a soft wake, clipped to the face.
            Item {
              anchors.centerIn: parent
              width: root.glyphSize * 0.86
              height: width
              clip: true
              visible: root.scanning

              Rectangle {
                width: parent.width
                height: parent.height * 0.34
                y: glyph.beam * parent.height - height / 2
                gradient: Gradient {
                  GradientStop { position: 0; color: Util.alpha(Color.accent, 0) }
                  GradientStop { position: 0.5; color: Util.alpha(Color.accent, 0.26) }
                  GradientStop { position: 1; color: Util.alpha(Color.accent, 0) }
                }
              }
              Rectangle {
                width: parent.width
                height: Math.max(1, Style.space(2))
                y: glyph.beam * parent.height - height / 2
                color: Color.accent
                opacity: 0.9
              }
            }
          }

          // Animation clock for the scan loops (beam + breathing).
          QtObject {
            id: glyph
            property real beam: 0
            property real breathe: 0
          }

          // Recognized: a square frame traces itself, then the check is drawn.
          Canvas {
            id: frame
            anchors.centerIn: parent
            width: root.glyphSize
            height: root.glyphSize
            visible: morph > 0.001

            property real morph: 0
            property real check: 0
            property color tone: root.green
            property bool round: root.finger

            onMorphChanged: requestPaint()
            onCheckChanged: requestPaint()
            onToneChanged: requestPaint()
            onRoundChanged: requestPaint()
            onWidthChanged: requestPaint()

            // The check, drawn on from its start point; shared by the square
            // frame and the fingerprint ring.
            function paintCheck(ctx, s, lw) {
              if (check <= 0.001) return
              var p0 = [0.3, 0.52], p1 = [0.44, 0.66], p2 = [0.7, 0.36]
              var l1 = Math.hypot(p1[0] - p0[0], p1[1] - p0[1])
              var l2 = Math.hypot(p2[0] - p1[0], p2[1] - p1[1])
              var d = check * (l1 + l2)
              ctx.lineWidth = Math.round(lw * 1.2)
              ctx.beginPath()
              ctx.moveTo(p0[0] * s, p0[1] * s)
              if (d <= l1) {
                var t = d / l1
                ctx.lineTo((p0[0] + (p1[0] - p0[0]) * t) * s, (p0[1] + (p1[1] - p0[1]) * t) * s)
              } else {
                var t2 = (d - l1) / l2
                ctx.lineTo(p1[0] * s, p1[1] * s)
                ctx.lineTo((p1[0] + (p2[0] - p1[0]) * t2) * s, (p1[1] + (p2[1] - p1[1]) * t2) * s)
              }
              ctx.stroke()
            }

            function rgba(c, a) {
              return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                + Math.round(c.b * 255) + "," + a + ")"
            }

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.clearRect(0, 0, width, height)
              var s = width
              var lw = Math.max(2, Math.round(s * 0.055))
              var a = s * 0.07 + lw / 2
              var side = s - 2 * a
              ctx.lineCap = root.finger ? "round" : "square"
              ctx.lineJoin = "miter"
              ctx.lineWidth = lw
              ctx.strokeStyle = rgba(tone, 1)

              if (round) {
                var c = s / 2
                var r = side / 2
                ctx.fillStyle = rgba(tone, 0.14 * morph)
                ctx.beginPath()
                ctx.arc(c, c, r, 0, 2 * Math.PI)
                ctx.fill()
                // Draw the ring from the top, clockwise.
                ctx.beginPath()
                ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * morph)
                ctx.stroke()
                paintCheck(ctx, s, lw)
                return
              }

              ctx.fillStyle = rgba(tone, 0.14 * morph)
              ctx.fillRect(a, a, side, side)

              // Trace the perimeter clockwise from the top-left corner.
              var left = 4 * side * morph
              var pts = [[a + side, a], [a + side, a + side], [a, a + side], [a, a]]
              var x = a, y = a
              ctx.beginPath()
              ctx.moveTo(x, y)
              for (var i = 0; i < 4 && left > 0; i++) {
                var step = Math.min(side, left)
                var tx = x + (pts[i][0] - x) * step / side
                var ty = y + (pts[i][1] - y) * step / side
                ctx.lineTo(tx, ty)
                x = pts[i][0]; y = pts[i][1]
                left -= step
              }
              ctx.stroke()

              paintCheck(ctx, s, lw)
            }
          }
        }

        Item { width: 1; height: Style.space(8) }

        Text {
          id: titleText
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.title
          // "Fingerprint Recognized" is half again as wide as "Face
          // Recognized", so let the title shrink to the card instead of
          // trimming the copy to the longest word that happens to fit.
          width: root.hudWidth - Style.space(28)
          horizontalAlignment: Text.AlignHCenter
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: Math.round(Style.font.bodySmall)
          font.family: root.uiFont
          font.pixelSize: Math.round(Style.font.title * 1.15)
          font.bold: true
          color: Color.popups.text
          Behavior on text {
            SequentialAnimation {
              NumberAnimation { target: titleText; property: "opacity"; to: 0; duration: 90 }
              PropertyAction {}
              NumberAnimation { target: titleText; property: "opacity"; to: 1; duration: 160 }
            }
          }
        }

        Item { width: 1; height: Style.space(4) }

        Text {
          id: subtitleText
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.subtitle
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          color: Util.alpha(Color.popups.text, 0.6)
          Behavior on text {
            SequentialAnimation {
              NumberAnimation { target: subtitleText; property: "opacity"; to: 0; duration: 90 }
              PropertyAction {}
              NumberAnimation { target: subtitleText; property: "opacity"; to: 1; duration: 160 }
            }
          }
        }

        Item { width: 1; height: Style.space(12) }

        // Who asked: SUDO / POLKIT tag.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: badgeRow.implicitWidth + Style.space(16)
          height: badgeRow.implicitHeight + Style.space(6)
          radius: Style.cornerRadius
          color: Util.alpha(Color.popups.text, 0.06)
          border.width: 1
          border.color: Util.alpha(Color.popups.text, 0.16)
          opacity: root.serviceName !== "" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180 } }

          Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: Style.space(6)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.badgeIcon
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.accent
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.serviceName === "" ? "SUDO" : root.serviceName.toUpperCase()
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.5
              color: Util.alpha(Color.popups.text, 0.78)
            }
          }
        }
      }
    }
  }
}
