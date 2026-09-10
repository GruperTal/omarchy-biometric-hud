# Face Unlock (Omarchy plugin)

A Windows Hello style tile for [facelock](https://github.com/tyvsmith/facelock) on Omarchy:
while your face is being scanned for `sudo` or polkit a small card slides in under the bar,
spins a ring around the face glyph, then shows **Face recognized** or **No match** and slides away.

It follows facelock's journal (`journalctl -f` on the daemon unit and the PAM module), since the
daemon's D-Bus signals are root-only. Nothing runs with privileges and nothing touches PAM.

## Requirements

- Omarchy 4 (Quickshell shell) with plugins enabled
- facelock installed and enrolled, with `pam_facelock.so` in the services you care about
- your user able to read the system journal (Omarchy users are in `wheel`, which is enough)

## Install

    omarchy plugin add https://github.com/gruper/omarchy-face-unlock

## Try it

    omarchy-shell face-unlock show '{"phase":"scanning"}'
    omarchy-shell face-unlock show '{"phase":"ok","similarity":"0.93"}'
