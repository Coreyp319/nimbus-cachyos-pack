# Nimbus Launchpad (`com.nimbus.launchpad`)

A full-screen, Big Sur–style application launcher with a **blur-and-zoom
intro/outro**, for Plasma 6 / Wayland. Part of Layer 9.

## What it is
A small Nimbus-owned plasmoid that **reuses the installed kicker C++ engine**
(`org.kde.plasma.private.kicker`) rather than forking the whole `kickerdash`
package (whose QML ships precompiled, with no source on disk):

- **`DashboardWindow`** — the frameless full-screen window. It only maps/unmaps
  and already asks KWin to blur the desktop behind it
  (`KWindowEffects::enableBlurBehind`), so the frosted backdrop is free.
- **`RootModel`** with `showAllApps: true` — the **category sidebar** (row 0 =
  "All Applications", rows 1.. = the app categories); the grid shows the selected
  category's apps via `rootModel.modelForRow(row)`. (`RootModel` only ever exposes
  the categories — `flat`/`showTopLevelItems` do NOT flatten its root, so the
  sidebar drives the grid instead.)
- **`RunnerModel`** (merged results) — type-to-search via KRunner (hides the
  sidebar and searches across all apps).
- **`KAStatsFavoritesModel`** — wired into the models; the favourites strip /
  pin UI is deferred (see below).

We supply our own content (`contents/ui/Launchpad.qml`) + open/close
choreography. The intro/outro is **pure QML**: the scrim fades in, the grid
zooms `0.92 → 1.0` + fades, and a GPU `MultiEffect` blur rolls off as it lands
(OutCubic, ~300 ms); the close reverses at 0.7× (InCubic). Because
`DashboardWindow` only maps/unmaps, we keep it mapped through the outro and unmap
it only when the animation finishes. Honours "reduce motion" (snaps instantly).

Tuning matches the pack's design reference (`/.claude/skills/gpu-effects/
reference/design-ux.md`): modal-range duration, exit faster than entrance, zero
overshoot (premium, not playful), white labels carry a shadow for legibility over
any wallpaper.

## Install / revert
```bash
bash 9-gpu-effects/launchpad/apply.sh           # deploy + swap onto the dock
bash 9-gpu-effects/launchpad/restore.sh         # swap kickerdash back
bash 9-gpu-effects/launchpad/restore.sh --purge # …and delete the plasmoid
```
`apply.sh` copies the plasmoid into `~/.local/share/plasma/plasmoids/`, swaps the
dock's app-launcher widget (`org.kde.plasma.kickerdash`) for this one in place
(same icon + left-most position), and reloads plasmashell so the new applet order
takes effect. It saves what it replaced so `restore.sh` can put it back. Layer 1's
dock builder also picks this up automatically when it's installed.

Configure via the widget settings (columns, icon size, labels, open duration,
backdrop dim, grid blur).

## Deferred (kickerdash features not yet reimplemented)
- Favourites strip + pin/unpin UI (the model is wired; the strip is not drawn yet).
- Paged grid + page dots (this is a single scrolling grid per category).
- Drag-to-reorder / drag-to-pin.

## Gotchas
- `DashboardWindow` **reparents** its `mainItem` into a separate top-level
  window, so `Launchpad.qml` must not read `plasmoid.*` — `main.qml` owns the
  Plasmoid context and passes config/models in as properties.
- The launcher's own QML needs a live plasmoid + the kicker engine, so the repo
  test only instantiates the config dialog; `qmllint` covers the rest.
