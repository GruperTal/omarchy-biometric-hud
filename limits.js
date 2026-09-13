// Ceilings for everything the plugin reads from a child process.
//
// Quickshell's SplitParser, given a delimiter, buffers inside Quickshell until
// that delimiter arrives, and StdioCollector keeps a child's whole output: in
// both cases the allocation happens before plugin code runs, so no check in a
// read handler can bound it. With an empty splitMarker, SplitParser instead
// hands over each chunk as it is read from the pipe and keeps nothing itself
// (src/io/datastream.cpp, SplitParser::parseBytes). Every reader here uses
// that raw delivery, and the lines are assembled below instead — with each
// length checked before the string it guards is built. Overflow is reported to
// the caller, which terminates the child at once.
//
// Lengths are UTF-16 code units, which is what a QML string allocates, so the
// ceiling bounds retained memory directly rather than approximating it.

var MAX_PENDING = 4096          // longest line held; the longest real one is ~430
var MAX_FRAMES_PER_WINDOW = 200 // a busy scan emits a handful a second
var WINDOW_MS = 1000
var MAX_COLLECTED = 4096        // pgrep -l for two process names; real output is under 100

function initialStream() {
  return { pending: "", windowStart: 0, frames: 0 }
}

// feed(stream, chunk, now) -> {stream, lines, overflow}
//   lines:    complete lines, in order, delimiter removed
//   overflow: the child broke a ceiling; stop it now. The returned stream is
//             reset, so nothing from the overflowing run is ever carried over.
function feed(stream, chunk, now) {
  var text = String(chunk)
  var pending = stream.pending
  var windowStart = stream.windowStart
  var frames = stream.frames
  var lines = []
  var start = 0

  for (;;) {
    var newline = text.indexOf("\n", start)
    var end = newline === -1 ? text.length : newline

    // The ceiling is checked on lengths alone, before the joined string exists.
    if (pending.length + (end - start) > MAX_PENDING)
      return { stream: initialStream(), lines: lines, overflow: true }

    if (newline === -1) {
      pending = pending + text.slice(start)
      break
    }

    if (now - windowStart >= WINDOW_MS) {
      windowStart = now
      frames = 0
    }
    if (++frames > MAX_FRAMES_PER_WINDOW)
      return { stream: initialStream(), lines: lines, overflow: true }

    lines.push(pending + text.slice(start, newline))
    pending = ""
    start = newline + 1
  }

  return { stream: { pending: pending, windowStart: windowStart, frames: frames }, lines: lines, overflow: false }
}

// collect(text, chunk) -> {text, overflow}
// The one-shot probe's whole answer, accumulated the same way: checked first,
// joined second, and abandoned the moment it cannot be a real answer.
function collect(text, chunk) {
  var add = String(chunk)
  if (text.length + add.length > MAX_COLLECTED)
    return { text: "", overflow: true }
  return { text: text + add, overflow: false }
}

if (typeof module !== "undefined") // ponytail: lets node require this QML JS file
  module.exports = { initialStream, feed, collect, MAX_PENDING, MAX_FRAMES_PER_WINDOW, WINDOW_MS, MAX_COLLECTED }
