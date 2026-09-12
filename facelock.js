// Reader for facelock: a pure reducer over its journal output, kept out of QML
// so it can be tested with `node --test`. Service.qml owns the processes; this
// file owns the decisions. The shared "who asked" probe lives in requester.js.
//
// State is {quiet, modality}: a scan the lock screen started shows nothing,
// because the lock screen draws its own face UI over everything. `modality`
// names the reader that owns the scan in flight — journald buffers where D-Bus
// does not, so facelock's verdict can arrive after PAM has already moved on to
// the fingerprint reader, and a verdict for a finished scan must not redraw the
// tile over the live one.

function initialState() {
  return { quiet: false, modality: "face" }
}

// One journal line in, at most one instruction out:
//   {state, probe: true}         ask who is waiting on PAM, then announce
//   {state, announce: {...}}     payload for the tile
function step(state, rawLine) {
  const line = String(rawLine).replace(/\x1b\[[0-9;]*m/g, "")
  const quiet = !!(state && state.quiet)
  const next = Object.assign({}, state)

  // A camera opened: this reader owns the tile until someone else claims it.
  if (line.indexOf("camera format negotiated") !== -1) {
    next.modality = "face"
    return { state: next, probe: true }
  }

  // A fingerprint scan has taken over; this line belongs to a scan that is over.
  if (next.modality === "finger") return { state: next }

  if (line.indexOf("authentication succeeded") !== -1) {
    if (quiet) return { state: { quiet: true, modality: "face" } }
    const m = line.match(/similarity="([0-9.]+)"/)
    return { state: { quiet: false, modality: "face" }, announce: { phase: "ok", modality: "face", similarity: m ? m[1] : "" } }
  }

  if (line.indexOf("authentication failed") !== -1)
    return quiet
      ? { state: { quiet: true, modality: "face" } }
      : { state: { quiet: false, modality: "face" }, announce: { phase: "fail", modality: "face" } }

  // A cancelled scan clears the quiet flag: no PAM line is coming to clear it.
  if (line.indexOf("authentication cancelled") !== -1)
    return { state: { quiet: false, modality: "face" }, announce: { phase: "cancel" } }

  // pam_facelock(sudo): authenticated — the authoritative name of the caller,
  // and the end of the scan either way.
  const pam = line.match(/^pam_facelock\(([^)]+)\): (\w+)/)
  if (pam)
    return quiet
      ? { state: { quiet: false, modality: "face" } }
      : { state: { quiet: false, modality: "face" }, announce: { phase: "service", service: pam[1], result: pam[2] } }

  return { state: { quiet: quiet, modality: "face" } }
}

if (typeof module !== "undefined") // ponytail: lets node require this QML JS file
  module.exports = { initialState, step }
