# Facelock HUD

> **This is an animation, nothing more.** It is a tile that looks good on top of a facelock setup
> you already have working. It does not authenticate you, does not install, configure or enrol
> anything, and cannot make a scan succeed or fail. Install it for the looks; if facelock is not
> already set up and working, this plugin has nothing to show and changes nothing.

A Windows Hello style face-scan tile for [facelock](https://github.com/tyvsmith/facelock) on
Omarchy, in Omarchy's own dress. While facelock scans your face for a terminal password prompt or
a polkit dialog, a card drops in under the bar: the face icon breathes under a scan beam, then a
square frame traces itself into a check, or the card turns red and shakes.

![Scanning Face, Face Recognized and Not Recognized tiles](preview.png)

Theme colours, theme border, theme corner radius, theme font. Lock-screen scans stay silent,
because Omarchy's lock screen already draws its own face UI.

**The tile only ever displays.** facelock and PAM do the authenticating, entirely on their own;
this plugin reads the outcome afterwards, out of the journal, and draws it. Take the plugin away
and your face unlock works exactly as before — with no animation.

## Requirements

- Omarchy 4 with Quattro shell plugins (tested on 4.0.3-1 / Quickshell 0.3.1).
- [facelock](https://github.com/tyvsmith/facelock) 0.2.x, **already set up and working** — enrolled,
  with `pam_facelock.so` in the PAM services you care about (`facelock setup` wires those up).
  Setting that up is facelock's job and yours; this plugin never does any of it.
- Permission to read the system journal — Omarchy accounts are in `wheel`, which is enough.
- A Nerd Font as the shell font, for the face and badge glyphs (Omarchy's default is one).

No camera access, no daemon, no elevated privileges, nothing to configure — and no change to your
facelock or PAM setup, in either direction.

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

## Adding another backend

The tile knows nothing about facelock — it renders whatever payload it is handed. A second
backend is a new reader, never a change to the UI.

### Without forking anything

The `show` call above takes your payloads just as happily as facelock's:

| field        | values                                    |
|--------------|-------------------------------------------|
| `phase`      | `scanning`, `ok`, `fail`, `cancel`, `service` |
| `service`    | PAM service name, e.g. `sudo`, `polkit-1`; `omarchy-lock-face` closes the tile |
| `similarity` | optional; `"0.93"` renders as `93% match`, and without it `ok` reads `Welcome back` |

A few lines of shell around your backend's own hook, or around a `journalctl` grep, is a complete
integration. Nothing in this plugin has to know about it.

### Inside the plugin

Fork it — or open a PR here, if it is a backend you can show real evidence for.

**1. Capture real lines before writing any code.** While a scan runs:

```bash
journalctl -f -o cat SYSLOG_FACILITY=10             # authpriv: every PAM module
journalctl -f -o cat _SYSTEMD_UNIT=<backend>.service
```

PAM modules log through `pam_syslog()`, which prints `pam_<module>(<service>:auth): <message>`, so
the caller and the outcome are already there for Howdy, fprintd, facelock or anything else, with
no per-backend work. What is *not* generic is the **start** of a scan and any score: facelock
announces `camera format negotiated`, most backends say nothing until they are done. A backend
with no start signal gets a result-only tile — no scan beam, just the check or the shake — which
is a fine place to stop; watching the camera open with `inotifywait -m -e open /dev/video*` is the
alternative, at the cost of a dependency.

**2. Write `<backend>.js`** beside [`events.js`](events.js), in the same shape: `initialState()`
and `step(state, line)` returning `{state, probe?, announce?}`. Keep it pure — no QML types — so
it runs under `node --test`. The guarded `module.exports` at the foot of `events.js` is what lets
one file be imported by both QML and node.

**3. Add a reader** in [`Service.qml`](Service.qml): one `Process` with a fixed argument vector
(not `sh -c` — the marketplace validator flags it) whose `SplitParser` calls
`root.apply(Backend.step(root.state, line))`. Readers are independent, so several can run at once
and only the backend that is actually installed will ever emit.

`apply()` takes `{state, probe, announce}`: `probe` re-runs the `pgrep` that asks which PAM helper
is waiting, and `announce` is the payload from the table above.

**4. Test with the lines you captured.** Add a file under `tests/`, then `./tests/run`.

**5. If the backend is not a camera**, give the tile a variant: the glyph, `title` and `subtitle`
in [`Tile.qml`](Tile.qml) currently say "Scanning Face" and "Look at the camera".

**6. If you publish your fork**, change `id` in `manifest.json` and the `IpcHandler` target in
`Tile.qml`. Two plugins cannot share either one.

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
- It is display-only, and that is checkable rather than a promise. There is no `PamContext`
  anywhere in this repository — the only way QML can take part in authentication — and no
  `TextField`, no `Keys` handler, `WlrKeyboardFocus.None` and an empty input `mask`, so the card
  cannot take a keystroke or even a click. A forged `Face Recognized` tile grants nothing:
  whatever PAM decided, it decided before the tile drew anything.
- Any process in your session can push a payload to the IPC target and pop a tile. That is
  cosmetic, and the same is true of every Quickshell IPC target.
- Similarity scores from your own journal are shown on your own screen; nothing is sent anywhere.

A static scan of this repo raises these advisory capabilities, all expected: `qml-process` (the
two readers above), `privilege` (the word `sudo` — it is a PAM service name here, printed on a
badge). A clean scan is evidence about one commit, not a security audit.

Report a security issue as a GitHub issue on this repository, or privately to the repository
owner if it should not be public first.

## License

MIT © 2026 Tal Gruper. Bundles no third-party code.
