#!/usr/bin/env bash
# Revert layer 9 — GPU UI effects. Restores Layer 1's stock blur and turns off
# the shader pass. Config is reverted by default; --purge also removes the
# installed/built packages (kept by default in case you re-enable later).
set -uo pipefail
PURGE="${1:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HOME/.cache/whitesur-gpu-effects"
reconf(){ qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true; }                       # stock effects
eff(){ qdbus6 org.kde.KWin /Effects "org.kde.kwin.Effects.$1" "$2" >/dev/null 2>&1 || true; }    # forks
enabled(){ [ "$(kreadconfig6 --file kwinrc --group Plugins --key "${1}Enabled" 2>/dev/null)" = "true" ]; }

echo "1/4 Blur fork → stock blur…"
# Restore stock blur only if a fork (glass / forceblur) was actually the active one.
FORK=""
enabled forceblur && FORK=forceblur
enabled glass     && FORK=glass
if [ -n "$FORK" ]; then
  kwriteconfig6 --file kwinrc --group Plugins --key "${FORK}Enabled" false
  kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled      true   # back to Layer 1's blur
  eff unloadEffect "$FORK"   # forks ignore /KWin reconfigure — unload via /Effects
  eff loadEffect blur
  reconf
  echo "    $FORK → stock KWin blur (Layer 1 default)."
else
  echo "    No blur fork was active — leaving blur settings as-is."
fi

echo "2/4 Desktop shaders pass off…"
kwriteconfig6 --file kwinrc --group Plugins --key kwin_effect_shadersEnabled false
eff unloadEffect kwin_effect_shaders

echo "3/4 Aurora wallpaper → previous…"
# Tear down the window- and music-reactivity bridges (KWin script + daemons) first.
[ -f "$HERE/interactive-bg/windows-restore.sh" ] && bash "$HERE/interactive-bg/windows-restore.sh" "$PURGE" || true
[ -f "$HERE/interactive-bg/audio-restore.sh" ]   && bash "$HERE/interactive-bg/audio-restore.sh"   "$PURGE" || true
# Reads its saved state from $BUILD, so it must run before the purge wipes it.
[ -f "$HERE/interactive-bg/restore.sh" ] && bash "$HERE/interactive-bg/restore.sh" "$PURGE" || \
  echo "    interactive-bg/restore.sh missing — skipped."

echo "4/4 Packages / build…"
if [ "$PURGE" = "--purge" ]; then
  for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { "$h" -Rns --noconfirm kwin-effects-glass-git kwin-effects-forceblur 2>/dev/null; break; }; done
  # kwin-effect-shaders installs via 'sudo make install' — uninstall via its build tree.
  SRC="$BUILD/kwin-effect-shaders"
  [ -f "$SRC/install.sh" ] && ( cd "$SRC" && bash install.sh UNINSTALL >/dev/null 2>&1 ) || true
  rm -rf "$BUILD" "$HOME/.local/share/kwin-effect-shaders_shaders"
  echo "    Purged Glass/forceblur + kwin-effect-shaders (build tree, shaders, package)."
else
  echo "    Left packages/build in place (run with --purge to remove)."
fi

reconf
echo "Done. Blur forks disabled; stock blur restored."
