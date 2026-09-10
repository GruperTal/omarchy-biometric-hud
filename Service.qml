import QtQuick
import Quickshell
import Quickshell.Io

// Follows facelock's journal (the daemon's D-Bus signals are root-only) and
// drives the tile: camera open = scanning, then the auth result, then the PAM
// line that names which service asked (sudo, polkit-1, omarchy-lock-face).
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "gruper.face-unlock"

  // The tile (Tile.qml) is handed this service by the host and reacts to
  // eventSerial; no summon round-trip through the host's panel registry.
  property string lastEvent: ""
  property int eventSerial: 0

  function announce(phase, extra) {
    var payload = extra || {}
    payload.phase = phase
    lastEvent = JSON.stringify(payload)
    eventSerial++
  }

  function handleLine(raw) {
    var line = String(raw).replace(/\x1b\[[0-9;]*m/g, "")
    if (line.indexOf("camera format negotiated") !== -1) { announce("scanning"); return }
    if (line.indexOf("authentication succeeded") !== -1) {
      var s = line.match(/similarity="([0-9.]+)"/)
      announce("ok", { similarity: s ? s[1] : "" })
      return
    }
    if (line.indexOf("authentication failed") !== -1) { announce("fail"); return }
    if (line.indexOf("authentication cancelled") !== -1) { announce("cancel"); return }
    var p = line.match(/^pam_facelock\(([^)]+)\): (\w+)/)
    if (p) announce("service", { service: p[1], result: p[2] })
  }

  property Process journal: Process {
    running: true
    command: ["journalctl", "-f", "-n", "0", "-o", "cat",
              "_SYSTEMD_UNIT=facelock-daemon.service", "+", "SYSLOG_IDENTIFIER=pam_facelock"]
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    onExited: root.restartTimer.restart()
  }

  // journalctl dies with the journal rotation once in a while; just come back.
  property Timer restartTimer: Timer {
    interval: 3000
    onTriggered: root.journal.running = true
  }
}
