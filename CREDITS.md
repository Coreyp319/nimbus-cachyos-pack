# Credits & third-party licenses

This pack stands on excellent upstream work. The original scripts here are MIT
(see LICENSE); the components below keep their own licenses.

## Downloaded at install time (Layer 1)
- **WhiteSur** theme suite — Plasma, Kvantum, GTK, icons, cursors, wallpapers
  by **vinceliuice** — https://github.com/vinceliuice — **GPL-3.0**.
- **Inter** font by **Rasmus Andersson (rsms)** —
  https://github.com/rsms/inter — **SIL Open Font License 1.1**.

## Bundled overlay files (locally authored, derive from upstream)
- **Layer 2** refined System Settings icons inherit/derive from WhiteSur
  (vinceliuice, **GPL-3.0**); the theme-aware re-bake script + systemd watcher
  are original.
- **Layer 3** `ResultDelegate.qml` / `ResultsView.qml` are patched copies of
  **KDE milou** (https://invent.kde.org/plasma/milou) — **LGPL-2.1-or-later /
  GPL-2.0-or-later**; the `claude_runner.py` D-Bus runner is original.

## Packages (installed via pacman, not redistributed here)
Kvantum, sassc, optipng, python-dbus, python-gobject — their respective
distro licenses.

If you redistribute this pack, keep these attributions and honor the upstream
licenses (notably GPL-3.0 for the WhiteSur-derived theme files).
