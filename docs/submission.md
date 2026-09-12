### Repository URL

https://github.com/GruperTal/omarchy-biometric-hud

### Category

System

### Tags

security, quickshell, hyprland

### Suggest a missing tag

_No response_

### Maintainer notes

Display only: the plugin shows what fprintd or facelock already decided, and takes no part in authentication. There is no PamContext anywhere in the repository, no text field, no key handling, WlrKeyboardFocus.None and an empty input mask, so the card cannot take a keystroke or a click.

It runs four read-only commands, all fixed argument vectors with no shell: journalctl -f scoped to facelock's unit and PAM identifier; gdbus monitor scoped to net.reactivated.Fprint (broadcast signals only, never BecomeMonitor); pgrep -l for two process names; and Omarchy's own omarchy-hw-laptop-closed. It reads three world-readable files (the theme's colors.toml, /etc/pam.d/sudo, /etc/pam.d/polkit-1) and writes none, installs no service, and makes no PAM change.

A static scan raises two advisory capabilities, both expected and explained in the README: qml-process for the readers above, and privilege because the word sudo appears as a PAM service name printed on a badge.

Tested on Omarchy 4.0.3-1 with Quickshell 0.3.1 and Hyprland 0.56.2: real fingerprint scans through sudo on a Goodix MOC sensor (matched, rejected, abandoned at the prompt) and facelock 0.2.1 face scans. ./tests/run covers the parsers with captured journal lines and bus signals.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
