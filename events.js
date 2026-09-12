// Pure reducer for facelock's journal output, kept out of QML so it can be
// tested with `node --test`. Service.qml owns the processes; this file owns
// the decisions.
//
// State is {quiet}: a scan the lock screen started shows nothing, because the
// lock screen draws its own face UI over everything.

function initialState() {
  return { quiet: false }
}

// One journal line in, at most one instruction out:
//   {state, probe: true}         ask who is waiting on PAM, then announce
//   {state, announce: {...}}     payload for the tile
function step(state, rawLine) {
  const line = String(rawLine).replace(/\x1b\[[0-9;]*m/g, "")
  const quiet = !!(state && state.quiet)

  if (line.indexOf("camera format negotiated") !== -1)
    return { state: { quiet: quiet }, probe: true }

  if (line.indexOf("authentication succeeded") !== -1) {
    if (quiet) return { state: { quiet: true } }
    const m = line.match(/similarity="([0-9.]+)"/)
    return { state: { quiet: false }, announce: { phase: "ok", similarity: m ? m[1] : "" } }
  }

  if (line.indexOf("authentication failed") !== -1)
    return quiet ? { state: { quiet: true } } : { state: { quiet: false }, announce: { phase: "fail" } }

  // A cancelled scan clears the quiet flag: no PAM line is coming to clear it.
  if (line.indexOf("authentication cancelled") !== -1)
    return { state: { quiet: false }, announce: { phase: "cancel" } }

  // pam_facelock(sudo): authenticated — the authoritative name of the caller,
  // and the end of the scan either way.
  const pam = line.match(/^pam_facelock\(([^)]+)\): (\w+)/)
  if (pam)
    return quiet
      ? { state: { quiet: false } }
      : { state: { quiet: false }, announce: { phase: "service", service: pam[1], result: pam[2] } }

  return { state: { quiet: quiet } }
}

// `pgrep -l` output for the PAM helpers facelock is allowed to answer. polkit
// wins over sudo: a polkit prompt in a terminal leaves a sudo process around.
// Neither means nothing is waiting on a terminal, so this scan is the lock
// screen's.
function resolveRequester(state, pgrepOutput) {
  const names = String(pgrepOutput || "")
    .split("\n")
    .map(function (l) { return l.trim().split(/\s+/).pop() })

  const who = names.indexOf("polkit-agent-he") !== -1 ? "polkit-1"
    : names.indexOf("sudo") !== -1 ? "sudo"
    : ""

  return who === ""
    ? { state: { quiet: true } }
    : { state: { quiet: false }, announce: { phase: "scanning", service: who } }
}

if (typeof module !== "undefined") // ponytail: lets node require this QML JS file
  module.exports = { initialState, step, resolveRequester }
