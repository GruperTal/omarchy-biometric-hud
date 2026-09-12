import QtQuick
import Quickshell
import Quickshell.Io
import "facelock.js" as Facelock
import "fprintd.js" as Fprintd
import "requester.js" as Requester

// Two readers, one tile. facelock is followed through the journal, because its
// daemon's D-Bus signals are root-only; fprintd is followed over the system bus,
// because pam_fprintd logs nothing per attempt. Both feed the tile through
// lastEvent/eventSerial. Read-only: nothing here runs with privileges, writes a
// file, or touches PAM. The rules live in facelock.js and fprintd.js.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "io.github.grupertal.biometric-hud"

  // The tile watches eventSerial and reads lastEvent.
  property string lastEvent: ""
  property int eventSerial: 0

  property var state: Facelock.initialState()

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
        root.apply(Facelock.step(root.state, line))
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
    onExited: root.apply(Requester.resolveRequester(root.state, requesterOut.text))
  }

  // fprintd's signals are broadcast, so an ordinary user receives them with a
  // match rule. `busctl monitor` would need BecomeMonitor, which the system bus
  // refuses to non-root; gdbus does not ask for it.
  property Process fprintd: Process {
    running: true
    command: ["gdbus", "monitor", "--system", "--dest", "net.reactivated.Fprint"]
    stdout: SplitParser {
      onRead: function(line) {
        root.fprintdFailures = 0
        root.apply(Fprintd.step(root.state, line))
      }
    }
    onExited: {
      root.fprintdFailures++
      root.fprintdTimer.restart()
    }
  }

  property int fprintdFailures: 0
  property Timer fprintdTimer: Timer {
    interval: Math.min(300000, 3000 * Math.max(1, root.fprintdFailures))
    onTriggered: root.fprintd.running = true
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
