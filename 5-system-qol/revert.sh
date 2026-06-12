#!/usr/bin/env bash
# Revert layer 5 — system QoL. Config/timers off by default; --purge also removes
# the installed packages (kept by default, since you may rely on them elsewhere).
set -uo pipefail
PURGE="${1:-}"

echo "1/3 Disabling paccache.timer…"
sudo systemctl disable --now paccache.timer 2>/dev/null || true

echo "2/3 Removing the fish QoL snippet…"
rm -f "$HOME/.config/fish/conf.d/qol.fish"

echo "3/3 Flathub remote + packages…"
if [ "$PURGE" = "--purge" ]; then
  sudo flatpak remote-delete --force flathub 2>/dev/null || true
  sudo pacman -Rns --noconfirm zoxide starship flatpak timeshift 2>/dev/null || true
  echo "    Purged shell tools, Flatpak, Timeshift (Flathub remote removed)."
else
  echo "    Left packages + Flathub remote in place (run with --purge to remove)."
  echo "    Timeshift snapshots are NOT deleted; manage them in 'sudo timeshift-gtk'."
fi

echo "Done. Open a new shell to drop the QoL integrations."
