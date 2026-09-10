import QtQuick
import Quickshell
import Quickshell.Io

// Follows facelock's journal (the daemon's D-Bus signals are root-only) and
// feeds the tile through lastEvent/eventSerial: camera open = scanning, then
// the auth result, then the PAM line that names which service asked.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "gruper.face-unlock"

  property string lastEvent: ""
  property int eventSerial: 0
  // This scan belongs to the lock screen: stay quiet until its PAM line lands.
  property bool quiet: false

  function announce(phase, extra) {
    var payload = extra || {}
    payload.phase = phase
    lastEvent = JSON.stringify(payload)
    eventSerial++
  }

  function handleLine(raw) {
    var line = String(raw).replace(/\x1b\[[0-9;]*m/g, "")
    if (line.indexOf("camera format negotiated") !== -1) {
      if (!requester.running) requester.running = true
      return
    }
    if (line.indexOf("authentication succeeded") !== -1) {
      if (quiet) return
      var s = line.match(/similarity="([0-9.]+)"/)
      announce("ok", { similarity: s ? s[1] : "" })
      return
    }
    if (line.indexOf("authentication failed") !== -1) { if (!quiet) announce("fail"); return }
    if (line.indexOf("authentication cancelled") !== -1) { quiet = false; announce("cancel"); return }
    var p = line.match(/^pam_facelock\(([^)]+)\): (\w+)/)
    if (p) {
      var wasQuiet = quiet
      quiet = false
      if (!wasQuiet) announce("service", { service: p[1], result: p[2] })
    }
  }

  property Process journal: Process {
    running: true
    command: ["journalctl", "-f", "-n", "0", "-o", "cat",
              "_SYSTEMD_UNIT=facelock-daemon.service", "+", "SYSLOG_IDENTIFIER=pam_facelock"]
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    onExited: root.restartTimer.restart()
  }

  // Who asked? facelock only answers sudo, polkit and the lock screen
  // (pam_policy), so whichever PAM helper is alive at camera-open is the
  // requester, and neither means the lock screen.
  // ponytail: a background `sudo` during a polkit prompt would mislabel; the
  // PAM line at the end corrects it.
  property Process requester: Process {
    command: ["sh", "-c", "if pgrep -x polkit-agent-he >/dev/null; then echo polkit-1; elif pgrep -x sudo >/dev/null; then echo sudo; fi"]
    stdout: StdioCollector { id: requesterOut; waitForEnd: true }
    onExited: {
      var who = String(requesterOut.text || "").trim()
      root.quiet = who === ""
      if (!root.quiet) root.announce("scanning", { service: who })
    }
  }

  // journalctl dies with journal rotation once in a while; just come back.
  property Timer restartTimer: Timer {
    interval: 3000
    onTriggered: root.journal.running = true
  }
}
