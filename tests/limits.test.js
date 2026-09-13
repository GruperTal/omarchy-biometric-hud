const test = require("node:test")
const assert = require("node:assert/strict")
const { initialStream, feed, collect, MAX_PENDING, MAX_FRAMES_PER_WINDOW, WINDOW_MS, MAX_COLLECTED } = require("../limits.js")

const real = 'INFO facelock_daemon::auth: authentication succeeded user="gruper" similarity="0.93" frames=3'

test("a line split across chunks comes out whole", () => {
  let s = initialStream()
  let r = feed(s, real.slice(0, 20), 1000)
  assert.deepEqual(r.lines, [])
  r = feed(r.stream, real.slice(20) + "\n", 1000)
  assert.deepEqual(r.lines, [real])
  assert.equal(r.stream.pending, "")
})

test("several lines in one chunk come out in order, with the tail kept", () => {
  const r = feed(initialStream(), "one\ntwo\nthr", 1000)
  assert.deepEqual(r.lines, ["one", "two"])
  assert.equal(r.stream.pending, "thr")
  assert.equal(r.overflow, false)
})

// The failure the marketplace review describes: a producer that never sends a
// delimiter. The check must trip before the oversized string is built, and the
// reset stream must carry nothing from the overflowing run.
test("an unterminated flood overflows before it is joined", () => {
  let s = initialStream()
  const chunk = "x".repeat(1024)
  let tripped = -1
  for (let i = 0; i < 10; i++) {
    const r = feed(s, chunk, 1000)
    s = r.stream
    if (r.overflow) { tripped = i; break }
    assert.ok(s.pending.length <= MAX_PENDING, "never holds more than the ceiling")
  }
  assert.equal(tripped, Math.floor(MAX_PENDING / 1024), "trips on the chunk that would cross it")
  assert.equal(s.pending, "", "nothing from the overflowing run survives")
})

test("a single chunk longer than the ceiling overflows without being kept", () => {
  const r = feed(initialStream(), "y".repeat(MAX_PENDING + 1), 1000)
  assert.equal(r.overflow, true)
  assert.deepEqual(r.lines, [])
})

test("a line exactly at the ceiling is still a line", () => {
  const r = feed(initialStream(), "z".repeat(MAX_PENDING) + "\n", 1000)
  assert.equal(r.overflow, false)
  assert.equal(r.lines[0].length, MAX_PENDING)
})

test("a burst of complete lines overflows too", () => {
  const burst = (real + "\n").repeat(MAX_FRAMES_PER_WINDOW + 1)
  const r = feed(initialStream(), burst, 1000)
  assert.equal(r.overflow, true)
  assert.equal(r.lines.length, MAX_FRAMES_PER_WINDOW, "everything before the cap is delivered")
})

test("the window resets, so ordinary traffic never trips it", () => {
  let s = feed(initialStream(), (real + "\n").repeat(MAX_FRAMES_PER_WINDOW), 1000).stream
  const r = feed(s, real + "\n", 1000 + WINDOW_MS)
  assert.equal(r.overflow, false)
  assert.deepEqual(r.lines, [real])
})

test("the probe's answer is collected until it cannot be real", () => {
  let r = collect("", "48001 sudo\n")
  r = collect(r.text, "48010 polkit-agent-he\n")
  assert.equal(r.text, "48001 sudo\n48010 polkit-agent-he\n")
  assert.equal(r.overflow, false)

  const big = collect("a".repeat(MAX_COLLECTED - 1), "bb")
  assert.equal(big.overflow, true)
  assert.equal(big.text, "", "an overflowing answer is no answer")
})
