# Face Unlock (Omarchy plugin)

A face-scan HUD for [facelock](https://github.com/tyvsmith/facelock) on Omarchy, in Omarchy's own style:
while your face is scanned for `sudo` or polkit a card drops in under the bar with a scan beam
over the face icon, then traces a check (**Face Recognized**) or shakes (**Not Recognized**). Theme colors, border and font throughout; lock-screen scans stay silent.

It follows facelock's journal (`journalctl -f` on the daemon unit and the PAM module), since the
daemon's D-Bus signals are root-only. Nothing runs with privileges and nothing touches PAM.

## Requirements

- Omarchy 4 (Quickshell shell) with plugins enabled
- facelock installed and enrolled, with `pam_facelock.so` in the services you care about
- your user able to read the system journal (Omarchy users are in `wheel`, which is enough)

## Install

    omarchy plugin add https://github.com/GruperTal/omarchy-face-unlock.git --enable

## Try it

    omarchy-shell face-unlock show '{"phase":"scanning"}'
    omarchy-shell face-unlock show '{"phase":"ok","similarity":"0.93"}'

## Setting up facelock itself

See [docs/facelock-setup.md](docs/facelock-setup.md): install, the config that works on an
RGB-only webcam, enrollment, PAM, and the Lock Screen Explorer patch for the lock screen.
