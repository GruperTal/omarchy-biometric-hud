const test = require("node:test")
const assert = require("node:assert/strict")
const { initialState, step } = require("../fprintd.js")
const { resolveRequester } = require("../requester.js")

const DEV = "/net/reactivated/Fprint/Device/0: "
// Captured from `gdbus monitor --system --dest net.reactivated.Fprint` during a
// real sudo on a Goodix MOC sensor: one touch that missed, then one that matched.
const CAPTURE = [
  DEV + "net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)",
  DEV + "org.freedesktop.DBus.Properties.PropertiesChanged ('net.reactivated.Fprint.Device', {'finger-needed': <true>}, @as [])",
  DEV + "org.freedesktop.DBus.Properties.PropertiesChanged ('net.reactivated.Fprint.Device', {'finger-present': <true>}, @as [])",
  DEV + "net.reactivated.Fprint.Device.VerifyStatus ('verify-no-match', true)",
  DEV + "org.freedesktop.DBus.Properties.PropertiesChanged ('net.reactivated.Fprint.Device', {'finger-present': <false>}, @as [])",
  DEV + "net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)",
  DEV + "net.reactivated.Fprint.Device.VerifyStatus ('verify-match', true)",
]

const run = (lines, state = initialState()) => {
  const announced = []
  let probes = 0
  for (const line of lines) {
    const r = step(state, line)
    state = r.state
    if (r.probe) probes++
    if (r.announce) announced.push(r.announce)
  }
  return { state, announced, probes }
}

test("a real scan: a miss, a retry, then a match", () => {
  const { announced, probes } = run(CAPTURE)
  assert.equal(probes, 2, "each verify asks again who is waiting")
  assert.deepEqual(announced, [
    { phase: "fail", modality: "finger" },
    { phase: "ok", modality: "finger" },
  ])
})

test("a badly read finger is a nudge, not a verdict", () => {
  // done=false: fprintd is still waiting on the same finger.
  const { announced } = run([
    DEV + "net.reactivated.Fprint.Device.VerifyStatus ('verify-retry-scan-too-short', false)",
    DEV + "net.reactivated.Fprint.Device.VerifyStatus ('verify-finger-not-centered', false)",
  ])
  assert.deepEqual(announced, [])
})

test("a lock-screen scan stays silent", () => {
  let state = initialState()
  const start = step(state, DEV + "net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)")
  assert.equal(start.probe, true)

  // Nothing is waiting on PAM in a terminal, so the lock screen owns this scan.
  const probed = resolveRequester(start.state, "")
  assert.equal(probed.announce, undefined)
  assert.equal(probed.state.quiet, true)

  const { announced } = run([DEV + "net.reactivated.Fprint.Device.VerifyStatus ('verify-match', true)"], probed.state)
  assert.deepEqual(announced, [])
})

test("the scanning tile a sudo scan opens is a fingerprint one", () => {
  const start = step(initialState(), DEV + "net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)")
  assert.deepEqual(resolveRequester(start.state, "48001 sudo\n").announce,
    { phase: "scanning", service: "sudo", modality: "finger" })
})

// Captured by cancelling a verify: the same ('verify-no-match', true) a real
// rejection ends with, but finger-needed drops and no finger ever arrives.
test("walking away from the prompt closes the tile, it does not blame the finger", () => {
  const { announced } = run([
    DEV + "net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)",
    DEV + "org.freedesktop.DBus.Properties.PropertiesChanged ('net.reactivated.Fprint.Device', {'finger-needed': <true>}, @as [])",
    DEV + "org.freedesktop.DBus.Properties.PropertiesChanged ('net.reactivated.Fprint.Device', {'finger-needed': <false>}, @as [])",
    DEV + "net.reactivated.Fprint.Device.VerifyStatus ('verify-no-match', true)",
  ])
  assert.deepEqual(announced, [{ phase: "cancel" }])
})

test("bus housekeeping is not a scan", () => {
  const { announced, probes } = run([
    "Monitoring signals from all objects owned by net.reactivated.Fprint",
    "The name net.reactivated.Fprint is owned by :1.26189",
    "The name net.reactivated.Fprint does not have an owner",
  ])
  assert.deepEqual(announced, [])
  assert.equal(probes, 0)
})
