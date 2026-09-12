// Ceilings for the two long-lived reader streams.
//
// Quickshell's SplitParser buffers until its delimiter arrives and exposes no
// maximum frame size, and StdioCollector has no byte cap, so the limits live
// here. Both streams are restricted at the source — journalctl to facelock's
// unit and the pam_facelock identifier, gdbus to a bus name only root's fprintd
// may own — but "restricted" is not "bounded", and anything that can write to
// the journal can put bytes in front of this parser.
//
// A frame over the cap is dropped, not truncated: a line that long is not
// facelock's or fprintd's, and half of it is worth nothing. A burst over the
// window cap stops the reader, which then comes back on the same backoff a
// crash uses.

var MAX_FRAME_BYTES = 4096      // longest real line seen is ~400
var MAX_FRAMES_PER_WINDOW = 200 // a busy scan emits a handful a second
var WINDOW_MS = 1000

function initialLimits() {
  return { windowStart: 0, frames: 0 }
}

// admit(limits, line, now) -> {limits, accept, flood}
//   accept: hand the line to a reader
//   flood:  stop the stream and let the backoff bring it back
function admit(limits, line, now) {
  var next = { windowStart: limits.windowStart, frames: limits.frames }

  if (now - next.windowStart >= WINDOW_MS) {
    next.windowStart = now
    next.frames = 0
  }
  next.frames++

  if (next.frames > MAX_FRAMES_PER_WINDOW)
    return { limits: next, accept: false, flood: true }

  if (String(line).length > MAX_FRAME_BYTES)
    return { limits: next, accept: false, flood: false }

  return { limits: next, accept: true, flood: false }
}

// The requester probe collects into one buffer instead of framing, so its
// output is capped on use: pgrep -l for two names cannot legitimately be long.
var MAX_COLLECTED_BYTES = 4096

function collected(text) {
  var out = String(text || "")
  return out.length > MAX_COLLECTED_BYTES ? "" : out
}

if (typeof module !== "undefined") // ponytail: lets node require this QML JS file
  module.exports = { initialLimits, admit, collected, MAX_FRAME_BYTES, MAX_FRAMES_PER_WINDOW, WINDOW_MS, MAX_COLLECTED_BYTES }
