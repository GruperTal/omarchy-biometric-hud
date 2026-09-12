const test = require("node:test")
const assert = require("node:assert/strict")
const { initialState, step } = require("../facelock.js")
const { resolveRequester } = require("../requester.js")

const ESC = String.fromCharCode(27)

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

// A sudo scan: camera opens, pgrep finds sudo, facelock matches.
test("sudo scan announces scanning, then the match, then the service", () => {
  let state = initialState()
  const open = step(state, ESC + "[32mINFO" + ESC + "[0m facelock_camera::capture: camera format negotiated device=/dev/video0 format=YUYV")
  assert.equal(open.probe, true)
  state = open.state

  const probed = resolveRequester(state, "48001 sudo\n")
  assert.deepEqual(probed.announce, { phase: "scanning", service: "sudo", modality: "face" })
  state = probed.state

  const { announced } = run([
    'INFO facelock_daemon::auth: authentication succeeded user="alice" similarity="0.93" frames=3',
    "pam_facelock(sudo): success for user alice",
  ], state)
  assert.deepEqual(announced, [
    { phase: "ok", modality: "face", similarity: "0.93" },
    { phase: "service", service: "sudo", result: "success" },
  ])
})

// The lock screen draws its own face UI, so a scan nobody asked for stays dark.
test("a scan with no PAM helper waiting announces nothing", () => {
  const probed = resolveRequester(initialState(), "")
  assert.equal(probed.announce, undefined)
  assert.equal(probed.state.quiet, true)

  const { announced, state } = run([
    'INFO facelock_daemon::auth: authentication succeeded user="alice" similarity="0.97" frames=3',
    "pam_facelock(omarchy-lock-face): success for user alice",
  ], probed.state)
  assert.deepEqual(announced, [])
  assert.equal(state.quiet, false, "the PAM line ends the quiet scan")
})

test("a failed scan is announced, a quiet one is not", () => {
  assert.deepEqual(run(["INFO facelock_daemon::auth: authentication failed user=\"alice\" similarity=\"0.12\""]).announced, [{ phase: "fail", modality: "face" }])
  assert.deepEqual(run(["INFO facelock_daemon::auth: authentication failed user=\"alice\""], { quiet: true }).announced, [])
})

// No PAM line follows a cancelled scan, so this is what clears quiet.
test("cancellation closes the tile and clears quiet", () => {
  const r = step({ quiet: true }, "authentication cancelled")
  assert.deepEqual(r.announce, { phase: "cancel" })
  assert.equal(r.state.quiet, false)
})

test("polkit wins over the sudo left behind by a terminal prompt", () => {
  const out = "48001 sudo\n48010 polkit-agent-he\n"
  assert.deepEqual(resolveRequester(initialState(), out).announce,
    { phase: "scanning", service: "polkit-1", modality: "face" })
})

// journald buffers and D-Bus does not, so facelock's verdict can land after PAM
// has already handed over to the fingerprint reader. Redrawing the tile then
// would replace a live fingerprint scan with a dead face result.
test("a verdict that arrives after the fingerprint scan started is dropped", () => {
  const { announced } = run([
    'INFO facelock_daemon::auth: authentication failed user="gruper" similarity="0.00"',
    "pam_facelock(sudo): no_match for user gruper",
  ], { quiet: false, modality: "finger" })
  assert.deepEqual(announced, [])
})

test("unrelated journal lines change nothing", () => {
  const { announced, probes, state } = run([
    "daemon listening on /run/facelock/daemon.sock",
    "loaded 2 templates for user",
  ])
  assert.deepEqual(announced, [])
  assert.equal(probes, 0)
  assert.equal(state.quiet, false)
})
