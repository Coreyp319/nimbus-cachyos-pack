#!/usr/bin/env bash
# Agent A — System Settings refinement: theme-aware monochrome section icons
# (+ optional Kvantum whitespace fork). User-level, no sudo. Reversible via revert.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="nimbus-refine-icons"   # neutralized from the original cocovox-* naming

echo ":: Installing refined System Settings icon theme…"
mkdir -p "$HOME/.local/share/icons"
rm -rf "$HOME/.local/share/icons/Nimbus-dark-refined"
cp -r "$HERE/icons/Nimbus-dark-refined" "$HOME/.local/share/icons/"
gtk-update-icon-cache -q -f "$HOME/.local/share/icons/Nimbus-dark-refined" 2>/dev/null || true

echo ":: Installing theme-aware re-bake script + color-scheme watcher…"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m755 "$HERE/bin/refine-icons" "$HOME/.local/bin/$NAME"
# Deploy systemd units, renaming references to the neutral name + pointing at the script.
sed "s|cocovox-refine-icons|$NAME|g" "$HERE/systemd/refine-icons.service" > "$HOME/.config/systemd/user/$NAME.service"
sed "s|cocovox-refine-icons|$NAME|g" "$HERE/systemd/refine-icons.path"    > "$HOME/.config/systemd/user/$NAME.path"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now "$NAME.path" 2>/dev/null || true

echo ":: Selecting refined icons + initial tone bake…"
kwriteconfig6 --file kdeglobals --group Icons --key Theme Nimbus-dark-refined
"$HOME/.local/bin/$NAME" 2>/dev/null || true
kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

# The refined Kvantum fork — light + dark variants. These carry the accent
# control work (focus rings on checkbox/radio/slider, scrollbar grab accent, the
# accent focus frame), so this layer SELECTS them as the active Kvantum theme,
# matching the current colour scheme. Layer 1's light/dark toggle is fork-aware
# and keeps them across mode switches; revert.sh restores plain WhiteSur.
if [ -d "$HERE/kvantum/NimbusRefined" ]; then
  mkdir -p "$HOME/.config/Kvantum"
  for kv in "$HERE"/kvantum/NimbusRefined*; do
    [ -d "$kv" ] && cp -r "$kv" "$HOME/.config/Kvantum/"
  done
  # Select the variant that matches the current scheme (dark → RefinedDark).
  SCHEME=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || echo "")
  case "$SCHEME" in *Dark*) RKV=NimbusRefinedDark ;; *) RKV=NimbusRefined ;; esac
  kwriteconfig6 --file "$HOME/.config/Kvantum/kvantum.kvconfig" --group General --key theme "$RKV"
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum
  echo ":: Refined Kvantum fork installed and selected ($RKV; auto-swaps on light↔dark)."
fi

echo ":: Done — refined System Settings icons are live and theme-aware (re-bake on light↔dark)."
