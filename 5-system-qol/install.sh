#!/usr/bin/env bash
# Layer 5 — System quality-of-life (CachyOS / Arch).
#
# Distinct from the desktop-look layers: this is general OS ergonomics, all opt-in
# and reversible. Uses sudo for package installs + the cache timer (it prompts).
#
#   • paccache.timer  — weekly prune of old cached packages (needs pacman-contrib)
#   • Flatpak + Flathub — unlocks the Flatpak app ecosystem in Discover
#   • Shell tooling   — zoxide + starship + fzf keybindings wired into fish
#   • Timeshift       — installs it (rsync mode); you pick the target in the GUI
#
# Run as your normal user: bash 5-system-qol/install.sh
# Reversible via revert.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user, not root."; exit 1; }
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
msg(){ printf '\n\033[1m:: %s\033[0m\n' "$1"; }

# --- paccache: weekly cache prune ---
msg "Pacman cache auto-prune (paccache.timer)…"
if pacman -Qq pacman-contrib >/dev/null 2>&1; then
  sudo systemctl enable --now paccache.timer && ok "paccache.timer enabled (keeps last 3 versions)"
else
  echo "  pacman-contrib not installed; run: sudo pacman -S pacman-contrib"
fi

# --- Flatpak + Flathub ---
msg "Flatpak + Flathub…"
sudo pacman -S --needed --noconfirm flatpak && {
  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  ok "Flatpak installed + Flathub remote added (log out/in for Discover to see it)"
}

# --- Shell tooling (fish): zoxide + starship + fzf ---
msg "Shell tooling (fish)…"
sudo pacman -S --needed --noconfirm zoxide starship fzf fd bat eza
mkdir -p "$HOME/.config/fish/conf.d"
install -m644 "$HERE/fish/qol.fish" "$HOME/.config/fish/conf.d/qol.fish"
ok "fish QoL snippet installed (zoxide 'z', starship prompt, fzf Ctrl-R/Ctrl-T/Alt-C)"
echo "    open a new terminal or run 'exec fish' to activate"

# --- Timeshift (system restore points) ---
msg "Timeshift…"
sudo pacman -S --needed --noconfirm timeshift && {
  ok "Timeshift installed"
  echo "    Configure once:  sudo timeshift-gtk"
  echo "    Suggested: RSYNC mode · target = your root disk (or an external drive"
  echo "    for true disaster recovery) · schedule Boot + Daily(5) + Weekly(3)."
}

msg "Layer 5 done."
