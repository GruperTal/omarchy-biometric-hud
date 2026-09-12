import QtQuick
import Quickshell
import Quickshell.Io
import "events.js" as Events

// Follows facelock's journal (the daemon's D-Bus signals are root-only) and
// feeds the tile through lastEvent/eventSerial. Read-only: nothing here runs
// with privileges, writes a file, or touches PAM. See events.js for the rules.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "io.github.grupertal.facelock-hud"

  // The tile watches eventSerial and reads lastEvent.
  property string lastEvent: ""
  property int eventSerial: 0

  property var state: Events.initialState()

  function apply(result) {
    state = result.state
    if (result.probe && !requester.running)
      requester.running = true
    if (result.announce) {
      lastEvent = JSON.stringify(result.announce)
      eventSerial++
    }
  }

  property Process journal: Process {
    running: true
    command: ["journalctl", "-f", "-n", "0", "-o", "cat",
              "_SYSTEMD_UNIT=facelock-daemon.service", "+", "SYSLOG_IDENTIFIER=pam_facelock"]
    stdout: SplitParser {
      onRead: function(line) {
        root.journalFailures = 0
        root.apply(Events.step(root.state, line))
      }
    }
    onExited: {
      root.journalFailures++
      root.restartTimer.restart()
    }
  }

  // Who asked? facelock only answers the services in its pam_policy, so
  // whichever PAM helper is alive when the camera opens is the requester.
  // ponytail: the PAM line at the end of the scan corrects a wrong guess.
  property Process requester: Process {
    command: ["pgrep", "-l", "^(sudo|polkit-agent-he)$"]
    stdout: StdioCollector { id: requesterOut; waitForEnd: true }
    onExited: root.apply(Events.resolveRequester(root.state, requesterOut.text))
  }

  // journalctl dies with journal rotation once in a while; come back, but back
  // off first. Where it cannot run at all — no systemd, or no permission to
  // read the journal — a fixed retry would respawn it every few seconds for as
  // long as the shell lives. The first line read resets this.
  property int journalFailures: 0
  property Timer restartTimer: Timer {
    interval: Math.min(300000, 3000 * Math.max(1, root.journalFailures))
    onTriggered: root.journal.running = true
  }
}
