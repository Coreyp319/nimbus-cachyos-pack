#!/usr/bin/env bash
# CoreyLavender — a true dark-lavender colour scheme, rebuilt to pass WCAG AA/AAA
# (violet elevation ladder, accent-coherent selection/focus, lightened semantics).
#
# This makes the scheme AVAILABLE and DURABLE without hijacking your session:
#   • installs CoreyLavender.colors into ~/.local/share/color-schemes/
#   • pins it as the WhiteSur-dark Look-and-Feel's default colour scheme, so it
#     survives login (the LnF defaults file is THE thing that re-asserts colours
#     at session start — left alone it would clobber a user scheme)
#   • Layer 1's light/dark toggle already prefers CoreyLavender for dark mode when
#     this .colors file is present, so it rides light↔dark too.
#
# It does NOT switch your live session — that happens on the next dark-mode toggle
# or login. Pass --apply to switch now. User-level, no sudo. Reversible.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
CS="$HOME/.local/share/color-schemes"
LNF="$HOME/.local/share/plasma/look-and-feel/com.github.vinceliuice.WhiteSur-dark/contents/defaults"

echo ":: Installing CoreyLavender colour scheme…"
mkdir -p "$CS"
[ -f "$CS/CoreyLavender.colors" ] && cp "$CS/CoreyLavender.colors" "$CS/CoreyLavender.colors.bak-$(date +%Y%m%d-%H%M%S)"
cp "$HERE/CoreyLavender.colors" "$CS/CoreyLavender.colors"
echo "   ✓ available in System Settings → Colours"

if [ -f "$LNF" ]; then
  echo ":: Pinning it as the WhiteSur-dark Look-and-Feel default (survives login)…"
  kwriteconfig6 --file "$LNF" --group kdeglobals --group General --key ColorScheme CoreyLavender
  echo "   ✓ LnF default → CoreyLavender"
else
  echo "   ! WhiteSur-dark Look-and-Feel not found — run Layer 1 first for login durability."
fi

if [ "$APPLY" = 1 ]; then
  echo ":: Applying live…"
  # plasma-apply-colorscheme short-circuits on an unchanged NAME even if the
  # .colors contents changed, so bounce through another scheme to force a reload.
  plasma-apply-colorscheme WhiteSurDark >/dev/null 2>&1 || true
  plasma-apply-colorscheme CoreyLavender >/dev/null 2>&1 && echo "   ✓ CoreyLavender is live" || true
else
  echo ":: Not applied live — effective on the next dark-mode toggle or login."
  echo "   Switch now:  plasma-apply-colorscheme CoreyLavender   (or re-run with --apply)"
fi
echo ":: Done."
