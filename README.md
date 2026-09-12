# Facelock HUD

A Windows Hello style face-scan tile for [facelock](https://github.com/tyvsmith/facelock) on
Omarchy, in Omarchy's own dress. While facelock scans your face for a terminal password prompt or
a polkit dialog, a card drops in under the bar: the face icon breathes under a scan beam, then a
square frame traces itself into a check, or the card turns red and shakes.

![Scanning Face, Face Recognized and Not Recognized tiles](preview.png)

Theme colours, theme border, theme corner radius, theme font. Lock-screen scans stay silent,
because Omarchy's lock screen already draws its own face UI.

**The tile only ever displays.** It cannot unlock anything, it never asks for a password, and it
has no say in whether authentication succeeds — facelock and PAM decide that, and this plugin
learns the outcome after the fact, from the journal.

## Requirements

- Omarchy 4 with Quattro shell plugins (tested on 4.0.3-1 / Quickshell 0.3.1).
- [facelock](https://github.com/tyvsmith/facelock) 0.2.x, enrolled, with `pam_facelock.so` in the
  PAM services you care about. See [docs/facelock-setup.md](docs/facelock-setup.md) for a working
  setup on an RGB-only webcam.
- Permission to read the system journal — Omarchy accounts are in `wheel`, which is enough.
- A Nerd Font as the shell font, for the face and badge glyphs (Omarchy's default is one).

No camera access, no daemon, no elevated privileges, and nothing to configure.

## Install

```bash
omarchy plugin add https://github.com/GruperTal/omarchy-face-unlock.git --enable
```

## Update

```bash
omarchy plugin update io.github.grupertal.facelock-hud
```

## Removal

```bash
omarchy plugin remove io.github.grupertal.facelock-hud
```

Nothing is left behind: the plugin writes no files, installs no services, and never touches PAM,
so removing the folder removes the plugin entirely. Your facelock setup is untouched either way.

## Try it without a camera

```bash
./demo/run           # a sudo scan that is recognized
./demo/run fail      # a sudo scan that is not
./demo/run polkit    # a polkit scan
```

Or drive one frame at a time:

```bash
omarchy-shell facelock show '{"phase":"scanning","service":"sudo"}'
omarchy-shell facelock show '{"phase":"ok","similarity":"0.93"}'
omarchy-shell facelock close
omarchy-shell facelock state          # scanning | ok | fail | closed
```

## Driving the tile from something else

`show` takes the same payload the built-in source produces, so any other biometric backend can
reuse the tile without touching this plugin:

| field        | values                                    |
|--------------|-------------------------------------------|
| `phase`      | `scanning`, `ok`, `fail`, `cancel`, `service` |
| `service`    | PAM service name, e.g. `sudo`, `polkit-1`; `omarchy-lock-face` closes the tile |
| `similarity` | `"0.93"`, shown as `93% match` on `ok`    |

Only facelock is read automatically. A fingerprint or Howdy source would be a new reader feeding
the same IPC, not a change to the tile.

## How it works

`Service.qml` follows two journal streams — `facelock-daemon.service` and the `pam_facelock`
syslog identifier — because facelock's D-Bus signals are root-only. `camera format negotiated`
opens a scan, `authentication succeeded|failed` resolves it, and the `pam_facelock(service):`
line names who asked. To label the card before that line arrives, one `pgrep` asks which PAM
helper is waiting; if none is, the scan belongs to the lock screen and the tile stays closed.

All of those rules live in [`events.js`](events.js) as pure functions, so they are tested against
real captured journal lines rather than by watching the screen.

## Tests

```bash
./tests/run
```

Manifest and tree validation, JSON fixtures, `bash -n`, six `node --test` cases over real journal
output, and `omarchy plugin validate` when Omarchy is present. CI runs the same script.

Live evidence for 1.0.0, on Omarchy 4.0.3-1 (Quickshell 0.3.1, Hyprland 0.56.2, three monitors at
scale 1) with facelock 0.2.1 installed: add, enable, reload and disable; the three tile states
over IPC (the preview above is those screenshots); and the journal path end to end, by replaying
real facelock lines through the journal — with a PAM helper waiting the tile opens on the camera
line, resolves on `authentication succeeded` and closes on the `omarchy-lock-face` PAM line, and
with none waiting the same sequence shows nothing at all.

Not tested: other Omarchy or facelock versions, fractional scaling, multi-user sessions, and
non-Hyprland compositors. A scan started by the lock screen while a `sudo` happens to be sitting
at a prompt is labelled as that `sudo`; the tile is drawn behind the session lock, where nothing
but the lock screen is shown, and the PAM line closes it.

## Security

Omarchy plugins run as unsandboxed code inside your long-lived `omarchy-shell` process, so review
this repository before enabling it. It is short on purpose.

- It runs exactly two commands, both read-only: `journalctl -f` restricted to facelock's unit and
  PAM identifier, and `pgrep -l` for two process names. Both are fixed argument vectors — no
  shell, no interpolation of journal content into a command.
- It never invokes `sudo` or `pkexec`, opens no network connection, writes no file, and makes no
  PAM, systemd, or facelock change.
- It is display-only. The tile has no text field and no key handling, and a forged
  `Face Recognized` tile grants nothing: authentication already happened in PAM.
- Any process in your session can push a payload to the IPC target and pop a tile. That is
  cosmetic, and the same is true of every Quickshell IPC target.
- Similarity scores from your own journal are shown on your own screen; nothing is sent anywhere.

A static scan of this repo raises these advisory capabilities, all expected: `qml-process` (the
two readers above), `privilege` (the word `sudo` — it is a PAM service name here, printed on a
badge), and on `docs/facelock-setup.md` `installer`, `package-manager` and `service-management`
(that file is documentation for setting up facelock; nothing in this plugin executes it). A clean
scan is evidence about one commit, not a security audit.

Report a security issue as a GitHub issue on this repository, or privately to the repository
owner if it should not be public first.

## License

MIT © 2026 Tal Gruper. Bundles no third-party code.
