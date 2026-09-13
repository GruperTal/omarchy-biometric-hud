import QtQuick
import Quickshell
import Quickshell.Io
import "facelock.js" as Facelock
import "fprintd.js" as Fprintd
import "requester.js" as Requester
import "limits.js" as Limits

// Two readers, one tile. facelock is followed through the journal, because its
// daemon's D-Bus signals are root-only; fprintd is followed over the system bus,
// because pam_fprintd logs nothing per attempt. Both feed the tile through
// lastEvent/eventSerial. Read-only: nothing here runs with privileges, writes a
// file, or touches PAM. The rules live in facelock.js and fprintd.js.
//
// Everything this plugin launches is launched the same way: an absolute path,
// never a name resolved through an inherited PATH, and a closed environment
// holding only what the child actually needs. The plugin lives inside a shell
// process that runs for the length of a login session, so neither its
// environment nor its idea of "journalctl" should be whatever the session
// happened to accumulate.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "io.github.grupertal.biometric-hud"

  // The tile watches eventSerial and reads lastEvent.
  property string lastEvent: ""
  property int eventSerial: 0

  property var state: Facelock.initialState()

  readonly property var childEnvironment: ({
    "PATH": "/usr/bin",   // nothing is resolved through it; a child that execs still gets a sane one
    "LC_ALL": "C"         // parsing is done against C-locale output, not the session's
  })

  // The one-shots are answers to a question asked now: if one has not answered
  // within this long it never will, so it is terminated rather than left to sit
  // in the process table.
  readonly property int oneShotDeadlineMs: 3000

  // Mirrors the clamshell gate PAM runs: with the lid shut the laptop's reader
  // is unreachable, so the stack skips pam_fprintd and the tile must not offer
  // a finger. /proc does not emit change events, so this is asked once per scan
  // rather than watched.
  property bool lidClosed: false

  property Process lid: Process {
    running: true   // know the answer before the first scan, not after it
    command: ["/usr/bin/omarchy-hw-laptop-closed"]   // the path PAM's own gate uses
    clearEnvironment: true
    environment: root.childEnvironment
    onStarted: root.lidDeadline.restart()
    onExited: function(code) {
      root.lidDeadline.stop()
      root.lidClosed = code === 0
    }
  }

  property Timer lidDeadline: Timer {
    interval: root.oneShotDeadlineMs
    onTriggered: root.lid.running = false
  }

  function apply(result) {
    state = result.state
    if (result.probe && !requester.running)
      requester.running = true
    if (result.probe && !lid.running)
      lid.running = true
    if (result.announce) {
      lastEvent = JSON.stringify(result.announce)
      eventSerial++
    }
  }

  // Both streams arrive as raw chunks (splitMarker: "") and are assembled into
  // lines in limits.js, where every length is checked before the string it
  // guards is built. A child that breaks a ceiling is terminated on the spot;
  // the backoff brings it back. See limits.js for why the parser must not
  // buffer on our behalf.
  property var journalStream: Limits.initialStream()
  property var fprintdStream: Limits.initialStream()

  property Process journal: Process {
    running: true
    command: ["/usr/bin/journalctl", "-f", "-n", "0", "-o", "cat",
              "_SYSTEMD_UNIT=facelock-daemon.service", "+", "SYSLOG_IDENTIFIER=pam_facelock"]
    clearEnvironment: true
    environment: root.childEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var fed = Limits.feed(root.journalStream, chunk, Date.now())
        root.journalStream = fed.stream
        if (fed.overflow) { root.journal.running = false; return }
        for (var i = 0; i < fed.lines.length; i++) {
          root.journalFailures = 0
          root.apply(Facelock.step(root.state, fed.lines[i]))
        }
      }
    }
    onExited: {
      root.journalStream = Limits.initialStream()
      root.journalFailures++
      root.restartTimer.restart()
    }
  }

  // Who asked? facelock only answers the services in its pam_policy, so
  // whichever PAM helper is alive when the camera opens is the requester.
  // ponytail: the PAM line at the end of the scan corrects a wrong guess.
  property Process requester: Process {
    command: ["/usr/bin/pgrep", "-l", "^(sudo|polkit-agent-he)$"]
    clearEnvironment: true
    environment: root.childEnvironment
    // Not StdioCollector: that keeps the whole output before any check can run.
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var got = Limits.collect(root.requesterText, chunk)
        root.requesterText = got.text
        if (got.overflow) root.requester.running = false
      }
    }
    onStarted: {
      root.requesterText = ""
      root.requesterDeadline.restart()
    }
    onExited: {
      root.requesterDeadline.stop()
      root.apply(Requester.resolveRequester(root.state, root.requesterText))
      root.requesterText = ""
    }
  }

  property string requesterText: ""

  property Timer requesterDeadline: Timer {
    interval: root.oneShotDeadlineMs
    onTriggered: root.requester.running = false
  }

  // fprintd's signals are broadcast, so an ordinary user receives them with a
  // match rule. `busctl monitor` would need BecomeMonitor, which the system bus
  // refuses to non-root; gdbus does not ask for it.
  property Process fprintd: Process {
    running: true
    command: ["/usr/bin/gdbus", "monitor", "--system", "--dest", "net.reactivated.Fprint"]
    clearEnvironment: true
    environment: root.childEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var fed = Limits.feed(root.fprintdStream, chunk, Date.now())
        root.fprintdStream = fed.stream
        if (fed.overflow) { root.fprintd.running = false; return }
        for (var i = 0; i < fed.lines.length; i++) {
          root.fprintdFailures = 0
          root.apply(Fprintd.step(root.state, fed.lines[i]))
        }
      }
    }
    onExited: {
      root.fprintdStream = Limits.initialStream()
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
