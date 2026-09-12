const test = require("node:test")
const assert = require("node:assert/strict")
const { initialLimits, admit, collected, MAX_FRAME_BYTES, MAX_FRAMES_PER_WINDOW, WINDOW_MS, MAX_COLLECTED_BYTES } = require("../limits.js")

const real = 'INFO facelock_daemon::auth: authentication succeeded user="gruper" similarity="0.93" frames=3'

test("a real line passes", () => {
  const r = admit(initialLimits(), real, 1000)
  assert.equal(r.accept, true)
  assert.equal(r.flood, false)
})

test("an oversized frame is dropped, and does not stop the stream", () => {
  const r = admit(initialLimits(), "x".repeat(MAX_FRAME_BYTES + 1), 1000)
  assert.equal(r.accept, false)
  assert.equal(r.flood, false, "one long line is junk, not an attack")
})

test("a burst stops the stream", () => {
  let limits = initialLimits()
  let stopped = -1
  for (let i = 0; i < MAX_FRAMES_PER_WINDOW + 5; i++) {
    const r = admit(limits, real, 1000)   // same instant: all inside one window
    limits = r.limits
    if (r.flood && stopped === -1) stopped = i
  }
  assert.equal(stopped, MAX_FRAMES_PER_WINDOW, "stops on the frame past the cap, not before")
})

test("the window resets, so ordinary traffic never trips it", () => {
  let limits = initialLimits()
  for (let i = 0; i < MAX_FRAMES_PER_WINDOW; i++) limits = admit(limits, real, 1000).limits
  const after = admit(limits, real, 1000 + WINDOW_MS)
  assert.equal(after.accept, true)
  assert.equal(after.flood, false)
})

test("collected output is used only when it is a plausible size", () => {
  assert.equal(collected("48001 sudo\n"), "48001 sudo\n")
  assert.equal(collected("x".repeat(MAX_COLLECTED_BYTES + 1)), "", "too big to be pgrep's answer")
  assert.equal(collected(undefined), "")
})
