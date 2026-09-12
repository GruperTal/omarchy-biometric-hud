// Which PAM helper is waiting? Shared by every reader: the backends differ,
// but "who asked for this scan" is the same question for all of them, and the
// answer decides whether the tile says SUDO, POLKIT, or stays shut because the
// scan belongs to the lock screen.

// `pgrep -l` output for the PAM helpers facelock is allowed to answer. polkit
// wins over sudo: a polkit prompt in a terminal leaves a sudo process around.
// Neither means nothing is waiting on a terminal, so this scan is the lock
// screen's.
function resolveRequester(state, pgrepOutput) {
  // Whichever reader opened this scan already stamped its modality; carry it
  // through, or the tile would draw a face for a fingerprint scan.
  const modality = (state && state.modality) || "face"
  const names = String(pgrepOutput || "")
    .split("\n")
    .map(function (l) { return l.trim().split(/\s+/).pop() })

  const who = names.indexOf("polkit-agent-he") !== -1 ? "polkit-1"
    : names.indexOf("sudo") !== -1 ? "sudo"
    : ""

  return who === ""
    ? { state: { quiet: true, modality: modality } }
    : { state: { quiet: false, modality: modality },
        announce: { phase: "scanning", service: who, modality: modality } }
}

if (typeof module !== "undefined") // ponytail: lets node require this QML JS file
  module.exports = { resolveRequester }
