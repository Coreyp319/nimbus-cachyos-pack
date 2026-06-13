#!/usr/bin/env bash
# Pick the swaync CSS that matches the active KDE color scheme, then live-reload.
# Mirrors how 2-settings-refine/bin/refine-icons reads the scheme from kdeglobals,
# so the existing nimbus-theme-toggle.sh (Meta+Ctrl+T) repaints swaync for free
# via the kdeglobals path-watcher — no edits to Layer 1 needed.
set -eu

D="$HOME/.config/swaync"
scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || echo "")
case "$scheme" in
  *Dark*) src="style-dark.css" ;;
  *)      src="style-light.css" ;;
esac

[ -f "$D/$src" ] || exit 0
cp -f "$D/$src" "$D/style.css"

# Reload only if the daemon is up (-sw = don't block waiting for it).
swaync-client --reload-css -sw >/dev/null 2>&1 || true
