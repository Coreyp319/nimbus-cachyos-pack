# WhiteSur macOS-style desktop pack — CachyOS / KDE Plasma 6

Turns a stock **CachyOS + KDE Plasma 6 (Wayland)** install into a cohesive
macOS-style desktop. Three independent layers — install any subset.

```bash
bash install.sh          # interactive, pick layers
bash install.sh -y       # install all three, no prompts
bash revert.sh           # undo (add --purge to delete installed files)
```

> Run as your **normal user** (not root). `sudo` is used only for packages and
> Layer 3's milou patch. **Log out / back in** afterward to activate `Meta+Space`
> and `Meta+Ctrl+T` (Wayland binds global shortcuts at login).

---

## Layers

### 1 · Base mac desktop  — `1-base/`
WhiteSur global theme (Plasma + Qt/Kvantum + GTK light & dark), icons, mac
cursors, **Inter** font, Big Sur wallpaper · floating **auto-hide dock** with
Launchpad + pinned apps · **Spotlight** (centered KRunner, `Meta+Space`) + file
search · mac-style window animations (scale/squash/maximize), Mission-Control
hot corner, edge tiling · heavy blur · frosted menus & Konsole · slight dock
bottom-margin · **one-click light↔dark toggle** (dock icon / Spotlight /
`Meta+Ctrl+T`) · Firefox set to **follow the system** light/dark theme · QoL:
NumLock on at login, Night Color (warm evenings).

⚠ **Replaces your panel/dock** (any panel with a task manager is rebuilt as the
mac dock) and restarts plasmashell. Reverting: System Settings → Global Theme →
Breeze, then remove the dock panel.

### 2 · System Settings refine  — `2-settings-refine/`
Uniform **monochrome line icons** for the System Settings sidebar sections
(replaces the mixed colorful set). A small **systemd path-watcher** re-tints them
to the active text color on every light↔dark switch (~400 ms), so they stay
readable in both modes. Also ships an optional **Kvantum whitespace fork**
(`WhiteSurRefined`, not auto-selected) that adds breathing room in classic Qt
dialogs. Fully reversible: `2-settings-refine/revert.sh`.

> Scope note: the Settings sidebar *spacing/layout* is compiled Kirigami QML and
> is **not** reachable by any theming overlay — only the iconography and selection
> colors are. This layer does the reachable part well.

### 3 · KRunner finder  — `3-krunner-finder/`
- **Row styling** *(needs sudo)*: 48px icons, two-line rows (filename + greyed
  path), tighter gutter, fade/lift animations. Patches milou's QML and installs a
  **pacman hook** so it survives milou upgrades. Backs up originals; revert with
  `sudo bash 3-krunner-finder/row-tweak/revert.sh`.
- **Web / Claude runner** *(no sudo)*: type and pause ~3 s for "Search the web"
  rows, or prefix for instant — `s …`/`ddg …` (DuckDuckGo), `gh …` (GitHub),
  `w …` (Wikipedia), `yt …` (YouTube). `c …`/`ai …` → **Ask Claude**, shown only
  if the `claude` CLI is on `PATH` (otherwise it stays hidden).

---

## Requirements
- Arch / CachyOS (`pacman`), **KDE Plasma 6**, **Wayland**
- Layer 1 installs (via sudo): `kvantum sassc optipng`
- Layer 3 runner deps: `python-dbus python-gobject` (web/Claude runner)
- Internet (Layer 1 clones the WhiteSur themes + downloads the Inter font)

## Caveats (please read)
- **Version fragility:** Layer 3's QML patch and the refined icons target *this*
  Plasma/milou (6.6.x). On a very different version the milou patch may no-op
  (the pacman hook re-applies on update); the rest degrades gracefully.
- **Community themes:** built on [vinceliuice/WhiteSur](https://github.com/vinceliuice)
  plus locally-authored overlay files. Installed under `$HOME`. Provided **as-is,
  no warranty** — skim the scripts before trusting them.
- Test on a spare machine / VM before sharing widely.

## Reverting everything
```bash
bash revert.sh           # layers 2 & 3 fully; layer 1 prints manual steps
bash revert.sh --purge   # also deletes the installed overlay files
```

## Layout
```
install.sh  revert.sh  README.md
1-base/            whitesur-cachyos-macos.sh
2-settings-refine/ install.sh revert.sh icons/ kvantum/ systemd/ bin/
3-krunner-finder/  install.sh revert.sh row-tweak/ claude-runner/
```
