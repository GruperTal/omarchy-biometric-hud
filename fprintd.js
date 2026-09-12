// Reader for fprintd, the fingerprint daemon behind pam_fprintd.
//
// pam_fprintd logs nothing per attempt, so unlike facelock there is no journal
// to follow. What it does do is drive fprintd over the system bus, and those
// signals are broadcast: `gdbus monitor --system --dest net.reactivated.Fprint`
// receives them as an ordinary user, without the root-only BecomeMonitor that
// `busctl monitor` asks for. A whole scan looks like this:
//
//   VerifyFingerSelected ('right-index-finger',)
//   PropertiesChanged (..., {'finger-needed': <true>}, ...)
//   PropertiesChanged (..., {'finger-present': <true>}, ...)
//   VerifyStatus ('verify-no-match', true)
//   VerifyFingerSelected ('right-index-finger',)      <- pam_fprintd retries
//   VerifyStatus ('verify-match', true)
//
// The boolean on VerifyStatus is fprintd's `done`: false means the sensor read
// badly and the same verify is still running, so it is a nudge, not a verdict.
//
// A cancelled verify — Ctrl-C at the prompt — emits that same
// ('verify-no-match', true), so the status alone cannot tell a rejection from a
// walk-away. What separates them is whether a finger ever landed: a real
// rejection reports finger-present first, a cancellation never does.

function initialState() {
  return { quiet: false, modality: "finger", touched: false }
}

function step(state, rawLine) {
  const line = String(rawLine)
  const next = Object.assign({}, state)

  // A verify has begun: this reader now owns the tile, and asks who is waiting.
  if (line.indexOf("VerifyFingerSelected") !== -1) {
    next.modality = "finger"
    next.touched = false
    return { state: next, probe: true }
  }

  // facelock owns the scan in flight; anything here is from an older one.
  if (next.modality !== "finger") return { state: next }

  if (line.indexOf("'finger-present': <true>") !== -1) {
    next.touched = true
    return { state: next }
  }

  const m = line.match(/VerifyStatus \('([a-z-]+)',\s*(true|false)\)/)
  if (!m) return { state: next }

  const status = m[1]
  const done = m[2] === "true"

  // verify-retry-scan-too-short, verify-finger-not-centered, verify-swipe-too-short:
  // fprintd is still waiting on the same finger, so the tile keeps scanning.
  if (!done) return { state: next }

  if (status === "verify-match")
    return next.quiet ? { state: next } : { state: next, announce: { phase: "ok", modality: "finger" } }

  // No finger ever touched the sensor, so nothing was rejected: the prompt was
  // abandoned. Close the tile instead of blaming the finger.
  if (!next.touched) return { state: next, announce: { phase: "cancel" } }

  return next.quiet ? { state: next } : { state: next, announce: { phase: "fail", modality: "finger" } }
}

if (typeof module !== "undefined") // ponytail: lets node require this QML JS file
  module.exports = { initialState, step }
