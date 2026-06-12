#!/usr/bin/env bash
# Layer 5 — System quality-of-life (CachyOS / Arch).
#
# Distinct from the desktop-look layers: general OS ergonomics, all opt-in and
# reversible. Each item is offered separately (answer per prompt); pass -y to
# accept them all non-interactively. Uses sudo for package installs (it prompts).
#
#   • paccache.timer  — weekly prune of old cached packages (needs pacman-contrib)
#   • Flatpak + Flathub — unlocks the Flatpak app ecosystem in Discover
#   • Shell tooling   — zoxide + starship + fzf keybindings wired into fish
#   • Timeshift       — installs it (rsync mode); you pick the target in the GUI
#
# Run as your normal user: bash 5-system-qol/install.sh   (add -y for all)
# Reversible via revert.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user, not root."; exit 1; }

ALL=0; case "${1:-}" in -y|--yes) ALL=1 ;; -h|--help)
  echo "Usage: bash install.sh [-y]   (-y sets up every QoL item without asking)"; exit 0 ;;
esac

ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
msg(){ printf '\n\033[1m:: %s\033[0m\n' "$1"; }
ask(){ [ "$ALL" = 1 ] && return 0; printf '  Set up %s? [Y/n] ' "$1"
       read -r r </dev/tty 2>/dev/null || r=n; case "$r" in [nN]*) return 1 ;; *) return 0 ;; esac; }

echo ":: Layer 5 — system QoL. Pick what you want (Enter = yes)."

# --- paccache: weekly cache prune ---
if ask "weekly pacman-cache prune (paccache.timer)"; then
  msg "paccache.timer…"
  if pacman -Qq pacman-contrib >/dev/null 2>&1; then
    sudo systemctl enable --now paccache.timer && ok "paccache.timer enabled (keeps last 3 versions)"
  else
    echo "  pacman-contrib not installed; run: sudo pacman -S pacman-contrib"
  fi
fi

# --- Flatpak + Flathub ---
if ask "Flatpak + Flathub"; then
  msg "Flatpak + Flathub…"
  sudo pacman -S --needed --noconfirm flatpak && {
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    ok "Flatpak installed + Flathub remote added (log out/in for Discover to see it)"
  }
fi

# --- Shell tooling (fish): zoxide + starship + fzf ---
if ask "fish shell tooling (zoxide + starship + fzf)"; then
  msg "Shell tooling (fish)…"
  sudo pacman -S --needed --noconfirm zoxide starship fzf fd bat eza
  mkdir -p "$HOME/.config/fish/conf.d"
  install -m644 "$HERE/fish/qol.fish" "$HOME/.config/fish/conf.d/qol.fish"
  ok "fish QoL snippet installed (zoxide 'z', starship prompt, fzf Ctrl-R/Ctrl-T/Alt-C)"
  echo "    open a new terminal or run 'exec fish' to activate"
fi

# --- Timeshift (system restore points) ---
if ask "Timeshift restore points"; then
  msg "Timeshift…"
  sudo pacman -S --needed --noconfirm timeshift && {
    ok "Timeshift installed"
    echo "    Configure once:  sudo timeshift-gtk"
    echo "    Suggested: RSYNC mode · target = your root disk (or an external drive"
    echo "    for true disaster recovery) · schedule Boot + Daily(5) + Weekly(3)."
  }
fi

msg "Layer 5 done."
