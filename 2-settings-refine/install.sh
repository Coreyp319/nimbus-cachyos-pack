#!/usr/bin/env bash
# Agent A — System Settings refinement: theme-aware monochrome section icons
# (+ optional Kvantum whitespace fork). User-level, no sudo. Reversible via revert.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="whitesur-refine-icons"   # neutralized from the original cocovox-* naming

echo ":: Installing refined System Settings icon theme…"
mkdir -p "$HOME/.local/share/icons"
rm -rf "$HOME/.local/share/icons/WhiteSur-dark-refined"
cp -r "$HERE/icons/WhiteSur-dark-refined" "$HOME/.local/share/icons/"
gtk-update-icon-cache -q -f "$HOME/.local/share/icons/WhiteSur-dark-refined" 2>/dev/null || true

echo ":: Installing theme-aware re-bake script + color-scheme watcher…"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m755 "$HERE/bin/refine-icons" "$HOME/.local/bin/$NAME"
# Deploy systemd units, renaming references to the neutral name + pointing at the script.
sed "s|cocovox-refine-icons|$NAME|g" "$HERE/systemd/refine-icons.service" > "$HOME/.config/systemd/user/$NAME.service"
sed "s|cocovox-refine-icons|$NAME|g" "$HERE/systemd/refine-icons.path"    > "$HOME/.config/systemd/user/$NAME.path"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now "$NAME.path" 2>/dev/null || true

echo ":: Selecting refined icons + initial tone bake…"
kwriteconfig6 --file kdeglobals --group Icons --key Theme WhiteSur-dark-refined
"$HOME/.local/bin/$NAME" 2>/dev/null || true
kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

# Optional: the Kvantum whitespace fork — installed but NOT auto-selected
# (it helps classic Qt config dialogs; opt in if you want it).
if [ -d "$HERE/kvantum/WhiteSurRefined" ]; then
  mkdir -p "$HOME/.config/Kvantum"
  cp -r "$HERE/kvantum/WhiteSurRefined" "$HOME/.config/Kvantum/"
  echo ":: Kvantum whitespace fork 'WhiteSurRefined' installed (NOT selected)."
  echo "   To enable it:  kwriteconfig6 --file ~/.config/Kvantum/kvantum.kvconfig --group General --key theme WhiteSurRefined"
fi

echo ":: Done — refined System Settings icons are live and theme-aware (re-bake on light↔dark)."
