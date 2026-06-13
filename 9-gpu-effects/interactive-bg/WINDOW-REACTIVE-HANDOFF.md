# Handoff — make the aurora react to windows being dragged

Spec + hard-won constraints for whoever builds the window-movement-reactive feature
of `com.nimbus.aurora`. The cursor-reactive base (v1) is shipped; this is the
deferred v2. Read `README.md` first for the plugin layout.

## Goal

When the user drags/moves a window, the aurora behind/around it should respond —
e.g. the flow displaces around each window rect, edges glow, and the *moving*
window leaves a velocity-based "wake". Most of the canvas is covered by windows, so
the payoff is visible in the gaps and as a moving window reveals background.

## The core constraint (why this isn't just a QML change)

On **Wayland**, a Plasma wallpaper runs inside `plasmashell` and has **zero access
to other windows' geometry or pixels** — that lives in the compositor (KWin). So you
need a bridge:

```
KWin script ──D-Bus──► bridge daemon ──state file──► wallpaper (main.qml) ──► shader
(live window     (callDBus; the         (atomic write;     (polls the file,
 geometry +       script sandbox         e.g. $XDG_RUNTIME   smooths, feeds
 move events)     CANNOT write files)    _DIR/nimbus-      shader uniforms)
                                         aurora/windows.json)
```

### Why each hop is shaped this way (verified this session)

- **KWin script is the only source of live geometry.** A plain session process
  cannot enumerate Wayland window geometry. A KWin *script* runs inside KWin and can.
- **KWin scripts are sandboxed: NO filesystem access.** They have `callDBus`,
  `print`, `readConfig`, `registerShortcut`, and `QTimer`. So the script must
  **push** data out via `callDBus` — it can't write the state file itself.
- **The wallpaper can read files / run commands.** v1 already uses
  `org.kde.plasma.plasma5support` `DataSource{engine:"executable"}` (see the
  colour-scheme probe in `main.qml`). Reuse that to `cat` the state file, or read it
  with `XMLHttpRequest` on a `file://` URL. Poll at ~30–60 Hz and smooth in QML.
- Net: you need **one small bridge daemon** that owns a D-Bus name (e.g.
  `org.nimbus.Aurora`), receives `UpdateWindows(s json)` from the KWin script, and
  writes the state file atomically. `dbus-python` + a `GLib` main loop are available
  (so is `Pillow`, if needed for the sibling colour feature). ~50 lines.

## Component specs

### 1. KWin script  (`~/.local/share/kwin/scripts/nimbus-aurora-windows/`)
Connect (KWin 6.x — **verify exact names against the running KWin, the scripting API
drifts**; quick check below):
- `workspace.windowList()` → array of Window. Per-window: `frameGeometry`
  (`{x,y,width,height}` in **global screen px**), `resourceClass`, `active`,
  `minimized`, `normalWindow`, `move`/`resize` (true during interactive op),
  `output` (which screen).
- Signals: `workspace.windowAdded`, `workspace.windowRemoved`,
  `workspace.windowActivated`; per-window `frameGeometryChanged`,
  `interactiveMoveResizeStarted/Stepped/Finished`.
On any change, build a compact JSON (window rects + active index + a moving flag +
computed velocity) and `callDBus("org.nimbus.Aurora","/","org.nimbus.Aurora",
"UpdateWindows", json)`. **Throttle** move events to ~30–60 Hz (coalesce with a
QTimer / timestamp guard) — `frameGeometryChanged` fires very rapidly during a drag.

Verify the API in ~1 min by loading a probe script:
`qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /path/probe.js`
then `start`, and `print()` `workspace.windowList().length` + a window's keys; watch
`journalctl --user -f | grep js`.

### 2. Bridge daemon  (`interactive-bg/aurora-bridge.py`, a systemd --user service)
- `dbus.service.Object` on the session bus, name `org.nimbus.Aurora`, method
  `UpdateWindows(json)`.
- On receive: write `${XDG_RUNTIME_DIR}/nimbus-aurora/windows.json` atomically
  (write tmp + `os.rename`). Keep it tiny.
- Run via a user unit installed/removed by the layer; opt-in.

### 3. Wallpaper consumer  (`contents/ui/main.qml`)
- A `Timer` (~33 ms) reads the state file (P5Support exec `cat`, or XHR `file://`).
- **Normalise** each rect from global screen px to this wallpaper's 0..1 space.
  NB **multi-monitor**: the wallpaper is per-containment/per-screen — filter to the
  windows on *this* screen and offset by this screen's geometry. (Dev box is single
  3440×1440 + a 3840×2160; don't assume one screen.)
- Smooth toward targets (Behaviors) so 30 Hz updates look fluid; the shader's own
  time animation fills gaps. Feed the shader (next).

### 4. Shader  (`contents/shaders/aurora.frag`)
- ShaderEffect **array uniforms are unreliable**; pass up to N windows as individual
  `vec4` properties (`uWin0..uWinN` = normalised x,y,w,h), plus `uWinCount`,
  `uActiveWin` (vec4) and `uActiveVel` (vec2). Or pack into a tiny data texture if N
  must be large.
- The **cursor bloom is your exact template**: in `aurora.frag`, `bloom`/`warpP`
  already show how to (a) add a soft radial glow at a point and (b) displace the
  flow toward it. Do the same per window rect (distance-to-rect field), and add a
  directional wake for `uActiveWin` driven by `uActiveVel`.
- Recompile: `qsb --qt6 -o aurora.frag.qsb aurora.frag` (qsb at
  `/usr/lib/qt6/bin/qsb`). UBO members bind to ShaderEffect properties by name.

## Install / revert wiring
Mirror into Layer 9: install copies the KWin script + enables it in `kwinrc`
`[Plugins] nimbus-aurora-windowsEnabled=true` (reload via
`qdbus6 org.kde.KWin /Effects` is for effects; for scripts use
`org.kde.kwin.Scripting`), installs+starts the user service, and adds a config
toggle ("React to window movement"). Revert disables/removes all three and the
state file. Keep it opt-in.

## Don't-repeat-my-mistakes
- **`ScreenShot2` is auth-gated** (`NoAuthorized`) — irrelevant to *geometry*, but it
  blocks the sibling "adapt colours to active window *content*" feature from a
  daemon. Geometry needs no such auth.
- Plasma 6 wallpaper gotchas (root must be `WallpaperItem`, `Kirigami.Theme` doesn't
  track the colour scheme, ShaderEffect needs `.qsb`) are documented in `README.md`
  and were all paid for already — don't rediscover them.
