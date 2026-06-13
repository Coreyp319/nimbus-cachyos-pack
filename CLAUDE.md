# CLAUDE.md

Guidance for working in this repo.

## What this is
**Nimbus CachyOS pack** — a personal **CachyOS + KDE Plasma 6 (Wayland)**
macOS-style desktop + OS customization, organized into **nine independent,
reversible layers**. Users install any subset: `bash install.sh` (interactive)
or `-y` (all nine); `bash revert.sh` undoes (`--purge` also deletes files).

## Branding — read before renaming anything
The pack builds **on top of** the upstream **WhiteSur** theme suite. Two namespaces
coexist and must not be conflated:
- **Nimbus = the pack's OWN artifacts.** `com.nimbus.aurora` (wallpaper plugin),
  `org.nimbus.Aurora` (D-Bus), `org.nimbus.dockseparator` (plasmoid),
  `NimbusRefined`/`NimbusRefinedDark` (Kvantum forks), `Nimbus-dark-refined`
  (icon fork), `nimbus-*` scripts/services (aurora bridges, theme-toggle,
  quicklook, refine-icons, gpu-effects cache).
- **WhiteSur = upstream, KEEP as-is.** `com.github.vinceliuice.WhiteSur*`
  (LookAndFeel), the WhiteSur global theme / icons / Aurorae decoration /
  wallpapers the pack *installs*, the base Kvantum theme `WhiteSur`/`WhiteSurDark`
  the fork derives from, and `Inherits=WhiteSur-*` chains. Descriptive/credit
  mentions ("WhiteSur-derived", "Big Sur palette") also stay.

## Layers (each its own dir with install.sh + revert.sh)
1. `1-base/nimbus-cachyos-macos.sh` — the full WhiteSur desktop: theme, dock,
   fonts, blur, mac animations, Spotlight, **light/dark toggle**
   (`nimbus-theme-toggle.sh`, Meta+Ctrl+T), boot splash. The big one; uses sudo.
2. `2-settings-refine/` — monochrome System Settings section icons (themed via a
   `nimbus-refine-icons` systemd watcher) + the **NimbusRefined Kvantum fork**
   (accent focus rings on checkbox/radio/slider, scrollbar grab accent); this
   layer SELECTS NimbusRefined as the active Kvantum theme.
3. `3-krunner-finder/` — two-line KRunner rows + an "Ask Claude / Ask Hermes /
   web-search" D-Bus runner (`dev.corey.krunner.claude` — intentionally NOT
   Nimbus-namespaced).
4. `4-login-lock/` — Big Sur SDDM login + lock screens (sudo).
5. `5-system-qol/` — paccache, Flatpak+Flathub, fish tooling, Timeshift.
6. `6-local-ai/` — on-GPU Ollama: KV-cache drop-in + Hermes/Gemma/Qwen Modelfiles.
7. `7-notifications/` — Apple-style swaync toasts + center, scheme-synced.
8. `8-dolphin-quicklook/` — Space previews the selection via kiview.
9. `9-gpu-effects/` — Glass blur fork + ReShade-style desktop GLSL shaders, and
   `interactive-bg/` = the **Nimbus Aurora wallpaper** (see below).

## The aurora wallpaper (`9-gpu-effects/interactive-bg/`)
Plasma 6 wallpaper plugin `com.nimbus.aurora` — a cursor/window/music-reactive
Big Sur GLSL aurora on the QtQuick scene graph (NOT a KWin effect).
- Shader: `contents/shaders/aurora.frag` (Vulkan GLSL `#version 440`); compile
  with `/usr/lib/qt6/bin/qsb --qt6 -o contents/shaders/aurora.frag.qsb <src>`.
  A prebuilt `.qsb` is committed as a fallback — **rebuild + commit it whenever
  `aurora.frag` changes.**
- Config UI: `contents/ui/config.qml` + the reusable `AuroraSlider.qml` /
  `AuroraComboBox.qml` / `AuroraColorButton.qml` (custom expressive controls with
  `QtQuick.Effects.MultiEffect` GPU shadows). Defaults live in
  `contents/config/main.xml`.
- Deploy/activate: `apply.sh` (idempotent; sets the wallpaper + recompiles shader).
  Bridges: `windows-apply.sh` (window reactivity), `audio-apply.sh` (music).
  Lock screen: `lockscreen-apply.sh`. Each has a matching `*-restore.sh`.

## Conventions
- **Reversible by default**: every standing system change goes through an
  install/revert pair. Mirror live tweaks back into the owning layer's script.
- **Idempotent installers**, run as the **normal user** (sudo only where noted).
- **Wayland only** — effects/shaders need it.
- Blur forks (`glass`/`forceblur`/`kwin_effect_shaders`) **ignore
  `/KWin reconfigure`** — drive them via `/Effects` (load/unload/reconfigureEffect).
  See the `.claude/skills/kwin-gpu-effects` skill.

## Testing — run before any deploy
```bash
bash tests/run.sh    # 0 = all pass
```
Covers `bash -n` (all scripts), `py_compile`, SVG/JSON/XML validity, and — the
critical one — **`QQmlComponent.create()` on the aurora config UI via PyQt6**
(`tests/qml_instantiate.py`). `qmllint` validates syntax but NOT construction: an
invalid signal handler passes lint yet throws at create() and silently blanks the
Plasma config dialog. Always run this before deploying QML.

## Releases
Tagged `vMAJOR.MINOR.PATCH` on `main`, published via `gh release create`. Commit
style: conventional (`feat(layerN): …`, `fix(…)`, `docs(…)`, `test:`).
