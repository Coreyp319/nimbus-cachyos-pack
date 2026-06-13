#!/usr/bin/env bash
# Revert CoreyLavender — restores the WhiteSur-dark Look-and-Feel default to
# WhiteSurDark, removes the scheme, and if it's the active scheme switches the
# live session back to WhiteSurDark. --purge also deletes the timestamped backups.
set -eu
CS="$HOME/.local/share/color-schemes"
LNF="$HOME/.local/share/plasma/look-and-feel/com.github.vinceliuice.WhiteSur-dark/contents/defaults"
PURGE="${1:-}"

echo "1/3 Restoring Look-and-Feel default colour scheme → WhiteSurDark…"
if [ -f "$LNF" ]; then
  kwriteconfig6 --file "$LNF" --group kdeglobals --group General --key ColorScheme WhiteSurDark
  echo "   ✓ LnF default → WhiteSurDark"
fi

echo "2/3 Removing CoreyLavender scheme…"
active=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || echo "")
rm -f "$CS/CoreyLavender.colors"
if [ "$active" = "CoreyLavender" ]; then
  # Don't leave the session pointing at a deleted scheme.
  plasma-apply-colorscheme WhiteSurDark >/dev/null 2>&1 || true
  echo "   ✓ active scheme was CoreyLavender → switched back to WhiteSurDark"
fi

if [ "$PURGE" = "--purge" ]; then
  rm -f "$CS"/CoreyLavender.colors.bak-* 2>/dev/null || true
  echo "3/3 Purged CoreyLavender backups."
else
  echo "3/3 Timestamped backups (if any) left on disk; --purge to remove."
fi
echo "Done."
